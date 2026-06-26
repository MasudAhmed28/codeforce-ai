/**
 * @description Tests for CodeForceSettingsController.
 */
@IsTest
private class CodeForceSettingsControllerTest {

    // ── Mock for successful Gemini test connection ──
    private class MockTestSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"candidates":[{"content":{"parts":[{"text":"CONNECTION_OK"}]}}]}');
            return res;
        }
    }

    private class MockTestApiError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"error":{"message":"API key not valid. Please pass a valid API key."}}');
            return res;
        }
    }

    @IsTest
    static void testConnectionSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockTestSuccess());

        Test.startTest();
        String result = CodeForceSettingsController.testConnection();
        Test.stopTest();

        System.assert(result.contains('successful'), 'Should report success');
    }

    @IsTest
    static void testConnectionApiError() {
        Test.setMock(HttpCalloutMock.class, new MockTestApiError());

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            CodeForceSettingsController.testConnection();
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw AuraHandledException on API error');
    }
}
