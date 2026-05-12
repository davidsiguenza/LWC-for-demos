# Loyalty Management — data model cheatsheet (validated against `B2BCCLoyalty` org)

All field names below were confirmed by `sf sobject describe` and live SOQL against org `storm.707ad0b4aed5c9@salesforce.com` (API v66, 2026-05-05). When something in this file doesn't match your target org, the target org is authoritative — update this cheatsheet.

## Core objects

| Object | Key fields (validated) |
|---|---|
| `LoyaltyProgram` | `Id`, `Name` **[REQ]**, `Status`, `Type` (picklist — e.g. `LOYALTY_PROGRAM`), `SubType`, `IsPrimary`, `Description`, `EscrowPeriod`, `CurrencyIsoCode`. ⚠️ **No `StartDate` field, no `ProgramType` — those are common doc mistakes.** |
| `LoyaltyProgramCurrency` | `Id`, `Name`, `LoyaltyProgramId`, `CurrencyType` (picklist — `Qualifying` / `Non-Qualifying`), `ExtendExpiration`, `CurrencyIsoCode`. ⚠️ **No `UsageType`.** |
| `LoyaltyTierGroup` | `Id`, `Name`, `LoyaltyProgramId` |
| `LoyaltyTier` | `Id`, `Name`, `LoyaltyTierGroupId`, `SequenceNumber` (not `TierSequenceNumber`) |
| `LoyaltyProgramMember` | `Id`, `MembershipNumber`, `MemberStatus`, `MemberType`, `EnrollmentDate`, `EnrollmentChannel`, `ContactId`, `AccountId`, `ProgramId` (⚠️ **not** `LoyaltyProgramId`) |
| `LoyaltyMemberTier` | `Id`, `LoyaltyMemberId`, `LoyaltyTierId` |
| `LoyaltyMemberCurrency` | `Id`, `Name`, `LoyaltyMemberId` (⚠️ **not** `LoyaltyProgramMemberId`), `LoyaltyProgramCurrencyId`, `PointsBalance`, `EscrowPointsBalance`, `TotalPointsAccrued`, `TotalPointsRedeemed`, `TotalPointsExpired`, `ExpirablePoints` |
| `TransactionJournal` | `Id`, `MemberId` (FK → `LoyaltyProgramMember`), `AccountId`, `LoyaltyProgramId`, `JournalTypeId` (FK → `JournalType`), `JournalSubTypeId` (FK → `JournalSubType`), `ActivityDate` **[REQ]**, `JournalDate`, `Status`, `TransactionAmount` (currency), `CurrencyIsoCode`, `OrderId`, `OrderItemId`, `ProductId`, `VoucherCode`, `Channel`, `Comment`, `IsAccrualJournalEntry`, `IsAdjustmentJournalEntry`, `IsWriteOffJournalEntry`. **Flag booleans on the journal (e.g. `IsAccrualJournalEntry`) are set by the platform's resolution job — you do NOT set them on insert.** |
| `Voucher` | `Id`, `LoyaltyProgramMemberId`, `VoucherCode`, `Status`, `FaceValue`, `ExpirationDate` |

## JournalType / JournalSubType — **separate objects**, not picklists

Unlike many Salesforce record-type scenarios, `JournalType` and `JournalSubType` in Loyalty Management are **first-class sObjects** you look up by Id. The Cirrus-pack SDO ships with 17 journal types already created at the org level (they are **not** scoped per LoyaltyProgram):

| JournalType.Name | Id (this org) | Used by |
|---|---|---|
| Accrual | `0lEg80000002a10EAA` | Accrual on order activation |
| Redemption | `0lEg80000002a13EAA` | Cart redemption on order activation |
| Accrual Reversal | `0lEg80000002a14EAA` | Return / cancellation handling (future) |
| Redemption Reversal | `0lEg80000002a12EAA` | Return / cancellation handling (future) |
| Manual Points Adjustment | `0lEg80000002a17EAA` | Admin correction UI (out of scope v1) |
| Referral, Points Transfer, Payment, Allocation, Points Expiration, Qualifying Points Reset, Transaction, Point of Sale Document, Sale Document, Point of Sale Return Document, Partner Return Document, Customer Purchase | — | Not used by this connector |

> **Resolve IDs fresh per target org.** The `Id`s above are examples from `B2BCCLoyalty`; in another org the same `Name` will have a different Id. Cache them in the Apex service (`LoyaltyJournalService.getJournalTypeId('Accrual')`).

## Relationships (validated)

```
LoyaltyProgram 1 — * LoyaltyProgramCurrency
               1 — * LoyaltyTierGroup 1 — * LoyaltyTier
               1 — * LoyaltyProgramMember (via ProgramId)
                         1 — * LoyaltyMemberCurrency (via LoyaltyMemberId)
                         1 — * LoyaltyMemberTier     (via LoyaltyMemberId)
                         1 — * TransactionJournal    (via MemberId)
                         1 — * Voucher
```

