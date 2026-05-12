# Seed data

## `sample-loyalty-program.json`

Minimal `LoyaltyProgram` record to bootstrap a demo when the target org has no program yet. The accompanying tiers and currency records need to be created in the UI (or added to this tree import once the exact field set for the current API version is confirmed on a real SDO) — they're kept out of this file for now because `LoyaltyTier` and `LoyaltyProgramCurrency` required-field shape drifts across releases.

### Usage

```bash
sf data tree import -p data/sample-loyalty-program.json -o <alias>
```

After the program is created, in the Loyalty Management app:
1. Add 3 tiers (e.g. `Silver`, `Gold`, `Platinum`) on a `LoyaltyTierGroup`.
2. Add one `LoyaltyProgramCurrency` of type `Points` with the exchange ratio you want (e.g. 10 points = 1 monetary unit).
3. Activate the program.

Then persist the resulting `LoyaltyProgramId` as the Phase 0 / Question 3 answer.

## `sample-members.csv` _(not yet present)_

Reserved for Phase F — buyer enrolment seed. Will be generated from the target org's BuyerGroup members at runtime, not committed.
