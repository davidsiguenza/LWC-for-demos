# Salesforce DX Project: Next Steps

Now that you’ve created a Salesforce DX project, what’s next? Here are some documentation resources to get you started.

## Schedule Appointment LWC (Experience Cloud / LWR Storefront)

This project includes a **Schedule Appointment** Lightning Web Component for Experience Cloud (LWR) storefronts.

### Features

- **Configurable button** – "Schedule an appointment" by default; the label can be changed in Experience Builder (**Button label** property).
- **Calendar** – Opens from today; users pick a date (past dates disabled).
- **Time slots** – 8 slots per day, 1 hour each (10:00–18:00). Shows **Filled** (1–2 mock-filled per day) and **Booked** (user's selection).
- **Person Account integration** – Saves each booking to the **Description** field of the Person Account linked to the logged-in Experience Cloud user (`User.ContactId` → `Contact.AccountId`). Format: `[Appointment] YYYY-MM-DD HH:00 - HH:00`.

### Setup

1. **Deploy** – Push the `force-app` source to your org (or deploy via your CI).
2. **Experience Builder** – Add the **Schedule Appointment** component to a Community/Experience Cloud page. Use the component's properties to set the button label.
3. **Apex access** – Grant **ScheduleAppointmentController** to the Experience Cloud profile(s) used by your site (Setup → Profiles → your community profile → Enabled Apex Class Access).
4. **Person Account** – Ensure your Experience Cloud users are linked to Person Accounts (e.g. Customer Community users with `ContactId` → Contact → Account). The controller uses `Contact.AccountId` as the Person Account.

### Targets

- `lightningCommunity__Page` and `lightningCommunity__Default` – Experience Builder.
- `lightning__AppPage` – Lightning App Builder.

### Tests

- **Apex:** `ScheduleAppointmentControllerTest` – Covers error cases and, when Communities is enabled and a "Customer Community Login User" profile exists, the full booking flow.
- **LWC:** `scheduleAppointment.test.js` – Unit tests for the component.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
