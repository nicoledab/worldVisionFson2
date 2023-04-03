/**
 * Created by daeunextier_je.lee on 2022-12-27.
 */

({

    fnInit : function(component, event, helper) {
        helper.forceInitialize();
        helper.getInitData(component);
    },

    fnClose : function(component, event, helper) {
         helper.modalClose(component);
    },

    fnPrevious : function(component, event, helper){
        component.set("v.isLoading", true);
        component.set("v.currentStep", "1");
        component.set("v.isLoading", false);
    },

    fnNext : function(component, event, helper) {
        component.set("v.currentStep", '2');
        helper.fnGetPaymentTypeList(component);
    },

    handleTabActive : function (component, event, helper){
        var targetId = event.getSource().get("v.id");
        component.set('v.selectedTabId', targetId);
        helper.fnGetPaymentTypeList(component);
    },

    handleOpportunitySelect : function (component, event, helper) {
        var selectedRows = event.getParam('selectedRows');
        var selectionIds = selectedRows.map(target => target.Id);
        var totalAmt = selectedRows.reduce(
            (a, b) => a + b.Amount, 0
        );
        component.set("v.totalAmt", totalAmt);
        component.set('v.totalCnt', selectionIds.length);
        component.set("v.selectionIds", selectionIds);
    },

    handlePaymentSelected :  function (component, event, helper) {
        var targetId = event.getSource().get("v.value");
        component.set('v.selectedPaymentId', targetId);
        helper.fnGetPaymentDetail(component);
    },

    /* 유효성 체크 */
    fnValidCheck : function(component, event, helper) {
        helper.validate(component);
    },

    /* 이니시스 빌키 생성 */
    fnGenerateBillKey : function(component, event, helper){
        helper.generateBillKey(component);
    },

    /* 효성 CMS 멤버 등록*/
    fnCmsRegister : function(component, event, helper){
        helper.agreementRegister(component);
    },

    /* 금일 기준 1년 상품 조회하기  hs.Jung 추가 */
    fnInquiryDate : function(component, event, helper){
        component.set("v.isLoading", true);

        component.set("v.selectionIds", []);
        component.set("v.totalAmt", 0);
        component.set('v.totalCnt', 0);
        helper.getOpportunityList(component);
    },


    // 결제 진행하기 전 confirm 메세지 :  hs.Jung 추가 3/20
    fnBeforePayConfirm : function(component, event, helper) {
        var selectedPayment = component.get("v.selectedPayment");
        var amount = component.get("v.totalAmt");
        var formattedAmount = parseInt(amount).toLocaleString();

        var sContent = "결제수단 : " + selectedPayment.Name + "\n" + "<br/>" +
                   "결제금액 : ₩" + formattedAmount;

        var param = {
            "sHeader"       : "결제를 진행하시겠습니까?",
            "sContent"      : sContent,
            "sConfirmBtn"   : "네",
            "sCancelBtn"    : "아니오",
            "confirmAction" : component.getReference("c.fnPayment")
        };
        helper.doCreateConfirmComponent(component, param);
    },

    // 결제 진행
    fnPayment : function (component, event, helper) {
        helper.forceInitialize();

        const selectedTabId = component.get("v.selectedTabId");

        switch (selectedTabId) {
            case '카드' : // 현재 선택된 결제수단이 카드인 경우
                helper.fnInstantPaymentCard(component);
                break;
            case '은행계좌' : // 현재 선택된 결제수단이 은행계좌인 경우
                helper.fnInstantPaymentAccount(component);
                break;
        }
    },

    handleUploadFinished : function(component, event, helper) {

        const {documentId} = event.getParam('files')[0];
        component.set("v.documentId", documentId);
        helper.contentVersionUpdate(component);

    },

});