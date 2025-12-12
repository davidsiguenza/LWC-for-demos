public without sharing class LoyaltyInfoController {

    @AuraEnabled(cacheable=true)
    public static LoyaltyDetails getMemberDetails() {
        try {
            // 1. Get User Context
            Id userId = UserInfo.getUserId();
            List<User> users = [SELECT ContactId, AccountId FROM User WHERE Id = :userId LIMIT 1];
            
            if (users.isEmpty() || users[0].ContactId == null) {
                return null;
            }

            String contactId = users[0].ContactId;

            // 2. Get Member Info
            List<LoyaltyProgramMember> members = [
                SELECT Id, MembershipNumber, Program.Name, MemberStatus 
                FROM LoyaltyProgramMember 
                WHERE ContactId = :contactId 
                ORDER BY LastModifiedDate DESC 
                LIMIT 1
            ];

            if (members.isEmpty()) {
                return null; 
            }

            LoyaltyProgramMember mem = members[0];
            String memId = mem.Id;

            LoyaltyDetails details = new LoyaltyDetails();
            details.programName = (mem.Program != null) ? mem.Program.Name : 'Loyalty Program';
            details.membershipNumber = mem.MembershipNumber;

            // 3. Get Active Tier Name (e.g., "Bronze")
            // We ignore the lookup ID since it might be null. We just want the Name.
            List<LoyaltyMemberTier> memberTiers = [
                SELECT Name 
                FROM LoyaltyMemberTier 
                WHERE LoyaltyMemberId = :memId 
                ORDER BY EffectiveDate DESC 
                LIMIT 1
            ];
            
            if (!memberTiers.isEmpty()) {
                // Logic Step 1: Capture the literal name
                String tierNameLiteral = memberTiers[0].Name;
                details.tierName = tierNameLiteral;

                System.debug('LoyaltyInfo: Found Member Tier Name: ' + tierNameLiteral);

                // Logic Step 2: Search LoyaltyTier object by Name
                // We find the Definition that matches this name.
                List<LoyaltyTier> tierDefinitions = [
                    SELECT Id 
                    FROM LoyaltyTier 
                    WHERE Name = :tierNameLiteral 
                    AND LoyaltyTierGroup.LoyaltyProgramId = :mem.ProgramId // Optional safety check
                    LIMIT 1
                ];

                if (!tierDefinitions.isEmpty()) {
                    Id realTierId = tierDefinitions[0].Id;
                    System.debug('LoyaltyInfo: Found Definition ID via Name match: ' + realTierId);

                    // Logic Step 3: Get Benefits using the ID we found by Name
                    List<LoyaltyTierBenefit> tierBenefits = [
                        SELECT Benefit.Name, Benefit.Description 
                        FROM LoyaltyTierBenefit 
                        WHERE LoyaltyTierId = :realTierId
                        ORDER BY Benefit.Name ASC
                    ];

                    for(LoyaltyTierBenefit ltb : tierBenefits) {
                        if(ltb.Benefit != null) {
                            details.benefits.add(ltb.Benefit.Name);
                        }
                    }
                } else {
                    System.debug('LoyaltyInfo: No LoyaltyTier definition found matching Name: ' + tierNameLiteral);
                }
            } else {
                details.tierName = 'Standard';
            }

            // 4. Get Points
            List<LoyaltyMemberCurrency> currencies = [
                SELECT Name, PointsBalance 
                FROM LoyaltyMemberCurrency 
                WHERE LoyaltyMemberId = :memId 
                ORDER BY LastModifiedDate DESC
            ];

            if (!currencies.isEmpty()) {
                LoyaltyMemberCurrency selectedCurrency = currencies[0];
                for(LoyaltyMemberCurrency c : currencies) {
                    if(c.Name != null && c.Name.containsIgnoreCase('Point')) {
                        selectedCurrency = c;
                        break;
                    }
                }
                details.pointsBalance = selectedCurrency.PointsBalance;
                details.currencyName = selectedCurrency.Name;
            } else {
                details.pointsBalance = 0;
            }

            // 5. Get Active Vouchers
            List<Voucher> vouchers = [
                SELECT Id, VoucherCode, DiscountPercent, FaceValue, ExpirationDate, 
                       VoucherDefinition.Description, VoucherDefinition.Name
                FROM Voucher 
                WHERE LoyaltyProgramMemberId = :memId 
                AND Status = 'Issued'
                AND (ExpirationDate >= TODAY OR ExpirationDate = null)
            ];

            for(Voucher v : vouchers) {
                VoucherInfo vInfo = new VoucherInfo();
                vInfo.code = v.VoucherCode;
                vInfo.expiry = v.ExpirationDate;
                
                if (v.DiscountPercent != null) {
                    vInfo.valueDisplay = v.DiscountPercent + '% Off';
                } else if (v.FaceValue != null) {
                    vInfo.valueDisplay = '$' + v.FaceValue; 
                } else {
                    vInfo.valueDisplay = (v.VoucherDefinition != null) ? v.VoucherDefinition.Name : 'Reward';
                }
                
                details.vouchers.add(vInfo);
            }

            return details;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoyaltyInfoController Error: ' + e.getMessage());
            throw new AuraHandledException('Unable to fetch loyalty details: ' + e.getMessage());
        }
    }

    public class LoyaltyDetails {
        @AuraEnabled public String programName;
        @AuraEnabled public String membershipNumber;
        @AuraEnabled public String tierName;
        @AuraEnabled public Decimal pointsBalance;
        @AuraEnabled public String currencyName;
        @AuraEnabled public List<String> benefits = new List<String>();
        @AuraEnabled public List<VoucherInfo> vouchers = new List<VoucherInfo>();
    }

    public class VoucherInfo {
        @AuraEnabled public String code;
        @AuraEnabled public String valueDisplay;
        @AuraEnabled public Date expiry;
    }
}