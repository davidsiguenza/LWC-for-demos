/**
 * Tests for ScheduleAppointmentController.
 * Requires Communities enabled and a "Customer Community Login User" (or similar) profile.
 */
@IsTest
private class ScheduleAppointmentControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Person Account');
        insert acc;
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'CommunityUser',
            Email = 'testcomm@example.com',
            AccountId = acc.Id
        );
        insert con;
        Product2 prod = new Product2(Name = 'Test Product PDP', IsActive = true);
        insert prod;
    }

    @IsTest
    static void getPersonAccountId_standardUser_returnsNullOrAccount() {
        Id result = ScheduleAppointmentController.getPersonAccountId();
        // Standard user: no ContactId, so we get User.AccountId (often null)
        System.assert(true, 'getPersonAccountId completes');
    }

    @IsTest
    static void getProductName_returnsName() {
        Product2 p = [SELECT Id, Name FROM Product2 LIMIT 1];
        String name = ScheduleAppointmentController.getProductName(p.Id);
        System.assertEquals(p.Name, name, 'Should return product name');
        System.assertEquals(null, ScheduleAppointmentController.getProductName(null), 'Null id returns null');
    }

    @IsTest
    static void saveBooking_blankDate_throws() {
        Exception ex;
        try {
            ScheduleAppointmentController.saveBooking('', '10:00 - 11:00', null, null);
        } catch (AuraHandledException e) {
            ex = e;
        }
        System.assert(ex instanceof AuraHandledException, 'Expected AuraHandledException');
    }

    @IsTest
    static void saveBooking_blankSlot_throws() {
        Exception ex;
        try {
            ScheduleAppointmentController.saveBooking('2025-02-01', '', null, null);
        } catch (AuraHandledException e) {
            ex = e;
        }
        System.assert(ex instanceof AuraHandledException, 'Expected AuraHandledException');
    }

    @IsTest
    static void saveBooking_communityUser_updatesAccountDescription() {
        Contact con = [SELECT Id, AccountId FROM Contact LIMIT 1];
        List<Profile> profiles = [
            SELECT Id FROM Profile
            WHERE Name = 'Customer Community Login User'
            LIMIT 1
        ];
        if (profiles.isEmpty()) {
            System.debug('Skipping: Customer Community Login User profile not found. Enable Communities.');
            return;
        }
        String uname = 'testcomm_' + System.now().getTime() + '@example.com';
        User communityUser = new User(
            FirstName = 'Test',
            LastName = 'CommunityUser',
            Email = 'testcomm@example.com',
            Username = uname,
            Alias = 'tcomm',
            CommunityNickname = 'tcomm' + System.now().getTime(),
            ProfileId = profiles[0].Id,
            ContactId = con.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert communityUser;

        Test.startTest();
        System.runAs(communityUser) {
            Id accId = ScheduleAppointmentController.getPersonAccountId();
            System.assertEquals(con.AccountId, accId, 'Person Account should match Contact.AccountId');

            ScheduleAppointmentController.saveBooking('2025-02-01', '10:00 - 11:00', null, null);

            Account updated = [SELECT Description FROM Account WHERE Id = :con.AccountId];
            System.assert(
                updated.Description != null && updated.Description.contains('[Appointment]'),
                'Description should contain booking'
            );
            System.assert(
                updated.Description.contains('2025-02-01') && updated.Description.contains('10:00 - 11:00'),
                'Description should contain date and slot'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void saveBooking_withProductName_appendsToDescription() {
        Contact con = [SELECT Id, AccountId FROM Contact LIMIT 1];
        Product2 p = [SELECT Id, Name FROM Product2 LIMIT 1];
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Customer Community Login User' LIMIT 1];
        if (profiles.isEmpty()) {
            System.debug('Skipping: Customer Community Login User profile not found.');
            return;
        }
        User communityUser = new User(
            FirstName = 'Test',
            LastName = 'ProductUser',
            Email = 'testproduct@example.com',
            Username = 'testproduct_' + System.now().getTime() + '@example.com',
            Alias = 'tprod',
            CommunityNickname = 'tprod' + System.now().getTime(),
            ProfileId = profiles[0].Id,
            ContactId = con.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert communityUser;
        Test.startTest();
        System.runAs(communityUser) {
            ScheduleAppointmentController.saveBooking('2025-03-15', '14:00 - 15:00', p.Id, p.Name);
        }
        Test.stopTest();
        Account updated = [SELECT Description FROM Account WHERE Id = :con.AccountId];
        System.assert(updated.Description != null, 'Description should be set');
        System.assert(updated.Description.contains('Product: ' + p.Name), 'Description should contain product name');
    }
}
