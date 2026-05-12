# Accrual flow — implementation notes

> **Implemented approach**: Apex trigger on `Order` (not Platform Event + Flow as originally planned). See `LoyaltyOrderJournalService.cls` and `LoyaltyOrderTrigger.trigger`. The Platform Event + Flow design was dropped in favour of a single pass of Apex because the demo needed direct control over the journal shape and the member resolution chain (Account → BillToContact → any Contact on the Account), which is awkward in record-triggered Flow.

> **Balance behavior**: the service inserts `TransactionJournal` rows with `Status='Pending'`. Salesforce does **not** move `LoyaltyMemberCurrency.PointsBalance` from journal inserts unless a `LoyaltyProgramProcess` is configured (see `POST_INSTALL_LOYALTY_PROCESS.md`). Until then, `LoyaltyAccountController.populateBalance` adds the sum of connector-inserted journals to the seed balance so the UI reflects the effective balance. This is a display-time computation, not a persisted aggregate.

---

## Original design (Platform Event + Flow) — kept for reference

Accrual is driven entirely by a **Platform Event** + a **record-triggered Flow** so that admins can tune ratios / journal subtypes without touching Apex.

## Platform Event — `Order_Completed__e`

| Field | Type | Source |
|---|---|---|
| `OrderId` | Text(18) | `Order.Id` |
| `BuyerAccountId` | Text(18) | `Order.AccountId` |
| `Subtotal` | Number(16,2) | `Order.TotalAmount` minus loyalty discount |
| `PointsRedeemed` | Number(18,0) | `Cart.LoyaltyPointsReserved__c` (0 if none) |
| `WebStoreId` | Text(18) | `Order.SalesStoreId` (or custom field if the stock one is absent) |

## Apex publisher — `OrderCompletedTrigger`

Minimal `after update` trigger on `Order`:

```apex
trigger OrderCompletedTrigger on Order (after update) {
    List<Order_Completed__e> events = new List<Order_Completed__e>();
    for (Order o : Trigger.new) {
        Order old = Trigger.oldMap.get(o.Id);
        if (o.Status == 'Activated' && old.Status != 'Activated') {
            events.add(new Order_Completed__e(
                OrderId__c = o.Id,
                BuyerAccountId__c = o.AccountId,
                Subtotal__c = o.TotalAmount,
                PointsRedeemed__c = /* resolved from Cart.LoyaltyPointsReserved__c via related lookup */,
                WebStoreId__c = o.SalesStoreId
            ));
        }
    }
    if (!events.isEmpty()) EventBus.publish(events);
}
```

_(Actual class lives in `triggers/OrderCompletedTrigger.trigger` — to be implemented.)_

## Flow — `Loyalty_Accrual_OnOrderActivated`

**Type:** Platform-event-triggered.  
**Event:** `Order_Completed__e`.

### Steps

1. **Get `LoyaltySiteMapping__mdt`** record where `WebStoreId__c = $Event.WebStoreId__c`. Extract `LoyaltyProgramId__c` and `AccrualRatio__c` (points per monetary unit).
2. **Get `LoyaltyProgramMember`** where `LoyaltyProgramId = <from step 1>` AND `AccountId = $Event.BuyerAccountId__c`.
   - If not found → log via Flow Fault and stop. Enrolment is Phase F's responsibility, not this Flow's.
3. **If `$Event.PointsRedeemed__c > 0`** → invoke `LoyaltyCreateTransactionJournal` with:
   - `JournalType` = `Redemption`
   - `TransactionAmount` = `-1 * $Event.PointsRedeemed__c`
   - `LoyaltyProgramMemberId` = from step 2
   - `RelatedOrderId` = `$Event.OrderId__c`
4. **Invoke `LoyaltyCreateTransactionJournal`** with:
   - `JournalType` = `Accrual`
   - `TransactionAmount` = `$Event.Subtotal__c * AccrualRatio__c`
   - `LoyaltyProgramMemberId` = from step 2
   - `RelatedOrderId` = `$Event.OrderId__c`
5. End.

## Fallback if `LoyaltyCreateTransactionJournal` invocable isn't available

Some earlier releases don't expose the invocable. In that case the Flow calls a bundled Apex invocable `B2BLoyalty_CreateJournal` which does:

```apex
insert new TransactionJournal(
    LoyaltyProgramMemberId = memberId,
    LoyaltyProgramId       = programId,
    JournalType            = 'Accrual', // or 'Redemption'
    TransactionAmount      = amount,
    ActivityDate           = System.now(),
    Status                 = 'Pending'
);
```

The platform's standard async trigger on `TransactionJournal` takes over from there and updates balances.

## Why low-code here specifically

Accrual rules are the **single most tweaked** piece of a loyalty demo: "show 2x on launch weekend", "double points for the VIP tier", "bonus for first order". Putting that logic in Flow means a sales engineer can edit it mid-demo without a redeploy. The Apex layer just guarantees the event fires once per activation.
