import { LightningElement, api, wire } from 'lwc';
import getMemberSummary from '@salesforce/apex/LoyaltyAccountController.getMemberSummary';

export default class LoyaltyBalanceCard extends LightningElement {
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

    get hasError() {
        return !!this.error;
    }

    get errorMessage() {
        return (this.error && (this.error.body?.message || this.error.message)) || 'Could not load loyalty data.';
    }

    get hasMember() {
        return !!this.summary && !!this.summary.memberId;
    }

    get hasEscrow() {
        return this.summary && this.summary.escrowPointsBalance > 0;
    }

    get formattedBalance() {
        return this.formatPoints(this.summary?.pointsBalance);
    }

    get formattedAvailable() {
        return this.formatPoints(this.summary?.pointsAvailableToRedeem);
    }

    get formattedEscrow() {
        return this.formatPoints(this.summary?.escrowPointsBalance);
    }

    get currencyLabel() {
        return this.summary?.currencyName || 'Points';
    }

    get membershipNumber() {
        return this.summary?.membershipNumber || '—';
    }

    get memberStatus() {
        return this.summary?.memberStatus || '';
    }

    get tierDisplay() {
        if (!this.summary?.currentTierName) return 'Not assigned';
        const group = this.summary.tierGroupName ? ` · ${this.summary.tierGroupName}` : '';
        return `${this.summary.currentTierName}${group}`;
    }

    formatPoints(n) {
        if (n === null || n === undefined) return '—';
        return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(n);
    }
}
