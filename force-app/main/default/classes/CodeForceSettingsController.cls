/**
 * @description Controller for CodeForce AI Settings page.
 *              Manages AI provider configuration and connection testing.
 */
public with sharing class CodeForceSettingsController {

    /**
     * @description Loads the current configuration from the Custom Setting.
     * @return Map of config field names to values
     */
    @AuraEnabled
    public static Map<String, String> getConfig() {
        CodeForce_Config__c cfg = CodeForce_Config__c.getInstance();
        Map<String, String> result = new Map<String, String>();
        result.put('provider',  cfg.Provider__c   != null ? cfg.Provider__c   : 'Gemini');
        result.put('model',     cfg.Model_Name__c != null ? cfg.Model_Name__c : 'gemini-2.5-flash');
        result.put('baseUrl',   cfg.Base_URL__c   != null ? cfg.Base_URL__c   : 'https://generativelanguage.googleapis.com');
        result.put('hasKey',    String.isNotBlank(cfg.API_Key__c) ? 'true' : 'false');
        return result;
    }

    /**
     * @description Saves the AI configuration to the Org-level Custom Setting.
     * @param provider  API format: 'Gemini' or 'OpenAI Compatible'
     * @param model     Model name string
     * @param baseUrl   Base API URL
     * @param apiKey    API Key (only saved if non-blank; pass blank to keep existing)
     */
    @AuraEnabled
    public static void saveConfig(String provider, String model, String baseUrl, String apiKey) {
        CodeForce_Config__c cfg = CodeForce_Config__c.getOrgDefaults();
        cfg.Provider__c   = provider;
        cfg.Model_Name__c = model;
        cfg.Base_URL__c   = baseUrl;
        if (String.isNotBlank(apiKey)) {
            cfg.API_Key__c = apiKey;
        }
        upsert cfg;
    }

    /**
     * @description Tests the AI API connection by sending a minimal prompt.
     * @return Success message string
     */
    @AuraEnabled
    public static String testConnection() {
        CodeForce_Config__c cfg = CodeForce_Config__c.getInstance();

        if (String.isBlank(cfg.API_Key__c)) {
            throw new AuraHandledException('No API key configured. Please save your API key first.');
        }

        String provider = cfg.Provider__c != null ? cfg.Provider__c : 'Gemini';
        String model    = cfg.Model_Name__c != null ? cfg.Model_Name__c : 'gemini-2.5-flash';
        String baseUrl  = cfg.Base_URL__c != null ? cfg.Base_URL__c : 'https://generativelanguage.googleapis.com';
        String apiKey   = cfg.API_Key__c;

        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);

            if (provider == 'Gemini') {
                req.setEndpoint(baseUrl + '/v1beta/models/' + model + ':generateContent?key=' + EncodingUtil.urlEncode(apiKey, 'UTF-8'));
                Map<String, Object> body = new Map<String, Object>{
                    'contents' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'parts' => new List<Map<String, String>>{
                                new Map<String, String>{ 'text' => 'Reply with exactly: CONNECTION_OK' }
                            }
                        }
                    },
                    'generationConfig' => new Map<String, Object>{ 'maxOutputTokens' => 20 }
                };
                req.setBody(JSON.serialize(body));
            } else {
                // OpenAI-compatible format (OpenAI, DeepSeek, Groq, Mistral, etc.)
                req.setEndpoint(baseUrl + '/v1/chat/completions');
                req.setHeader('Authorization', 'Bearer ' + apiKey);
                Map<String, Object> body = new Map<String, Object>{
                    'model' => model,
                    'messages' => new List<Map<String, String>>{
                        new Map<String, String>{ 'role' => 'user', 'content' => 'Reply with exactly: CONNECTION_OK' }
                    },
                    'max_tokens' => 20
                };
                req.setBody(JSON.serialize(body));
            }

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return 'Connection successful! ' + provider + ' API (' + model + ') is responding correctly.';
            } else {
                Map<String, Object> errBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String errMsg;
                if (errBody.containsKey('error')) {
                    Object errObj = errBody.get('error');
                    if (errObj instanceof Map<String, Object>) {
                        errMsg = (String) ((Map<String, Object>) errObj).get('message');
                    } else {
                        errMsg = String.valueOf(errObj);
                    }
                } else {
                    errMsg = res.getBody();
                }
                throw new AuraHandledException(
                    provider + ' API error (HTTP ' + res.getStatusCode() + '): ' + errMsg
                );
            }
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (System.CalloutException ce) {
            throw new AuraHandledException(
                'Could not reach ' + baseUrl + '. Check your Base URL and network settings. Error: ' + ce.getMessage()
            );
        } catch (Exception ex) {
            throw new AuraHandledException('Connection test failed: ' + ex.getMessage());
        }
    }
}
