/**
 * Created by daeunextier_je.lee on 2023-02-02.
 */

@IsTest
public with sharing class IF_INICIS_INSTANT_PAYMENT_test {

    @testSetup
    static void testSetUp() {

    }

    static testMethod void testBehavior(){
        Test.startTest();

        IF_INICIS_INSTANT_PAYMENT.RequestPayload request = new IF_INICIS_INSTANT_PAYMENT.RequestPayload();

        request.clientIp      = '0.0.0.0';
        request.mid           = 'testMid';
        request.url           = 'test.test.';
        request.moid          = '';
        request.goodName      = '';
        request.buyerName     = '';
        request.buyerEmail    = 'test@test.com';
        request.buyerTel      = '010-0000-0000';
        request.price         = 100;
        request.billKey       = 'testBillKey';
        request.regNo         = '';
        request.cardPw        = '';
        request.tax           = '';
        request.taxFree       = '';
        request.currency_x    = '';
        request.cardQuota     = '';
        request.quotaInterest = '';
        request.authentification = '';

        Test.setMock(HttpCalloutMock.class, new HttpCalloutSuccessMock());
        IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request, new List<Id>{});

        Test.setMock(HttpCalloutMock.class, new HttpCalloutFailMock());
        IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request, new List<Id>{});

        Test.stopTest();
    }

    private static HTTPResponse newResponse(Integer statusCode) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        res.setStatusCode(statusCode);
        res.setBody('{}');
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