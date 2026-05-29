# B2B Commerce × Loyalty Management — Reusable Connector

Connects a Salesforce B2B Commerce on Core storefront with Loyalty Management on SDOs, sandboxes, or production orgs.

**Start here:** [`SKILL.md`](SKILL.md) — full install guide, phase-by-phase, with all the commands that actually worked on a real org.

## TL;DR

```bash
# 1. Authenticate target org
sf org login web --alias MyTargetOrg

# 2. Copy package files into your SFDX project (avoids source-tracking conflicts)
cp -r sfdx-source/force-app/main/default/* /path/to/your/project/force-app/main/default/
cd /path/to/your/project

# 3. Deploy in strict order (each step depends on the previous)
sf project deploy start --source-dir force-app/main/default/objects/LoyaltySiteMapping__mdt \
                        --source-dir force-app/main/default/objects/Order_Completed__e \
                        --target-org MyTargetOrg
sf project deploy start --source-dir force-app/main/default/classes/LoyaltyAccountController.cls \
                        --source-dir force-app/main/default/classes/LoyaltyAccountController.cls-meta.xml \
                        --source-dir force-app/main/default/classes/LoyaltyOrderJournalService.cls \
                        --source-dir force-app/main/default/classes/LoyaltyOrderJournalService.cls-meta.xml \
                        --source-dir force-app/main/default/classes/LoyaltyRedemptionController.cls \
                        --source-dir force-app/main/default/classes/LoyaltyRedemptionController.cls-meta.xml \
                        --source-dir force-app/main/default/triggers/LoyaltyOrderTrigger.trigger \
                        --source-dir force-app/main/default/triggers/LoyaltyOrderTrigger.trigger-meta.xml \
                        --target-org MyTargetOrg
sf project deploy start --source-dir force-app/main/default/lwc/loyaltyBalanceCard \
                        --source-dir force-app/main/default/lwc/loyaltyTierProgress \
                        --source-dir force-app/main/default/lwc/loyaltyTransactionHistory \
                        --source-dir force-app/main/default/lwc/loyaltyVouchers \
                        --source-dir force-app/main/default/lwc/loyaltyCheckoutRedemption \
                        --source-dir force-app/main/default/lwc/loyaltyCartRefresher \
                        --target-org MyTargetOrg
sf project deploy start --source-dir force-app/main/default/permissionsets \
                        --source-dir force-app/main/default/flows \
                        --target-org MyTargetOrg

# 4. Create the CMDT mapping record via Apex (SOAP deploy fails with UNKNOWN_EXCEPTION — skip it)
#    Label MUST be ≤ 40 chars. Edit IDs before running:
sf apex run --file ../scripts/create-cmdt.apex --target-org MyTargetOrg

# 5. Assign permset + enrol buyers — edit WebStoreId/LoyaltyProgramId at the top first:
sf apex run --file ../scripts/postinstall.apex --target-org MyTargetOrg

# 6. Wire page + menu (SKILL.md Phase H: metadata option or Experience Builder)
#    ⚠️ Each LWC needs webStoreId attribute set — do NOT leave it blank

# 7. Publish the site
sf community publish --name "<SiteName>" --target-org MyTargetOrg
```

> **If widgets show empty / no data after deploy**, check in this order:
> 1. `B2BLoyalty_Buyer` permset assigned? → `sf data query -q "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '<userId>' AND PermissionSet.Name = 'B2BLoyalty_Buyer'" -o MyTargetOrg`
> 2. `webStoreId` attribute set on each LWC in the page view?
> 3. `LoyaltySiteMapping__mdt` record exists with correct WebStoreId + LoyaltyProgramId?
> 4. `LoyaltyProgramMember` exists for the user's AccountId or ContactId?

## What this gives you

| Area | Component | Where the user sees it |
|---|---|---|
| **My Account** | `loyaltyBalanceCard` | Balance + membership + current tier |
| | `loyaltyTierProgress` | N-tier circular stepper with progress |
| | `loyaltyTransactionHistory` | Paginated journal history |
| | `loyaltyVouchers` | Issued voucher list |
| **Checkout** | `loyaltyCheckoutRedemption` | Redeem points → cart discount, on Cart page |
| **Backend** | `LoyaltyOrderTrigger` + service | On order activation, writes Accrual + Redemption `TransactionJournal` rows |
| **Config** | `LoyaltySiteMapping__mdt` | WebStore ↔ LoyaltyProgram + 3 ratio knobs |

## Stable version

**v1.1.0** (2026-05-29) — second org deploy validated on `storm.0cf5298163cad6` (Dentaid SDO). 6 new gotchas documented, Phase H updated with metadata option, TL;DR rewritten.
**v1.0.0** (2026-05-06) — initial validation on `storm.707ad0b4aed5c9`.

## Requirements

- Salesforce SDO / sandbox / scratch org with **Loyalty Management** license (`LoyaltyManagementPsl`).
- Existing B2B Commerce WebStore (provisioned by `sf-b2b-demo-builder` or equivalent).
- API v66+.
- `sf` CLI authenticated against the target org.

## What this does NOT do

- Create WebStores, BuyerGroups, pricebooks, or product catalogs — use `sf-b2b-demo-builder` first.
- Configure `LoyaltyProgramProcess` rules — see `references/POST_INSTALL_LOYALTY_PROCESS.md` for that optional production step.
- Deploy Experience Builder layout changes — storefront wiring is manual (Phase H).

## License

Demo tooling — no license attached. Use internally for Salesforce demos / proofs of concept.
