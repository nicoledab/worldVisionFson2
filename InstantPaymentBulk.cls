/************************************************************************************
 * File Name   		: InstantPaymentBulk.cls
 * Author	  		: Jieun.Lee
 * Date				: 2022-12-26
 * Tester	  		: InstantPaymentBulk_test.cls
 * Description 		: 후원자의 Opportunity 목록 조회 후 선택된 후원금에 대해 다건 즉시결제 수행
 * Modification Log
 * ===================================================================================
 * Ver      Date            Author          Modification
 * ===================================================================================
   1.0      2022-12-26      Jieun.Lee        Create
*************************************************************************************/

public with sharing class InstantPaymentBulk {

    /**
     *  현재 후원자의 후원금 목록 조회
     */
    @AuraEnabled
    public static List<Opportunity> getOpportunityList(Id recordId){
        return [
                SELECT Id, Name, Amount, StageName, CloseDate, RecordType.Name, CampaignId, Campaign.Name
                FROM   Opportunity
                WHERE  npsp__Primary_Contact__c =: recordId
                AND    StageName IN ('청구에러', '미성사', 'Pledged')
                //AND    RecordType.Name = '일시후원'
        ];
    }

    /**
     *  현재 후원자 정보 조회
     */
    @AuraEnabled
    public static Contact getContact(Id recordId){
        return [
                SELECT Id, Name, D_DonorNo__c, Email, CMS_InstantPayment_Register_Id__c, CMS_InstantPayment_Register_YN__c
                FROM   Contact
                WHERE  Id =: recordId
        ][0];
    }

    /**
     * 선택된 결제수단 단 건 조회
     */
    @AuraEnabled
    public static PaymentType__c getPaymentType(Id paymentId){
        return [
                SELECT Id,
                        Name,
                        Contact__r.D_DonorNo__c,
                        Secure_AccountNo__c,
                        // 카드 결제수단
                        CardExpiryDate__c,
                        ConfirmInfo__c,
                        BillKey__c,
                        CreditCardOwner__c,
                        Contact__r.Email,
                        //은행계좌 결제수단
                        BankAccountCode__c,
                        Type__c
                FROM  PaymentType__c
                WHERE Id =: paymentId
                AND   AuthStatus__c NOT IN ('F', 'I')
        ];
    }

    /**
     * 현재 후원자의 결제수단 목록 조회
     */
    @AuraEnabled
    public static List<PaymentType__c> getPaymentTypeList(Id recordId, String paymentType){
        return [
                SELECT Id,
                       Name,
                       Contact__r.D_DonorNo__c,
                       Secure_AccountNo__c,
                       // 카드 결제수단
                       CardExpiryDate__c,
                       ConfirmInfo__c,
                       BillKey__c,
                       CreditCardOwner__c,
                       Contact__r.Email,
                       //은행계좌 결제수단
                       BankAccountCode__c,
                       Type__c
                FROM  PaymentType__c
                WHERE Contact__c = : recordId
                AND   Type__c =: paymentType
                AND   AuthStatus__c NOT IN ('F', 'I')
        ];
    }
    // 2023.01.30 추가
    // 현재 사용자의 프로필이 은행계좌 즉시결제 사용 가능한 프로필인 경우 true 반환한다.
    public static Boolean isAccountPaymentUser() {
        List<String> bankPaymentProfiles = new List<String>{
                'System Administrator', '월드비전-재무팀'
        };

        Profile userProfile = [
                SELECT Name
                FROM   Profile
                WHERE  Id =: UserInfo.getProfileId()
        ][0];

        return bankPaymentProfiles.contains(userProfile.Name);
    }

    public static ContentVersion getContentVersion(Id documentId){
        return [
                SELECT Id, VersionData, Title, FileExtension, ContentSize, IsCmsAgreement__c
                FROM   ContentVersion
                WHERE  ContentDocumentId =: documentId
                AND    IsLatest = true
                LIMIT 1
        ][0];
    }

    @AuraEnabled
    public static List<HyosungCMSInstantPaymentBank__mdt> getUsableBank(){
        return [
                SELECT MasterLabel, Code__c
                FROM   HyosungCMSInstantPaymentBank__mdt
        ];
    }

    @AuraEnabled
    public static Map<String, Object> getInitData(Id recordId){
        Map<String, Object> result = new Map<String, Object>();

        List<String> bankPaymentProfiles = new List<String>{
              'System Administrator', '월드비전-재무팀'
        };

        // 현재 사용자가 재무팀이면 true
        Boolean isBankPaymentUser = bankPaymentProfiles.contains([SELECT Name FROM Profile WHERE Id =: UserInfo.getProfileId()][0].Name);

        result.put('opportunityList'     , getOpportunityList(recordId));
        result.put('usableBankList'      , getUsableBank());
        result.put('isCmsRegistered'     , getContact(recordId).CMS_InstantPayment_Register_YN__c);
        result.put('isAccountPaymentUser', isAccountPaymentUser());

        return result;
    }

    @AuraEnabled
    public static PrepareResultWrapper generateBillKey(PaymentType__c selectedPayment){
        PrepareResultWrapper result = new PrepareResultWrapper();

        // Bill Key Generate API Call
        IF_INICIS_BILLKEY_REQ.ResponsePayload response = CardBillKeyGenerate.getBillKey(selectedPayment, null);

        result.isFailed   = !response.resultCode.equals('00');
        result.resultMsg  = response.resultMsg;
        result.billKey    = response.billKey;

        if(String.isNotBlank(selectedPayment.Id)){
            CardBillKeyGenerate.updatePaymentType(selectedPayment.Id, result.billKey, result.isFailed ? result.resultMsg : null);
        }

        return result;
    }

    @AuraEnabled
    public static PaymentResultWrapper instantPaymentCard(Id contactId, PaymentType__c selectedPayment, Decimal amount){

        IF_INICIS_INSTANT_PAYMENT.RequestPayload  request  = new IF_INICIS_INSTANT_PAYMENT.RequestPayload();
        IF_INICIS_INSTANT_PAYMENT.ResponsePayload response = new IF_INICIS_INSTANT_PAYMENT.ResponsePayload();
        Contact objContact = getContact(contactId);
        String transactionTime = system.now().format('YYYYMMddHHmmss');

        // format : IN_{D_Donor__c}_{yyyyMMddhhmmss}
        String moid  = 'IN_'
                     + objContact.D_DonorNo__c + '_'
                     + transactionTime;

        request.moid       = moid;
        request.price      = amount;
        request.goodName   = '[월드비전]' + objContact.Name + '_후원금_일괄_즉시결제';
        request.clientIp   = '000.000.000.000';
        request.regNo      = String.isNotBlank(selectedPayment.ConfirmInfo__c) ? selectedPayment.ConfirmInfo__c : '';
        request.buyerEmail = String.isNotBlank(objContact.Email) ? objContact.Email : 'not_available';
        request.buyerName  = selectedPayment.CreditCardOwner__c;
        request.billKey    = selectedPayment.BillKey__c;

        response = IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request);

        if (!Test.isRunningTest()) {
            if (response.resultMsg != null && response.resultMsg.contains('Read')) {
                response = IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request);
            }
        }

        PaymentResultWrapper wrapper = new PaymentResultWrapper();
        wrapper.resultCode    = response.resultCode;
        wrapper.resultMsg     = response.resultMsg;
        wrapper.transactionId = response.tid;

        return wrapper;
    }



    /*
    * 효성 CMS 동의자료 등록
    * (CMS 회원 등록 시 선행 필수)
    */
    @AuraEnabled
    public static PrepareResultWrapper agreementRegister(Id recordId, Id documentId){
        PrepareResultWrapper wrapper = new PrepareResultWrapper();

        try{
            ContentVersion cv = getContentVersion(documentId);

            IF_HYOSUNG_AGREEMENT_REG.ResponsePayload response = new IF_HYOSUNG_AGREEMENT_REG.ResponsePayload();
            IF_HYOSUNG_AGREEMENT_REG.RequestPayload  request  = new IF_HYOSUNG_AGREEMENT_REG.RequestPayload();

            request.memberId = recordId;
            request.file     = cv;

            response = IF_HYOSUNG_AGREEMENT_REG.getInstance().execute(request);
            system.debug('response : ' +  response);

            // 인터페이스 실패 시
            if(response.error != null){
                throw new CustomException(response.error.message); // Custom Exception Fire
            }
            // 인터페이스 성공 & 동의자료 등록 실패 시
            else if(response.agreementFile != null && response.agreementFile.result.code != 'Y'){
                throw new CustomException(response.agreementFile.result.message); // Custom Exception Fire
            }
            // 인터페이스 성공 & 동의자료 등록 성공 시
            else {
                wrapper.isFailed       = false;
                wrapper.memberId       = response.agreementFile.memberId;
                wrapper.agreementKey   = response.agreementFile.agreementKey;
                wrapper.registerStatus = response.agreementFile.registerStatus;
            }
        }

        catch(Exception e){
            throw new CustomException(e.getMessage()); // Custom Exception Fire
        }
        system.debug('wrapper : ' + wrapper);
        return wrapper;
    }

    /**
     * 효성 CMS 시스템 회원 등록
     * (계좌 즉시결제 기능 이용 시 선행 필수)
     */
    @AuraEnabled
    public static PrepareResultWrapper cmsMemberRegister(Id recordId, PaymentType__c selectedPayment){
        PrepareResultWrapper wrapper = new PrepareResultWrapper();

        IF_HYOSUNG_MEMBER_REG.ResponsePayload response = new IF_HYOSUNG_MEMBER_REG.ResponsePayload();
        IF_HYOSUNG_MEMBER_REG.RequestPayload  request  = new IF_HYOSUNG_MEMBER_REG.RequestPayload();

        Contact objContact = getContact(recordId);
        String memberId = objContact.Id; // format : HS_{D_DonorNo__c}_{Contact.Id}

        request.memberId       = memberId;
        request.memberName     = objContact.Name;
        request.paymentCompany = selectedPayment.BankAccountCode__c;
        request.paymentNumber  = selectedPayment.Secure_AccountNo__c;
        request.payerName      = selectedPayment.CreditCardOwner__c;
        request.payerNumber    = selectedPayment.ConfirmInfo__c;
        request.receiptFlag    = 'N';

        response = IF_HYOSUNG_MEMBER_REG.getInstance().execute(request, recordId);

        if(response.error != null){ // CMS Register Failed?
            throw new CustomException(response.error.message); // Custom Exception Fire
        }

        memberId = response.member.memberId;

        wrapper.isFailed   = !response.member.result.code.equals('0000');
        wrapper.resultMsg  = response.member.result.message;
        wrapper.memberId   = memberId;

        Boolean isUpdate = (objContact.CMS_InstantPayment_Register_Id__c == null)
                        || (objContact.CMS_InstantPayment_Register_Id__c != memberId);

        //upsertContact(recordId, memberId, isUpdate);

        return wrapper;
    }

    /**
     * 효성 CMS 계좌 즉시이체
     */
    @AuraEnabled
    public static PaymentResultWrapper instantPaymentAccount(String contactId, PaymentType__c selectedPayment, Decimal amount){

        IF_HYOSUNG_INSTANT_PAYMENT.RequestPayload  request  = new IF_HYOSUNG_INSTANT_PAYMENT.RequestPayload();
        IF_HYOSUNG_INSTANT_PAYMENT.ResponsePayload response = new IF_HYOSUNG_INSTANT_PAYMENT.ResponsePayload();
        PaymentResultWrapper wrapper = new PaymentResultWrapper();

        String transactionTime = system.now().format('YYYYMMddHHmmss');

        Contact objContact = getContact(contactId);

        try {
            String memberId = objContact.CMS_InstantPayment_Register_Id__c;
            String transactionId  = 'HS_'
                                  + objContact.D_DonorNo__c + '_'
                                  + transactionTime;

            request.transactionId = transactionId;
            request.memberId      = memberId;
            request.callAmount    = amount;
            response = IF_HYOSUNG_INSTANT_PAYMENT.getInstance().execute(request);

            if(!response.payment.result.code.equals('0000') && response.error != null){
                throw new CustomException(response.error.message);
            }

            wrapper.resultCode      = response.payment.result.code;
            wrapper.transactionId   = response.payment.transactionId;
            wrapper.transactionTime = transactionTime;

            if (response.error != null) {
                wrapper.resultMsg = response.error.message;
            }
        }

        catch (Exception e) {
            system.debug('instantPaymentAccount error msg : ' + e.getMessage() + '  &&&&& and line  :' + e.getLineNumber());
        }

        return wrapper;

    }

    /**
     * 즉시결제 수행 후 결과에 따라 Opportunity 필드에 결과 업데이트
     */
    @AuraEnabled
    public static void updateOpportunities(List<Id> selectedIds, String paymentType, String failReason, String tid){
        List<Opportunity> updateOpportunities = [
                SELECT Id, StageName, Inisis_FirstPaymentCode__c, RecordType.DeveloperName, PaymentMethod2__c, PaymentMethod2Real__c
                FROM   Opportunity
                WHERE  Id IN : selectedIds
        ];

        String  stageName = '';
        String  paymentMethod = '';
        Boolean isRecurring = false;

        for(Opportunity objOppty :  updateOpportunities){

            // 즉시결제 성공이라면 'Closed Won'을, 실패라면 '청구에러'를 StageName 필드에 업데이트한다.
            stageName     = String.isBlank(failReason) ? 'Closed Won' : '청구에러';
            isRecurring   = (objOppty.RecordType.DeveloperName.equals('RecurringDonation'));

            switch on paymentType {
                when '카드' {
                    objOppty.Inisis_FirstPaymentCode__c = tid;
                    paymentMethod = '즉시결제-이니시스';
                }
                when '은행계좌' {
                    objOppty.HSCMS_FirstPaymentCode__c  = tid;
                    paymentMethod = '즉시결제-효성';
                }
            }

            // 즉시결제 성공인 경우 PurchaseDate__c 값을 금일로 업데이트
            if(stageName.equals('Closed Won')){
                objOppty.PurchaseDate__c = system.today();
                objOppty.PaymentMethod2Real__c = paymentMethod;
            }

            objOppty.StageName = stageName;
            objOppty.Instantpayment_Fail_Reason__c = failReason;
        }

        update updateOpportunities;
    }

    @AuraEnabled
    public static ContentVersion contentVersionUpdate(Id documentId){
        ContentVersion cv = getContentVersion(documentId);
        String errorMsg   = null;
        Boolean isValid   = false;

        switch on cv.FileExtension {
            // 서면일 경우 파일 크기는 4.5MB를 초과할 수 없다
            when 'jpg', 'jpeg', 'png', 'gif', 'tif', 'tiff', 'pdf' {
                isValid  = cv.ContentSize <= 4718592;
                errorMsg = '서면일 경우 파일 크기는 4.5MB를 초과할 수 없습니다.';
            }
            // 녹취일 경우 파일 크기는 300KB를 초과할 수 없다
            when 'wav', 'mp3', 'wma' {
                isValid = cv.ContentSize <= 307200;
                errorMsg = '서면일 경우 파일 크기는 300KB를 초과할 수 없습니다.';
            }
            // 전자서명일 경우 파일 크기는 5KB를 초과할 수 없다
            when 'der' {
                isValid = cv.ContentSize <= 5120;
                errorMsg = '서면일 경우 파일 크기는 5KB를 초과할 수 없습니다.';
            }
        }

        cv = new ContentVersion(Id = cv.Id);
        cv.IsCmsAgreement__c = true;
        update cv;

        if(!isValid){
            throw new CustomException(errorMsg);
        }

        return cv;
    }

    @AuraEnabled
    public static void accountPaymentAfter(Id recordId){
        system.debug('contactId : ' + recordId);

        // 업로드 된 동의자료 파일 삭제
        delete [ SELECT Id
                 FROM   ContentDocument
                 WHERE  Id IN (
                        select ContentDocumentId
                        from   ContentVersion
                        where  FirstPublishLocationId =: recordId
                        and    IsCmsAgreement__c = true
        )];

        // 효성 cms에 등록된 해당 후원자의 회원 정보 삭제
        cmsMemberDelete(recordId);
    }

    @Future(Callout=true)
    public static void cmsMemberDelete(Id recordId){
        IF_HYOSUNG_MEMBER_DEL.getInstance().execute(recordId);
    }

    /**
     * 효성 CMS에 회원 등록 완료 후 Contact 필드에 결과 업데이트
     */
    public static void upsertContact(Id recordId, String memberId, Boolean isUpdate){
        Contact upsertContact = new Contact();

        upsertContact.Id = recordId;
        upsertContact.CMS_InstantPayment_Register_YN__c = true;
        upsertContact.CMS_InstantPayment_Register_Id__c = memberId;

        if(!isUpdate){
            upsertContact.CMS_InstantPayment_RegisterDate__c = system.today();
        }

        update upsertContact;
    }


    public class PrepareResultWrapper {
        @AuraEnabled public String  resultMsg;      // 결과 메시지
        @AuraEnabled public String  billKey;        // 빌키
        @AuraEnabled public String  memberId;       // 회원 ID
        @AuraEnabled public String  registerStatus; // 동의 상태
        @AuraEnabled public String  agreementKey;   // 동의키
        @AuraEnabled public Boolean isFailed;       // 실패 여부
    }

    public class PaymentResultWrapper {
        @AuraEnabled public String resultCode;
        @AuraEnabled public String resultMsg;
        @AuraEnabled public String transactionId;
        @AuraEnabled public String transactionTime;
    }
}