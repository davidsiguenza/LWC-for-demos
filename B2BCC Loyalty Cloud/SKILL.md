---
name: sf-b2b-loyalty-connector
description: >-
  Connects a Salesforce B2B Commerce on Core WebStore with Loyalty Management on an SDO (Solution Demo Org) or sandbox. Runs three preflight questions (target org, WebStore, LoyaltyProgram), then deploys Apex services, four My Account LWCs (balance, transaction history, vouchers, tier progress), a Checkout redemption LWC placed on the Cart page, an Apex trigger on Order that creates Accrual + Redemption TransactionJournals on order activation, and permission sets. Uses standard Loyalty objects as the source of truth (LoyaltyProgram, LoyaltyTier, LoyaltyProgramCurrency, TransactionJournal) — LoyaltySiteMapping__mdt only carries the WebStore↔Program mapping and ratios. Use when integrating Loyalty Cloud with B2B Commerce, exposing loyalty widgets in the storefront private area, enabling points redemption at checkout, or syncing accrual/redemption to TransactionJournal. Assumes the storefront has already been provisioned by sf-b2b-demo-builder / sf-b2b-store-generator.
---

# B2B Commerce × Loyalty Management — Reusable Connector

> **Status: v1.0.0 stable (2026-05-06)**. Validated end-to-end against org `B2BCCLoyalty` (`storm.707ad0b4aed5c9@salesforce.com`) on API v66. Every phase below has deployed commands that actually worked on a real SDO.

## What you get after running this skill

| Component | What it does | Where |
|---|---|---|
| 4 My Account LWCs | Balance card, tier stepper, transaction history, vouchers | `/b2benhanced/account` sidebar entry "Loyalty" |
| 1 Checkout redemption LWC | Redeem points as a cart discount | Cart page (`/b2benhanced/cart`) |
| 1 Apex trigger + service | Creates Accrual + Redemption TransactionJournals on Order.Status → Activated | Fires automatically |
| `LoyaltySiteMapping__mdt` | Maps WebStore ↔ LoyaltyProgram + ratios (accrual / redemption / min-points) | Custom metadata |
| `B2BLoyalty_Buyer` permset | Read on loyalty objects + CRUD on CartItemPriceAdjustment | License-specific (Customer Community Plus) |
| Auto-enrolment script | Enrols every Account in the store's BuyerGroup into the LoyaltyProgram | `scripts/postinstall.apex` |

## Target environment

- **Salesforce SDO** with **B2B Commerce Enhanced** demo pack + **Loyalty Management** license active (PSLs: `LoyaltyManagementPsl`, `LoyaltyManagementLitePsl`).
- Storefront already provisioned (by `sf-b2b-demo-builder` or equivalent). This skill does not create WebStores, BuyerGroups, pricebooks, or catalogs.
- API v66 or higher.

## Maintenance rule

- When a phase runs successfully, append commands + field names confirmed valid for the current API version.
- When something breaks or changes, **replace** the affected subsection — don't stack contradictions.
- IDs below (WebStore, LoyaltyProgram, JournalType) are examples from the validation org — **always resolve fresh with SOQL** in the target org.

---

## Phase 0 — Preflight questions (mandatory)

**Hard rule:** ask the three questions below and wait for answers before touching metadata. Capture answers as session context.

### Q1 — Target org

```bash
sf org list --json
```

Format alias/username/instanceUrl and ask user to pick one, or `sf org login web --alias <new-alias>`. Set the chosen alias as default for the session — every later command uses `-o <alias>`.

### Q2 — Target WebStore

```bash
sf data query -q "SELECT Id, Name, DefaultLanguage FROM WebStore ORDER BY Name" -o <alias>
```

Capture `<WebStoreId>` and `<WebStoreName>`. Typical SDO values: `SDO - B2B Commerce Enhanced` → `0ZEg8000000RrHxGAK`.

### Q3 — Loyalty Program

```bash
sf data query -q "SELECT Id, Name, Status, Type, IsPrimary FROM LoyaltyProgram" -o <alias>
```

Options:
- **(a) Reuse existing** — user picks one → capture `<LoyaltyProgramId>`. The SDO ships with `Cirrus Loyalty` (`0lpg80000001njRAAQ`).
- **(b) Create from seed** — run `scripts/seed-loyalty.sh <alias>`. Only provisions the LoyaltyProgram skeleton; tiers + currency need manual setup in Loyalty Management UI (see `data/README.md`).
- **(c) Abort** — user wants to set up the program in the UI first.

