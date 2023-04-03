/**
 * Created by daeunextier_je.lee on 2022-12-27.
 */

({
    refreshView : null,
    closeQuickAction : null,
    stageLabelMap : {'청구에러' : '청구에러', 'Pledged' : '약정등록', 'Closed Lost' : '미성사'},

    // 페이지 접근 시 초기화 함수
    getInitData : function(component){
        component.set("v.isLoading", true);

        // 날짜 조건 검색 기능 hs.jung 추가
        let currentYear = new Date().getFullYear();
        let formattedStartDate = currentYear + "-01-01";
        let formattedEndDate = currentYear + "-12-31";

        component.set("v.dateStart", formattedStartDate);
        component.set("v.dateEnd", formattedEndDate);


        const params = {
            'recordId' : component.get("v.recordId") // Contact Record Id
           ,'startDate' : formattedStartDate
           ,'endDate' : formattedEndDate
        };

        this.apex(component, 'getInitData', params)
        .then(result => {
            console.log('getInitData result : ', result);
            // opportunityList      : 현재 후원자의 즉시결제 가능 후원금 리스트
            // isAccountPaymentUser : 현재 사용자의 은행계좌 즉시결제 사용 가능 여부
            // bankOptions          : 효성 CMS 즉시출금 가능 은행 목록
            const {opportunityList, isAccountPaymentUser, bankOptions, cmsAccountKey} = result;

            if(!opportunityList.length){
                this.showToast('error', '즉시결제 가능한 후원금이 없습니다.');
        //                 this.modalClose(component);
            }

            // lightning:datatable columns 에 맞게 후원금 리스트 데이터 재정의
            opportunityList.forEach(record => {
                const stageNameRefine = this.stageLabelMap[record.StageName];
                record.OpptyLink    = `/${record.Id}`;
                record.CampaignLink = `/${record.CampaignId}`;
                record.StageName    = stageNameRefine;
                record.CampaignName = (record.Campaign)   ? record.Campaign.Name   : null;
                record.RecordType   = (record.RecordType) ? record.RecordType.Name : null;
            });

            component.set("v.bankOptions", bankOptions);
            component.set("v.cmsAccountKey", cmsAccountKey);
        //             component.set("v.opportunityList", opportunityList);
        //             component.set("v.totalOpportunityList", opportunityList);
            component.set("v.opportunityList", opportunityList);
            component.set("v.isAccountPaymentUser", isAccountPaymentUser);

            // 후원금 dataTable 컬럼 세팅
            this.setColumns(component, opportunityList);
        })
        .catch(error => {
            console.log('fnGetInitData error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            component.set("v.isLoading", false);
        })
    },

    // 후원금 목록 데이터 테이블 컬럼 세팅
    setColumns : function(component, result) {
        var columns = [
            {fieldName:"OpptyLink",    label : "상품명",     type: 'url', typeAttributes: {label: { fieldName: 'Name'}, target: '_blank'}},
            {fieldName:"RecordType",   label : "후원유형",    type: 'text'},
            {fieldName:"Amount",       label : "금액",       type: 'currency', typeAttributes: {currencyCode: 'KRW'}},
            {fieldName:"StageName",    label : "단계",       type: 'text'},
            {fieldName:"CloseDate",    label : "이체일",     type: 'date'},
            {fieldName:"CampaignLink", label : "인입 캠페인", type: 'url', typeAttributes: {label: { fieldName: 'CampaignName'}, target: '_blank'}},
        ];
        component.set("v.columns", columns);
    },

    // 결제수단 목록 조회
    fnGetPaymentTypeList : function(component) {

        component.set("v.isLoading", true);
        component.set('v.isPrecedingInvalid', true);
        component.set('v.isPaymentInvalid', true);
        component.set("v.documentId", null);

        var params = {
            recordId : component.get("v.recordId"),
            strType  : component.get("v.selectedTabId")
        };

        this.apex(component, 'getPaymentTypeList', params)
        .then(result => {
            console.log('getListPaymentType result : ', result);
            this.fnOptionRender(component, result);
        })
        .catch(error => {
             console.log('fnGetInitData error : ', error);
             const errorMsg =  !error.length ? error.message : error[0].message;
             this.showToast('error', errorMsg);
            component.set("v.isLoading", false);
        });
    },


    // PaymentType__c 레코드 리스트로 radioGroup 옵션 리스트 생성
    fnOptionRender : function(component, paymentTypes) {

        const selectedTabId = component.get("v.selectedTabId");
        const options = [];

        paymentTypes.forEach(target => {
            const cardName   = target.Name.substring(0, target.Name.indexOf('_'));
            const cardNumber = target.Secure_AccountNo__c.substring(target.Secure_AccountNo__c.length - 4 , target.Secure_AccountNo__c.length);

            options.push({
                value : target.Id,
                label : `${cardName} (${cardNumber})`
            });
        });

        options.sort();

        options.push({
            value : '직접입력', label : '직접입력'
        });

        component.set("v.paymentOptions" , options);

        if(options.length == 0){
            component.set("v.selectedPayment", {});
        }
        else{
            component.set("v.selectedPaymentId", options[0].value);
        }

        this.fnGetPaymentDetail(component);
    },

    // 선택된 PaymentType의 레코드 정보 조회
    fnGetPaymentDetail : function (component) {

        component.set('v.isLoading', true);
        component.set('v.isPrecedingInvalid', true);
        component.set('v.isPaymentInvalid'  , true);
        component.set("v.documentId", null);

        const selectedTabId = component.get("v.selectedTabId");
        const selectedPaymentId = component.get("v.selectedPaymentId");

        if(selectedPaymentId === '직접입력'){
            const directPayment = {
                'Id'      : `직접입력`,
                'Name'    : `${selectedTabId} 직접입력`,
                'Type__c' : selectedTabId,
            }
            component.set("v.selectedPayment", directPayment);
            this.validate(component);
            component.set('v.isLoading', false);
            return false;
        }

        this.apex(component, 'getPaymentType', {'paymentId' : selectedPaymentId})
        .then(result => {
            console.log('fnGetPaymentDetail result : ', result);
            let {CardExpiryDate__c : cardExpiryDate} = result;

            if(cardExpiryDate){
                cardExpiryDate = cardExpiryDate.substring(0, 7);
            }

            result.CardExpiryDate__c = cardExpiryDate;
            component.set("v.selectedPayment", result);

            if(this.validate(component)){
                let preceding = ('카드' == selectedTabId) ? '빌키생성' : '회원등록';

                const toastMsg = `결제 전에 ${preceding}을 먼저 진행해주세요`;
                this.showToast('warning', toastMsg);
            }
        })
        .catch(error => {
            console.log('getPaymentType error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            component.set("v.isLoading", false);
        });

    },

    /*  날짜 조건 검색 기능  hs.Jung 추가 */
    getOpportunityList :  function(component) {
        component.set("v.isLoading", true);
        let dStart = component.get("v.dateStart");
        let dEnd = component.get("v.dateEnd");

        var params = {
            recordId : component.get("v.recordId"),
            startDate : dStart,
            endDate : dEnd
        };

        const isInvalid = (dStart > dEnd);
        if(isInvalid) {
            this.showToast('error', '조회 시작일은 조회 종료일보다 이전이어야 합니다.');
            component.set("v.isLoading", false);
            return true; 
        }

        this.apex(component, 'getOpportunityList', params)
        .then(result => {
            console.log('getOpportunityList result : ', result);
             result.forEach(record => {
                 const stageNameRefine = this.stageLabelMap[record.StageName];
                 record.OpptyLink    = `/${record.Id}`;
                 record.CampaignLink = `/${record.CampaignId}`;
                 record.StageName    = stageNameRefine;
                 record.CampaignName = (record.Campaign)   ? record.Campaign.Name   : null;
                 record.RecordType   = (record.RecordType) ? record.RecordType.Name : null;
             });
            component.set("v.opportunityList", result);
            component.set("v.isLoading", false);
        })
        .catch(error => {
             console.log('fnGetInitData error : ', error);
             const errorMsg =  !error.length ? error.message : error[0].message;
             this.showToast('error', errorMsg);
            component.set("v.isLoading", false);
        });

    },


    /* 해당 결제수단에 대해 이니시스 빌키 발급 */
    generateBillKey :  function(component) {
        component.set("v.isLoading", true);

        const selectedPaymentId = component.get("v.selectedPaymentId");
        const selectedPayment   = component.get("v.selectedPayment");
        const cardExpiryDate    = selectedPayment.CardExpiryDate__c;

        if(selectedPaymentId == '직접입력'){
            selectedPayment.Id = null;
        }

        selectedPayment.CardExpiryDate__c = cardExpiryDate + '-01';

        var params = {selectedPayment : selectedPayment};

        this.apex(component, 'generateBillKey', params)
        .then(result => {
            console.log('generateBillKey result : ', result);
            const {resultMsg, isFailed, billKey} = result;

            selectedPayment.Id = selectedPaymentId;
            selectedPayment.BillKey__c = billKey;
            selectedPayment.CardExpiryDate__c = cardExpiryDate;

            component.set('v.selectedPayment', selectedPayment);

            if(isFailed){
                this.showToast('error', resultMsg);
                component.set("v.isLoading", false);
                return;
            }

            this.validate(component);
            this.showToast('success', '빌키 생성이 완료되었습니다.');
        })
        .catch(error => {
            console.log('generateBillKey error : ', error);
            this.showToast('error', error[0].message);
        })
        .then(() => {
            component.set("v.isLoading", false);
        });
    },

    /* 카드 결제 진행 */
    fnInstantPaymentCard : function(component) {
        component.set("v.isLoading", true);

        const selectedPayment = component.get("v.selectedPayment");

        delete selectedPayment.CardExpiryDate__c;

        var params = {
            contactId       : component.get("v.recordId"),
            amount          : component.get("v.totalAmt"),
            selectedIds     : component.get("v.selectionIds"),
            selectedPayment : selectedPayment,
        };

        this.apex(component, 'instantPaymentCard', params)
        .then(result => {
            console.log('fnInstantPaymentCard result : ', result);
            var {resultMsg, isFailed, transactionId} = result;
            this.fnUpdateOpportunities(component, isFailed, resultMsg, transactionId);
        })
        .catch(error => {
            console.log('instantPaymentCard error : ', error);
            this.showToast('error', error[0].message);
            component.set("v.isLoading", false);
        });
    },

    // 동의자료 여부 필드 업데이트
    contentVersionUpdate : function(component) {
        component.set("v.isLoading", true);
        const param = {
            'documentId' : component.get("v.documentId")
        };

        this.apex(component, 'contentVersionUpdate', param)
        .then(result => {
            console.log('contentVersionUpdate result : ', result);
        })
        .catch(error => {
            component.set("v.documentId", null);
            console.log('contentVersionUpdate error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            this.validate(component);
            component.set("v.isLoading", false);
        })
    },

    /* 효성 CMS 동의자료 등록 */
    agreementRegister :  function(component) {
        component.set("v.isLoading", true);
        var params = {
            'recordId'   : component.get("v.recordId"),
            'documentId' : component.get("v.documentId"),
        };
        console.log('agreementRegister params : ', params);
        this.apex(component, 'agreementRegister', params)
        .then(result => {
            console.log('agreementRegister result : ', result);
            var {resultMsg, isFailed} = result;

            if (isFailed) {
                this.showToast('error', resultMsg);
            }
            else {
                this.cmsMemberRegister(component);
            }
        })
        .catch(error => {
            console.log('agreementRegister error : ', error);
            this.showToast('error', error[0].message);
            component.set("v.isLoading", false);
        });
    },

    /* 효성 CMS 회원 등록 */
    cmsMemberRegister :  function(component) {
        component.set("v.isLoading", true);

        const params = {
            'contactId' : component.get("v.recordId"),
            'selectedPayment' : component.get("v.selectedPayment")
        };

        this.apex(component, 'cmsMemberRegister', params)
        .then(result => {
            console.log('cmsMemberRegister result : ', result);
            const {isFailed, resultMsg, memberId, bankCode, paymentNumber} = result;

            if(bankCode && paymentNumber){
                component.set("v.cmsAccountKey", (paymentNumber + bankCode));
            }

            if(isFailed){
                this.showToast('error', resultMsg);
                component.set("v.isLoading", false);
                return;
            }

            // attribute setting
            component.set("v.isCmsRegistered", true);
            component.set("v.cmsAccountKey", (paymentNumber + bankCode));
            // invalid check
            this.actionEnableCheck(component);
            this.showToast('success', '회원등록이 성공적으로 진행되었습니다.');
            component.set("v.isLoading", false);

        })
        .catch(error => {
            console.log('cmsMemberRegister error : ', error);
            this.showToast('error', error[0].message);
            component.set("v.isLoading", false);
        });
    },


    /* 은행계좌 결제 진행 */
    fnInstantPaymentAccount : function(component) {
        component.set("v.isLoading", true);

        var params = {
            contactId       : component.get("v.recordId"), // 후원자 recordId
            amount          : component.get("v.totalAmt"), // 결제 총액
            selectedPayment : component.get("v.selectedPayment"), // 사용자 선택 결제수단 레코드 정보
            selectedIds     : component.get("v.selectionIds"),
        };
        console.log('fnInstantPaymentAccount params : ', params);

        this.apex(component, 'instantPaymentAccount', params)
        .then(result => {
            console.log('fnInstantPaymentAccount result : ', result);
            const {resultMsg, isFailed, transactionId} = result;
            this.fnUpdateOpportunities(component, isFailed, resultMsg, transactionId);
        })
        .catch(error => {
            console.log('fnInstantPaymentAccount error : ', error);
            this.showToast('error', error[0].message);
            component.set("v.isLoading", false);
        });
    },

    /* 즉시 결제 성공 시 후처리
    * 1. 선택된 Opportunity 일괄 업데이트
    */
    fnUpdateOpportunities : function(component, isFailed, resultMsg, transactionId) {
        const selectionIds  = component.get("v.selectionIds");
        const selectedTabId = component.get("v.selectedTabId");

        const params = {
                selectedIds : selectionIds,
                paymentType : selectedTabId,
                failReason  : (!isFailed) ? null : resultMsg,
                tid         : transactionId,
                paymentDate : null
        };
        console.log('fnUpdateOpportunities params : ', params);

        this.apex(component, 'updateOpportunities', params)
        .then(result => {
            console.log('fnUpdateOpportunities result : ', result);
            if (!isFailed) {
                this.showToast('success', '일괄 즉시결제가 완료되었습니다.');
                this.modalClose(component);
            }
            else{
                this.showToast('error', resultMsg);
            }
        })
        .catch(error => {
            console.log('fnUpdateOpportunities error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            if(isFailed){
                component.set("v.isCmsRegistered"   , false);
                component.set("v.isPaymentInvalid"  , true);
                component.set("v.isPrecedingInvalid", true);
                component.set("v.isIsCmsAgreement"  , true);
                this.validate(component);
            }
            component.set("v.isLoading", false);
        })
    },

    // 효성 cms 회원 삭제
    accountPaymentAfter : function(component) {
        var params = {
            'recordId' : component.get("v.recordId")
        };
        console.log('accountPaymentAfter params : ', params);

        this.apex(component, 'accountPaymentAfter', params)
        .then(result => {
            console.log('accountPaymentAfter SUCCESS');
        })
        .catch(error => {
            console.log('accountPaymentAfter error : ', error);
            this.showToast('error', error[0].message);
        });
    },


    validate : function(component) {
        try{
            // 필수 필드 누락 및 입력 형식 오류 체크
            this.inputValidCheck(component);
            // inputValidCheck 결과에 따라 회원등록, 빌키생성, 결제 버튼의 활성화/비활성화 여부를 결정한다.
            // actionEnableCheck 함수는 선행단계(빌키생성, 회원등록) 를 수행할 수 없는 상태일 경우 true 값을 반환한다.
            // actionEnableCheck 반환값은 사용자 메시지('회원 등록/빌키생성 을 먼저 진행해주세요') 출력 판단에 사용된다.
            return this.actionEnableCheck(component);
        }
        catch(e){
            console.log('validate error : ', e);
        }
    },

    // 유효성 체크 (필수 필드 누락 및 입력 형식 오류)
    inputValidCheck : function(component) {
        let invalidRequires = []; // 입력 누락된 필수 입력 필드 목록
        let invalidFormats  = []; // 입력 형식 오류 메시지 목록
        let requiredFields  = component.find("requireField");
        let valueCheckPassFields = ['BillKey__c', 'agreement']; // 입력 누락 체크 제외 필드

        if(requiredFields.length){
            requiredFields.forEach(field => {
                const fieldValue = field.get("v.value");
                const fieldName  = field.get("v.name");
                // 필수 필드 입력 누락 체크
                if(!fieldValue && !valueCheckPassFields.includes(fieldName)){
                    invalidRequires.push(field.get("v.label"));
                }
                // 입력 형식 오류 체크
                else {
                    switch (fieldName) {
                        case 'cardNumber' : // 카드번호
                            if (fieldValue.length < 15) {
                                invalidFormats.push('카드번호는 열다섯 자리 이상이어야 합니다.')
                            }
                            break;
                        case 'bankAccountNumber' : // 계좌번호
                            if (fieldValue.length < 11) {
                                invalidFormats.push('계좌번호는 열한 자리 이상이어야 합니다.')
                            }
                            break;
                        case 'cardAccountOwner' : // 카드소유자 명
                            if (fieldValue.length < 2) {
                                invalidFormats.push('카드소유자 명은 두 글자 이상이어야 합니다.')
                            }
                            break;
                        case 'cardConfirmInfo' :
                        case 'bankConfirmInfo' :
                            // VALID FORMAT : yyMMdd or 000-00-00000
                            if(!((RegExp(/\d{2}(0[1-9]|1[012])(0[1-9]|[12][0-9]|3[01])/).test(fieldValue)) || (RegExp(/[0-9]{10}/).test(fieldValue)))){
                                invalidFormats.push('생년월일/사업자등록번호는 YYMMDD 혹은 0000000000 형식이어야 합니다.');
                            }
                            break;
                        case 'CardExpiryDate__c' : // 카드 유효기간
                            // VALID FORMAT : yyyy-MM
                            if(!(RegExp(/\d{4}-(0[1-9]|1[012])/).test(fieldValue))) {
                                invalidFormats.push('유효기간은 YYYY-MM 형식이어야 합니다.');
                            }
                            break;
                        case 'agreement' : // 동의자료 업로드
                            const documentId = component.get("v.documentId");
                            if(!documentId){
                                invalidFormats.push('동의자료를 업로드는 필수입니다.');
                            }
                            break;
                    }
                }
            });
        }

        component.set("v.invalidRequires", invalidRequires);
        component.set("v.invalidFormats" , invalidFormats);

        return this.actionEnableCheck(component);
    },

    // 액션버튼 (빌키생성, 회원등록, 결제) 활성화 여부 체크
    actionEnableCheck : function(component) {

        let isPaymentInvalid   = true; // 결제 버튼 비활성화 여부
        let isPrecedingInvalid = true; // 빌키생성 / 회원등록 등 필수 선행 액션 버튼 비활성화 여부

        const invalidRequires = component.get("v.invalidRequires");
        const invalidFormats  = component.get("v.invalidFormats");
        const selectedTabId   = component.get("v.selectedTabId");
        const selectedPayment = component.get("v.selectedPayment");
        let   isCmsRegistered = component.get("v.isCmsRegistered");

        // 입력 오류 및 필수 필드 누락 존재 여부
        let inputInvalid = (invalidRequires.length > 0) || (invalidFormats.length > 0);
        console.log(' * * * * * * * * * * * * * * * * * * * * * * * * * * *');
        switch (selectedTabId) {
            case '카드' :
                isPrecedingInvalid = !(!inputInvalid && !selectedPayment.BillKey__c);
                isPaymentInvalid   = !selectedPayment.BillKey__c;
                break;
            case '은행계좌' :
                let cmsAccountKey = component.get("v.cmsAccountKey");
                let {BankAccountCode__c : bankCode, Secure_AccountNo__c : accountNo} = selectedPayment;
                // 효성 cms에 계좌가 등록되어 있고 현재 선택된 결제수단의 계좌번호 및 은행코드가 입력된 경우
                // 등록 계좌 정보와 선택 계좌 정보를 비교한다.
                // 계좌 정보가 다를 경우 회원등록을 선행하도록 강제한다.
                // 계좌 정보가 동일한 경우 '회원등록' 버튼 비활성화 및 '결제' 버튼 활성화한다.
                if(cmsAccountKey && accountNo && bankCode){
                    // 사용자 선택 결제정보를 String Key 값으로 조합힌다. (format : {계좌번호 + 은행코드})
                    let selectedAccountKey = (accountNo + bankCode);
                    // 입력된 계좌번호 길이가 유효할 경우 비교 판단 진행한다.
                    if(selectedAccountKey.length >= 11){
                        // CMS에서 조회된 계좌번호는 인덱스 3~7 사이 글자가 '*'으로 마스킹 처리되어 반환되므로
                        // 비교값에 사용할 선택 계좌 정보 키값 또한 동일하게 마스킹 처리한다.
                        selectedAccountKey = selectedAccountKey.replace(selectedAccountKey.substring(3, 7), '****');
                        // 등록 계좌 정보와 선택 계좌 정보가 동일할 경우 회원등록이 완료된 것으로 간주해 해당 버튼을 비활성화한다.
                        isCmsRegistered = (cmsAccountKey == selectedAccountKey);
                    }
                    console.log('actionEnableCheck selectedAccountKey : ', selectedAccountKey);
                }
                else {
                    isCmsRegistered = false;
                }

                console.log('actionEnableCheck cmsAccountKey   : ', cmsAccountKey);
                console.log('actionEnableCheck isCmsRegistered : ', isCmsRegistered);

                if(isCmsRegistered){
                    inputInvalid = false;
                    component.set("v.invalidRequires", []);
                    component.set("v.invalidFormats", []);
                }

                isPrecedingInvalid = (isCmsRegistered || inputInvalid);
                isPaymentInvalid   = !isCmsRegistered;
                console.log('actionEnableCheck isPrecedingInvalid : ', isPrecedingInvalid);
                console.log('actionEnableCheck isPaymentInvalid   : ', isPaymentInvalid);
                break;
        }

        component.set("v.isPaymentInvalid"  , isPaymentInvalid);
        component.set("v.isPrecedingInvalid", isPrecedingInvalid);

        return isPaymentInvalid;
    },

	showToast : function(type, message) {
        var evt = $A.get("e.force:showToast");
        evt.setParams({
            key     : "info_alt",
            type    : type,
            message : message
        });
        evt.fire();
    },

    /**
     * 결제 진행 전 확인 창 hs.jung 3/20
     */
    doCreateConfirmComponent : function(component, param) {
        console.log( ' doCreateConfirmComponent 2:::: ');
        $A.createComponent(
            "c:DN_Confirm",
            {
                "sHeader"       : param.sHeader,
                "sContent"      : param.sContent,
                "sConfirmBtn"   : param.sConfirmBtn,
                "sCancelBtn"    : param.sCancelBtn,
                "confirmAction" : param.confirmAction
            },
            function(cCommonConfirm, status, errorMessage) {
                if(status === "SUCCESS") {
                    // callback action
                    component.set("v.CommonConfirm", cCommonConfirm);

                } else if (status === "INCOMPLETE") {
                    console.log("No response from server or client is offline.");
                } else if (status === "ERROR") {
                    console.log("Error: " + errorMessage);
                }
            }
        );
    },

    forceInitialize : function(){
        this.refreshView = $A.get("e.force:refreshView");
        this.closeQuickAction = $A.get("e.force:closeQuickAction");
    },

    modalClose : function(component){
        const selectedTabId    = component.get("v.selectedTabId");
        const isPaymentInvalid = component.get("v.isPaymentInvalid");

       if('은행계좌' === selectedTabId){
            this.accountPaymentAfter(component);
       }

       this.refreshView.fire();
       this.closeQuickAction.fire();
    },

    apex : function(component, apexMethod, params) {
        return new Promise($A.getCallback(function(resolve, reject) {
            try {
                var action = component.get("c." + apexMethod);
                action.setParams(params);
                action.setCallback( this , function(response) {
                    var state  = response.getState();
                    if(state == 'SUCCESS') {
                        resolve(response.getReturnValue());
                    }
                    if(state == 'ERROR') {
                        var errors = response.getError();
                        reject(errors);
                    }
                });
                $A.enqueueAction(action);
            }
            catch(e){
                this.showToast('error', '알수없는 오류가 발생했습니다. 관리자에게 문의하세요.');
            }
        }));
    },
});