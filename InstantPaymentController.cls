/************************************************************************************
 * Description :
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2022-09-14     hs.jung          Create
*************************************************************************************/

public with sharing class InstantPaymentController {

    static final Boolean IS_TEST = Test.isRunningTest();

    /** 즉시결제 첫 접근 시 초기화 데이터 조회 */
    @AuraEnabled
    public static Map<String, Object> getInitData(Id recordId, String strType) {
        Map<String, Object> result = new Map<String, Object>();
        Opportunity currentRecord = getOpportunity(recordId);

        // 현재 후원금 레코드 (SObject : Opportuntiy)
        result.put('currentOppty', currentRecord);
        // 현재 후원자의 결제수단 목록 (SObject : PaymentType__c)
        result.put('listPaymentType', getPaymentTypeList(recordId, strType));
        // 현재 사용자가 재무팀인지 여부 (재무팀만 은행계좌 즉시결제 사용 가능케 요구사항 변경됨 2023.01.30)
        result.put('isAccountPaymentUser', InstantPaymentBulkController.isAccountPaymentUser());
        // 현재 효성 CMS 즉시출금 서비스 가능 은행 목록
        result.put('bankOptions', getBankOptions());
        // 현재 후원자의 효성 CMS 등록된 결제 정보({계좌번호 + 은행코드}) -- 회원등록되지 않았을 경우 '' 반환된다.
        result.put('cmsAccountKey', InstantPaymentBulkController.getCMSAccountKey(currentRecord.npsp__Primary_Contact__c));
        return result;
    }

    public static Opportunity getOpportunity(Id recordId) {
        Opportunity objOpportunity = [
                SELECT    Id
                        , Name
                        , Amount
                        , StageName
                        , PaymentMethod2__c
                        , npsp__Primary_Contact__c
                        , npsp__Primary_Contact__r.Name
                        , npsp__Primary_Contact__r.D_DonorNo__c
                        , npsp__Primary_Contact__r.CMS_InstantPayment_Register_YN__c
                        , Instantpayment_Fail_Reason__c
                FROM Opportunity
                WHERE Id = :recordId
        ][0];
        return objOpportunity;
    }

    // 사용자의 결제수단 목록 조회 - 받는 파라미터가 Opportunity 아이디
    @AuraEnabled
    public static List<PaymentType__c> getPaymentTypeList(Id recordId, String strType) {
        List<PaymentType__c> listPaymentType = [
                SELECT   Id
                        , Name
                        , Contact__c
                        , Secure_AccountNo__c
                        , CardExpiryDate__c
                        , ConfirmInfo__c
                        , BillKey__c
                        , Contact__r.D_DonorNo__c
                        , CreditCardOwner__c
                        , Contact__r.Email
                        , BankAccountName__r.Name
                        , Type__c
                        , BankAccountName__c
                        , BankAccountCode__c
                FROM   PaymentType__c
                WHERE  Contact__c = :getOpportunity(recordId).npsp__Primary_Contact__c
                AND    AuthStatus__c NOT IN ('F', 'I')
                AND    Type__c =: strType
        ];

        return listPaymentType;
    }


    // 사용자의 '결제수단' 정보 불러오기
    @AuraEnabled
    public static PaymentType__c getPaymentType(Id paymentId) {
        System.debug('사용자의 결제수단 정보 불러오기 : ' +  paymentId);
        PaymentType__c objPaymentType = [
                SELECT   Id
                        , Name
                        , Contact__c
                        , Secure_AccountNo__c
                        , CardExpiryDate__c
                        , ConfirmInfo__c
                        , BankAccountName__c
                        , BankAccountName__r.Name
                        , BillKey__c
                        , Contact__r.D_DonorNo__c
                        , Contact__r.CMS_InstantPayment_Register_YN__c
                        , CreditCardOwner__c
                        , Contact__r.Email
                        , Type__c
                        , BankAccountCode__c
                FROM   PaymentType__c
                WHERE  Id =: paymentId
        ][0];
        return objPaymentType;
    }

    /**
     *  현재 후원자 정보 조회
     */
    @AuraEnabled
    public static Contact getContact(Id recordId){
        return [
                SELECT Id, Name, D_DonorNo__c, Email, Phone, MobilePhone
                FROM   Contact
                WHERE  Id =: recordId
        ][0];
    }

    /* 사용 가능한 목록 은행 조회 */
    public static List<HyosungCMSInstantPaymentBank__mdt> getCmsServiceBankList(){
        return [
                SELECT MasterLabel, Code__c
                FROM   HyosungCMSInstantPaymentBank__mdt
        ];
    }


    public static List<Map<String, String>> getBankOptions(){
        List<Map<String, String>> result = new List<Map<String, String>>();

        for(HyosungCMSInstantPaymentBank__mdt bank : getCmsServiceBankList()){
            Map<String, String> optionMap = new Map<String, String>();
            optionMap.put('label', bank.MasterLabel);
            optionMap.put('value', bank.Code__c);
            result.add(optionMap);
        }

        return result;
    }

    // 이니시스 카드 빌키 생성
    @AuraEnabled
    public static InstantPaymentBulkController.PrepareResultWrapper generateBillKey(PaymentType__c selectedPayment) {
        return InstantPaymentBulkController.generateBillKey(selectedPayment);
    }

    // 빌키 발급 실패 사유 업데이트
    @AuraEnabled
    public static void updatePaymentType(Id recordId,  String resultMsg) {
        PaymentType__c paymentType = new PaymentType__c();
        paymentType.Id = recordId;
        paymentType.Bill_Key_FailReason__c = resultMsg;
        update paymentType;
        system.debug('updatePaymentType : ' + paymentType);
    }


    // 이니시스 카드 즉시결제
    @AuraEnabled
    public static ResponseWrapper instantPaymentCard(Id recordId, PaymentType__c selectedPayment, Decimal amount) {
        /** 후원금 유효성 확인
         *  부적절한 후원금인 경우 Custom Exception 발생시킨다.
         */
        List<Id> opptyIds = new List<Id>{recordId};
        InstantPaymentBulkController.checkInvalidStage(opptyIds);
        /** 후원금 유효성 확인 */

        IF_INICIS_INSTANT_PAYMENT.RequestPayload  request  = new IF_INICIS_INSTANT_PAYMENT.RequestPayload();
        IF_INICIS_INSTANT_PAYMENT.ResponsePayload response = new IF_INICIS_INSTANT_PAYMENT.ResponsePayload();

        Opportunity objOppty   = getOpportunity(recordId);
        Contact objContact     = getContact(objOppty.npsp__Primary_Contact__c);
        String transactionTime = system.now().format('YYYYMMddHHmmss');

        // format : IN_{D_Donor__c}_{yyyyMMddhhmmss}
        String moid  = 'IN_'
                     + objContact.D_DonorNo__c + '_'
                     + transactionTime;

        request.moid       = moid;
        request.price      = amount;
        request.goodName   = '[월드비전] ' + objOppty.Name + '_즉시결제';
        request.clientIp   = '000.000.000.000';
        request.regNo      = String.isNotBlank(selectedPayment.ConfirmInfo__c) ? selectedPayment.ConfirmInfo__c : '';
        request.buyerEmail = String.isNotBlank(objContact.Email) ? objContact.Email : 'not_available';
        request.buyerName  = selectedPayment.CreditCardOwner__c;
        request.billKey    = selectedPayment.BillKey__c;

        if(!IS_TEST){
            response = IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request, opptyIds);
            if (response.resultMsg != null && response.resultMsg.contains('Read')) {
                response = IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request, opptyIds);
            }
        }

        ResponseWrapper wrapper = new ResponseWrapper();
        wrapper.resultCode    = response.resultCode;
        wrapper.resultMsg     = response.resultMsg;
        wrapper.transactionId = response.tid;

        Boolean isSuccess = String.isNotBlank(response.resultCode) && response.resultCode.equals('00');
        String  failedMsg = isSuccess ? null : wrapper.resultMsg;
        updateOpportunity(recordId, selectedPayment.Type__c, failedMsg, wrapper.transactionId);

        return wrapper;
    }

    /*
     * ContentVersion -  IsCmsAgreement__c (효성 CMS 동의자료 여부) 필드 업데이트
     *  > 은행계좌 즉시결제 완료 시 관련 파일 삭제 위함
     * (CMS 회원 등록 시 선행 필수)
     * 2023-01-30 je.lee 추가
     */
    @AuraEnabled
    public static ContentVersion contentVersionUpdate(Id documentId){
        return InstantPaymentBulkController.contentVersionUpdate(documentId);
    }

    /*
     * 효성 CMS 동의자료 등록
     * (CMS 회원 등록 시 선행 필수)
     * 2023-01-30 je.lee 추가
     */
    @AuraEnabled
    public static InstantPaymentBulkController.PrepareResultWrapper agreementRegister(Id contactId, Id documentId){
        return InstantPaymentBulkController.agreementRegister(contactId, documentId);
    }

    /*
     * 효성 CMS 회원 등록
     * 은행계좌 즉시결제 시 선행 필수
     * 2023-01-30 je.lee 변경
     */
    @AuraEnabled
    public static InstantPaymentBulkController.PrepareResultWrapper cmsMemberRegister(Id contactId, PaymentType__c selectedPayment){
        return InstantPaymentBulkController.cmsMemberRegister(contactId, selectedPayment);
    }
    /**
     *  2023-01-30 JE.LEE 추가 START
     */
    /*
     * 효성 CMS 은행계좌 즉시결제
     * 2023-01-30 je.lee 추가
     */
    @AuraEnabled
    public static InstantPaymentBulkController.PaymentResultWrapper instantPaymentAccount(Id recordId, Id contactId, PaymentType__c selectedPayment, Decimal amount){
        List<Id> opptyIds = new List<Id>{recordId};
        InstantPaymentBulkController.PaymentResultWrapper wrapper = new InstantPaymentBulkController.PaymentResultWrapper();

        wrapper = InstantPaymentBulkController.instantPaymentAccount(contactId, selectedPayment, amount, opptyIds);
        if(!IS_TEST){
            String failedMsg  = wrapper.isFailed ? wrapper.resultMsg : null;
            updateOpportunity(recordId, selectedPayment.Type__c, failedMsg, wrapper.transactionId);
        }

        return wrapper;
    }


    // 즉시결제 완료 후 성공 여부에 따라 후원금의 필드를 업데이트한다.
    @AuraEnabled
    public static void updateOpportunity(Id opptyId, String paymentType, String failReason, String tid) {
        List<Id> opptyIds = new List<Id>{opptyId};
        InstantPaymentBulkController.updateOpportunities(opptyIds, paymentType, failReason, tid, null);

    }

    /*
     * 효성 CMS 은행계좌 즉시결제 완료 이후 SFDC 내 후원자 동의자료 삭제 및 효성 CMS 회원삭제 I/F 송신
     * 2023-01-30 je.lee 추가
     */
    @AuraEnabled
    public static void accountPaymentAfter(Id recordId, Id contactId){

        // 업로드 된 동의자료 파일 삭제
        delete [
                SELECT Id
                FROM   ContentDocument
                WHERE  Id IN (
                        select ContentDocumentId
                        from   ContentVersion
                        where  FirstPublishLocationId =: recordId
                        and    IsCmsAgreement__c = true
                )
        ];
    }


    // 현재 IP 정보 가져오기 (빌키 발급 IF 필수 파라미터)
    public static String getIPAddress() {
        LocationWrapper wrapper = new LocationWrapper();
        wrapper.clientIp = '000.000.000.00';
        return wrapper.clientIp;
    }


    public class LocationWrapper {
        public String clientIp;
    }

    public class ResponseWrapper {
        @AuraEnabled public String resultMsg;
        @AuraEnabled public String resultCode;
        @AuraEnabled public String transactionId;
        @AuraEnabled public String billKey;
    }

    public class PrepareResultWrapper {
        @AuraEnabled public String resultCode;
        @AuraEnabled public String resultMsg;
        @AuraEnabled public String billKey;
        @AuraEnabled public String memberId;
    }


}