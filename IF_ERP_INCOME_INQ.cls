/************************************************************************************
 * Description : IF-INCOME-001 입금내역 조회
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2023-02-13     hs.jung          Create
*************************************************************************************/

public with sharing class IF_ERP_INCOME_INQ {

    private IF_ERP_INCOME_INQ() { }

    private static IF_ERP_INCOME_INQ sInstance = null;

    public static IF_ERP_INCOME_INQ getInstance() {
        System.debug('IF_ERP_INCOME_INQ getInstance()  ' );
        if (sInstance == null) sInstance = new IF_ERP_INCOME_INQ();
        return sInstance;
    }

    // 인터페이스 호출 정보
    private static final String IFID = 'IF_ERP_INCOME_INQ';  //IF_ERP_INCOME_INQ

    public class Input {
        public DataWrapper data; 
        public input(){
            data = new DataWrapper();
        }
    }

    public class Output {
        public string code;
        public string message;
        public List<resultWrapper> result;

    }

    public class DataWrapper {
        public string trnxdate;  // ex) 20230105
        public String[] accountNo;
        public String[] cmsNo;
//        public String[] accountHyphenNo; // '-'

    }

    public class resultWrapper {
        public string bankAccountMemo;
        public string accountNo; //
        public string virtualAccountNo;
        public string amount;
        public string inComeType;
        public string purchaseNo;
        public string purchaseDate;
        public string purchaseTime;
        public string purchaseType;
    }



    public Output execute(Input objInput) {
        system.debug('IF_ERP_INCOME_INQ execute access >>> ' + objInput );
        Output objOutput = new Output();
        String requestBody = JSON.serialize(objInput);
        String responseBody = null;
        try{
            IFUtil ifUtil = new IFUtil(IFID);
            system.debug('encoded requestBody : ' + requestBody);
            HttpResponse response = ifUtil.webCallout(requestBody, true);

            if(response.getStatusCode() == 200) {
                responseBody = response.getBody();
                System.debug('IF_ERP_INCOME_INQ execute OK ');
                objOutput = (Output) JSON.deserialize(responseBody, Output.class);
            }

        }
        catch (Exception e) {
            system.debug('IF_ERP_INCOME_INQ execute error line : ' + e.getLineNumber() + ' , message : ' + e.getMessage());
            objOutput.code = '-1';
            objOutput.message = '에러가 발생했습니다. : ' + e.getMessage();
        }

        return objOutput;
    }

}