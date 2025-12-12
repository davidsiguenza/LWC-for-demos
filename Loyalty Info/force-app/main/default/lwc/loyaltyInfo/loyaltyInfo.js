import { LightningElement, track, wire } from 'lwc';
import getMemberDetails from '@salesforce/apex/LoyaltyInfoController.getMemberDetails';

export default class LoyaltyInfo extends LightningElement {
    @track loyaltyData;
    @track error;
    @track isLoading = true;

    @wire(getMemberDetails)
    wiredDetails({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.loyaltyData = data;
            this.error = undefined;
        } else if (error) {
            console.error('Loyalty Component Error:', error);
            this.error = error;
            this.loyaltyData = undefined;
        } else {
            this.loyaltyData = null;
        }
    }

    get hasBenefits() {
        return this.loyaltyData && this.loyaltyData.benefits && this.loyaltyData.benefits.length > 0;
    }

    get hasVouchers() {
        return this.loyaltyData && this.loyaltyData.vouchers && this.loyaltyData.vouchers.length > 0;
    }

    get errorMessage() {
        if (!this.error) return '';
        return this.error.body ? this.error.body.message : this.error.message;
    }
}