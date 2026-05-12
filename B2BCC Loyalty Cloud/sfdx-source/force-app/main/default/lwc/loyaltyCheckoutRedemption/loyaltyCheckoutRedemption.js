import { LightningElement, api } from 'lwc';
import getQuote from '@salesforce/apex/LoyaltyRedemptionController.getQuote';
import applyRedemption from '@salesforce/apex/LoyaltyRedemptionController.applyRedemption';
import removeRedemption from '@salesforce/apex/LoyaltyRedemptionController.removeRedemption';

// Build tag — bump this on every change so you can verify in the browser
// which version of the LWC is actually running (it appears in the fallback message).
const BUILD_TAG = 'v6-2026-05-05-reload';

export default class LoyaltyCheckoutRedemption extends LightningElement {
    @api webStoreId;
    @api recordId;
    @api cartIdOverride;

    quote;
    loading = true;
    submitting = false;
    pointsInput = 0;
    statusMessage = '';
    statusVariant = '';

    get initialCartId() {
        return this.cartIdOverride || this.recordId || null;
    }

    connectedCallback() {
        this.loadQuote(this.initialCartId);
    }

    loadQuote(cartId) {
        this.loading = true;
        return getQuote({ cartId: cartId, webStoreId: this.webStoreId })
            .then((data) => {
                this.quote = data;
                if (this.hasActiveRedemption) {
                    this.pointsInput = data.currentlyReservedPoints;
                } else if (data && data.minPointsToRedeem && !this.pointsInput) {
                    this.pointsInput = data.minPointsToRedeem;
                }
                this.statusMessage = '';
            })
            .catch((error) => {
                this.quote = undefined;
                this.statusMessage = (error && error.body && error.body.message) ||
                    (error && error.message) || 'Could not load redemption options.';
                this.statusVariant = 'error';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get resolvedCartId() {
        return (this.quote && this.quote.cartId) || this.cartId;
    }

    get hasQuote() {
        return !!this.quote && !!this.quote.cartId && !!this.quote.memberId;
    }

    get fallbackMessage() {
        const suffix = ' [' + BUILD_TAG + ']';
        if (!this.quote) return 'Loading redemption options…' + suffix;
        if (!this.quote.cartId) return 'No cart in context. Add items and open your cart.' + suffix;
        if (!this.quote.memberId) return 'You are not enrolled in a loyalty program for this store.' + suffix;
        return 'Loyalty redemption unavailable.' + suffix;
    }

    get hasActiveRedemption() {
        return this.quote && this.quote.currentlyReservedPoints && this.quote.currentlyReservedPoints > 0;
    }

    get activeRedemptionMessage() {
        const pts = this.formatNumber(this.quote && this.quote.currentlyReservedPoints);
        const disc = this.activeDiscountAmount;
        return pts + ' points applied (' + disc + ' off).';
    }

    get activeDiscountAmount() {
        if (!this.quote || !this.quote.currentlyReservedPoints || !this.quote.redemptionRatio) return '—';
        return this.formatCurrency(this.quote.currentlyReservedPoints / this.quote.redemptionRatio);
    }

    get ratioLabel() {
        if (!this.quote || !this.quote.redemptionRatio) return '';
        return this.quote.redemptionRatio + ' pts = $1';
    }

    get currencyLabel() { return (this.quote && this.quote.currencyName) || 'points'; }

    get formattedAvailable() {
        return this.formatNumber(this.quote && this.quote.availablePoints);
    }

    get estimatedLabel() {
        const pts = Number(this.pointsInput) || 0;
        const ratio = this.quote && this.quote.redemptionRatio;
        const discount = pts && ratio ? this.formatCurrency(pts / ratio) : this.formatCurrency(0);
        const min = this.quote && this.quote.minPointsToRedeem;
        if (min && min > 0) {
            return 'Estimated discount: ' + discount + ' · Minimum: ' + this.formatNumber(min) + ' points';
        }
        return 'Estimated discount: ' + discount;
    }

    get applyDisabled() {
        if (this.submitting) return true;
        const pts = Number(this.pointsInput) || 0;
        if (pts <= 0) return true;
        if (this.quote && this.quote.availablePoints != null && pts > this.quote.availablePoints) return true;
        if (this.quote && this.quote.minPointsToRedeem && pts < this.quote.minPointsToRedeem) return true;
        return false;
    }

    get statusClass() {
        const base = 'slds-text-body_small slds-m-top_small';
        if (this.statusVariant === 'error') return base + ' slds-text-color_error';
        if (this.statusVariant === 'success') return base + ' slds-text-color_success';
        return base;
    }

    handleInputChange(ev) {
        this.pointsInput = ev.target.value;
        this.statusMessage = '';
    }

    handleApply() {
        this.submitting = true;
        this.statusMessage = '';
        applyRedemption({
            cartId: this.resolvedCartId,
            webStoreId: this.webStoreId,
            pointsToRedeem: Number(this.pointsInput)
        })
            .then((result) => {
                this.statusMessage = result.message;
                this.statusVariant = result.success ? 'success' : 'error';
                return this.refreshQuote();
            })
            .then(() => this.notifyCartChanged())
            .catch((e) => {
                this.statusMessage = (e.body && e.body.message) || e.message || 'Could not apply points.';
                this.statusVariant = 'error';
            })
            .finally(() => {
                this.submitting = false;
            });
    }

    handleRemove() {
        this.submitting = true;
        removeRedemption({ cartId: this.resolvedCartId })
            .then((result) => {
                this.statusMessage = result.message;
                this.statusVariant = result.success ? 'success' : 'error';
                return this.refreshQuote();
            })
            .then(() => this.notifyCartChanged())
            .catch((e) => {
                this.statusMessage = (e.body && e.body.message) || e.message || 'Could not remove points.';
                this.statusVariant = 'error';
            })
            .finally(() => {
                this.submitting = false;
            });
    }

    /**
     * Forces sibling commerce components (cart summary, totals, line items) to
     * reflect the new CartItemPriceAdjustment rows we just wrote. The stock
     * commerce cart summary caches its data and only re-fetches on a full
     * navigation, so we reload the page. The user sees the status message
     * briefly before reload.
     */
    notifyCartChanged() {
        this.dispatchEvent(new CustomEvent('cartchanged', { bubbles: true, composed: true }));
        window.setTimeout(() => {
            window.location.reload();
        }, 900);
    }

    refreshQuote() {
        return this.loadQuote(this.resolvedCartId);
    }

    formatNumber(v) {
        if (v == null) return '0';
        return new Intl.NumberFormat().format(v);
    }

    formatCurrency(v) {
        if (v == null) return '—';
        return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(v);
    }
}
