/**
 * @description Tests for CodeReviewService with mocked AI callout.
 */
@IsTest
private class CodeReviewServiceTest {

    // ── Mocks ──

    private class MockGeminiSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String aiJson = '{"score":72,"summary":"Needs bulkification fixes.",' +
                '"issues":[{"title":"SOQL in loop","severity":"Critical",' +
                '"explanation":"Query inside for loop hits governor limits.",' +
                '"impact":"Fails above 100 records.","fix":"Move query before loop and use a Map.",' +
                '"sampleCode":"Map<Id,Account> acctMap = new Map<Id,Account>([SELECT Id FROM Account]);"}]}';

            // Gemini wraps the text inside candidates[].content.parts[].text
            String body = '{"candidates":[{"content":{"parts":[{"text":' +
                JSON.serialize(aiJson) + '}]}}]}';
            res.setBody(body);
            return res;
        }
    }

    private class MockOpenAISuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String aiJson = '{"score":85,"summary":"Good code quality.",' +
                '"issues":[{"title":"Missing null check","severity":"Low",' +
                '"explanation":"No null check.","impact":"NullPointerException.",' +
                '"fix":"Add null check.","sampleCode":"if(x!=null){}"}]}';

            // OpenAI wraps the text inside choices[].message.content
            String body = '{"choices":[{"message":{"content":' +
                JSON.serialize(aiJson) + '}}]}';
            res.setBody(body);
            return res;
        }
    }

    private class MockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    // ── Test Setup ──

    @TestSetup
    static void setupConfig() {
        CodeForce_Config__c cfg = new CodeForce_Config__c();
        cfg.Provider__c   = 'Gemini';
        cfg.Model_Name__c = 'gemini-2.5-flash';
        cfg.Base_URL__c   = 'https://generativelanguage.googleapis.com';
        cfg.API_Key__c    = 'test-api-key-12345';
        insert cfg;
    }

    // ── Tests ──

    @IsTest
    static void testReviewCodeGeminiSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockGeminiSuccess());

        Test.startTest();
        CodeReviewService.ReviewResult result = CodeReviewService.reviewCode(
            'for (Account a : accts) { List<Contact> c = [SELECT Id FROM Contact]; }',
            'Apex'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(72, result.score, 'Score should match mock');
        System.assertEquals(1, result.issues.size(), 'Should have 1 issue');
        System.assertEquals('Critical', result.issues[0].severity);

        // Verify DB Insert
        List<Code_Review__c> history = [SELECT Id, Language__c, Score__c FROM Code_Review__c];
        System.assertEquals(1, history.size(), 'Should have saved 1 history record');
        System.assertEquals('Apex', history[0].Language__c, 'Language should be saved');
        System.assertEquals(72, history[0].Score__c, 'Score should be saved');
    }

    @IsTest
    static void testReviewCodeOpenAISuccess() {
        // Switch config to OpenAI
        CodeForce_Config__c cfg = CodeForce_Config__c.getOrgDefaults();
        cfg.Provider__c   = 'OpenAI Compatible';
        cfg.Model_Name__c = 'gpt-4o';
        cfg.Base_URL__c   = 'https://api.openai.com';
        update cfg;

        Test.setMock(HttpCalloutMock.class, new MockOpenAISuccess());

        Test.startTest();
        CodeReviewService.ReviewResult result = CodeReviewService.reviewCode(
            'public class Foo { }',
            'Apex'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(85, result.score);
        System.assertEquals(1, result.issues.size());
        System.assertEquals('Low', result.issues[0].severity);
    }

    @IsTest
    static void testReviewCodeEmptyInput() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            CodeReviewService.reviewCode('', 'Apex');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw AuraHandledException for empty input');
    }

    @IsTest
    static void testReviewCodeNoApiKey() {
        CodeForce_Config__c cfg = CodeForce_Config__c.getOrgDefaults();
        cfg.API_Key__c = null;
        update cfg;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            CodeReviewService.reviewCode('public class Foo {}', 'Apex');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for missing API key');
    }

    @IsTest
    static void testReviewCodeHttpError() {
        Test.setMock(HttpCalloutMock.class, new MockError());

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            CodeReviewService.reviewCode('public class Foo {}', 'Apex');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw AuraHandledException on HTTP 500');
    }

    @IsTest
    static void testBuildPrompt() {
        String prompt = CodeReviewService.buildPrompt('insert a;', 'Trigger');
        System.assert(prompt.contains('Trigger'), 'Should contain language');
        System.assert(prompt.contains('insert a;'), 'Should contain code');
        System.assert(prompt.contains('governor'), 'Should mention governor limits');
    }

    @IsTest
    static void testParseResponseWithCodeFences() {
        String raw = '```json\n{"score":90,"summary":"Clean","issues":[]}\n```';
        CodeReviewService.ReviewResult result = CodeReviewService.parseResponse(raw);
        System.assertEquals(90, result.score);
        System.assert(result.issues.isEmpty());
    }

    @IsTest
    static void testParseResponseWithMultipleIssues() {
        String raw = '{"score":45,"summary":"Multiple problems found.",' +
            '"issues":[' +
            '{"title":"DML in loop","severity":"Critical","explanation":"DML inside loop","impact":"Governor limit","fix":"Collect and bulk DML","sampleCode":"insert records;"},' +
            '{"title":"Missing null check","severity":"Low","explanation":"No null check","impact":"NullPointerException","fix":"Add null check","sampleCode":"if(x!=null){}"}' +
            ']}';
        CodeReviewService.ReviewResult result = CodeReviewService.parseResponse(raw);
        System.assertEquals(45, result.score);
        System.assertEquals(2, result.issues.size());
        System.assertEquals('Critical', result.issues[0].severity);
        System.assertEquals('Low', result.issues[1].severity);
    }
}
