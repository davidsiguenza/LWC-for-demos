import { LightningElement, api, wire } from 'lwc';
import getMemberSummary from '@salesforce/apex/LoyaltyAccountController.getMemberSummary';
import getTransactions from '@salesforce/apex/LoyaltyAccountController.getTransactions';

const COLUMNS = [
    { label: 'Date', fieldName: 'activityDate', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Type', fieldName: 'journalType', type: 'text' },
    { label: 'Subtype', fieldName: 'journalSubType', type: 'text' },
    { label: 'Points', fieldName: 'transactionAmount', type: 'number',
      cellAttributes: { alignment: 'right' } },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

export default class LoyaltyTransactionHistory extends LightningElement {
    @api webStoreId;
    @api pageSize = 15;

    memberId;
    transactions = [];
    error;
    loading = true;
    columns = COLUMNS;
    offset = 0;
    lastPageSize = 0;

    @wire(getMemberSummary, { webStoreId: '$webStoreId' })
    wiredMember({ data, error }) {
        if (data) {
            this.memberId = data.memberId;
            this.error = undefined;
            this.offset = 0;
            this.loadPage();
        } else if (error) {
            this.error = error;
            this.loading = false;
        }
    }

    async loadPage() {
        if (!this.memberId) {
            this.loading = false;
            return;
        }
        this.loading = true;
        try {
            const rows = await getTransactions({
                memberId: this.memberId,
                limitSize: this.pageSize,
                offsetSize: this.offset
            });
            this.transactions = rows || [];
            this.lastPageSize = this.transactions.length;
            this.error = undefined;
        } catch (e) {
            this.error = e;
            this.transactions = [];
        } finally {
            this.loading = false;
        }
    }

    get hasError() { return !!this.error; }
    get errorMessage() {
        return (this.error && (this.error.body?.message || this.error.message)) || 'Could not load transactions.';
    }
    get hasTransactions() { return this.transactions && this.transactions.length > 0; }
    get prevDisabled() { return this.offset <= 0; }
    get nextDisabled() { return this.lastPageSize < this.pageSize; }

    handleNext() {
        this.offset += this.pageSize;
        this.loadPage();
    }
    handlePrev() {
        this.offset = Math.max(0, this.offset - this.pageSize);
        this.loadPage();
    }
}
