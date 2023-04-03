/************************************************************************************
 * Description : 후원금 즉시결제의 은행계좌 탭 : 결제진행 버튼 (출금신청)
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2022-09-29     hs.jung          Create
*************************************************************************************/

public with sharing class IF_HYOSUNG_INSTANT_PAYMENT {
    private IF_HYOSUNG_INSTANT_PAYMENT() {
    }
    private static IF_HYOSUNG_INSTANT_PAYMENT sInstance = null;

    // 클래스 인스턴스화 함수
    public static IF_HYOSUNG_INSTANT_PAYMENT getInstance() {
        if (sInstance == null) sInstance = new IF_HYOSUNG_INSTANT_PAYMENT();
        return sInstance;
    }
    // 인터페이스 호출 정보
    private static final String IFID = 'IF_HYOSUNG_INSTANT_PAYMENT';


    public class RequestPayload {
        public String  transactionId;  // 거래 ID(고유 값) 30
        public String  memberId;       // 회원 ID  20
        public Decimal callAmount;     // 결제 요청 금액
    }

    // 응답 파라미터 명세
    public class ResponsePayload {
        public Payment payment;
        public ErrorWrapper error;
    }

    public class Payment {
        public String status;
        public String transactionId;
        public String memberId;
        public String memberName;
        public String paymentDate;
        public String callAmount;
        public String actualAmount;
        public String fee;

        public Result result;
        public List<Links> links;

    }

    public class Result {
        public String flag;
        public String code;
        public String message;
    }

    public class Links {
        public string rel;
        public string href;
    }

    public class ErrorWrapper {
        public string message;
        public string developerMessage;
    }



    public ResponsePayload execute(RequestPayload objInput, List<Id> selectedIds) {
        ResponsePayload objOutput = new ResponsePayload();

        try{
            String requestBody = System.JSON.serialize(objInput);
            requestBody += '--IF_LOG_DESCRIPTION--';
            requestBody += '결제 대상 후원금 : ' + String.join(selectedIds, ', ');
            IFUtil ifUtil = new IFUtil(IFID);

            HttpResponse response = ifUtil.webCallout(requestBody, true);
            String responseBody = response.getBody();
            system.debug('출금신청 responseBody : ' + responseBody);
            system.debug(' 출금신청 deserialize   >>>>>>  ' + JSON.deserialize(responseBody, ResponsePayload.class));
            //responseBody = '{"payment":{"status":"처리완료","transactionId":"HS_002405930_20230220190734","memberId":"0030p00000ZrSILAA3","memberName":"이지은","paymentDate":"2023/02/20","callAmount":30000,"actualAmount":0,"fee":800,"result":{"flag":"N","code":"3001","message":"잔액부족"},"links":[{"rel":"self","href":"http://api-test.hyosungcms.co.kr/v1/custs/sdsitest/payments/realcms/HS_002405930_20230220190734"}]}}';
            objOutput = (ResponsePayload) JSON.deserialize(responseBody, ResponsePayload.class);

        }
        catch (Exception e) {
            if(!test.isRunningTest()){
                system.debug('getLineNumber : ' + e.getLineNumber() +' :::' + e.getMessage());
                objOutput.Payment.result.Code = '-1';
                objOutput.Payment.result.message = '에러가 발생했습니다(' + e.getLineNumber() + ') : ' + e.getMessage();
            }

        }

        return objOutput;
    }

}