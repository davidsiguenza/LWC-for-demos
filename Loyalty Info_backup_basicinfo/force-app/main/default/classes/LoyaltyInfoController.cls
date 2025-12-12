public without sharing class LoyaltyInfoController {

    @AuraEnabled(cacheable=true)
    public static LoyaltyDetails getMemberDetails() {
        try {
            // 1. Get current User's Contact ID
            Id userId = UserInfo.getUserId();
            List<User> users = [SELECT ContactId, AccountId FROM User WHERE Id = :userId LIMIT 1];
            
            if (users.isEmpty() || users[0].ContactId == null) {
                return null;
            }

            String contactId = users[0].ContactId;

            // 2. Get Program Member info 
            // We use dynamic SOQL or standard SOQL. 
            // Note: LoyaltyProgramMember is the parent record.
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
            LoyaltyDetails details = new LoyaltyDetails();
            
            // Safe handling of Program Name
            details.programName = (mem.Program != null) ? mem.Program.Name : 'Loyalty Program';
            details.membershipNumber = mem.MembershipNumber;
            
            String memId = mem.Id;

            // 3. Get Active Tier [FIXED FIELD NAME HERE]
            // The relationship field is 'LoyaltyMemberId', NOT 'LoyaltyProgramMemberId'
            List<LoyaltyMemberTier> tiers = [
                SELECT Name, LoyaltyTierGroup.Name 
                FROM LoyaltyMemberTier 
                WHERE LoyaltyMemberId = :memId 
                ORDER BY EffectiveDate DESC 
                LIMIT 1
            ];
            
            if (!tiers.isEmpty()) {
                details.tierName = tiers[0].Name;
            } else {
                details.tierName = 'Standard';
            }

            // 4. Get Points (Currency) [FIXED FIELD NAME HERE]
            // The relationship field is also 'LoyaltyMemberId' here
            List<LoyaltyMemberCurrency> currencies = [
                SELECT Name, PointsBalance 
                FROM LoyaltyMemberCurrency 
                WHERE LoyaltyMemberId = :memId 
                ORDER BY LastModifiedDate DESC
            ];
            
            details.pointsBalance = 0;
            details.currencyName = 'Points';

            if (!currencies.isEmpty()) {
                // Logic: Prioritize a currency with "Point" in the name, otherwise take the most recent
                LoyaltyMemberCurrency selectedCurrency = currencies[0];
                
                for(LoyaltyMemberCurrency c : currencies) {
                    if(c.Name != null && c.Name.containsIgnoreCase('Point')) {
                        selectedCurrency = c;
                        break;
                    }
                }
                
                details.pointsBalance = selectedCurrency.PointsBalance;
                details.currencyName = selectedCurrency.Name;
            }

            return details;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoyaltyInfoController Error: ' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('Unable to fetch loyalty details: ' + e.getMessage());
        }
    }

    public class LoyaltyDetails {
        @AuraEnabled public String programName;
        @AuraEnabled public String membershipNumber;
        @AuraEnabled public String tierName;
        @AuraEnabled public Decimal pointsBalance;
        @AuraEnabled public String currencyName;
    }
}