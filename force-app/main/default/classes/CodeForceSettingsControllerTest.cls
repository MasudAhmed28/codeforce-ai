/**
 * @description Tests for CodeForceSettingsController.
 */
@IsTest
private class CodeForceSettingsControllerTest {

    // ── Mock for successful connection test ──
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

    @TestSetup
    static void setupConfig() {
        CodeForce_Config__c cfg = new CodeForce_Config__c();
        cfg.Provider__c   = 'Gemini';
        cfg.Model_Name__c = 'gemini-2.5-flash';
        cfg.Base_URL__c   = 'https://generativelanguage.googleapis.com';
        cfg.API_Key__c    = 'test-api-key-12345';
        insert cfg;
    }

    @IsTest
    static void testGetConfig() {
        Test.startTest();
        Map<String, String> cfg = CodeForceSettingsController.getConfig();
        Test.stopTest();

        System.assertEquals('Gemini', cfg.get('provider'));
        System.assertEquals('gemini-2.5-flash', cfg.get('model'));
        System.assertEquals('true', cfg.get('hasKey'));
    }

    @IsTest
    static void testSaveConfig() {
        Test.startTest();
        CodeForceSettingsController.saveConfig('OpenAI Compatible', 'gpt-4o', 'https://api.openai.com', 'new-key');
        Test.stopTest();

        CodeForce_Config__c cfg = CodeForce_Config__c.getOrgDefaults();
        System.assertEquals('OpenAI Compatible', cfg.Provider__c);
        System.assertEquals('gpt-4o', cfg.Model_Name__c);
        System.assertEquals('https://api.openai.com', cfg.Base_URL__c);
        System.assertEquals('new-key', cfg.API_Key__c);
    }

    @IsTest
    static void testSaveConfigKeepsExistingKey() {
        Test.startTest();
        CodeForceSettingsController.saveConfig('Gemini', 'gemini-2.5-pro', 'https://generativelanguage.googleapis.com', '');
        Test.stopTest();

        CodeForce_Config__c cfg = CodeForce_Config__c.getOrgDefaults();
        System.assertEquals('gemini-2.5-pro', cfg.Model_Name__c);
        System.assertEquals('test-api-key-12345', cfg.API_Key__c, 'Blank API key should not overwrite existing');
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

    @IsTest
    static void testConnectionNoApiKey() {
        // Remove the API key
        CodeForce_Config__c cfg = CodeForce_Config__c.getOrgDefaults();
        cfg.API_Key__c = null;
        update cfg;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            CodeForceSettingsController.testConnection();
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for missing API key');
    }
}
