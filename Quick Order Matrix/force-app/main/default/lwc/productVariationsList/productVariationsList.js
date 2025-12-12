import { LightningElement, api, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getProductVariations from "@salesforce/apex/B2BProductVariationsController.getProductVariations";
import addItemsToCart from "@salesforce/apex/B2BProductVariationsController.addItemsToCart";

// --- IMPORTANT: Native module to refresh the Mini Cart in LWR ---
import { refreshCartSummary } from "commerce/cartApi";

export default class ProductVariationsList extends LightningElement {
  @api recordId;
  @track variations = [];
  @track error;
  @track isLoading = true;
  @track columnHeader = "Variation";
  @track isMatrix = false; // New: Flag for matrix view
  @track matrixColumns = []; // Header values for columns
  @track matrixRows = []; // Rows structure

  quantities = {};

  @wire(getProductVariations, { productId: '$recordId' })
  wiredVariations({ error, data }) {
    this.isLoading = false;
    console.log('wiredVariations triggered. recordId:', this.recordId);
    if (data) {
        console.log('wiredVariations data:', JSON.stringify(data));

      // First, detecting attributes
      let allAttributes = new Set();
      data.forEach((item) => {
        if (item.attributeMap) {
          Object.keys(item.attributeMap).forEach((key) =>
            allAttributes.add(key)
          );
        }
      });

      const attributesList = Array.from(allAttributes);

      // DECISION: Matrix (2 attributes) vs List (1 or >2)
      if (attributesList.length === 2) {
        this.isMatrix = true;
        this.buildMatrix(data, attributesList);
      } else {
        this.isMatrix = false;
        this.buildList(data);
      }
      this.error = undefined;
    } else if (error) {
      console.error("Error loading variations:", error);
      this.error = "Could not load variations.";
    }
  }

  buildList(data) {
    this.variations = data.map((item) => {
      // Updated logic: Create structured array for better visual rendering
      let attributeItems = [];
      if (item.attributeMap) {
        const entries = Object.entries(item.attributeMap);
        if (entries.length > 0) {
            // Sort keys if needed, currently random order from Map
            attributeItems = entries.map(([key, val]) => {
                return { label: key, value: val };
            });
        }
      }
      
      // Fallback if no map (should verify against controller logic)
      if (attributeItems.length === 0) {
          attributeItems.push({ label: item.label || 'Option', value: item.value || '-' });
      }

      // Header logic (simple rollback to "Variations" if multiple attributes mixed)
      if (item.label && item.label !== "Option") {
        this.columnHeader =
          this.columnHeader === "Variation" ? item.label : "Options";
      }

      return {
        uniqueKey: item.id,
        realProductId: item.productId,
        attributeItems: attributeItems, // New structure
        // displayValue: displayVal, // Removed in favor of attributeItems
        productSku: item.sku || "-",
        rowClass: item.isCurrent ? "row-current" : "",
        isCurrent: item.isCurrent,
      };
    });
  }

  buildMatrix(data, attributes) {
    // Attr 1 = Row, Attr 2 = Column
    const rowAttr = attributes[0];
    const colAttr = attributes[1];

    this.columnHeader = rowAttr; // Top-Left header indicates Row Attribute

    let colValues = new Set();
    let rowValues = new Set();
    let productMap = {}; // Key: "RowVal|ColVal" -> Product

    data.forEach((item) => {
      const rVal = item.attributeMap[rowAttr];
      const cVal = item.attributeMap[colAttr];

      if (rVal && cVal) {
        colValues.add(cVal);
        rowValues.add(rVal);
        productMap[`${rVal}|${cVal}`] = item;
      }
    });

    // Sort columns and rows (alphabetic or numeric if possible)
    this.matrixColumns = Array.from(colValues).sort();
    const sortedRows = Array.from(rowValues).sort();

    this.matrixRows = sortedRows.map((rVal) => {
      let cells = this.matrixColumns.map((cVal) => {
        const prod = productMap[`${rVal}|${cVal}`];
        return {
          key: `${rVal}-${cVal}`,
          exists: !!prod,
          productId: prod ? prod.productId : null,
          sku: prod ? prod.sku || "-" : "",
          isCurrent: prod ? prod.isCurrent : false,
        };
      });
      return {
        label: rVal,
        cells: cells,
      };
    });
  }

  get hasVariations() {
    return this.variations && this.variations.length > 0;
  }

  handleQuantityChange(event) {
    const prodId = event.target.dataset.id;
    const qty = event.target.value;

    if (qty && qty > 0) {
      this.quantities[prodId] = qty;
    } else {
      delete this.quantities[prodId];
    }
  }

  async handleAddToCart() {
    const itemsToAdd = Object.keys(this.quantities).map((prodId) => {
      return {
        productId: prodId,
        quantity: this.quantities[prodId],
      };
    });

    if (itemsToAdd.length === 0) {
      this.showToast(
        "Attention",
        "Please select at least one unit.",
        "warning"
      );
      return;
    }

    this.isLoading = true;

    try {
      // 1. Apex Call (Backend)
      await addItemsToCart({ items: itemsToAdd });

      // 2. Visual Success
      this.showToast("Added!", "Products added to cart.", "success");
      this.clearInputs();

      // 3. DEFINITIVE STEP: Force Mini Cart refresh
      // This function tells the store: "Hey, data has changed, reload it".
      await refreshCartSummary();
    } catch (error) {
      console.error("Cart error:", error);
      const msg = error.body ? error.body.message : error.message;
      this.showToast("Error", msg, "error");
    } finally {
      this.isLoading = false;
    }
  }

  clearInputs() {
    this.quantities = {};
    const inputs = this.template.querySelectorAll("lightning-input");
    if (inputs) {
      inputs.forEach((input) => {
        input.value = null;
      });
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