> **Do not start Phase A** until all three answers are captured and confirmed by the user.

### Execution order

| # | Phase | Purpose |
|---|---|---|
| A | Prerequisites check | Fail fast if PSL missing, WebStore invalid, JournalType records absent |
| B | Deploy metadata (CMDT object first) | Salesforce requires the CMDT object before Apex that references it |
| C | Deploy Apex + LWCs + permset | The main deploy |
| D | Seed loyalty program | Only if Q3 option (b) |
| E | Config mapping | Create the `LoyaltySiteMapping__mdt` record |
| F | Assign permset | Every buyer user in the store gets `B2BLoyalty_Buyer` |
| G | Enrol buyers | Create `LoyaltyProgramMember` for every Account in the store's BuyerGroup |
| H | Storefront wiring | Experience Builder — new "Loyalty" page + menu entry + place LWC on Cart page |
| I | (Optional) Enable native balance updates | See `references/POST_INSTALL_LOYALTY_PROCESS.md` |
| Z | Smoke test | End-to-end walkthrough as a buyer |

---

## Phase A — Prerequisites check

```bash
# 1. PSL is active
sf data query -q "SELECT DeveloperName, Status FROM PermissionSetLicense WHERE DeveloperName = 'LoyaltyManagementPsl'" -o <alias>
# Must return 1 row with Status='Active'. If missing, user needs to activate Loyalty Management in Setup.

# 2. Core Loyalty sObjects reachable
for obj in LoyaltyProgram LoyaltyProgramMember LoyaltyMemberCurrency TransactionJournal JournalType; do
  sf data query -q "SELECT COUNT() FROM ${obj}" -o <alias>
done

# 3. WebStore is the right one
sf data query -q "SELECT Id, Name FROM WebStore WHERE Id = '<WebStoreId>'" -o <alias>

# 4. Required JournalType records exist (ship with the Loyalty package; both are mandatory for this connector)
sf data query -q "SELECT Id, Name FROM JournalType WHERE Name IN ('Accrual','Redemption')" -o <alias>
```

⚠️ **Schemas drift between releases.** Before coding anything new, run `sf sobject describe --sobject <ObjectName>` and diff against `references/LOYALTY_DATA_MODEL.md`. Known gotchas in this API version (v66):
- `LoyaltyProgram` has `Type` (picklist `LOYALTY_PROGRAM`) — **no** `StartDate`, **no** `ProgramType`.
- `LoyaltyProgramMember` uses `ProgramId`, not `LoyaltyProgramId`.
- `LoyaltyMemberCurrency.LoyaltyMemberId`, not `LoyaltyProgramMemberId`.
- `LoyaltyTier.SequenceNumber`, not `TierSequenceNumber`. Thresholds live on `MinimumEligibleBalance` / `MaximumEligibleBalance`.
- `JournalType` / `JournalSubType` are first-class sObjects (~17 records ship with the demo), not picklists. Reference via `TransactionJournal.JournalTypeId`.

---

## Phase B — Deploy metadata (CMDT object first)

```bash
cd /path/to/B2BCCLoyaltyCloud/sfdx-source

# Object + fields FIRST. If Apex references the CMDT before the object exists, compile fails.
sf project deploy start --source-dir force-app/main/default/objects --target-org <alias> --wait 10
```

Expect: `LoyaltySiteMapping__mdt` + 5 fields (WebStoreId, LoyaltyProgramId, AccrualRatio, RedemptionRatio, MinPointsToRedeem) created.

## Phase C — Deploy Apex + LWCs + permset

```bash
# Apex classes + trigger
sf project deploy start --source-dir force-app/main/default/classes force-app/main/default/triggers --target-org <alias> --wait 10

# LWCs
sf project deploy start --source-dir force-app/main/default/lwc --target-org <alias> --wait 10

# Permission set
sf project deploy start --source-dir force-app/main/default/permissionsets --target-org <alias> --wait 10
```

> **Known issue — CMDT records via SOAP**: deploying `force-app/main/default/customMetadata/` via SOAP on SDOs fails with `UNKNOWN_EXCEPTION` (not a hang — it returns immediately with `numberComponentsTotal: 0`). Skip this step entirely and create the record in Phase E via Apex anonymous or Setup UI. `LoyaltyAccountController` falls back to `LoyaltyProgram WHERE IsPrimary = true` when the mapping record is missing, so the demo keeps working without it.

