/**
 * @description Core service for AI-powered code reviews.
 *              Dynamically supports Gemini and OpenAI-compatible APIs
 *              based on the CodeForce_Config__c Custom Setting.
 */
public with sharing class CodeReviewService {

    private static final Integer TIMEOUT_MS = 120000;

    @AuraEnabled
    public static ReviewResult reviewCode(String code, String language) {
        if (String.isBlank(code)) {
            throw new AuraHandledException('Please paste some code to review.');
        }

        CodeForce_Config__c cfg = CodeForce_Config__c.getInstance();
        if (String.isBlank(cfg.API_Key__c)) {
            throw new AuraHandledException(
                'No API key configured. Go to the CodeForce AI Settings tab to add your API key.'
            );
        }

        String provider = cfg.Provider__c   != null ? cfg.Provider__c   : 'Gemini';
        String model    = cfg.Model_Name__c != null ? cfg.Model_Name__c : 'gemini-2.5-flash';
        String baseUrl  = cfg.Base_URL__c   != null ? cfg.Base_URL__c   : 'https://generativelanguage.googleapis.com';
        String apiKey   = cfg.API_Key__c;

        try {
            String prompt   = buildPrompt(code, language);
            String aiContent = callAI(provider, model, baseUrl, apiKey, prompt);
            ReviewResult result = parseResponse(aiContent);

            if (Schema.sObjectType.Code_Review__c.isCreateable()) {
                Code_Review__c history = new Code_Review__c();
                history.Language__c = language;
                history.Original_Code__c = code.length() > 131000 ? code.substring(0, 131000) : code;
                history.Score__c = result.score;
                history.Summary__c = result.summary != null && result.summary.length() > 255 ? result.summary.substring(0, 255) : result.summary;
                String issuesJson = JSON.serialize(result.issues);
                history.Issues_JSON__c = issuesJson.length() > 131000 ? issuesJson.substring(0, 131000) : issuesJson;

                insert history;
                result.recordId = history.Id;
            }

            return result;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (System.CalloutException ce) {
            throw new AuraHandledException('Review failed (callout error): ' + ce.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Review failed: ' + ex.getMessage());
        }
    }

    @TestVisible
    private static String buildPrompt(String code, String language) {
        return
            'You are a Salesforce Certified Technical Architect reviewing ' + language + ' code.\n\n' +
            'CODE:\n```\n' + code + '\n```\n\n' +
            'Find all issues including: governor limit violations, SOQL/DML in loops, ' +
            'bulkification problems, security vulnerabilities, CRUD/FLS violations, ' +
            'sharing model issues, trigger anti-patterns, test coverage gaps, ' +
            'performance problems, and maintainability concerns.\n\n' +
            'For each issue provide: a short title, severity (Critical / High / Medium / Low), ' +
            'an explanation, the impact, and a concrete fix with corrected sample code.\n\n' +
            'Also give an overall score 0-100 and a one-line summary.\n\n' +
            'Respond ONLY with valid JSON — no markdown, no code fences — in this shape:\n' +
            '{"score":0,"summary":"...","issues":[{"title":"...","severity":"Critical|High|Medium|Low",' +
            '"explanation":"...","impact":"...","fix":"...","sampleCode":"..."}]}';
    }

    @TestVisible
    private static String callAI(String provider, String model, String baseUrl, String apiKey, String prompt) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);

        if (provider == 'Gemini') {
            req.setEndpoint(baseUrl + '/v1beta/models/' + model + ':generateContent?key=' + EncodingUtil.urlEncode(apiKey, 'UTF-8'));
            Map<String, Object> body = new Map<String, Object>{
                'contents' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'parts' => new List<Map<String, String>>{
                            new Map<String, String>{ 'text' => prompt }
                        }
                    }
                },
                'generationConfig' => new Map<String, Object>{
                    'temperature'      => 0.2,
                    'maxOutputTokens'  => 8192,
                    'responseMimeType' => 'application/json'
                }
            };
            req.setBody(JSON.serialize(body));
        } else {
            // OpenAI-compatible format (OpenAI, DeepSeek, Groq, Mistral, Together AI, etc.)
            req.setEndpoint(baseUrl + '/v1/chat/completions');
            req.setHeader('Authorization', 'Bearer ' + apiKey);
            Map<String, Object> body = new Map<String, Object>{
                'model' => model,
                'messages' => new List<Map<String, String>>{
                    new Map<String, String>{ 'role' => 'user', 'content' => prompt }
                },
                'temperature' => 0.2,
                'max_tokens' => 8192
            };
            req.setBody(JSON.serialize(body));
        }

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'AI API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        Map<String, Object> jsonRes = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        if (provider == 'Gemini') {
            // Gemini response: candidates[0].content.parts[0].text
            List<Object> candidates = (List<Object>) jsonRes.get('candidates');
            if (candidates == null || candidates.isEmpty()) {
                throw new AuraHandledException('Empty response from Gemini.');
            }
            Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
            Map<String, Object> content        = (Map<String, Object>) firstCandidate.get('content');
            List<Object> parts                 = (List<Object>) content.get('parts');
            Map<String, Object> firstPart      = (Map<String, Object>) parts[0];
            return (String) firstPart.get('text');
        } else {
            // OpenAI-compatible response: choices[0].message.content
            List<Object> choices = (List<Object>) jsonRes.get('choices');
            if (choices == null || choices.isEmpty()) {
                throw new AuraHandledException('Empty response from AI provider.');
            }
            Map<String, Object> firstChoice = (Map<String, Object>) choices[0];
            Map<String, Object> message     = (Map<String, Object>) firstChoice.get('message');
            return (String) message.get('content');
        }
    }

    @TestVisible
    private static ReviewResult parseResponse(String content) {
        String clean = content.trim();
        if (clean.startsWith('```'))  { clean = clean.substringAfter('\n'); }
        if (clean.endsWith('```'))    { clean = clean.substringBeforeLast('```'); }
        clean = clean.trim();

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(clean);

        ReviewResult result  = new ReviewResult();
        result.score         = data.get('score') != null ? Integer.valueOf(data.get('score')) : 0;
        result.summary       = (String) data.get('summary');
        result.issues        = new List<ReviewIssue>();

        List<Object> issuesList = (List<Object>) data.get('issues');
        if (issuesList != null) {
            for (Object obj : issuesList) {
                Map<String, Object> m = (Map<String, Object>) obj;
                ReviewIssue issue     = new ReviewIssue();
                issue.title           = (String) m.get('title');
                issue.severity        = (String) m.get('severity');
                issue.explanation     = (String) m.get('explanation');
                issue.impact          = (String) m.get('impact');
                issue.fix             = (String) m.get('fix');
                issue.sampleCode      = (String) m.get('sampleCode');
                result.issues.add(issue);
            }
        }

        return result;
    }

    public class ReviewResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Integer score;
        @AuraEnabled public String summary;
        @AuraEnabled public List<ReviewIssue> issues;
    }

    public class ReviewIssue {
        @AuraEnabled public String title;
        @AuraEnabled public String severity;
        @AuraEnabled public String explanation;
        @AuraEnabled public String impact;
        @AuraEnabled public String fix;
        @AuraEnabled public String sampleCode;
    }
}
