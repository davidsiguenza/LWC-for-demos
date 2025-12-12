import { LightningElement } from 'lwc';
import validateCredit from '@salesforce/apex/CheckoutCreditController.validateCredit';

export default class CreditValidator extends LightningElement {
    
    showWarning = false;
    shortageAmount = 0;

    connectedCallback() {
        console.log('Validating credit...');

        validateCredit()
            .then(result => {
                if (result && result.hasCredit === false) {
                    // CASE: INSUFFICIENT CREDIT
                    this.showWarning = true;
                    this.shortageAmount = parseFloat(result.shortage).toFixed(2);
                    
                    // Hide the option using its specific HTML attribute
                    this.hidePurchaseOrder();
                    
                } else {
                    // CASE: SUFFICIENT CREDIT
                    this.showWarning = false;
                    this.showPurchaseOrder();
                }
            })
            .catch(error => {
                console.error('Error:', error);
            });
    }

    // --- CSS MAGIC (Based on your screenshot) ---
    
    hidePurchaseOrder() {
        if (document.getElementById('hide-po-style')) return;

        const style = document.createElement('style');
        style.id = 'hide-po-style';
        
        // We target the value="purchase-order" attribute directly
        style.innerText = `
            /* STRATEGY 1 (Modern): If the browser supports :has (Chrome/Edge/Safari)
               Hides the parent container 'span.slds-radio' if it contains the prohibited input */
            span.slds-radio:has(input[value="purchase-order"]) {
                display: none !important;
            }

            /* STRATEGY 2 (Compatibility): Hides the input and its adjacent label directly */
            input[value="purchase-order"],
            input[value="purchase-order"] + label {
                display: none !important;
            }
        `;
        
        document.head.appendChild(style);
        console.log('Purchase Order hidden via HTML attribute value="purchase-order".');
    }

    showPurchaseOrder() {
        const style = document.getElementById('hide-po-style');
        if (style) {
            style.remove();
        }
    }
}