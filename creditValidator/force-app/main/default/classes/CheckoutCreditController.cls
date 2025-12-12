public without sharing class CheckoutCreditController {

    // No parameters needed; Apex automatically detects the calling user
    @AuraEnabled
    public static Map<String, Object> validateCredit() {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // 1. AUTO-DETECTION: Find the current user's ACTIVE cart
            String userId = UserInfo.getUserId();
            
            // Find a cart belonging to this user that is not closed
            List<WebCart> carts = [
                SELECT GrandTotalAmount, AccountId 
                FROM WebCart 
                WHERE OwnerId = :userId 
                AND (Status = 'Active' OR Status = 'Checkout') 
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (carts.isEmpty()) {
                System.debug('No active cart found for user: ' + userId);
                result.put('hasCredit', true); // If no cart exists, do not block
                return result;
            }

            WebCart cart = carts[0];
            
            // 2. Retrieve account credit limit
            List<Account> accounts = [SELECT CreditLimit__c FROM Account WHERE Id = :cart.AccountId LIMIT 1];
            
            if (accounts.isEmpty()) {
                result.put('hasCredit', true);
                return result;
            }

            Account acc = accounts[0];
            
            // 3. Validation
            Decimal creditLimit = acc.CreditLimit__c != null ? acc.CreditLimit__c : 0;
            Decimal cartTotal = cart.GrandTotalAmount != null ? cart.GrandTotalAmount : 0;

            if (cartTotal > creditLimit) {
                // FAIL: Insufficient credit
                result.put('hasCredit', false);
                result.put('shortage', cartTotal - creditLimit);
                
                // Debug to verify logic in logs
                System.debug('INSUFFICIENT CREDIT: Total ' + cartTotal + ' > Limit ' + creditLimit);
            } else {
                // SUCCESS: Sufficient credit
                result.put('hasCredit', true);
                System.debug('CREDIT OK: Total ' + cartTotal + ' <= Limit ' + creditLimit);
            }
            
        } catch (Exception e) {
            System.debug('Error in CheckoutCreditController: ' + e.getMessage());
            result.put('hasCredit', true); 
        }
        
        return result;
    }
}