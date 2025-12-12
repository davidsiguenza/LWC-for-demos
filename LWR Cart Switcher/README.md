[Install Package](https://login.salesforce.com/packaging/installPackage.apexp?p0=04t07000000xcap)

This component will give your customers the opportunity to manage different active carts and change between them during the commerce experience.

More post install instructions can be found here: https://salesforce.quip.com/EWSpAJb7BO3B

## UPDATE 11 DEC 2025 - NEW SDO Compatible

This update makes the compoent compatible with the new SDO architecture of Commerce on Core. Making some kew changes in filed names

## UPDATE 19 JAN 2024 - SHARING CAPABILITY ADDED

With this update a new **SHARING** capability have been added.

Now each cart has the **"Share"** button that shares the visibility of the car with every user that might have access to the Account that owns the Cart (through External Managed Accounts for instance).

Once a Cart is shared a **"Take Ownership"** button si displayed to each use that can see the cart and this way they can take ownership of them, make changes, and then release the ownership (if needed) with the "Release Ownership" button to give back the cart to the original owner.

## UPDATE 5 JUL 2023 - LWR STOREFRONTS

If you want to us this component on LWR website an update must be done since (currently) the CurrentUser.effectiveAccountId is not an available parameter in LWR.

In order to make it work you can download the SFDX project from [this GitHub repo](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/LWR%20Cart%20Switcher) and just deploy the "b2bleCartSwitcher" LWC to override the configuration

This way the effectiveAccountId is taken from the session context and not from the component parameter.