> **Known issue — source tracking conflicts when deploying from the package directory**: running `sf project deploy start --source-dir ...` from `B2BCCLoyaltyCloud/sfdx-source/` fails with `UNKNOWN_EXCEPTION` on classes/triggers if the target org already has components tracked under a different project (e.g. the org was previously used by another SFDX project). The root cause is the source-tracking DB disagreeing with org state. **Reliable fix**: copy the relevant `force-app/main/default/` subdirs into the target project's own `force-app` directory and run all `sf project deploy` commands from there instead.

> **Permset license**: `B2BLoyalty_Buyer.permissionset-meta.xml` is currently keyed to `Customer Community Plus`. If your target org uses a different buyer license (e.g. Partner Community), **delete and recreate** the permset with the correct license — `license` is not editable post-deploy. Delete by `sf data delete record --sobject PermissionSet --record-id <id>` then re-deploy.

## Phase D — Seed loyalty program

Only run this if Q3 chose option (b). Otherwise skip.

```bash
./scripts/seed-loyalty.sh <alias>
```

This imports `data/sample-loyalty-program.json` — only the `LoyaltyProgram` record. Tiers + LoyaltyProgramCurrency must be created manually in the Loyalty Management app (too much schema drift between releases to script them reliably). See `data/README.md`.

## Phase E — Config mapping

Create one `LoyaltySiteMapping__mdt` record linking the WebStore to the LoyaltyProgram. Three ways, in order of preference:

1. **Apex anonymous** (works everywhere):

    ```apex
    Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
    cmd.fullName = 'LoyaltySiteMapping__mdt.SDO_B2B';
    cmd.label = 'SDO B2B Loyalty';  // ⚠️ max 40 chars — "SDO B2B Store → <Program>" is too long!

    for (Map<String, Object> f : new List<Map<String, Object>>{
        new Map<String, Object>{ 'field' => 'WebStoreId__c', 'value' => '<WebStoreId>' },
        new Map<String, Object>{ 'field' => 'LoyaltyProgramId__c', 'value' => '<LoyaltyProgramId>' },
        new Map<String, Object>{ 'field' => 'AccrualRatio__c', 'value' => 0.01 },
        new Map<String, Object>{ 'field' => 'RedemptionRatio__c', 'value' => 10 },
        new Map<String, Object>{ 'field' => 'MinPointsToRedeem__c', 'value' => 100 }
    }) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = (String) f.get('field');
        v.value = f.get('value');
        cmd.values.add(v);
    }

    Metadata.DeployContainer container = new Metadata.DeployContainer();
    container.addMetadata(cmd);
    Metadata.Operations.enqueueDeployment(container, null);
    ```

2. **Setup UI**: Setup → Custom Metadata Types → `Loyalty Site Mapping` → New → fill the 5 fields.

3. **Skip entirely** — controller fallback picks `LoyaltyProgram.IsPrimary = true` and defaults the ratios (10:1 redemption, 0.01 accrual, no minimum).

## Phase F — Assign permset to buyer users

`scripts/postinstall.apex` auto-assigns `B2BLoyalty_Buyer` to every active user in the store's BuyerGroup. Before running, edit the two IDs at the top:

```apex
Id webStoreId      = '<WebStoreId>';       // Phase 0 / Q2
Id loyaltyProgramId = '<LoyaltyProgramId>'; // Phase 0 / Q3
```

Run:
```bash
sf apex run --file scripts/postinstall.apex --target-org <alias>
```

Expect `Enrolled new members: N` + `Assigned B2BLoyalty_Buyer to users: N` in the debug log.

> **Critical — don't skip this phase**: without `B2BLoyalty_Buyer` the buyer user has no access to the Apex classes (`LoyaltyAccountController`, `LoyaltyRedemptionController`) or to the Loyalty objects (LoyaltyProgramMember, LoyaltyMemberCurrency, LoyaltyTier, TransactionJournal, Voucher). The LWCs will render with the "Could not load loyalty data" error message or silently show "You are not enrolled" — which is identical to a missing member and hard to debug. **Always check this first when the widgets show no data.**

