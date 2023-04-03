/**
 * Created by hs.jung on 2022-09-15.
 */

({
    refreshView : null,
    closeQuickAction : null,
    paymentStages : ['청구에러', 'Closed Lost', 'Pledged'],

    getInitData : function(component)  {
        try {
            component.set("v.showSpinner", true);

            const selectedTabId =  component.get("v.selectedTabId");
            const params = {
                'recordId' : component.get("v.recordId"),
                'strType'  : selectedTabId
            };

            this.apex(component, 'getInitData', params)
            .then(result => {
                console.log('getInitData result : ', result);
                let invalidMsg;
                const {listPaymentType, isAccountPaymentUser, bankOptions, cmsAccountKey, currentOppty} = result;

                if(!this.paymentStages.includes(currentOppty.StageName)){
                    invalidMsg = '즉시결제를 실행할 수 없는 후원금 단계입니다.';
                }

                if(invalidMsg){
                    this.showToast('error', invalidMsg);
                    this.modalClose(component);
                }

                component.set("v.bankOptions"         , bankOptions);
                component.set("v.cmsAccountKey"       , cmsAccountKey);
                component.set("v.opptyAmount"         , currentOppty.Amount);
                component.set("v.contactId"           , currentOppty.npsp__Primary_Contact__c);
                component.set("v.isCmsRegistered"     , currentOppty.npsp__Primary_Contact__r.CMS_InstantPayment_Register_YN__c);
                component.set("v.isAccountPaymentUser", isAccountPaymentUser);

                // 좌측 결제수단 라디오 그룹 옵션 목록 세팅
                this.fnOptionRender(component, listPaymentType);
            })
            .catch(error => {
                 console.log('fnGetInitData error : ', error);
                 this.showToast('error', error[0].message);
            })
            .then(() => {
                component.set("v.showSpinner", false);
            });
        }
        catch (e) {
            console.log('getInitData error : ', e);
        }
    },

    // 결제수단 목록 조회
    fnGetPaymentTypeList : function(component) {

        component.set("v.showSpinner", true);
        component.set('v.isPrecedingInvalid', true);
        component.set('v.isPaymentInvalid', true);
        component.set("v.documentId", null);

        var params = {
            recordId : component.get("v.recordId"),
            strType  : component.get("v.selectedTabId")
        };

        this.apex(component, 'getPaymentTypeList', params)
        .then(result => {
            console.log('getPaymentTypeList result : ', result);
            this.fnOptionRender(component, result);
        })
        .catch(error => {
            console.log('getPaymentTypeList error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            component.set("v.showSpinner", false);
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

        component.set("v.paymentOptions", options);

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

        component.set("v.showSpinner", true);
        component.set('v.isPaymentInvalid'  , true); // 결제버튼 비활성화 여부
        component.set('v.isPrecedingInvalid', true); // 회원등록, 빌키생성 버튼 비활성화 여부
        component.set("v.documentId", null);

        const selectedTabId = component.get("v.selectedTabId");
        const selectedPaymentId = component.get("v.selectedPaymentId");

        if(selectedPaymentId === '직접입력'){
            const directPayment = {
                'Id'      : `직접입력`,
                'Name'    : `${selectedTabId} 직접입력`,
                'Type__c' : selectedTabId
            };
            component.set("v.selectedPayment", directPayment);
            this.validate(component);
            component.set("v.showSpinner", false);
            return true;
        }

        this.apex(component, 'getPaymentType', {'paymentId' : selectedPaymentId})
        .then(result => {
            console.log('fnGetPaymentDetail result : ', result);
            let {CardExpiryDate__c : cardExpiryDate} = result;

            // 카드 유효기간 필드 값을 yyyy-MM 형식에 맞춰 재정의
            if(cardExpiryDate){
                cardExpiryDate = cardExpiryDate.substring(0, 7);
            }

            result.CardExpiryDate__c = cardExpiryDate;
            component.set("v.selectedPayment", result);

            if(this.validate(component)){
                const preceding = ('카드' == selectedTabId) ? '빌키생성' : '회원등록';

                const toastMsg  = `결제 전에 ${preceding}을 먼저 진행해주세요`;
                this.showToast('warning', toastMsg);
            }
        })
        .catch(error => {
            console.log('fnGetPaymentDetail error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            component.set("v.showSpinner", false);
        });
    },

    // 빌키 발급
    generateBillKey : function(component){
        component.set("v.showSpinner", true);

        const selectedPaymentId = component.get("v.selectedPaymentId");
        const selectedPayment   = component.get("v.selectedPayment");
        const cardExpiryDate    = selectedPayment.CardExpiryDate__c;

        if(selectedPaymentId == '직접입력'){ // SObject 파라미터로 전송될 때 TypeError 발생으로 직접입력일 경우 null 처리 후 원복함
            selectedPayment.Id = null;
        }

        selectedPayment.CardExpiryDate__c = cardExpiryDate + '-01';

        const params = {
            'selectedPayment' : selectedPayment
        };

        this.apex(component, 'generateBillKey', params)
        .then(result => {
            console.log('generateBillKey result : ', result);
            const {isFailed, resultMsg, billKey} = result;

            selectedPayment.Id = selectedPaymentId;
            selectedPayment.BillKey__c = billKey;
            selectedPayment.CardExpiryDate__c = cardExpiryDate;

            component.set('v.selectedPayment', selectedPayment);

            if(isFailed){
                this.showToast('error', resultMsg);
                component.set("v.showSpinner", false);
                return;
            }

            this.validate(component);
            this.showToast('success', '빌키 생성이 완료되었습니다.');
        })
        .catch(error => {
            console.log('generateBillKey error : ', error);
            const {message, stackTrace} = error[0];
            this.showToast('error', message + '\r\n' + stackTrace);
        })
        .finally(() => {
            component.set("v.showSpinner", false);
        })
    },

    // 카드 결제 진행
    fnInstantPaymentCard : function(component) {
        component.set("v.showSpinner", true);
        const selectedPayment   = component.get('v.selectedPayment');
        const selectedPaymentId = component.get('v.selectedPaymentId');
        const recordId          = component.get('v.recordId');
        const amount            = component.get('v.opptyAmount');

        delete selectedPayment.CardExpiryDate__c;

        const params = {
                 'recordId'        : recordId,
                 'selectedPayment' : selectedPayment,
                 'amount'          : amount
        };

        this.apex(component, 'instantPaymentCard', params)
        .then(result => {
            console.log('instantPayCard result : ', result);
            const {resultCode, resultMsg, transactionId} = result;
            if(resultCode == '00'){ // 성공일 경우
                this.showToast('success', '카드 즉시결제가 완료되었습니다.');
                this.modalClose(component);
            }
            else {
                this.showToast('error', resultMsg);
            }
        })
        .catch(error => {
            console.log('fnInstantPaymentCard error : ', error);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            component.set("v.showSpinner", false);
        });
    },

    // 은행계좌 즉시결제 진행
    fnInstantPaymentAccount : function(component) {

        component.set("v.showSpinner", true);
        const selectedPayment = component.get("v.selectedPayment");

        var params = {
            recordId        : component.get("v.recordId"),
            contactId       : component.get("v.contactId"),
            amount          : component.get("v.opptyAmount"),
            selectedPayment : selectedPayment
        };

        this.apex(component, 'instantPaymentAccount', params)
        .then(result => {
            console.log('fnInstantPaymentAccount success result : ', result);
            var {resultMsg, isFailed, transactionId} = result;
            if(isFailed){
                component.set("v.isCmsRegistered"   , false);
                component.set("v.isPaymentInvalid"  , true);
                component.set("v.isPrecedingInvalid", true);
                component.set("v.isIsCmsAgreement"  , true);
                this.validate(component);
                this.showToast('error', resultMsg);
                component.set("v.showSpinner", false);
            }
            else{
                this.showToast('success', '일괄 즉시결제가 완료되었습니다.');
                this.modalClose(component);
            }
        })
        .catch(error => {
            console.log('fnInstantPaymentAccount error : ', error);
            this.showToast('error', error[0].message);
            component.set("v.showSpinner", false);
        });
    },

    // 은행계좌 즉시결제 완료 후 후처리 (업로드 된 동의자료 파일 삭제 및 해당 후원자의 효성 CMS 회원 정보 삭제)
    accountPaymentAfter : function(component) {
        var params = {
            recordId  : component.get("v.recordId"),
            contactId : component.get("v.contactId")
        };

        this.apex(component, 'accountPaymentAfter', params)
        .then(result => {
            console.log('accountPaymentAfter result : ', result);
        })
        .catch(error => {
            console.log('accountPaymentAfter error : ', error);
        });
    },

    /* 효성 CMS 동의자료 등록 */
    agreementRegister :  function(component) {
        component.set("v.showSpinner", true);
        var params = {
            contactId   : component.get("v.contactId"),
            documentId : component.get("v.documentId")
        };

        this.apex(component, 'agreementRegister', params)
        .then(result => {
            console.log('agreementRegister result : ', result);
            var {resultMsg, isFailed} = result;

            if (isFailed) {
                this.showToast('error', resultMsg);
                component.set("v.showSpinner", false);
            }
            else {
                this.cmsMemberRegister(component);
            }
        })
        .catch(error => {
            console.log('agreementRegister error : ', error);
            this.showToast('error', error[0].message);
            component.set("v.showSpinner", false);
        });
    },

    /* 효성 CMS 멤버 등록 및 갱신  */
    cmsMemberRegister :  function(component) {
        component.set("v.showSpinner", true);
        var selectedPayment = component.get("v.selectedPayment");

        var params = {
            contactId : component.get("v.contactId"),
            selectedPayment : selectedPayment
        };

        this.apex(component, 'cmsMemberRegister', params)
        .then(result => {
            // 결과 확인
            console.log('cmsMemberRegister result : ', result);

            const {isFailed, resultMsg, memberId, bankCode, paymentNumber} = result;

            if(bankCode && paymentNumber){
                component.set("v.cmsAccountKey", (paymentNumber + bankCode));
            }

            // failed result handling
            if(isFailed){
                this.showToast('error', resultMsg);
                return true;
            }

            // attribute setting
            component.set("v.isCmsRegistered", true);
            component.set("v.cmsAccountKey"  , (paymentNumber + bankCode));
            // invalid check
            this.validate(component);
            this.showToast('success', '회원등록이 성공적으로 진행되었습니다.');
        })
        .catch(error => {
            console.log('fnCmsMemberRegister error : ', error);
            this.showToast('error', error[0].message);
        })
        .then(() => {
            component.set("v.showSpinner", false);
        })
    },


    // 동의자료 여부 필드 업데이트
    contentVersionUpdate : function(component) {
        const documentId = component.get("v.documentId");
        const param = {'documentId' : documentId};

        this.apex(component, 'contentVersionUpdate', param)
        .then(result => {
            console.log('contentVersionUpdate result : ', result);
        })
        .catch(error => {
            console.log('contentVersionUpdate error : ', error);
            component.set("v.documentId", null);
            this.showToast('error', error[0].message);
        })
        .finally(() => {
            this.validate(component);
        })
    },

    forceInitialize : function(){
        this.refreshView = $A.get("e.force:refreshView");
        this.closeQuickAction = $A.get("e.force:closeQuickAction");
    },

    // Quick Action 종료 및 기존 화면 Refresh
    modalClose : function(component){
        const selectedTabId    = component.get("v.selectedTabId");
        const isPaymentInvalid = component.get("v.isPaymentInvalid");

       if('은행계좌' === selectedTabId){
            this.accountPaymentAfter(component);
       }

       this.refreshView.fire();
       this.closeQuickAction.fire();
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

    // 필수 필드 누락 및 입력 형식 오류 체크
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
                                invalidFormats.push('카드번호는 열다섯 자리 이상이어야 합니다.');
                            }
                            break;
                        case 'bankAccountNumber' : // 계좌번호
                            if (fieldValue.length < 11) {
                                invalidFormats.push('계좌번호는 열한 자리 이상이어야 합니다.');
                            }
                            break;
                        case 'cardAccountOwner' : // 카드소유자 명
                            if (fieldValue.length < 2) {
                                invalidFormats.push('카드소유자명은 두 글자 이상이어야 합니다.');
                            }
                            break;
                        case 'cardConfirmInfo' :
                        case 'bankConfirmInfo' :
                            // VALID FORMAT : yyMMdd or 0000000000
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
                                invalidFormats.push('동의자료를 업로드해 주세요.');
                            }
                            break;
                    }
                }
            });
        }
        component.set("v.invalidRequires", invalidRequires);
        component.set("v.invalidFormats" , invalidFormats);

    },

    // 액션버튼 (빌키생성, 회원등록, 결제) 활성화 여부 체크
    actionEnableCheck : function(component) {

        let isPrecedingInvalid = true;
        let isPaymentInvalid   = true;

        const invalidRequires = component.get("v.invalidRequires");
        const invalidFormats  = component.get("v.invalidFormats");
        const selectedPayment = component.get("v.selectedPayment");
        const selectedTabId   = component.get("v.selectedTabId");
        let   isCmsRegistered = component.get("v.isCmsRegistered");

        // 입력 오류 및 필수 필드 누락 존재 여부
        let   inputInvalid = (invalidRequires.length > 0) || (invalidFormats.length > 0);

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
                console.log('actionEnableCheck cmsAccountKey : ', cmsAccountKey);

                if(isCmsRegistered){
                    inputInvalid = false;
                    component.set("v.invalidRequires", []);
                    component.set("v.invalidFormats", []);
                }

                isPrecedingInvalid = (isCmsRegistered || inputInvalid);
                isPaymentInvalid   = !isCmsRegistered;
                break;
        }
        component.set("v.isPaymentInvalid"  , isPaymentInvalid);
        component.set("v.isPrecedingInvalid", isPrecedingInvalid);

        return isPaymentInvalid;
    },


    /**
     * 토스트 메세지 출력 이벤트 발생
     * @param {string} type 메세지 유형 (success, error, info, warning, other)
     * @param {string} message 토스트에 보여질 메세지
     */
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
                //console.log('apex error : ', e);
            }
        }));
    },

});