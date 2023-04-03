/************************************************************************************
 * Description :
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2022-12-08     hs.jung          Create
*************************************************************************************/

@IsTest
private class InstantPaymentController_test {


    @TestSetup
    private static void testSetUp() {

        account objAccount = new Account();
        objAccount.Name = 'Test Account';
        objAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('School').getRecordTypeId();
        insert objAccount;

        Contact objContact = new Contact();
        objContact.AccountId = objAccount.Id;
        objContact.RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Donor').getRecordTypeId();
        objContact.LastName = 'TestContact';
        objContact.MobilePhone = '000-0000-0000';
        insert objContact;
        System.debug( 'objContact.MobilePhone :: ' + objContact.MobilePhone);

        Opportunity objOpportunity = new Opportunity();
        objOpportunity.ContactId = objContact.Id;
        objOpportunity.Name = '테스트Opportunity';
        objOpportunity.CloseDate = Date.newInstance(2019, 12, 25);
        objOpportunity.PurchaseDate__c = Date.newInstance(2019, 12, 25);
        objOpportunity.SysCloseDate__c = objOpportunity.CloseDate;
        objOpportunity.StageName = 'Closed Won';
        objOpportunity.Amount = 30000;
        objOpportunity.npsp__Primary_Contact__c = objContact.id; 
        Insert objOpportunity;

        CommonCode__c objCommonCode = new CommonCode__c();
        objCommonCode.Name = 'AA카드';
        objCommonCode.Code__c = '000000';
        objCommonCode.CardNoStart__c = '0000';
        objCommonCode.CardCompany__c = 'AA';
        objCommonCode.CardType__c = '신용카드(일반)';
        insert objCommonCode;

        PaymentType__c cardPayment = new PaymentType__c();
        cardPayment.Contact__c = objContact.Id;
        cardPayment.Name = 'Nametest';
        cardPayment.RecordTypeId = Schema.SObjectType.PaymentType__c.getRecordTypeInfosByDeveloperName().get('Card').getRecordTypeId();
        cardPayment.Secure_AccountNo__c = '0000000000000000';
        cardPayment.ConfirmInfo__c = '101010';
        cardPayment.CreditCardOwner__c = 'CreditCardOwnertest';
        cardPayment.CardExpiryDate__c = System.today();
        cardPayment.Type__c = '카드';
        insert cardPayment;

        PaymentType__c accountPayment = cardPayment.clone();
        accountPayment.BankAccountCode__c = '020';
        accountPayment.Secure_AccountNo__c = '1002851377074';
        accountPayment.ConfirmInfo__c = '960315';
        accountPayment.Type__c = '은행계좌';
        accountPayment.RecordTypeId = Schema.SObjectType.PaymentType__c.getRecordTypeInfosByDeveloperName().get('BankAccount').getRecordTypeId();
        insert accountPayment;

        ContentVersion objContentVersion = new ContentVersion();
        objContentVersion.Title = 'Test ContentVersion';
        objContentVersion.VersionData = Blob.valueOf('test file data');
        objContentVersion.FirstPublishLocationId = objOpportunity.Id;
        objContentVersion.PathOnClient = '/' + objContentVersion.Title;
        insert objContentVersion;

    }

    static testMethod void testBehaivor() {

        Test.startTest();

        Id contactId        = [SELECT Id FROM Contact][0].Id;
        Id opportunityId    = [SELECT Id FROM Opportunity][0].Id;
        Id cardPaymentId    = [SELECT Id FROM PaymentType__c WHERE Type__c = '카드'][0].Id;
        Id accountPaymentId = [SELECT Id FROM PaymentType__c WHERE Type__c = '은행계좌'][0].Id;
        Id documentId       = [SELECT Id FROM ContentDocument][0].Id;

        PaymentType__c cardPayment    = InstantPaymentController.getPaymentType(cardPaymentId);
        PaymentType__c accountPayment = InstantPaymentController.getPaymentType(accountPaymentId);

        InstantPaymentController.getInitData(opportunityId, '카드');
        InstantPaymentController.getOpportunity(opportunityId);
        InstantPaymentController.getContact(contactId);
        InstantPaymentController.generateBillKey(cardPayment);
        InstantPaymentController.updatePaymentType(cardPaymentId, null);
        InstantPaymentController.instantPaymentCard(opportunityId, cardPayment, 100);
        InstantPaymentController.contentVersionUpdate(documentId);
        InstantPaymentController.agreementRegister(contactId, documentId);
        InstantPaymentController.cmsMemberRegister(contactId, accountPayment);
        InstantPaymentController.instantPaymentAccount(opportunityId, contactId, accountPayment, 100);
        InstantPaymentController.updateOpportunity(opportunityId, '카드', null, 'testTID');
        InstantPaymentController.accountPaymentAfter(opportunityId, contactId);

        test.stopTest();
    }

}