> **Individual assignment** (when postinstall.apex was not run or missed a user): run directly from Developer Console or sf apex run:
> ```apex
> Id userId = '<buyerUserId>';  // User.Id of the specific buyer
> PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'B2BLoyalty_Buyer' LIMIT 1];
> insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
> ```
> If you get `DUPLICATE_VALUE`, the permset is already assigned — that's fine.

## Phase G — Enrol buyers into the LoyaltyProgram

Same `scripts/postinstall.apex` (Phase F) handles this — it creates `LoyaltyProgramMember` rows for every BuyerGroup member that isn't enrolled yet. Uses `AccountId` binding.

> **B2B vs Cirrus seed convention**: the Cirrus demo pack enrols members by `ContactId` (see Lauren Bailey, `0lMg80000001q6DEAQ`). `LoyaltyAccountController` queries `WHERE AccountId = :accountId OR ContactId = :contactId`, so both conventions coexist. If you re-enrol manually, prefer `AccountId` for new B2B demos.

## Phase H — Storefront wiring

Two approaches — **metadata** (faster, repeatable) or **Experience Builder** (visual). Use metadata when you already have the site's `DigitalExperience` project locally; use Experience Builder when you don't.

### Option A — Metadata deploy (recommended for existing SFDX projects)

This is reliable when the site workspace is already in your project. Validated on `SDO_B2B_Commerce_Enhanced1`.

**H.1 — Create route**

`force-app/main/default/digitalExperiences/site/<SiteName>/sfdc_cms__route/MyLoyalty__c/_meta.json`:
```json
{ "apiName": "MyLoyalty__c", "type": "sfdc_cms__route", "path": "routes" }
```

`force-app/main/default/digitalExperiences/site/<SiteName>/sfdc_cms__route/MyLoyalty__c/content.json`:
```json
{
  "type": "sfdc_cms__route",
  "title": "My Loyalty",
  "contentBody": {
    "activeViewId": "myLoyalty",
    "configurationTags": [],
    "pageAccess": "UseParent",
    "routeType": "custom-my-loyalty",
    "urlPrefix": "my-loyalty"
  },
  "urlName": "my-loyalty"
}
```

> ⚠️ Custom routes **must** use the `__c` suffix on the folder/apiName and `custom-<name>` on `routeType`. Not obvious, causes a deploy error otherwise.

**H.2 — Create view**

`force-app/main/default/digitalExperiences/site/<SiteName>/sfdc_cms__view/myLoyalty/_meta.json`:
```json
{ "apiName": "myLoyalty", "type": "sfdc_cms__view", "path": "views" }
```

`force-app/main/default/digitalExperiences/site/<SiteName>/sfdc_cms__view/myLoyalty/content.json`:
```json
{
  "type": "sfdc_cms__view",
  "title": "My Loyalty",
  "contentBody": {
    "component": {
      "children": [
        { "children": [ /* title section — clone from myProfile */ ], ... },
        {
          "attributes": { "sectionConfig": "{\"UUID\":\"...\",\"columns\":[{\"columnWidth\":\"2\",...},{\"columnWidth\":\"10\",...}]}" },
          "children": [
            { "children": [
              { "definition": "commerce_builder:navigationMenuItemList", "attributes": { "navigationLinkSetDevName": "B2B_My_Account_Menu" } }
            ] },
            { "children": [
              { "definition": "c:loyaltyBalanceCard",        "attributes": { "webStoreId": "<WebStoreId>" } },
              { "definition": "c:loyaltyTierProgress",       "attributes": { "webStoreId": "<WebStoreId>" } },
              { "definition": "c:loyaltyVouchers",           "attributes": { "webStoreId": "<WebStoreId>" } },
              { "definition": "c:loyaltyTransactionHistory", "attributes": { "webStoreId": "<WebStoreId>" } }
            ] }
          ],
          "definition": "community_layout:section"
        }
      ],
      "definition": "community_layout:sldsFlexibleLayout"
    },
    "dataProviders": [],
    "themeLayoutType": "Inner",
    "viewType": "custom-my-loyalty"
  },
  "urlName": "my-loyalty"
}
```

> ⚠️ **`webStoreId` is required on each LWC attribute.** Without it `@wire getMemberSummary(webStoreId)` is called with `undefined`, the wire adapter never fires, and the components render the "not enrolled" empty state — which looks identical to a permission error. Set `webStoreId` explicitly on every loyalty LWC.

