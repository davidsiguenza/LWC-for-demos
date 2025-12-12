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
            // Data is null (no member found)
            this.loyaltyData = null;
        }
    }

    get isEmpty() {
        return !this.isLoading && !this.error && !this.loyaltyData;
    }

    get errorMessage() {
        if (!this.error) return '';
        // Safe access to error body
        return this.error.body ? this.error.body.message : this.error.message || 'Unknown Error';
    }
}