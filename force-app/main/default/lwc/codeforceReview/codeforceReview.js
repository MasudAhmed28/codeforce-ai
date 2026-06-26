import { LightningElement, track } from 'lwc';
import reviewCode from '@salesforce/apex/CodeReviewService.reviewCode';

export default class CodeforceReview extends LightningElement {
    code = '';
    language = 'Apex';
    isLoading = false;
    errorMessage = '';

    @track result = null;

    languageOptions = [
        { label: 'Apex Class',      value: 'Apex' },
        { label: 'Trigger',         value: 'Trigger' },
        { label: 'Batch Apex',      value: 'Batch Apex' },
        { label: 'Queueable',       value: 'Queueable' },
        { label: 'LWC JavaScript',  value: 'LWC JavaScript' },
        { label: 'LWC HTML',        value: 'LWC HTML' }
    ];

    // ── Getters ──

    get reviewButtonLabel() {
        return this.isLoading ? 'Reviewing...' : 'Review Code';
    }

    get isReviewDisabled() {
        return this.isLoading || !this.code.trim();
    }

    get hasResults() {
        return this.result !== null && !this.isLoading;
    }

    get showEmptyState() {
        return !this.result && !this.isLoading && !this.errorMessage;
    }

    get noIssues() {
        return this.result && this.result.issues && this.result.issues.length === 0;
    }

    get criticalCount() {
        return this._countSeverity('Critical');
    }
    get highCount() {
        return this._countSeverity('High');
    }
    get mediumCount() {
        return this._countSeverity('Medium');
    }
    get lowCount() {
        return this._countSeverity('Low');
    }

    get scoreBannerClass() {
        if (!this.result) return 'score-banner';
        const s = this.result.score;
        if (s >= 80) return 'score-banner score-great';
        if (s >= 60) return 'score-banner score-ok';
        return 'score-banner score-bad';
    }

    // ── Handlers ──

    handleCodeChange(event) {
        this.code = event.target.value;
    }

    handleLanguageChange(event) {
        this.language = event.detail.value;
    }

    handleClear() {
        this.code = '';
        this.result = null;
        this.errorMessage = '';
        const textArea = this.template.querySelector('textarea');
        if (textArea) {
            textArea.value = '';
        }
    }

    async handleReview() {
        this.isLoading = true;
        this.errorMessage = '';
        this.result = null;

        try {
            const raw = await reviewCode({ code: this.code, language: this.language });

            // Add UI state to each issue
            const issues = (raw.issues || []).map((issue, idx) => ({
                ...issue,
                expanded: idx === 0, // auto-expand first issue
                cardClass: 'issue-card issue-' + (issue.severity || 'Medium').toLowerCase(),
                severityClass: 'severity-tag sev-' + (issue.severity || 'Medium').toLowerCase(),
                chevron: idx === 0 ? 'utility:chevrondown' : 'utility:chevronright'
            }));

            this.result = { ...raw, issues };
        } catch (error) {
            this.errorMessage = error.body ? error.body.message : error.message || 'Unknown error';
        } finally {
            this.isLoading = false;
        }
    }

    toggleIssue(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.result = {
            ...this.result,
            issues: this.result.issues.map((issue, i) => {
                if (i === idx) {
                    const expanded = !issue.expanded;
                    return {
                        ...issue,
                        expanded,
                        chevron: expanded ? 'utility:chevrondown' : 'utility:chevronright'
                    };
                }
                return issue;
            })
        };
    }

    // ── Helpers ──

    _countSeverity(sev) {
        if (!this.result || !this.result.issues) return 0;
        return this.result.issues.filter(i => i.severity === sev).length || 0;
    }
}
