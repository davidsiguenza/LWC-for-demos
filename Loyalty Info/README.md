# Loyalty Info Component

## Troubleshooting & Configuration

If you see "Loyalty information unavailable," ensure the following permissions are assigned to the **Community User Profile** or via a **Permission Set**:

### 1. Essential Object Permissions (Read Access)
* `LoyaltyProgram`
* `LoyaltyProgramMember`
* `LoyaltyMemberTier`
* `LoyaltyMemberCurrency`

### 2. Field Level Security (FLS)
The generic "Read" on the object is not enough. Ensure the profile has **Read Access** to these specific fields:
* **LoyaltyProgramMember**: `MembershipNumber`, `MemberStatus`, `Program` (Lookup)
* **LoyaltyMemberTier**: `Name`, `EffectiveDate`
* **LoyaltyMemberCurrency**: `PointsBalance`, `Name`
* **Voucher**: 'VoucherCode', `Status`, `ExpirationDate`, `FaceValue`, `DiscountPercent`
* **LoyaltyTierBenefit**: `Benefit` (Lookup)
* **Benefit**: `Name` `Description`


### 3. Sharing Rules
Even if the Apex class is `without sharing`, it is best practice to create a **Sharing Set** or **Sharing Rule** if using "Customer Community Plus" licenses:
* Create a Sharing Rule on `LoyaltyProgramMember` giving the user access to their own records (Match `Contact.Id` to `LoyaltyProgramMember.ContactId`).

### 4. License Check
Ensure the User actually has the **Loyalty Management** permission set license assigned.