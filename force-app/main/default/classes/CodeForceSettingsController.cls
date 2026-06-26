/**
 * @description Controller for CodeForce AI Settings page.
 *              Tests the Gemini API connection via Named Credential.
 */
public with sharing class CodeForceSettingsController {

    /**
     * @description Tests the Gemini API connection by sending a minimal prompt
     *              via the Named Credential. Verifies the External Credential
     *              is properly configured with a valid API key.
     * @return Success message string
     */
    @AuraEnabled
    public static String testConnection() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Gemini_AI/v1beta/models/gemini-2.5-flash:generateContent');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);

            // Minimal test payload
            Map<String, Object> body = new Map<String, Object>{
                'contents' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'parts' => new List<Map<String, String>>{
                            new Map<String, String>{ 'text' => 'Reply with exactly: CONNECTION_OK' }
                        }
                    }
                },
                'generationConfig' => new Map<String, Object>{
                    'maxOutputTokens' => 20
                }
            };
            req.setBody(JSON.serialize(body));

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return 'Connection successful! Gemini API is responding correctly.';
            } else {
                Map<String, Object> errBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> error = (Map<String, Object>) errBody.get('error');
                String errMsg = error != null ? (String) error.get('message') : res.getBody();
                throw new AuraHandledException(
                    'Gemini API error (HTTP ' + res.getStatusCode() + '): ' + errMsg
                );
            }
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (System.CalloutException ce) {
            throw new AuraHandledException(
                'Named Credential not configured. Please set up the External Credential ' +
                'with your Gemini API key. Error: ' + ce.getMessage()
            );
        } catch (Exception ex) {
            throw new AuraHandledException('Connection test failed: ' + ex.getMessage());
        }
    }
}
