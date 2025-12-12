import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProductIdsBySkus from '@salesforce/apex/CsvCartUploaderController.getProductIdsBySkus';
import { addItemToCart, refreshCartSummary } from 'commerce/cartApi';

export default class CsvCartUploader extends LightningElement {
    @track products = null;
    @track isLoading = false;
    @track isAdding = false;
    @track errorMessage = '';

    // Executes when the user selects a file
    async handleFileChange(event) {
        this.isLoading = true;
        this.products = null;
        this.errorMessage = '';

        const file = event.target.files[0];
        if (!file) {
            this.isLoading = false;
            return;
        }

        try {
            const fileContents = await this.readFile(file);
            const parsedData = this.parseCSV(fileContents);
            
            const skus = parsedData.map(p => p.sku);
            
            // Apex Call. We now expect a Map<String, Product2>
            const skuToProductMap = await getProductIdsBySkus({ skus: skus });

            this.products = parsedData.map(p => {
                // Get the full record from the map (can be undefined if it doesn't exist)
                const productRecord = skuToProductMap[p.sku];
                
                // Safely extract ID and Name
                const productId = productRecord ? productRecord.Id : null;
                const productName = productRecord ? productRecord.Name : '-'; 

                return {
                    ...p,
                    productId: productId,
                    name: productName, // Store name for HTML display
                    status: productId ? '✔️ Valid' : '❌ SKU not found',
                    badgeClass: productId ? 'slds-theme_success' : 'slds-theme_error',
                    isAdded: false // New flag to disable inputs after adding
                };
            });

        } catch (error) {
            this.errorMessage = 'Error processing file. Please check the format.';
            console.error(error);
        } finally {
            this.isLoading = false;
        }
    }

    // --- NEW METHODS FOR EDITING ---

    handleQuantityChange(event) {
        const sku = event.target.dataset.sku;
        const newQty = parseInt(event.target.value, 10);

        if (this.products) {
            this.products = this.products.map(p => {
                if (p.sku === sku) {
                    return { ...p, quantity: newQty };
                }
                return p;
            });
        }
    }

    handleDelete(event) {
        const sku = event.target.dataset.sku;
        if (this.products) {
            this.products = this.products.filter(p => p.sku !== sku);
        }
    }

    // Executes when clicking the "Add All to Cart" button
    async handleAddToCart() {
        this.isAdding = true;
        this.isLoading = true;

        const validProducts = this.products.filter(p => p.productId);

        if (validProducts.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'No valid products to add to cart.',
                variant: 'error'
            }));
            this.isAdding = false;
            this.isLoading = false;
            return;
        }

        // Create a promise for each product to add
        const promises = validProducts.map(p => addItemToCart(p.productId, p.quantity));

        try {
            // Wait for all promises to complete
            await Promise.all(promises);
            
            // Update visual state (status and badge)
            // FIXED CODE (Uses Object.assign)
            this.products = this.products.map(p => {
                if (p.productId) {
                    // Create a clean copy of the object and overwrite properties
                    return Object.assign({}, p, { 
                        status: '✅ Added', 
                        badgeClass: 'slds-theme_success',
                        isAdded: true // Disable inputs 
                    });
                }
                return p;
            });
            
            await refreshCartSummary();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: `${validProducts.length} product(s) added to cart.`,
                variant: 'success'
            }));

        } catch (error) {
             this.dispatchEvent(new ShowToastEvent({
                title: 'Error adding to cart',
                message: 'Some products could not be added. Please check your cart.',
                variant: 'error'
            }));
            console.error('Error adding products:', error);
        } finally {
            this.isAdding = false;
            this.isLoading = false;
        }
    }

    // --- Helper Functions ---

    // Reads file content
    readFile(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error);
            reader.readAsText(file);
        });
    }

    // Parses CSV text into an array of objects
    parseCSV(csvText) {
        const rows = csvText.split('\n').filter(row => row.trim() !== '');
        // Skip header if the word "sku" is detected
        const dataRows = (rows[0].toLowerCase().includes('sku')) ? rows.slice(1) : rows;

        return dataRows.map(row => {
            const columns = row.split(',');
            return {
                sku: columns[0] ? columns[0].trim() : '',
                quantity: columns[1] ? parseInt(columns[1].trim(), 10) : 1
            };
        });
    }
}