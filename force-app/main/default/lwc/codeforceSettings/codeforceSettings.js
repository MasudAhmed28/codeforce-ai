import { LightningElement } from 'lwc';
import testConnection from '@salesforce/apex/CodeForceSettingsController.testConnection';

export default class CodeforceSettings extends LightningElement {
    isTesting = false;
    connectionMessage = '';
    connectionSuccess = false;
    connectionError = false;

    get testButtonLabel() {
        return this.isTesting ? 'Testing...' : 'Test Connection';
    }

    get showDefault() {
        return !this.connectionSuccess && !this.connectionError && !this.isTesting;
    }

    async handleTestConnection() {
        this.isTesting = true;
        this.connectionSuccess = false;
        this.connectionError = false;
        this.connectionMessage = '';

        try {
            const result = await testConnection();
            this.connectionSuccess = true;
            this.connectionMessage = result;
        } catch (error) {
            this.connectionError = true;
            this.connectionMessage = error.body
                ? error.body.message
                : error.message || 'Unknown error occurred.';
        } finally {
            this.isTesting = false;
        }
    }
}
