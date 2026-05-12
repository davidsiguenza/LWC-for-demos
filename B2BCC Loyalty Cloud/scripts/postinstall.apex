// Post-install Apex — run AFTER the metadata deploy.
// Assigns permission sets and enrols buyer accounts into the loyalty program.
//
// Before executing, replace the placeholder IDs in the two variables below with
// the values captured in Phase 0 (Q2 = WebStoreId, Q3 = LoyaltyProgramId).
//
// Usage:
//   sf apex run --file scripts/postinstall.apex --target-org <alias>

Id webStoreId      = '000000000000000000';  // TODO Phase 0 / Q2
Id loyaltyProgramId = '000000000000000000'; // TODO Phase 0 / Q3

// -------- 1. Resolve the store's BuyerGroup members (Accounts) --------
List<BuyerGroupMember> bgms = [
    SELECT BuyerId
    FROM BuyerGroupMember
    WHERE BuyerGroup.Id IN (
        SELECT BuyerGroupId FROM WebStoreBuyerGroup WHERE WebStoreId = :webStoreId
    )
];
Set<Id> buyerAccountIds = new Set<Id>();
for (BuyerGroupMember m : bgms) buyerAccountIds.add(m.BuyerId);
System.debug('Buyer accounts in store: ' + buyerAccountIds.size());

// -------- 2. Skip accounts already enrolled --------
Set<Id> alreadyEnrolled = new Set<Id>();
for (LoyaltyProgramMember lpm : [
    SELECT AccountId FROM LoyaltyProgramMember
    WHERE LoyaltyProgramId = :loyaltyProgramId AND AccountId IN :buyerAccountIds
]) {
    alreadyEnrolled.add(lpm.AccountId);
}

// -------- 3. Create LoyaltyProgramMember for the rest --------
List<LoyaltyProgramMember> toInsert = new List<LoyaltyProgramMember>();
for (Id accId : buyerAccountIds) {
    if (alreadyEnrolled.contains(accId)) continue;
    toInsert.add(new LoyaltyProgramMember(
        LoyaltyProgramId = loyaltyProgramId,
        AccountId        = accId,
        EnrollmentDate   = System.now(),
        MemberStatus     = 'Active'
    ));
}
if (!toInsert.isEmpty()) {
    insert toInsert;
    System.debug('Enrolled new members: ' + toInsert.size());
} else {
    System.debug('All buyer accounts already enrolled. Nothing to do.');
}

// -------- 4. Assign B2BLoyalty_Buyer permset to users linked to those accounts --------
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'B2BLoyalty_Buyer' LIMIT 1];
List<User> buyerUsers = [
    SELECT Id FROM User
    WHERE IsActive = true AND Contact.AccountId IN :buyerAccountIds
];
Set<Id> existingAssignees = new Set<Id>();
for (PermissionSetAssignment a : [
    SELECT AssigneeId FROM PermissionSetAssignment
    WHERE PermissionSetId = :ps.Id AND AssigneeId IN :new Map<Id, User>(buyerUsers).keySet()
]) existingAssignees.add(a.AssigneeId);

List<PermissionSetAssignment> psaToInsert = new List<PermissionSetAssignment>();
for (User u : buyerUsers) {
    if (existingAssignees.contains(u.Id)) continue;
    psaToInsert.add(new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = u.Id));
}
if (!psaToInsert.isEmpty()) {
    insert psaToInsert;
    System.debug('Assigned B2BLoyalty_Buyer to users: ' + psaToInsert.size());
}
