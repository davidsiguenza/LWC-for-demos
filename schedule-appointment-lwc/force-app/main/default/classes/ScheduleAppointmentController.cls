/**
 * Apex controller for Schedule Appointment LWC.
 * Resolves the current user's Person Account (via Contact) and persists
 * booking info to Account.Description.
 * Uses "without sharing" so Experience Cloud users can update their own
 * Person Account (Contact.AccountId) despite org-wide sharing; we only
 * ever update the Account resolved from the current user's Contact.
 */
public without sharing class ScheduleAppointmentController {
    private static final String BOOKING_PREFIX = '[Appointment] ';
    private static final String BOOKING_FORMAT = BOOKING_PREFIX + '{0} {1}';

    /**
     * Returns the Person Account Id linked to the current Experience Cloud user.
     * Uses User.ContactId -> Contact.AccountId (typical for Person Accounts / B2C).
     * Falls back to User.AccountId when present (e.g. Partner Community).
     */
    @AuraEnabled(cacheable=true)
    public static Id getPersonAccountId() {
        Id userId = UserInfo.getUserId();
        List<User> users = [
            SELECT Id, ContactId, AccountId
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return null;
        }
        User u = users[0];
        if (u.ContactId != null) {
            List<Contact> contacts = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :u.ContactId
                LIMIT 1
            ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                return contacts[0].AccountId;
            }
        }
        return u.AccountId;
    }

    /**
     * Returns the Product2.Name for the given product Id, or null if not found.
     */
    @AuraEnabled(cacheable=true)
    public static String getProductName(Id productId) {
        if (productId == null) return null;
        List<Product2> products = [SELECT Name FROM Product2 WHERE Id = :productId LIMIT 1];
        return products.isEmpty() ? null : products[0].Name;
    }

    /**
     * Appends a booking line to the Account.Description for the current user's
     * Person Account. Format: "[Appointment] YYYY-MM-DD HH:00–HH:00" or
     * "[Appointment] YYYY-MM-DD HH:00–HH:00 | Product: {name}" / "| Product ID: {id}" when product context exists.
     */
    @AuraEnabled
    public static void saveBooking(String dateStr, String slotLabel, String productId, String productName) {
        if (String.isBlank(dateStr) || String.isBlank(slotLabel)) {
            throw new AuraHandledException('Date and slot are required.');
        }
        Id accountId = getPersonAccountId();
        if (accountId == null) {
            throw new AuraHandledException('No Person Account linked. Please log in with a linked account.');
        }
        List<Account> accounts = [
            SELECT Id, Description
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        Account acc = accounts[0];
        String base = String.format(BOOKING_FORMAT, new List<String>{ dateStr, slotLabel });
        if (String.isNotBlank(productName)) {
            base += ' | Product: ' + productName;
        } else if (String.isNotBlank(productId)) {
            base += ' | Product ID: ' + productId;
        }
        String separator = String.isBlank(acc.Description) ? '' : '\n';
        acc.Description = (acc.Description == null ? '' : acc.Description) + separator + base;
        try {
            update acc;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }
}
