# B2B Commerce × Loyalty Management — Reusable Connector

Connects a Salesforce B2B Commerce on Core storefront with Loyalty Management on SDOs, sandboxes, or production orgs.

**Start here:** [`SKILL.md`](SKILL.md) — full install guide, phase-by-phase, with all the commands that actually worked on a real org.

## TL;DR

```bash
# 1. Authenticate target org
sf org login web --alias MyTargetOrg

# 2. Deploy metadata (CMDT object → classes → LWCs → permset)
cd sfdx-source
sf project deploy start --source-dir force-app/main/default/objects       --target-org MyTargetOrg
sf project deploy start --source-dir force-app/main/default/classes force-app/main/default/triggers --target-org MyTargetOrg
sf project deploy start --source-dir force-app/main/default/lwc           --target-org MyTargetOrg
sf project deploy start --source-dir force-app/main/default/permissionsets --target-org MyTargetOrg

# 3. Edit WebStoreId + LoyaltyProgramId at the top of scripts/postinstall.apex, then:
sf apex run --file ../scripts/postinstall.apex --target-org MyTargetOrg

# 4. Wire the 4 My Account LWCs + the Cart redemption LWC in Experience Builder (SKILL.md Phase H)

# 5. Publish the site
```

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

**v1.0.0-stable** (2026-05-06) — validated end-to-end on SDO `storm.707ad0b4aed5c9`.

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