**H.3 — Add menu item**

In `navigationMenus/<SiteName>_My_Account_Menu.navigationMenu-meta.xml` (check the exact filename with `sf data query -q "SELECT DeveloperName FROM NavigationMenu WHERE Label = 'B2B My Account Menu'"` and look for the matching file):
```xml
<navigationMenuItem>
    <label>Loyalty</label>
    <position>10</position>
    <publiclyAvailable>false</publiclyAvailable>
    <target>/my-loyalty</target>
    <type>InternalLink</type>
</navigationMenuItem>
```

**H.4 — Deploy in order**

```bash
# 1. Route + view FIRST (nav menu references the URL — can't deploy nav menu before route exists)
sf project deploy start \
  --source-dir force-app/main/default/digitalExperiences/site/<SiteName>/sfdc_cms__route/MyLoyalty__c \
  --source-dir force-app/main/default/digitalExperiences/site/<SiteName>/sfdc_cms__view/myLoyalty \
  --target-org <alias> --ignore-conflicts

# 2. Then nav menu
sf project deploy start \
  --source-dir force-app/main/default/navigationMenus/B2B_My_Account_Menu.navigationMenu-meta.xml \
  --target-org <alias>

# 3. Publish
sf community publish --name "<SiteName>" --target-org <alias>
```

> ⚠️ Deploying the nav menu before the route is created causes `No page found in site for URL path /my-loyalty`. Always deploy route+view first, nav menu second.

---

### Option B — Experience Builder (visual, no SFDX project needed)

1. Open Experience Builder for the target site (e.g. `SDO - B2B Commerce Enhanced`).
2. **New page** "My Loyalty":
   - Clone from My Profile (keeps the sidebar navigation intact).
   - URL slug: `my-loyalty`.
   - In the right column, drop the 4 LWCs top-to-bottom:
     - `Loyalty — Balance`
     - `Loyalty — Tier Progress`
     - `Loyalty — Vouchers`
     - `Loyalty — Transaction History`
   - For each LWC, set the **WebStore Id** property in the property panel to `<WebStoreId>`. ⚠️ Do not leave it blank — see Option A warning above.
3. **Add menu item** to `B2B My Account Menu`:
   - Edit the Navigation List Menu on My Profile.
   - Add Menu Item → Name `Loyalty`, Type `Site Page`, Page = the one you just created.
   - Save menu.
4. **Cart page** — drop `Loyalty — Checkout Redemption` into the Cart page (`/cart`), sidebar, above Coupon Codes. Do NOT place it on the Checkout page itself — the Commerce LWR checkout uses its own extension model and breaks with generic LWCs (status 404 on `cart_view`).
5. **Publish** the site.

Known behaviour: after clicking "Apply points" in the checkout redemption widget, `window.location.reload()` fires so the stock Cart Summary re-fetches. This is because `commerce/cartApi` module is not available via static import in custom LWCs and dynamic imports are blocked by the LWC compiler.

## Phase I — Enable native balance updates (optional, production)

Out of the box this connector shows an **effective balance** = seed `PointsBalance` + SUM(connector-inserted `TransactionJournal` without an associated `LoyaltyLedger`). That's a display-time computation in `LoyaltyAccountController.populateBalance` — the `LoyaltyMemberCurrency.PointsBalance` field itself is read-only and only the native `LoyaltyProgramProcess` engine updates it (via creating a `LoyaltyLedger` row).

The `Loyalty_Run_Process_on_TJ_Pending` Flow is **deployed and active** — it auto-invokes `runProgramProcessForTransactionJournal` on every Pending journal this connector inserts. While there's no Program Process configured, the action is a no-op (no ledger created; the delta keeps the balance correct). Once an admin configures Accrual + Redemption Program Processes in Setup, the Flow automatically routes each journal through the right process, ledgers get created, `PointsBalance` updates natively, and those journals drop out of our delta — no code change.

For production rollouts, follow `references/POST_INSTALL_LOYALTY_PROCESS.md` to:
1. Configure Accrual + Redemption Program Processes in Setup.
2. Backfill existing unprocessed journals by re-saving them (the Flow fires again on update) or via the Program Process "Run Now" UI.

**Self-healing**: the delta counts journals that **don't have a ledger**. A journal's ledger appearance atomically removes it from the delta and adds it to `PointsBalance` — the widget stays correct before, during, and after Program Process configuration.

