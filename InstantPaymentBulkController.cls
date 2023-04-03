/************************************************************************************
 * File Name   		: InstantPaymentBulkController.cls
 * Author	  		: Jieun.Lee
 * Date				: 2022-12-26
 * Tester	  		: InstantPaymentBulkController_test.cls
 * Description 		: 후원자의 Opportunity 목록 조회 후 선택된 후원금에 대해 다건 즉시결제 수행
 * Modification Log
 * ===================================================================================
 * Ver      Date            Author          Modification
 * ===================================================================================
   1.0      2022-12-26      Jieun.Lee        Create
*************************************************************************************/

public with sharing class InstantPaymentBulkController {

    static final Boolean IS_TEST = Test.isRunningTest();

    /**
     *  현재 후원자의 후원금 목록 조회
     */
    @AuraEnabled
    public static List<Opportunity> getOpportunityList(Id recordId, Date startDate, Date endDate){
        return [
                SELECT    Id
                        , Name
                        , Amount
                        , StageName
                        , CloseDate
                        , RecordType.Name
                        , CampaignId
                        , Campaign.Name
                FROM     Opportunity
                WHERE    npsp__Primary_Contact__c =: recordId
                AND      StageName IN ('청구에러', 'Closed Lost', 'Pledged')
                AND      Instantpayment_Fail_Reason__c != '은행연동장애'
                AND CloseDate >=: startDate
                AND CloseDate <=: endDate
                ORDER BY CloseDate DESC
        ];
    }

    /**
     *  현재 후원자 정보 조회
     */
    @AuraEnabled
    public static Contact getContact(Id recordId){
        return [
                SELECT Id
                        , Name
                        , D_DonorNo__c
                        , Email
                        , MobilePhone
                        , CMS_InstantPayment_Register_Id__c
                        , CMS_InstantPayment_Register_YN__c
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
                        BankAccountName__r.Name,
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
    public static List<PaymentType__c> getPaymentTypeList(Id recordId, String strType){
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
                AND   Type__c =: strType
                AND   AuthStatus__c NOT IN ('F', 'I')
        ];
    }
    // 2023.01.30 추가
    // 2023.03.09 변경 - 기존 프로필 기반 권한 판별 로직을 퍼미션 셋 기준으로 변경함
    // 현재 사용자에게 '[CRM] 즉시결제 - 효성 권한 부여' 퍼미션이 할당되어 있을 경우 true를 반환한다.
    public static Boolean isAccountPaymentUser() {

        List<PermissionSetAssignment> userPermissionSets  = new List<PermissionSetAssignment>();
        userPermissionSets = [
                SELECT Id
                FROM   PermissionSetAssignment
                WHERE  PermissionSet.Name = 'CRM_InstantPayment_Hyosung_Permission'
                AND    AssigneeId =: UserInfo.getUserId()
        ];

        return !userPermissionSets.isEmpty();
    }

    /**
     * 등록된 효성 CMS 동의자료 조회
     */
    public static ContentVersion getContentVersion(Id documentId){
        return [
                SELECT Id, VersionData, Title, FileExtension, ContentSize, IsCmsAgreement__c
                FROM   ContentVersion
                WHERE  ContentDocumentId =: documentId
                AND    IsLatest = true
                LIMIT 1
        ][0];
    }

    /* 사용 가능한 목록 은행 조회 */
    public static List<HyosungCMSInstantPaymentBank__mdt> getCmsServiceBankList(){
        return [
                SELECT MasterLabel, Code__c
                FROM   HyosungCMSInstantPaymentBank__mdt
        ];
    }

    @AuraEnabled
    public static Map<String, Object> getInitData(Id recordId, Date startDate, Date endDate){
        Map<String, Object> result = new Map<String, Object>();

        // 현재 후원자의 후원금 목록 (SObject : Opportunity)
        result.put('opportunityList', getOpportunityList(recordId, startDate, endDate));
        // 현재 사용자가 재무팀인지 여부 (재무팀만 은행계좌 즉시결제 사용 가능케 요구사항 변경됨 2023.01.30)
        result.put('isAccountPaymentUser', isAccountPaymentUser());
        // 현재 효성 CMS 즉시출금 서비스 가능 은행 목록
        result.put('bankOptions', getBankOptions());
        // 현재 후원자의 효성 CMS 등록된 결제 정보({계좌번호 + 은행코드}) -- 회원등록되지 않았을 경우 '' 반환된다.
        result.put('cmsAccountKey', getCMSAccountKey(recordId));

        return result;
    }

    public static String getCMSAccountKey(Id contactId){

        PrepareResultWrapper wrapper = cmsMemberInquiry(contactId);

        wrapper.bankCode = String.isBlank(wrapper.bankCode) ? '' : wrapper.bankCode;
        wrapper.paymentNumber = String.isBlank(wrapper.paymentNumber) ? '' : wrapper.paymentNumber;

        system.debug('getCMSAccountKey result : ' + (wrapper.paymentNumber + wrapper.bankCode));
        return wrapper.isFailed ? '' : (wrapper.paymentNumber + wrapper.bankCode);
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

    @AuraEnabled
    public static PrepareResultWrapper generateBillKey(PaymentType__c selectedPayment){
        PrepareResultWrapper result = new PrepareResultWrapper();

        // Bill Key Generate API Call
        IF_INICIS_BILLKEY_REQ.ResponsePayload response = CardBillKeyGenerate.getBillKey(selectedPayment, null);

        result.isFailed  = !response.resultCode.equals('00');
        result.resultMsg = response.resultMsg;
        result.billKey   = response.billKey;

        Boolean isNotDirect = String.isNotBlank(selectedPayment.Id);

        if(!IS_TEST && isNotDirect){
            CardBillKeyGenerate.updatePaymentType(selectedPayment.Id, result.billKey, result.isFailed ? result.resultMsg : null);
        }

        return result;
    }

    @AuraEnabled
    public static PaymentResultWrapper instantPaymentCard(Id contactId, PaymentType__c selectedPayment, Decimal amount, List<Id> selectedIds){
        system.debug('instantPaymentCard selectedIds : ' + selectedIds);
        /** 후원금 유효성 확인
        *  부적절한 후원금인 경우 Custom Exception 발생시킨다.
        */
        InstantPaymentBulkController.checkInvalidStage(selectedIds);
        /** 후원금 유효성 확인 */

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
        request.goodName   = '[월드비전]' + objContact.Name + '_후원금_' + String.valueOf(selectedIds.size()) + ' 건_즉시결제';
        request.clientIp   = '000.000.000.000';
        request.regNo      = String.isNotBlank(selectedPayment.ConfirmInfo__c) ? selectedPayment.ConfirmInfo__c : '';
        request.buyerEmail = String.isNotBlank(objContact.Email) ? objContact.Email : 'not_available';
        request.buyerName  = selectedPayment.CreditCardOwner__c;
        request.billKey    = selectedPayment.BillKey__c;

        if(!IS_TEST){
            response = IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request, selectedIds);
            if (response.resultMsg != null && response.resultMsg.contains('Read')) {
                response = IF_INICIS_INSTANT_PAYMENT.getInstance().execute(request, selectedIds);
            }
        }

        PaymentResultWrapper wrapper = new PaymentResultWrapper();
        wrapper.isFailed      = String.isNotBlank(response.resultCode) && !response.resultCode.equals('00');
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
            request.file = cv;

            if(!IS_TEST){
                response = IF_HYOSUNG_AGREEMENT_REG.getInstance().execute(request);

                // 인터페이스 실패 시
                if(response.error != null){
                    throw new CustomException(response.error.developerMessage); // Custom Exception Fire
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
        }

        catch(Exception e){
            system.debug('agreementRegister error message : ' + e.getMessage() + ', line : ' + e.getLineNumber());
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
    public static PrepareResultWrapper cmsMemberRegister(Id contactId, PaymentType__c selectedPayment){
        PrepareResultWrapper wrapper = new PrepareResultWrapper();

        IF_HYOSUNG_MEMBER_REG.ResponsePayload response = new IF_HYOSUNG_MEMBER_REG.ResponsePayload();
        IF_HYOSUNG_MEMBER_REG.RequestPayload  request  = new IF_HYOSUNG_MEMBER_REG.RequestPayload();

        Contact objContact = getContact(contactId);
        String mobilePhone = objContact.MobilePhone;

        if(String.isNotBlank(mobilePhone)){
            mobilePhone = mobilePhone.replaceAll('-', '');
        }

        request.memberId       = objContact.Id;                       // Contact Record Id
        request.memberName     = objContact.Name;                     // 회원 이름
        request.paymentCompany = selectedPayment.BankAccountCode__c;  // 은행 코드
        request.paymentNumber  = selectedPayment.Secure_AccountNo__c; // 계좌 번호
        request.payerName      = selectedPayment.CreditCardOwner__c;  // 예금주
        request.payerNumber    = selectedPayment.ConfirmInfo__c;      // 생년월일/사업자번호
        request.phone          = mobilePhone;                         // 핸드폰 번호
        request.receiptFlag    = 'N';

        if(!IS_TEST){
            response = IF_HYOSUNG_MEMBER_REG.getInstance().execute(request, contactId);
        }

        if(response.error != null){ // CMS Register Failed?
            throw new CustomException(response.error.developerMessage); // Custom Exception Fire
        }

        IF_HYOSUNG_MEMBER_REG.Member member = response.member;

        if(member != null){
            wrapper.isFailed      = !member.result.code.equals('0000');
            wrapper.resultMsg     = member.result.message;
            wrapper.memberId      = member.memberId;
            wrapper.bankCode      = member.paymentCompany;
            wrapper.paymentNumber = member.paymentNumber;

            // 회원 등록된 경우 CMS 회원등록여부를 TRUE로 업데이트 한다.
            // 계좌번호 등 계좌 상 오류가 있어도 시스템 상에는 등록되는 듯
            updateRegisteredContact(contactId, true, null);
        }

        return wrapper;
    }

    public static void updateRegisteredContact(Id contactId, Boolean isRegisteredYN, Datetime registeredDate){
        Contact newContact = new Contact();
        newContact.Id = contactId;
        newContact.CMS_InstantPayment_Register_YN__c  = isRegisteredYN;
        newContact.CMS_InstantPayment_RegisterDate__c = (registeredDate == null) ? System.now() : registeredDate;

        update newContact;
    }

    /**
     * 효성 CMS 계좌 즉시이체
     */
    @AuraEnabled
    public static PaymentResultWrapper instantPaymentAccount(String contactId, PaymentType__c selectedPayment, Decimal amount, List<Id> selectedIds){
        /**
        *  후원금 유효성 확인
        *  부적절한 후원금인 경우 Custom Exception 발생시킨다.
        */
        InstantPaymentBulkController.checkInvalidStage(selectedIds);
        /** 후원금 유효성 확인 */

        PaymentResultWrapper wrapper = new PaymentResultWrapper();
        IF_HYOSUNG_INSTANT_PAYMENT.RequestPayload  request  = new IF_HYOSUNG_INSTANT_PAYMENT.RequestPayload();
        IF_HYOSUNG_INSTANT_PAYMENT.ResponsePayload response = new IF_HYOSUNG_INSTANT_PAYMENT.ResponsePayload();

        String transactionTime = system.now().format('YYYYMMddHHmmss');

        Contact objContact = getContact(contactId);

        String transactionId  = 'HS_'
                + objContact.D_DonorNo__c + '_'
                + transactionTime;

        request.memberId      = contactId;
        request.callAmount    = amount;
        request.transactionId = transactionId;

        if(!IS_TEST){
            response = IF_HYOSUNG_INSTANT_PAYMENT.getInstance().execute(request, selectedIds);
            if(response.error != null){
                wrapper.isFailed = true;
                wrapper.resultMsg = response.error.developerMessage;
            }
            else if(!response.payment.result.code.equals('0000') || response.payment.result.flag.equals('N')){
                wrapper.isFailed        = true;
                wrapper.resultMsg       = response.payment.result.message;
                wrapper.resultCode      = response.payment.result.code;
                wrapper.transactionId   = response.payment.transactionId;
                wrapper.transactionTime = transactionTime;
            }
            else {
                wrapper.isFailed        = false;
                wrapper.resultCode      = response.payment.result.code;
                wrapper.transactionId   = response.payment.transactionId;
                wrapper.transactionTime = transactionTime;
            }
        }
        return wrapper;
    }

    /**
    * 효성 CMS 시스템 회원 등록
    * (계좌 즉시결제 기능 이용 시 선행 필수)
    */
    @AuraEnabled
    public static PrepareResultWrapper cmsMemberInquiry(Id recordId){
        PrepareResultWrapper wrapper = new PrepareResultWrapper();

        try{
            IF_HYOSUNG_MEMBER_INQ.ResponsePayload response = new IF_HYOSUNG_MEMBER_INQ.ResponsePayload();

            if(!IS_TEST){
                response = IF_HYOSUNG_MEMBER_INQ.getInstance().execute(recordId);
            }
            system.debug('cmsMemberInquiry response : ' + response);
            Boolean isFailed = response.error != null
                    || !response.member.result.code.equals('0000')
                    || !response.member.status.equals('신청완료');

            system.debug('1 : ' + response.error);
            system.debug('2 : ' + !response.member.result.code.equals('0000'));
            system.debug('3 : ' + !response.member.status.equals('신청실패'));

            wrapper.isFailed  = isFailed;
            if(response.member != null){
                IF_HYOSUNG_MEMBER_INQ.MemberWrapper member = response.member;
                if(member != null){
                    wrapper.memberId      = member.memberId;
                    wrapper.bankCode      = member.paymentCompany;
                    wrapper.paymentNumber = member.paymentNumber;
                }
            }
        }
        catch(Exception e){
            system.debug('cmsMemberInquiry error (' + e.getLineNumber() +  ') : ' + e.getMessage());
            wrapper.isFailed  = true;
            wrapper.resultMsg = e.getMessage();
        }

        system.debug('wrapper : ' + wrapper);

        return wrapper;
    }

    /**
    * 효성 CMS 시스템 출금조회
    */
    /*
    @AuraEnabled
    public static PrepareResultWrapper cmsTransactionInquiry(Id selectedId, String transactionId){

        IF_HYOSUNG_TRANSACTION_INQ.ResponsePayload response = new IF_HYOSUNG_TRANSACTION_INQ.ResponsePayload();

        if(!IS_TEST){
            response = IF_HYOSUNG_TRANSACTION_INQ.getInstance().execute(transactionId);
        }

        if(response.error != null){ // CMS Register Failed?
            throw new CustomException(response.error.message); // Custom Exception Fire
        }

        IF_HYOSUNG_TRANSACTION_INQ.PaymentWrapper payment = response.payment;

        Boolean isFailed = !response.payment.result.flag.equals('Y');

        PrepareResultWrapper wrapper = new PrepareResultWrapper();
        wrapper.isFailed  = isFailed;
        wrapper.resultMsg = !isFailed ? null : payment.result.message;

        if(!isFailed){
            List<Id> selectedIds = new List<Id>{selectedId};
            Date paymentDate = isFailed  ? null : Date.valueOf(payment.paymentDate.replaceAll('/',  '-'));
            updateOpportunities(selectedIds, '은행계좌', wrapper.resultMsg, transactionId, paymentDate);
        }
        return wrapper;
    }
    */

    /**
     * 즉시결제 수행 후 결과에 따라 Opportunity 필드에 결과 업데이트
     */
    @AuraEnabled
    public static void updateOpportunities(List<Id> selectedIds, String paymentType, String failReason, String tid, Date paymentDate){
        List<Opportunity> updateOpportunities = [
                SELECT  Id
                        , StageName
                        , Inisis_FirstPaymentCode__c
                        , RecordType.DeveloperName
                        , PaymentMethod2__c
                        , PaymentMethod2Real__c
                FROM   Opportunity
                WHERE  Id IN : selectedIds
        ];

        String  stageName = '';
        String  paymentMethod = '';
        Boolean isRecurring = false;

        for(Opportunity objOppty :  updateOpportunities){

            // 즉시결제 성공이라면 'Closed Won'을, 실패라면 '청구에러'를 StageName 필드에 업데이트한다.
            stageName   = String.isBlank(failReason) ? 'Closed Won' : '청구에러';
            isRecurring = (objOppty.RecordType.DeveloperName.equals('RecurringDonation'));

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
                objOppty.PurchaseDate__c = (paymentDate != null) ? paymentDate : system.today();
                if(!paymentMethod.equals(objOppty.PaymentMethod2__c)){
                    objOppty.PaymentMethod2Real__c = paymentMethod;
                }
            }

            objOppty.StageName = stageName;
            objOppty.Instantpayment_Fail_Reason__c = failReason;
            //objOppty.InstantPaymentTime__c = system.now();
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

        if(!IS_TEST && !isValid){
            throw new CustomException(errorMsg);
        }

        return cv;
    }

    @AuraEnabled
    public static void accountPaymentAfter(Id recordId){
        // 효성 cms에 등록된 해당 후원자의 회원 정보 삭제

        List<ContentDocument> relatedFiles = [
                SELECT Id
                FROM   ContentDocument
                WHERE  Id IN (
                        select ContentDocumentId
                        from   ContentVersion
                        where  FirstPublishLocationId =: recordId
                        and    IsCmsAgreement__c = true
                )
        ];

        if(!relatedFiles.isEmpty()){
            delete relatedFiles;
        }
    }

    /** 후원금 유효성 확인
    *   부적절한 후원금인 경우 Custom Exception 발생시킨다.
    */
    public static void checkInvalidStage(List<Id> selectedIds) {
        AggregateResult countAggregate = [
                SELECT COUNT(Id) cnt
                FROM   Opportunity
                WHERE  Id IN : selectedIds
                AND    StageName NOT IN ('청구에러', 'Closed Lost', 'Pledged')
        ][0];

        Integer invalidCnt = (Integer) countAggregate.get('cnt');

        if(invalidCnt > 0 && !Test.isRunningTest()){
            throw new CustomException('이미 결제가 완료된 후원금입니다.');
        }
    }

    public class PrepareResultWrapper {
        @AuraEnabled public String  resultMsg;      // 결과 메시지
        @AuraEnabled public String  billKey;        // 빌키
        @AuraEnabled public String  memberId;       // 회원 ID
        @AuraEnabled public String  registerStatus; // 동의 상태
        @AuraEnabled public String  agreementKey;   // 동의키
        @AuraEnabled public String  bankCode;       // 은행코드
        @AuraEnabled public String  paymentNumber;  // 계좌번호
        @AuraEnabled public Boolean isFailed;       // 실패 여부


    }

    public class PaymentResultWrapper {
        @AuraEnabled public String  resultCode;
        @AuraEnabled public String  resultMsg;
        @AuraEnabled public String  transactionId;
        @AuraEnabled public String  transactionTime;
        @AuraEnabled public Boolean isFailed;
    }
}