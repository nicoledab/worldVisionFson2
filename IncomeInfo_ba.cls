/************************************************************************************
 * Description : IF-INCOME-001 입금내역 조회
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2023-02-07     hs.jung          Create
*************************************************************************************/

//  실행 : Database.executeBatch(new IncomeInfo_ba(system.today().addDays(-1)));

global class IncomeInfo_ba implements Database.Batchable<Sobject>, Database.Stateful, Database.AllowsCallouts {
    global Datetime targetDate;

    public IncomeInfo_ba() {
    }

    global IncomeInfo_ba(Datetime dt) {
        if (dt <> null) {
            dt.format('yyyyMMdd');
            this.targetDate = dt;
        }
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
                SELECT Id
                FROM Contact
                LIMIT 1
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Contact> scope) {
        try {
            List<LocalAccountNo__c> listAccountNos = [
                    SELECT BankAccountNo__c, AccountNo_NoHyphen__c
                    FROM LocalAccountNo__c
                    WHERE Deposit_List_Target__c = true
            ];

            IF_ERP_INCOME_INQ.Input objInput = new IF_ERP_INCOME_INQ.Input();
            IF_ERP_INCOME_INQ.Output objOutput = new IF_ERP_INCOME_INQ.Output();

            objInput.data.trnxdate = String.valueOf(targetDate.format('yyyyMMdd'));

            objInput.data.accountNo = new List<String>();
            objInput.data.cmsNo = new List<String>();
            for (LocalAccountNo__c obj : listAccountNos) {
                objInput.data.accountNo.add(obj.BankAccountNo__c.replace('-', ''));
                objInput.data.cmsNo.add(obj.BankAccountNo__c.replace('-', ''));

            }

//        :::: 인터페이스 정의서 test request  ::::::
//        objInput.data.accountNo = new List<String>{'099010230413', '08301217230'};
//        objInput.data.cmsNo = new List<String>{'26980074318277', '26980074318593'};

            System.debug('objInput ::::' + objInput);
            objOutput = IF_ERP_INCOME_INQ.getInstance().execute(objInput);
            System.debug('obj Output ! ::::' + objOutput);

            if (!Test.isRunningTest()) {
                if (!objOutput.result.isEmpty()) {
                    System.debug('objOutput Empty check !');
                    doInsertIncome(objOutput.result, targetDate); // 입금처리(InCome__c) 객체에 필드 맵핑 insert
                }
            }

        } catch (CalloutException ce) {
            System.debug('CalloutException] getMessage() : ' + ce.getMessage());
        }

    }

    public static void doInsertIncome(List<IF_ERP_INCOME_INQ.resultWrapper> datas, datetime targetDate) {
        try {
            Date targetDateForm = Date.newInstance(targetDate.year(), targetDate.month(), targetDate.day());

            // Create and insert Income record
            Income__c objIncome = new Income__c();
            objIncome.Type__c = 'bank';
            objIncome.IncomeDate__c = targetDateForm;
            objIncome.TypeName__c = '계좌 입금 내역 : ' + string.valueOf(targetDateForm);
            insert objIncome;

            Set<String> accountSetNos = new Set<String>();
            for (IF_ERP_INCOME_INQ.resultWrapper wrapper : datas) {
                accountSetNos.add(wrapper.accountNo);
            }

            List<LocalAccountNo__c> listAccountNos = [
                    SELECT Id, BankAccountNo__c, AccountNo_NoHyphen__c
                    FROM LocalAccountNo__c
                    WHERE AccountNo_NoHyphen__c = :accountSetNos
            ];

            Map<String, LocalAccountNo__c> accountNoToRecordMap = new Map<String, LocalAccountNo__c>();
            for (LocalAccountNo__c record : listAccountNos) {
                accountNoToRecordMap.put(record.AccountNo_NoHyphen__c, record);
            }

            List<IncomeDetail__c> incomeDetailsToInsert = new List<IncomeDetail__c>();
            for (IF_ERP_INCOME_INQ.resultWrapper wrapper : datas) {
                IncomeDetail__c objIncomeDetail = new IncomeDetail__c();
                objIncomeDetail.Income__c = objIncome.Id;
                objIncomeDetail.bankAccountMemo__c = wrapper.bankAccountMemo;
                objIncomeDetail.virtualAccountNo__c = wrapper.virtualAccountNo;
                objIncomeDetail.Amount__c = Integer.valueOf(wrapper.amount);
                objIncomeDetail.IncomeType__c = wrapper.inComeType;
                objIncomeDetail.PurchaseNo__c = Integer.valueOf(wrapper.purchaseNo);
                objIncomeDetail.PurchaseDate__c = targetDateForm;
                objIncomeDetail.purchaseType__c = wrapper.purchaseType;

                if (accountNoToRecordMap.containsKey(wrapper.accountNo)) {
                    objIncomeDetail.AccountNo__c = accountNoToRecordMap.get(wrapper.accountNo).BankAccountNo__c;
                }else{
                    objIncomeDetail.AccountNo__c = '';
                }

                incomeDetailsToInsert.add(objIncomeDetail);
            }

            insert incomeDetailsToInsert;
        } catch (Exception e) {
            System.debug('LineNumber: ' + e.getLineNumber() + ', Message: ' + e.getMessage());
        }
    }


    global void finish(Database.BatchableContext bc) {
        system.debug('IncomeInfo_ba finish access');

    }
}