## Phase Z — Smoke test checklist

As a buyer (e.g. Lauren Bailey in the validation org):

1. ✓ Login → navigate to Account → Loyalty menu → 4 cards visible, no "Apex request is invalid".
2. ✓ Balance card shows non-zero balance + tier name.
3. ✓ Tier progress stepper shows N tiers with current one highlighted in tier color.
4. ✓ Transaction History shows at least the seed journals.
5. ✓ Cart page → add items → widget "Redeem Loyalty Points" shows available + ratio.
6. ✓ Enter points → Apply → success message → page reloads → item-level discount visible.
7. ✓ Complete checkout → Order confirmation shows the discount in the summary.
8. ✓ `Order.Status = Activated` → `LoyaltyOrderTrigger` fires → 2 `TransactionJournal` rows appear (Accrual + Redemption).
9. ✓ Back to Loyalty → balance reflects the new journals (effective balance drops by redemption, rises by accrual).

---

## Architecture reference

### Files

```
B2BCCLoyaltyCloud/
├── SKILL.md                               (this file)
├── references/
│   ├── LOYALTY_DATA_MODEL.md              — field-level cheatsheet validated against API v66
│   ├── REDEMPTION_FLOW.md                 — sequence diagram of the cart redemption
│   ├── ACCRUAL_FLOW.md                    — current Apex impl + original Platform Event design
│   └── POST_INSTALL_LOYALTY_PROCESS.md    — Phase I instructions
├── sfdx-source/
│   ├── sfdx-project.json                  — API v66
│   └── force-app/main/default/
│       ├── classes/
│       │   ├── LoyaltyAccountController.cls       — My Account (4 widgets)
│       │   ├── LoyaltyRedemptionController.cls    — Cart redemption
│       │   └── LoyaltyOrderJournalService.cls     — Accrual + Redemption journals on Order activation
│       ├── triggers/
│       │   └── LoyaltyOrderTrigger.trigger        — Order after update → Activated
│       ├── flows/
│       │   └── Loyalty_Run_Process_on_TJ_Pending.flow-meta.xml — auto-invokes runProgramProcessForTransactionJournal on every new Pending journal
│       ├── lwc/
│       │   ├── loyaltyBalanceCard/
│       │   ├── loyaltyTierProgress/
│       │   ├── loyaltyTransactionHistory/
│       │   ├── loyaltyVouchers/
│       │   └── loyaltyCheckoutRedemption/
│       ├── objects/LoyaltySiteMapping__mdt/       — object + 5 fields
│       ├── customMetadata/                         — one record (SDO default); may fail to deploy via SOAP
│       └── permissionsets/
│           └── B2BLoyalty_Buyer.permissionset-meta.xml
├── data/
│   ├── sample-loyalty-program.json        — minimal LoyaltyProgram seed
│   └── README.md                          — notes on manual tier/currency setup
└── scripts/
    ├── deploy.sh                          — single-command full deploy
    ├── seed-loyalty.sh                    — Phase D
    └── postinstall.apex                   — Phases F + G
```

### Control flow

**My Account widgets** → `@wire getMemberSummary(webStoreId)` → `LoyaltyAccountController`:
1. `resolveProgramIdForStore(webStoreId)` — first from `LoyaltySiteMapping__mdt`, fallback to `LoyaltyProgram.IsPrimary = true`.
2. `resolveBuyerAccountId()` + `resolveBuyerContactId()` — from running User.
3. Find `LoyaltyProgramMember WHERE ProgramId = :p AND (AccountId = :a OR ContactId = :c)`.
4. Populate balance + tier + stepper + connector journal delta.

**Redemption** → `loyaltyCheckoutRedemption` LWC → `LoyaltyRedemptionController.applyRedemption(cartId, webStoreId, points)`:
1. Validate balance + min.
2. Remove any prior loyalty adjustments on this cart (identified by `CartItemPriceAdjustment.Name = 'Loyalty Points Redemption'`).
3. Prorate the discount across cart items; create one `CartItemPriceAdjustment` per item.
4. `rollUpAdjustmentsToCart` — write `CartItem.TotalAdjustmentAmount` + `AdjustmentAmount` + `TotalPriceAfterAllAdjustments`.
5. LWC fires `window.location.reload()` so stock summaries re-fetch.

