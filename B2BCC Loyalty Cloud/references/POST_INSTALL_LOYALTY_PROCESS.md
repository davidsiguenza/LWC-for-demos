# Post-install: enable native balance updates via Loyalty Program Process

**Status**: optional, but recommended for production rollouts.
**Estimated time**: 30–60 min in Setup per program.

## Why this step exists

This connector writes `TransactionJournal` rows on every redemption and order activation, and those journals carry the correct points delta (e.g. `-100` for a redemption, `+50` for an accrual). However, **Salesforce Loyalty Management does not update `LoyaltyMemberCurrency.PointsBalance` automatically** from a journal insert — the balance is only moved when a **Loyalty Program Process** evaluates that journal and writes a matching `LoyaltyLedger` row.

As a consequence:

- Out of the box, after install, `LoyaltyMemberCurrency.PointsBalance` stays at its seed value forever (all our journals remain `Pending` and the `LoyaltyLedger` table stays empty).
- The four My Account widgets and the checkout redemption widget would always show the seed balance minus whatever adjustment math the widget itself does in code.

To bridge this gap for demos, `LoyaltyAccountController.pendingJournalDelta` adds `SUM(TransactionJournal.TransactionAmount)` of the journals this connector wrote **that do not yet have a `LoyaltyLedger`** to the raw balance — so **the UI always shows the correct effective balance** even if `LoyaltyProgramProcess` is not configured. That delta is a display-time computation, not a persisted aggregate. The connector also ships a record-triggered Flow (`Loyalty_Run_Process_on_TJ_Pending`) that invokes the standard `runProgramProcessForTransactionJournal` action on every Pending journal — as soon as Program Process is configured, it's wired up automatically.

**When you enable `LoyaltyProgramProcess` rules, you get the real thing**:
- `TransactionJournal.Status` moves from `Pending` → `Processed` automatically.
- `LoyaltyLedger` rows are created (one per processed journal) and the standard Loyalty reports (CRM Analytics "Loyalty Analytics" app) start working.
- `LoyaltyMemberCurrency.PointsBalance` updates natively.

✅ **Self-healing via `LoyaltyLedger`**: the display-time delta counts journals that **don't have a `LoyaltyLedger`** — not journals with `Status='Pending'`. Why: the invocable action `runProgramProcessForTransactionJournal` (called automatically by our Flow) flips `Status` to `Processed` even when no Program Process is configured, without creating a ledger or moving the balance. Checking for ledger existence is the ground truth.

When Program Process is configured, it creates a `LoyaltyLedger` row per processed journal and updates `LoyaltyMemberCurrency.PointsBalance` in the same transaction. That journal's amount atomically migrates from the delta (dropped because a ledger now exists) into the native balance. No code change needed, no double-counting window, safe to leave in place forever.

---

## Step 1 — Open Loyalty Program Processes

