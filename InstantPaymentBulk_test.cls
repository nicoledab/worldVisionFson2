/**
 * Created by daeunextier_je.lee on 2023-01-10.
 */

@IsTest
private class InstantPaymentBulk_test {

    @TestSetup
    private static void testSetUp(){
        account objAccount = new Account();
        objAccount.Name = 'Test Account';
        insert objAccount;

        Contact objContact = new Contact();
        objContact.AccountId = objAccount.Id;
        objContact.RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Donor').getRecordTypeId();
        objContact.LastName = 'TestContact';
        insert objContact;

        CommonCode__c objCommonCode = new CommonCode__c();
        objCommonCode.Name           = 'AA카드';
        objCommonCode.Code__c        = '000000';
        objCommonCode.CardNoStart__c = '0000';
        objCommonCode.CardCompany__c = 'AA';
        objCommonCode.CardType__c    = '신용카드(일반)';
        insert objCommonCode;


        PaymentType__c objPaymentType = new PaymentType__c();
        objPaymentType.Contact__c = objContact.Id;
        objPaymentType.RecordTypeId = Schema.SObjectType.PaymentType__c.getRecordTypeInfosByDeveloperName().get('Card').getRecordTypeId();
        objPaymentType.Secure_AccountNo__c = '0000000000000000';
        objPaymentType.ConfirmInfo__c = '101010';
        objPaymentType.CardExpiryDate__c = System.today();
        objPaymentType.BankAccountName__c = objCommonCode.Id;
        insert objPaymentType;
    }

    static testMethod void doTest() {
        Test.startTest();

        PaymentType__c objPayment = [SELECT Id FROM PaymentType__c][0];
        Contact objContact = [SELECT Id FROM Contact][0];

        objPayment = InstantPaymentBulk.getPaymentType(objPayment.Id);
        objContact = InstantPaymentBulk.getContact(objContact.Id);

        InstantPaymentBulk.getOpportunityList(null);
        InstantPaymentBulk.getPaymentTypeList(null, '카드');
        InstantPaymentBulk.getUsableBank();
        InstantPaymentBulk.getInitData(null);
        InstantPaymentBulk.generateBillKey(objPayment);
        InstantPaymentBulk.instantPaymentCard(objContact.Id, objPayment, 100);
        InstantPaymentBulk.upsertCmsMember(objContact.Id, objPayment);
        InstantPaymentBulk.instantPaymentAccount(objContact.Id, objPayment, 100);
        InstantPaymentBulk.updateOpportunities(new List<Id>{}, '카드', '', '');
        InstantPaymentBulk.upsertContact(objContact.Id, 'testMemberId', false);

        Test.stopTest();
    }
}