**Accrual + Redemption journals** → `LoyaltyOrderTrigger` (after update on `Order`) → `LoyaltyOrderJournalService.processOrders(orderIds)`:
1. Aggregate `OrderItemAdjustmentLineItem` rows tagged `Loyalty Points Redemption` — compute points redeemed.
2. Compute accrual: `Order.TotalAmount * AccrualRatio` (default `0.01`).
3. Resolve member via Account → BillTo/ShipToContact → any Contact on the Account.
4. Insert 2 `TransactionJournal` rows per order (Redemption negative, Accrual positive).
5. Flip Status → Processed (best effort; no-op if Program Process not configured).

### Key design decisions

- **LoyaltySiteMapping__mdt is the only config** — tiers, ratios, and program settings live on standard Loyalty objects. The custom metadata type only carries the WebStore↔Program mapping and 3 tunable knobs.
- **Display-time balance delta** (not a DB field) — lets the widget show the correct balance when `LoyaltyProgramProcess` isn't configured, while being obvious to remove once it is.
- **Discretionary CartItemPriceAdjustment** (not CartAdjustmentGroup) — AdjustmentSource = `Discretionary` keeps the discount independent of Promotions and easy to filter out from Apex.
- **Name-based marker** — we identify our own adjustments by `CartItemPriceAdjustment.Name = 'Loyalty Points Redemption'`, because `Description` is a textarea and can't be filtered in SOQL.
- **Account + Contact enrolment fallback** — Cirrus demo seeds members by Contact, B2B production convention is Account; the connector accepts either.

### Known gotchas (carry to the next deploy)

| # | Gotcha | Why | How to recover |
|---|---|---|---|
| 1 | CMDT records fail during SOAP deploy with `UNKNOWN_EXCEPTION` | SDO quirk — `numberComponentsTotal: 0`, no useful error | Create via Apex anonymous (Phase E) or Setup UI |
| 2 | Permset license not editable | Salesforce platform rule | Delete + redeploy; or ship multiple permsets keyed to each license |
| 3 | `recordId` is null on Cart page | Commerce LWR doesn't populate it | Apex auto-discovers via `resolveActiveCartId` (Status IN Active/Checkout + OwnerId = running user) |
| 4 | `@wire` with `$cartId` never fires | LWR strict with undefined reactive params | Use imperative call from `connectedCallback` |
| 5 | Checkout page 404 (`cart_view`, `checkout_view`) | LWC dropped on Checkout page breaks the bundle | Place LWC on Cart page only; Checkout needs a Commerce subflow |
| 6 | `CartItem*PriceAdjustment` doesn't recalc cart totals | Commerce pricing engine only fires on specific actions | Patch `CartItem` aggregate fields ourselves; `WebCart.TotalAmount` stays stale until real pricing action |
| 7 | `LoyaltyMemberCurrency.PointsBalance` is read-only | Salesforce platform rule | Use display-time delta (demo) or configure `LoyaltyProgramProcess` (prod) |
| 8 | `Order.ContactId` doesn't exist | Release-dependent | Use `BillToContactId` + `ShipToContactId` + fallback to `Contact WHERE AccountId = Order.AccountId` |
| 9 | LWCs show "not enrolled" or empty — but member exists | `webStoreId` attribute not set on the LWC in the page view | Set `webStoreId` explicitly (Phase H, Option A) or via Experience Builder property panel |
| 10 | LWCs show error "Apex request is invalid" — but member exists | `B2BLoyalty_Buyer` permset not assigned to the buyer | Assign permset (Phase F individual assignment); confirm with `PermissionSetAssignment` query |
| 11 | Source tracking conflicts when deploying from `sfdx-source/` dir | SDO org already tracked by a different project in source tracking DB | Copy metadata dirs into the target project's `force-app/` and deploy from there |
| 12 | CMDT record label max 40 chars | Platform field limit | Keep label ≤ 40 chars: "SDO B2B Commerce Enhanced Loyalty" (33) is fine; "SDO B2B Commerce Enhanced to Cirrus Loyalty" (45) fails |
| 13 | Nav menu deploy fails with "No page found for URL path" | Nav menu deployed before the route exists | Deploy route+view first, nav menu second (see Phase H.4 order) |
| 14 | Custom route `__c` suffix missing → "To create custom route, suffix with `__c`" | LWR custom route naming convention | Route folder AND `apiName` in `_meta.json` must end in `__c`; `routeType`/`viewType` must use `custom-<name>` |