1. **Setup → Loyalty Management → Programs** → open the target program (in our SDO it's **Cirrus Loyalty**, `0lpg80000001njRAAQ`).
2. In the program details page, scroll down to **Processes** (or open the **Processes** tab if using the new UI).
3. You need to create (or verify exist) three process flows:
   - **Accrual Process** — runs on Accrual journals, credits the Member Currency.
   - **Redemption Process** — runs on Redemption journals, debits the Member Currency.
   - **Tier Assessment Process** — recalculates the member's tier based on new accruals (optional for the balance demo, required for the tier widget to auto-advance).

## Step 2 — Create the Accrual Process

1. Click **New Process** → choose **Accrual**.
2. Fill in:
   - **Process Name**: `Accrual — Order-based`
   - **Description**: "Credits points when an Accrual TransactionJournal is inserted from an order activation."
3. Save. A Flow opens in Flow Builder with a pre-built template named `<ProgramName>_Accrual_<random>`.
4. The template has three canvas sections:
   - **Get member currency** (lookup element)
   - **Calculate points** (assignment / formula)
   - **Create Loyalty Ledger** (create records)
5. For our connector, the journal **already carries** the correct points in `TransactionJournal.TransactionAmount`. So simplify the flow:
   - Remove the "Calculate points" logic that multiplies by a ratio; our `TransactionAmount` is already in points.
   - In the **Create Loyalty Ledger** step, map:
     - `LoyaltyProgramMemberId` ← `$Record.MemberId`
     - `LoyaltyProgramCurrencyId` ← output of "Get member currency"
     - `TransactionJournalId` ← `$Record.Id`
     - `EventType` ← `Credit`
     - `Points` ← `$Record.TransactionAmount`
     - `ActivityDate` ← `$Record.ActivityDate`
6. **Activate** the flow.

## Step 3 — Create the Redemption Process

1. **New Process** → **Redemption**.
2. Same approach as Step 2, but:
   - `EventType` ← `Debit`
   - `Points` ← `ABS($Record.TransactionAmount)` (Debit points are stored positive in the ledger; the `EventType` carries the sign semantically).
3. Activate.

## Step 4 — Tier assessment (optional)

If you want `LoyaltyMemberTier` to auto-advance when a member crosses `MinimumEligibleBalance`:

1. **New Process** → **Tier Processing**.
2. Template uses `TotalPointsAccrued` vs `LoyaltyTier.MinimumEligibleBalance` to move the member up.
3. Activate. Required only if the demo script shows tier progression in real time.

## Step 5 — Trigger scope

By default, Program Processes fire on **insert** of `TransactionJournal` records matching the process's scope (JournalType filter in the process config). Verify on each process's "Scope" tab:

- Accrual Process → `JournalType.Name == 'Accrual'`
- Redemption Process → `JournalType.Name == 'Redemption'`

## Step 6 — Backfill existing Pending journals (one-time)

Any journals the connector inserted *before* you enabled the processes will stay `Pending` forever. To backfill:

1. **Setup → Loyalty Program Processes → <process> → Run Now** — runs the process against all existing in-scope journals.
2. Or, via Apex anonymous (requires `LoyaltyManagement` permset):
   ```apex
   // Re-save journals to re-trigger process evaluation
   List<TransactionJournal> pending = [
     SELECT Id FROM TransactionJournal
     WHERE Status = 'Pending' AND OrderId != NULL
   ];
   // touch to re-fire triggers/processes
   update pending;
   ```

## Step 7 — Verify

After Steps 1–6, run this check in Dev Console / anonymous Apex:

```apex
Id memberId = '<Lauren or your test member>';
System.debug([SELECT PointsBalance, TotalPointsAccrued, TotalPointsRedeemed
              FROM LoyaltyMemberCurrency WHERE LoyaltyMemberId = :memberId
              ORDER BY PointsBalance DESC NULLS LAST LIMIT 1]);
System.debug([SELECT COUNT() FROM LoyaltyLedger WHERE LoyaltyProgramMemberId = :memberId]);
System.debug([SELECT COUNT() FROM TransactionJournal WHERE MemberId = :memberId AND Status = 'Processed']);
```

Expect:
- `PointsBalance` reflects the seed **plus** all connector-driven accruals **minus** redemptions.
- `LoyaltyLedger` has 1 row per processed journal.
- `TransactionJournal.Status = 'Processed'` for every connector-inserted journal.

---

## After enabling Program Process: no code cleanup needed

As of v1.1, the display-time delta **only counts Pending journals**. Once Program Process flips a journal to Processed (and updates `LoyaltyMemberCurrency.PointsBalance` natively), that journal automatically drops out of the delta. No double-count window, no code change required — leave `pendingJournalDelta` in place.

If you want to verify:
```apex
Id memberId = '<test member>';
// Should equal 0 once all Pending journals have been processed
System.debug([SELECT SUM(TransactionAmount) total FROM TransactionJournal
              WHERE MemberId = :memberId AND OrderId != NULL AND Status = 'Pending'][0]);
// Should reflect every Processed journal's impact
System.debug([SELECT PointsBalance FROM LoyaltyMemberCurrency
              WHERE LoyaltyMemberId = :memberId ORDER BY PointsBalance DESC LIMIT 1][0]);
```

---

## Alternative: the Connect API route (if you don't want Flow Builder)

Salesforce exposes a Connect REST endpoint that runs a Program Process on demand:

```
POST /services/data/v66.0/loyalty/programs/<programId>/program-processes/<processName>/runs
```

Body:
```json
{
  "journalIds": ["0lVg80000001uWPEAY", "..."]
}
```

You'd wrap this in an HTTP callout from Apex and invoke it from the `LoyaltyOrderTrigger` after inserting the journals. This requires a **Remote Site Setting** for the org's `my.salesforce.com` domain and a Named Credential for authentication, so it's more setup than the Flow route — usually only worth it if you want Apex-only deploys.

Until the ProgramProcess is configured, the Connect endpoint returns a 404 because the process name doesn't exist.
