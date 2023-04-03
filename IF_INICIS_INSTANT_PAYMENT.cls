/************************************************************************************
 * Description :
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2022-09-29     hs.jung          Create
*************************************************************************************/

public with sharing class IF_INICIS_INSTANT_PAYMENT {
    // 클래스 생성자
    private IF_INICIS_INSTANT_PAYMENT() {
    }
    private static IF_INICIS_INSTANT_PAYMENT sInstance = null;

    // 클래스 인스턴스화 함수
    public static IF_INICIS_INSTANT_PAYMENT getInstance() {
        if (sInstance == null) sInstance = new IF_INICIS_INSTANT_PAYMENT();
        return sInstance;
    }

    // 인터페이스 호출 정보
    private static final String IFID = 'IF_INICIS_INSTANT_PAYMENT';

    // MID - TEST : INIBillTst
    private static String inicis_key; // TEST : rKnPljRn5m6J9Mzz
    private static String inicis_iv;  // TEST : W2KLNKra6Wxc1P==

    // 요청 파라미터 명세 : 빌링승인 요청
    public class RequestPayload {

        /* 필수 파라미터 */
        public String type = 'Billing';                 // 고정값
        public String paymethod = 'Card';               // [Card:신용카드, HPP:휴대폰]
        public String timestamp = System.now().format('YYYYMMddHHmmss'); // 전문생성일시

        public String  clientIp;                         // 가맹점 요청 서버IP (추후 거래 확인 등에 사용됨)
        public String  mid;                              // 가맹점 ID
        public String  url = System.Url.getSalesforceBaseUrl().getHost(); // 가맹점 url
        public String  moid;                             // 가맹점 주문번호
        public String  goodName;                         // 상품명
        public String  buyerName;                        // 구매자명
        public String  buyerEmail;                       // 구매자 이메일주소 "@", "." 외 특수문자 입력불가
        public String  buyerTel;                         // 구매자 연락처
        public Decimal price = 0;                       // 결제금액
        public String  billKey;                          // 승인요청할 빌링키 값
        public String  authentification = '00';          //  본인인증 여부 ["00" 고정] , 본인인증 안함 가맹점으로 별도계약된 경우 "99" 로 세팅

        public String regNo;                            // 생년월일 [YYMMDD] 또는 사업자번호
        public String cardPw;                           // 카드비밀번호 앞 2자리
        public String tax;                              // 비과세  - "부가세 업체정함" 계약가맹점만 설정필요
        public String taxFree;                          // 비과세  - "부가세 업체정함" 계약가맹점만 설정필요
        public String currency_x ='';                   // 통화코드 [WON,USD] 'currency'는 SF의 예약어
        public String cardQuota;                        // 할부기간 ["00":일시불, 그 외 : 02, 03 ...]
        public String quotaInterest;                    // 무이자구분 ["1":무이자]

        public String hashData;
    }

    // 응답 파라미터 명세
    public class ResponsePayload {
        public String resultCode;
        public String resultMsg;
        public String payDate;
        public String payTime;
        public String payAuthCode;
        public String tid;
        public String price;
        public String cardCode;
        public String cardQuota;
        public String checkFlg;
        public String prtcCode;
    }


    // 인터페이스 호출 함수
    public ResponsePayload execute(RequestPayload objInput, List<Id> selectedIds) {
        System.debug(' INICIS 인터페이스 >>> ' + objInput );
        ResponsePayload objOutput = new ResponsePayload();

        try {
            // INICIS API 접근 정보 세팅
            INICISApiKey__mdt apiKeyInfo = CardBillKeyGenerate.getAPIAccessInfo();
            inicis_iv  = apiKeyInfo.IV__c;
            inicis_key = apiKeyInfo.INIAPIKey__c;

            // 가맹점 ID 정보 세팅
            objInput.mid = apiKeyInfo.MIDPayment__c;

            // 특정 파라미터 암호화 (AES 128-CBC 방식 사용)
            objInput.regNo  = generateAES128(inicis_key, inicis_iv, objInput.regNo);

            /* hashData 값 생성 */
            // 변환 전문 포맷 : {INIAPIKey + type + paymethod + timestamp + clientIp + mid + moid + price + billKey}
            String hashContext = inicis_key + objInput.type+ objInput.paymethod + objInput.timestamp + objInput.clientIp + objInput.mid + objInput.moid + objInput.price + objInput.billKey;
            // 특정 파라미터 해시화 (SHA-512 방식 사용)
            Blob encrypted   = Crypto.generateDigest('SHA-512', Blob.valueOf(hashContext));
            // SHA-512 암호화 전문 16진수 기반 인코딩
            objInput.hashData = EncodingUtil.convertToHex(encrypted);

            // 해당 API에서 json이 아닌 key=value 형식으로 요청 파라미터를 처리하기 때문에 문자열로 변환해 별도 처리한다.
            String requestBody = '';
            requestBody += 'type='             + objInput.type + '&';
            requestBody += 'paymethod='        + objInput.paymethod + '&';
            requestBody += 'timestamp='        + objInput.timestamp + '&';
            requestBody += 'clientIp='         + objInput.clientIp + '&';
            requestBody += 'mid='              + objInput.mid + '&';
            requestBody += 'url='              + objInput.url + '&';
            requestBody += 'moid='             + objInput.moid + '&';
            requestBody += 'goodName='         + objInput.goodName + '&';
            requestBody += 'buyerName='        + objInput.buyerName + '&';
            requestBody += 'buyerEmail='       + objInput.buyerEmail + '&';
            requestBody += 'buyerTel='         + objInput.buyerTel + '&';
            requestBody += 'price='            + objInput.price + '&';
            requestBody += 'billKey='          + objInput.billKey + '&';
            requestBody += 'authentification=' + objInput.authentification + '&';
            requestBody += 'regNo='            + urlEncode(objInput.regNo) + '&';
            requestBody += 'cardPw='           + objInput.cardPw + '&';
            requestBody += 'tax='              + objInput.tax + '&';
            requestBody += 'taxFree='          + objInput.taxFree + '&';
            requestBody += 'currency_x='       + objInput.currency_x + '&';
            requestBody += 'cardQuota='        + objInput.cardQuota + '&';
            requestBody += 'quotaInterest='    + objInput.quotaInterest + '&';
            requestBody += 'hashData='         + objInput.hashData;


            IFUtil ifUtil = new IFUtil(IFID);

            system.debug('encoded requestBody : ' + requestBody);
            // FOR IF_Log__c Description__c
            requestBody += '--IF_LOG_DESCRIPTION--';
            requestBody += '결제 대상 후원금 : ' + String.join(selectedIds, ', ');

            HttpResponse response = ifUtil.webCallout(requestBody, true);

            if (response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                objOutput = (ResponsePayload) JSON.deserialize(responseBody, ResponsePayload.class);
            }

        } catch (Exception e) {
            objOutput.resultCode = '-1';
            objOutput.resultMsg = '에러가 발생했습니다(' + e.getLineNumber() + ') : ' + e.getMessage();
            system.debug('@@@@@@@@@@@@@@@@@@@@@@@ INICIS Error : ' + e.getMessage()); 
        }

        return objOutput;
    }

    // Optional
    // 기타 처리 함수 (필요시)

    // AES 암호화 수행
    public static String generateAES128(String key, String iv, String context){
        String result = null;
        if(context != null){
            Blob encrypted = Crypto.encrypt('AES128', Blob.valueOf(key), Blob.valueOf(iv), Blob.valueOf(context)); // 암호화
            result = EncodingUtil.base64Encode(encrypted);
        }
        return result;
    }

    public static String urlEncode(String param){
        return EncodingUtil.urlEncode(param, 'UTF-8');
    }

}