## Queries this connector relies on (validated syntax)

```sql
-- Member for a logged-in B2B buyer (enrolled by AccountId, not ContactId)
SELECT Id, MembershipNumber, MemberStatus, EnrollmentDate
FROM LoyaltyProgramMember
WHERE ProgramId = :programId AND AccountId = :buyerAccountId

-- Balance (one row per currency; in a Points-only program there is exactly one)
SELECT PointsBalance, EscrowPointsBalance, ExpirablePoints,
       LoyaltyProgramCurrency.Name, LoyaltyProgramCurrency.CurrencyType
FROM LoyaltyMemberCurrency
WHERE LoyaltyMemberId = :memberId

-- Current tier
SELECT LoyaltyTier.Name, LoyaltyTier.SequenceNumber,
       LoyaltyTier.LoyaltyTierGroup.Name
FROM LoyaltyMemberTier
WHERE LoyaltyMemberId = :memberId

-- History (last 30)
SELECT JournalType.Name, JournalSubType.Name,
       TransactionAmount, ActivityDate, Status, OrderId
FROM TransactionJournal
WHERE MemberId = :memberId
ORDER BY ActivityDate DESC LIMIT 30

-- Active vouchers
SELECT VoucherCode, FaceValue, ExpirationDate, Status
FROM Voucher
WHERE LoyaltyProgramMemberId = :memberId AND Status = 'Issued'
```

## Permission Set Licenses (real DeveloperNames)

Confirmed via `SELECT DeveloperName, Status FROM PermissionSetLicense WHERE DeveloperName LIKE '%oyalty%'`:

| DeveloperName | MasterLabel | Notes |
|---|---|---|
| `LoyaltyManagementPsl` | Loyalty Management Psl | Core license. Users need this assigned via `PermissionSetLicenseAssign`. |
| `LoyaltyManagementLitePsl` | Loyalty Management Lite | Restricted feature set (no Promotions / Benefits automation). |
| `LoyaltyAnalyticsPlusPsl` | Loyalty Analytics Apps | For CRM Analytics loyalty dashboards — not needed by this connector. |

The `LoyaltyManagement` permission set (not PSL) does **not** exist with that exact name in this org. Use **`LoyaltyAnalyticsUser`** (the one PermissionSet present) or provide a custom permset `B2BLoyalty_Admin` that grants access to all Loyalty objects used here.

## Gotchas (validated)

- **Enrolment key**: `LoyaltyProgramMember` has **both** `ContactId` and `AccountId`. The Cirrus demo program (`0lpg80000001njRAAQ`) was seeded with Contact-based members. For the B2B connector we enrol by `AccountId` (BuyerAccount). Make sure the program allows it — the schema does, but some flow-based enrolment actions may default to Contact.
- **Balance aggregation**: never sum `TransactionJournal.TransactionAmount` to compute balance — always read `LoyaltyMemberCurrency.PointsBalance`. The journal → balance update is async and you'll race the aggregation.
- **JournalType/SubType are Ids, not strings**: when creating a `TransactionJournal` from Apex, don't write `JournalType = 'Accrual'` (there is no such field). Use `JournalTypeId = <Id of the Accrual record>`. Cache the lookup once.
- **`Is*JournalEntry` booleans are set by platform**: `IsAccrualJournalEntry`, `IsRedemptionJournalEntry`, etc. — the platform sets these during journal resolution, not your insert code.
- **Async tier progression**: tier recalculation runs on a background job after a journal is created; UI widgets should tolerate ~seconds of staleness.
- **Escrow**: `EscrowPointsBalance` is reserved (pending return/claw-back window). Subtract it from `PointsBalance` when showing "available to redeem".

## Reference IDs in the `B2BCCLoyalty` target org

_Captured 2026-05-05. Re-verify if reusing this file against a different org._

```
LoyaltyProgram        Cirrus Loyalty          0lpg80000001njRAAQ
LoyaltyTierGroup      Cirrus Loyalty Group    0ltg80000001mPBAAY
LoyaltyTier           Bronze Tier             0lgg80000001lRVAAY  (seq 1)
LoyaltyTier           Silver Tier             0lgg80000001lRWAAY  (seq 2)
LoyaltyTier           Gold Tier               0lgg80000001lRXAAY  (seq 3)
WebStore              SDO - B2B Commerce Enhanced   0ZEg8000000RrHxGAK
JournalType           Accrual                 0lEg80000002a10EAA
JournalType           Redemption              0lEg80000002a13EAA
JournalType           Accrual Reversal        0lEg80000002a14EAA
JournalType           Redemption Reversal     0lEg80000002a12EAA
```
