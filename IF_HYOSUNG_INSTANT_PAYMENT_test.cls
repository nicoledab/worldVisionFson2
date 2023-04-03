/************************************************************************************
 * Description :
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2023-01-03     hs.jung          Create
*************************************************************************************/

@IsTest
private class IF_HYOSUNG_INSTANT_PAYMENT_test {
    @testSetup
    static void testSetUp() {
        IF_Master__c objMaster = new IF_Master__c();
        objMaster.Name               = 'IF_HYOSUNG_INSTANT_PAYMENT';
        objMaster.Endpoint__c        = 'https://api-test.hyosungcms.co.kr:1443/v1/payments/realcms';
        objMaster.Type__c            = 'OutBound';
        objMaster.Method__c          = 'POST';
        objMaster.WebServiceType__c  = 'REST';
        objMaster.ContentType__c     = 'application/json';
        objMaster.IsSendParameter__c = false;
        insert objMaster;
    }

    @IsTest
    static void testBehavior() {
        Test.startTest();

        Test.setMock(HttpCalloutMock.class, new HttpCalloutSuccessMock());
        IF_HYOSUNG_INSTANT_PAYMENT.getInstance().execute(null, new List<Id>());
        Test.stopTest();
    }


    private static HTTPResponse newResponse(Integer statusCode) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode);
        res.setBody('');
        return res;
    }

    private class HttpCalloutSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = newResponse(200);
            return res;
        }
    }
    private class HttpCalloutFailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = newResponse(201);
            return res;
        }
    }

}