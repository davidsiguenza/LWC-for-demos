import { LightningElement, api, wire } from 'lwc';
import getMemberSummary from '@salesforce/apex/LoyaltyAccountController.getMemberSummary';

export default class LoyaltyTierProgress extends LightningElement {
    @api webStoreId;

    summary;
    error;
    loading = true;

    @wire(getMemberSummary, { webStoreId: '$webStoreId' })
    wired({ data, error }) {
        this.loading = false;
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.summary = undefined;
        }
    }

    get hasError() { return !!this.error; }
    get errorMessage() {
        return (this.error && (this.error.body?.message || this.error.message)) || 'Could not load tier data.';
    }
    get hasStepper() {
        return this.summary && Array.isArray(this.summary.tierStepper) && this.summary.tierStepper.length > 0;
    }
    get currentTierName() { return this.summary?.currentTierName || 'Not assigned'; }
    get nextTierName() { return this.summary?.nextTierName || ''; }
    get showNextTier() { return !!this.summary?.nextTierName; }
    get atTopTier() {
        return this.hasStepper && this.summary.currentTierName && !this.summary.nextTierName;
    }
    get showProgressCopy() {
        return this.summary && this.summary.progressToNextTier !== null &&
               this.summary.progressToNextTier !== undefined && !!this.summary.nextTierName;
    }
    get progressPct() {
        if (this.summary?.progressToNextTier == null) return 0;
        return Math.round(this.summary.progressToNextTier * 100);
    }
    get pointsToNextTier() {
        if (this.summary?.pointsToNextTier == null) return '';
        return new Intl.NumberFormat().format(this.summary.pointsToNextTier);
    }
    get currencyLabel() { return this.summary?.currencyName || 'points'; }

    get currentTierStyle() {
        const c = this.summary?.currentTierColor;
        return c ? `color: ${c};` : '';
    }

    /**
     * Augments each step with UI metadata so the template stays declarative.
     * Rendered as: [marker][connector][marker][connector][marker]
     * so the last step gets `hasConnector = false`.
     */
    get stepperWithMeta() {
        const steps = this.summary?.tierStepper;
        if (!steps || steps.length === 0) return [];
        const progress = (this.summary.progressToNextTier ?? 0);
        return steps.map((step, idx) => {
            const isLast = idx === steps.length - 1;
            let markerClass = 'tier-marker';
            if (step.isCurrent) markerClass += ' is-current';
            if (step.isLocked) markerClass += ' is-locked';
            let connectorFillPct;
            if (step.isCompleted) {
                connectorFillPct = 100;
            } else if (step.isCurrent) {
                connectorFillPct = Math.round(progress * 100);
            } else {
                connectorFillPct = 0;
            }
            return {
                ...step,
                containerClass: 'tier-step',
                markerClass,
                markerStyle: step.color ? `background: ${step.color};` : '',
                thresholdLabel: this.formatThreshold(step),
                hasConnector: !isLast,
                connectorKey: `${step.tierId}-conn`,
                connectorFillStyle: `width: ${connectorFillPct}%;`
            };
        });
    }

    formatThreshold(step) {
        if (step.minPoints == null) return '';
        const fmt = new Intl.NumberFormat();
        if (step.maxPoints == null) return `${fmt.format(step.minPoints)}+ pts`;
        return `${fmt.format(step.minPoints)}–${fmt.format(step.maxPoints)} pts`;
    }
}
