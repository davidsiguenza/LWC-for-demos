import { LightningElement, api, wire } from 'lwc';
import getMemberSummary from '@salesforce/apex/LoyaltyAccountController.getMemberSummary';
import getVouchers from '@salesforce/apex/LoyaltyAccountController.getVouchers';

export default class LoyaltyVouchers extends LightningElement {
    @api webStoreId;

    memberId;
    rawVouchers = [];
    error;
    loading = true;

    @wire(getMemberSummary, { webStoreId: '$webStoreId' })
    wiredMember({ data, error }) {
        if (data) {
            this.memberId = data.memberId;
        } else if (error) {
            this.error = error;
            this.loading = false;
        }
    }

    @wire(getVouchers, { memberId: '$memberId' })
    wiredVouchers({ data, error }) {
        this.loading = false;
        if (data) {
            this.rawVouchers = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.rawVouchers = [];
        }
    }

    get hasError() { return !!this.error; }
    get errorMessage() {
        return (this.error && (this.error.body?.message || this.error.message)) || 'Could not load vouchers.';
    }
    get hasVouchers() { return this.rawVouchers && this.rawVouchers.length > 0; }

    get vouchers() {
        return (this.rawVouchers || []).map((v) => ({
            ...v,
            displayValue: this.formatValue(v),
            formattedExpiration: v.expirationDate
                ? new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: '2-digit' })
                    .format(new Date(v.expirationDate))
                : '—'
        }));
    }

    formatValue(v) {
        if (v.discountPercent) return `${v.discountPercent}% off`;
        const amt = (v.remainingValue != null ? v.remainingValue : v.faceValue);
        if (amt == null) return '—';
        return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(amt);
    }
}
