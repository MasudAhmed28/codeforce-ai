import { LightningElement } from 'lwc';
import getConfig       from '@salesforce/apex/CodeForceSettingsController.getConfig';
import saveConfig      from '@salesforce/apex/CodeForceSettingsController.saveConfig';
import testConnection  from '@salesforce/apex/CodeForceSettingsController.testConnection';

const PROVIDER_DEFAULTS = {
    'Gemini':              { baseUrl: 'https://generativelanguage.googleapis.com', model: 'gemini-2.5-flash' },
    'OpenAI Compatible':   { baseUrl: 'https://api.openai.com',                   model: 'gpt-4o' }
};

export default class CodeforceSettings extends LightningElement {
    provider = 'Gemini';
    model    = 'gemini-2.5-flash';
    baseUrl  = 'https://generativelanguage.googleapis.com';
    apiKey   = '';
    hasExistingKey = false;

    isSaving  = false;
    isTesting = false;

    showSuccess    = false;
    showError      = false;
    statusMessage  = '';

    providerOptions = [
        { label: 'Google Gemini',       value: 'Gemini' },
        { label: 'OpenAI Compatible',   value: 'OpenAI Compatible' }
    ];

    connectedCallback() {
        this.loadConfig();
    }

    async loadConfig() {
        try {
            const cfg = await getConfig();
            this.provider       = cfg.provider  || 'Gemini';
            this.model          = cfg.model     || 'gemini-2.5-flash';
            this.baseUrl        = cfg.baseUrl   || 'https://generativelanguage.googleapis.com';
            this.hasExistingKey = cfg.hasKey === 'true';
        } catch (e) {
            // First install — no config yet, use defaults
        }
    }

    // ── Getters ──

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Save Configuration';
    }

    get testButtonLabel() {
        return this.isTesting ? 'Testing...' : 'Test Connection';
    }

    get apiKeyPlaceholder() {
        return this.hasExistingKey ? '••••••••  (key saved — leave blank to keep)' : 'Paste your API key here';
    }

    // ── Handlers ──

    handleProviderChange(event) {
        this.provider = event.detail.value;
        const defaults = PROVIDER_DEFAULTS[this.provider];
        if (defaults) {
            this.baseUrl = defaults.baseUrl;
            this.model   = defaults.model;
        }
        this.clearStatus();
    }

    handleModelChange(event) {
        this.model = event.target.value;
        this.clearStatus();
    }

    handleBaseUrlChange(event) {
        this.baseUrl = event.target.value;
        this.clearStatus();
    }

    handleApiKeyChange(event) {
        this.apiKey = event.target.value;
        this.clearStatus();
    }

    async handleSave() {
        this.isSaving = true;
        this.clearStatus();

        try {
            await saveConfig({
                provider: this.provider,
                model:    this.model,
                baseUrl:  this.baseUrl,
                apiKey:   this.apiKey
            });
            this.showSuccess   = true;
            this.statusMessage = 'Configuration saved successfully!';
            if (this.apiKey) {
                this.hasExistingKey = true;
                this.apiKey = '';
            }
        } catch (error) {
            this.showError     = true;
            this.statusMessage = error.body ? error.body.message : error.message || 'Failed to save configuration.';
        } finally {
            this.isSaving = false;
        }
    }

    async handleTestConnection() {
        this.isTesting = true;
        this.clearStatus();

        try {
            const result = await testConnection();
            this.showSuccess   = true;
            this.statusMessage = result;
        } catch (error) {
            this.showError     = true;
            this.statusMessage = error.body ? error.body.message : error.message || 'Connection test failed.';
        } finally {
            this.isTesting = false;
        }
    }

    clearStatus() {
        this.showSuccess  = false;
        this.showError    = false;
        this.statusMessage = '';
    }
}
