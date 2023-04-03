/**
 * Created by hs.jung on 2022-09-15.
 */

({

    fnInit : function(component, event, helper) {
        helper.forceInitialize();
        helper.getInitData(component);
    },

    // 결제수단 목록 중 하나 선택 시
    choosePayment : function(component, event, helper){
        helper.fnGetPaymentDetail(component);
    },

    fnCancel: function(component, event, helper) {
        helper.modalClose(component);
    },

    fnValidCheck : function(component, event, helper){
       helper.validate(component);
    },

    clickPaymentTab : function(component, event, helper){
        var targetId = event.getSource().get("v.id");
        component.set("v.selectedTabId", targetId);
        helper.fnGetPaymentTypeList(component);
    },

    handleUploadFinished : function(component, event, helper) {
        const {documentId} = event.getParam('files')[0];
        component.set("v.documentId", documentId);
        helper.contentVersionUpdate(component);
    },

    // 2023-01-30 je.lee 추가
    fnCmsRegister : function(component, event, helper) {
        helper.agreementRegister(component);
    },

    //빌키 발급
    fnBillKeyGenerate : function(component, event, helper) {
        helper.generateBillKey(component);
    },

    // 결제 진행하기 전 confirm
    fnBeforePayConfirm : function(component, event, helper) {
        var selectedPayment = component.get("v.selectedPayment");
        var amount = component.get("v.opptyAmount");
        var formattedAmount = parseInt(amount).toLocaleString();

        var sContent = "결제수단 : " + selectedPayment.Name + "\n" + "<br/>" +
                   "결제금액 : ₩" + formattedAmount;

        var param = {
            "sHeader"       : "결제를 진행하시겠습니까?",
            "sContent"      : sContent,
            "sConfirmBtn"   : "네",
            "sCancelBtn"    : "아니오",
            "confirmAction" : component.getReference("c.fnPay")
        };
        helper.doCreateConfirmComponent(component, param);
    },

    // 결제 진행
    fnPay : function(component, event, helper) {
        console.log('결제 진행::: ');
        helper.forceInitialize();

        var selectedTabId = component.get('v.selectedTabId');

        switch (selectedTabId) {
            case '카드' :
                helper.fnInstantPaymentCard(component);
                break;
            case '은행계좌' :
                helper.fnInstantPaymentAccount(component);
                break;
        }
    },
});