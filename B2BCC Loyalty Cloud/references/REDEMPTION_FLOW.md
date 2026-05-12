# Redemption flow — checkout

End-to-end sequence when a buyer redeems points at checkout.

```
Buyer (storefront LWR)
  │
  │ 1. Opens Checkout page
  ▼
loyaltyCheckoutRedemption LWC
  │
  │ 2. @wire getMemberBalance(programId, accountId)  ─── Apex: LoyaltyAccountController ─── SOQL: LoyaltyMemberCurrency
  │◀── { available: 2400, ratio: "10 pts = 1 EUR", minRedeem: 100 }
  │
  │ 3. Buyer enters "500" → "Apply"
  │
  │ 4. applyRedemption(cartId, 500)                  ─── Apex: LoyaltyRedemptionController
  │                                                       ├─ validate: 500 ≤ available - escrow
  │                                                       ├─ validate: 500 >= minRedeem
  │                                                       ├─ compute monetary value: 500 / 10 = 50.00
  │                                                       ├─ create CartAdjustmentGroup (-50.00)
  │                                                       └─ set Cart.LoyaltyPointsReserved__c = 500
  │
  │ 5. ◀── { success: true, discountApplied: 50.00, remainingBalance: 1900 }
  │
  │ 6. Cart re-renders with discount line
  │
  ▼
Buyer confirms checkout → Order created → Order.Status = Activated
  │
  │ 7. OrderCompletedTrigger (Apex) publishes Order_Completed__e
  │         { OrderId, BuyerAccountId, Subtotal, PointsRedeemed: 500, WebStoreId }
  ▼
Flow: Loyalty_Accrual_OnOrderActivated (platform-event-triggered)
  │
  │ 8. Get LoyaltyProgramMember via LoyaltySiteMapping__mdt (WebStoreId → ProgramId) + AccountId
  │
  │ 9. LoyaltyCreateTransactionJournal (Redemption, -500 pts)
  │10. LoyaltyCreateTransactionJournal (Accrual, +subtotal * ratio)
  │
  ▼
TransactionJournal records (2) → async balance update → LoyaltyMemberCurrency.PointsBalance refreshed
```

## Edge cases

- **Partial return / order cancellation**: out of scope for v1. A cancelled order leaves the Redemption journal in place (customer keeps the discount, points don't come back). Document this in the demo script — real implementations need a reversal journal on cancellation.
- **Cart abandoned after redemption applied**: `Cart.LoyaltyPointsReserved__c` is informational only; points are **not** reserved in Loyalty until the Order activates. No cleanup needed on abandonment.
- **Multiple redemption attempts on the same cart**: each call to `applyRedemption` should remove any prior `CartAdjustmentGroup` this connector created and replace with the new one. Use a marker on the adjustment's `Description` or a dedicated adjustment type code to find it.
- **Concurrent activation of two orders**: each `Order_Completed__e` is processed independently; the balance update serializes at the `LoyaltyMemberCurrency` level. Correctness holds even under race.

## Why a Platform Event and not a direct trigger

- Decouples Order activation from Loyalty processing: if Loyalty Management is temporarily unavailable or the Flow errors, the Order still commits and the event can be replayed.
- Lets admins swap the downstream Flow without touching Apex — `LoyaltyCreateTransactionJournal` configuration (JournalSubType, ActivityDate) lives in Flow, not code.
- Keeps the Apex footprint minimal (one trigger + one publish call), which makes the package easier to install into orgs with existing Order automation.