---

## Reference resources

- **Loyalty Management cheatsheet**: `references/LOYALTY_DATA_MODEL.md` (field-level, validated).
- **B2B Commerce LWC repo**: [forcedotcom/b2b-commerce-open-source-components](https://github.com/forcedotcom/b2b-commerce-open-source-components/tree/main/force-app/main/default/sfdc_cms__lwc) — source of truth for stock LWCs.
- **Parent skill**: `sf-b2b-demo-builder` (builds the storefront this connector plugs into).

---

## Work log

| Date | Phase | Change | Notes |
|------|-------|--------|-------|
| 2026-05-05 | Scaffold | Project skeleton + SKILL.md outline | No metadata deployed yet. |
| 2026-05-05 | Phase A (validation) | Verified against org `B2BCCLoyalty` (API v66). Cirrus pack present: program `0lpg80000001njRAAQ`, tier group `0ltg80000001mPBAAY`, 3 tiers, 1 existing member. WebStore `SDO - B2B Commerce Enhanced` (`0ZEg8000000RrHxGAK`). | Corrected `LOYALTY_DATA_MODEL.md` for v66 field names. Corrected seed JSON. |
| 2026-05-05 | My Account (build + deploy) | `LoyaltyAccountController`, `LoyaltySiteMapping__mdt` object, 4 LWCs. Smoke tested with Lauren. | CMDT record deploy hangs — controller has fallback to `IsPrimary` program. |
| 2026-05-05 | Storefront wiring | Built Experience Builder page + menu entry. `B2BLoyalty_Buyer` permset (Customer Community Plus) assigned to 8 buyer users. ContactId fallback in controller. | Permset license not editable; may need variants per license. |
| 2026-05-05 | Tier stepper | `LoyaltyAccountController.populateTier` now returns `TierStep[]`. LWC is a circular-marker stepper adaptive to N tiers, reading `Color` from `LoyaltyTier`. Seeded Cirrus thresholds (Bronze 0–499, Silver 500–1999, Gold 2000+). Promoted Lauren to Silver. | Fully auto-adaptive — add a tier in Setup and the stepper picks it up. |
| 2026-05-05 | Redemption | `LoyaltyRedemptionController` + `loyaltyCheckoutRedemption` LWC. `CartItemPriceAdjustment` prorated across items. Permset extended with Cart + CartItemPriceAdjustment (C/R/U/D). LWC uses imperative Apex call (not `@wire`) + `window.location.reload()` after apply. | Checkout page breaks with LWCs — use Cart page only. `WebCart.TotalAmount` is read-only so Cart Summary shows pre-discount total until Commerce recalcs (cosmetic; order confirmation is correct). |
| 2026-05-05 | Accrual + balance delta | `LoyaltyOrderJournalService` + `LoyaltyOrderTrigger` on Order activation. Member resolution with Account→Contact fallback. `LoyaltyAccountController` adds SUM of connector journals to seed balance. Documented trade-off in `references/POST_INSTALL_LOYALTY_PROCESS.md`. | `LoyaltyMemberCurrency.PointsBalance` is read-only; Program Process required for native updates. |
| 2026-05-06 | v1.0.0 stable | SKILL.md rewritten as executable guide reflecting real implementation. Tagged `v1.0.0-stable` in git. | Next: robustness work (TBD with user). |
| 2026-05-29 | Second org deploy | Deployed into `dentaid` (`storm.0cf5298163cad6`) — SDO B2B Commerce Enhanced, WebStore `0ZEJ6000000lEJdOAM`, Cirrus Loyalty `0lpJ6000000xVzXIAU`. Surfaced 6 new issues (gotchas 9–14). Page built via metadata (Option A in Phase H) instead of Experience Builder. | New issues: (1) CMDT SOAP deploy returns `UNKNOWN_EXCEPTION` immediately (not a hang); (2) source-tracking conflicts when deploying from package dir → copy to project; (3) `webStoreId` attribute mandatory on LWCs; (4) `B2BLoyalty_Buyer` not auto-assigned when postinstall.apex not run; (5) CMDT label 40-char limit; (6) nav-menu-before-route ordering error. All documented in gotchas + phases. |
