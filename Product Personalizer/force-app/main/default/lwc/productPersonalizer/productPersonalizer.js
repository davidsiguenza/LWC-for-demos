import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import * as cartApi from 'commerce/cartApi';
import ICONS_ZIP from '@salesforce/resourceUrl/ProductPersonalizer_Icons';
import FABRIC_JS from '@salesforce/resourceUrl/ProductPersonalizer_Fabric';
import getProductInfo from '@salesforce/apex/ProductPersonalizerController.getProductInfo';
import updateCartItemCustomization from '@salesforce/apex/ProductPersonalizerController.updateCartItemCustomization';

const PRODUCT_ID_REGEX = /\b(01t[A-Za-z0-9]{12,15})\b/;

const MAX_TEXT_LENGTH = 40;
const CANVAS_SIZE = 480;

const FONT_OPTIONS = [
    { value: 'sans-bold', label: 'Sans bold', family: 'Helvetica Neue, Arial, sans-serif', weight: 'bold' },
    { value: 'serif', label: 'Serif', family: 'Georgia, Times New Roman, serif', weight: '600' },
    { value: 'condensed', label: 'Condensed', family: 'Arial Narrow, Helvetica, sans-serif', weight: 'bold' }
];
const COLOR_OPTIONS = [
    { value: '#ffffff', label: 'Blanco' },
    { value: '#000000', label: 'Negro' },
    { value: '#C8102E', label: 'Rojo' },
    { value: '#002F6C', label: 'Azul Dentaid' }
];

export default class ProductPersonalizer extends LightningElement {
    @api productId; // deprecated
    @api buttonLabel = 'Personalizar tu producto';
    @api primaryColor = '#002F6C';

    resolvedProductId;
    productInfo;
    error;
    isModalOpen = false;
    activeTab = 'text';

    text = '';
    selectedFont = FONT_OPTIONS[0].value;
    selectedColor = COLOR_OPTIONS[1].value;
    selectedIconKey = null;

    icons = [];
    iconsLoaded = false;

    _fabricLoaded = false;
    _fabricCanvas;
    _textObj;
    _iconObj;
    isAddingToCart = false;

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        const fromParam =
            pageRef?.attributes?.recordId ||
            pageRef?.attributes?.productId ||
            pageRef?.state?.recordId ||
            pageRef?.state?.productId;
        let id = fromParam;
        if (!id) {
            const path =
                (typeof window !== 'undefined' && window.location && window.location.pathname) || '';
            const match = path.match(PRODUCT_ID_REGEX);
            id = match ? match[1] : null;
        }
        this.resolvedProductId = id;
    }

    @wire(getProductInfo, { productId: '$resolvedProductId' })
    wiredProduct({ data, error }) {
        if (data) {
            this.productInfo = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.productInfo = undefined;
        }
    }

    get isCustomizable() {
        return !!this.productInfo?.isCustomizable;
    }

    get buttonStyle() {
        return `background-color: ${this.primaryColor}; border-color: ${this.primaryColor};`;
    }

    get isTextTab() {
        return this.activeTab === 'text';
    }
    get isIconTab() {
        return this.activeTab === 'icon';
    }
    get textTabClass() {
        return `pp-tab ${this.isTextTab ? 'pp-tab--active' : ''}`;
    }
    get iconTabClass() {
        return `pp-tab ${this.isIconTab ? 'pp-tab--active' : ''}`;
    }

    get fontOptions() {
        return FONT_OPTIONS.map((f) => ({
            ...f,
            class: f.value === this.selectedFont ? 'pp-chip pp-chip--active' : 'pp-chip'
        }));
    }

    get colorOptions() {
        return COLOR_OPTIONS.map((c) => ({
            ...c,
            class: c.value === this.selectedColor ? 'pp-swatch pp-swatch--active' : 'pp-swatch',
            style: `background-color: ${c.value};`
        }));
    }

    get iconOptions() {
        return this.icons.map((i) => ({
            ...i,
            class: i.key === this.selectedIconKey ? 'pp-icon pp-icon--active' : 'pp-icon'
        }));
    }

    get remainingChars() {
        return MAX_TEXT_LENGTH - this.text.length;
    }

    get canAddToCartDisabled() {
        return this.isAddingToCart || !(this.text.trim() || this.selectedIconKey);
    }

    get addToCartLabel() {
        return this.isAddingToCart ? 'Añadiendo...' : 'Añadir al carrito';
    }

    handleOpen() {
        this.isModalOpen = true;
        this.ensureIconsLoaded();
        this.ensureFabricLoaded().then(() => {
            requestAnimationFrame(() => this.initCanvas());
        });
    }

    handleClose() {
        this.isModalOpen = false;
        this.destroyCanvas();
    }

    handleTextTab() {
        this.activeTab = 'text';
    }
    handleIconTab() {
        this.activeTab = 'icon';
    }

    handleTextChange(event) {
        this.text = event.target.value;
        this.syncTextObject();
    }

    handleFontChange(event) {
        this.selectedFont = event.currentTarget.dataset.value;
        this.syncTextObject();
    }

    handleColorChange(event) {
        this.selectedColor = event.currentTarget.dataset.value;
        this.syncTextObject();
    }

    handleIconSelect(event) {
        const key = event.currentTarget.dataset.key;
        if (this.selectedIconKey === key) {
            this.selectedIconKey = null;
            this.removeIconObject();
        } else {
            this.selectedIconKey = key;
            this.addOrReplaceIconObject();
        }
    }

    handleClearDesign() {
        this.text = '';
        this.selectedIconKey = null;
        this.syncTextObject();
        this.removeIconObject();
    }

    async handleAddToCart() {
        if (this.canAddToCartDisabled) return;
        this.isAddingToCart = true;
        const payload = this.buildPayload();
        try {
            const added = await this.invokeAddToCart();
            await this.persistCustomization(added, payload);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Producto personalizado añadido',
                    message: 'Tu diseño se ha guardado con el producto en el carrito.',
                    variant: 'success'
                })
            );
            this.handleClose();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[ProductPersonalizer] add to cart failed', e);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No se pudo añadir al carrito',
                    message: (e && (e.message || (e.body && e.body.message))) || 'Error desconocido',
                    variant: 'error'
                })
            );
        } finally {
            this.isAddingToCart = false;
        }
    }

    async invokeAddToCart() {
        // commerce/cartApi signatures have evolved across LWR versions. Try the most
        // common forms in order until one works. Positional (productId, quantity) is
        // the current supported form on recent storefronts; the object form throws
        // JSON_PARSER_ERROR on some versions because the serializer wraps it as an array.
        const pid = this.resolvedProductId;
        if (typeof cartApi.addItemToCart === 'function') {
            try {
                return await cartApi.addItemToCart(pid, 1);
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[ProductPersonalizer] addItemToCart(positional) failed, retrying object form', e);
                return await cartApi.addItemToCart({ productId: pid, quantity: 1 });
            }
        }
        if (typeof cartApi.addToCart === 'function') {
            return cartApi.addToCart(pid, 1);
        }
        throw new Error('commerce/cartApi no expone addItemToCart/addToCart en este storefront');
    }

    async persistCustomization(cartResult, payload) {
        const cartItemId = this.extractCartItemId(cartResult);
        if (!cartItemId) {
            // eslint-disable-next-line no-console
            console.warn('[ProductPersonalizer] could not locate cartItemId, skipping update', cartResult);
            return;
        }
        await updateCartItemCustomization({
            cartItemId,
            customizationJson: JSON.stringify(payload)
        });
    }

    extractCartItemId(result) {
        if (!result) return null;
        if (result.cartItemId) return result.cartItemId;
        if (result.id && String(result.id).startsWith('0a9')) return result.id;
        if (result.cartItem && result.cartItem.cartItemId) return result.cartItem.cartItemId;
        if (Array.isArray(result.cartItems) && result.cartItems.length) {
            const last = result.cartItems[result.cartItems.length - 1];
            return last.cartItemId || last.id || null;
        }
        return null;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    ensureIconsLoaded() {
        if (this.iconsLoaded) return;
        fetch(`${ICONS_ZIP}/icons.json`)
            .then((r) => r.json())
            .then((catalog) => {
                this.icons = (catalog?.icons || []).map((i) => ({
                    ...i,
                    url: `${ICONS_ZIP}/${i.file}`
                }));
                this.iconsLoaded = true;
            })
            .catch((e) => {
                // eslint-disable-next-line no-console
                console.error('[ProductPersonalizer] icons.json load failed', e);
            });
    }

    ensureFabricLoaded() {
        if (this._fabricLoaded && window.fabric) return Promise.resolve();
        return loadScript(this, FABRIC_JS).then(() => {
            this._fabricLoaded = true;
        });
    }

    initCanvas() {
        if (!window.fabric) return;
        const el = this.template.querySelector('canvas.pp-canvas');
        if (!el) return;
        if (this._fabricCanvas) return;

        this._fabricCanvas = new window.fabric.Canvas(el, {
            backgroundColor: '#ffffff',
            preserveObjectStacking: true,
            selection: false
        });

        this.loadBackgroundImage();
    }

    destroyCanvas() {
        if (this._fabricCanvas) {
            this._fabricCanvas.dispose();
            this._fabricCanvas = null;
            this._textObj = null;
            this._iconObj = null;
        }
    }

    loadBackgroundImage() {
        const url = this.productInfo?.imageUrl || this.productInfo?.displayUrl;
        if (!url || !this._fabricCanvas || !window.fabric) return;
        // No crossOrigin: shop.dentaid.es does not send CORS headers. The canvas will be
        // "tainted" (toDataURL will be blocked) but rendering works. We persist a JSON
        // payload, not a rendered PNG, so tainting is acceptable.
        window.fabric.Image.fromURL(url, (img) => {
            if (!img || !this._fabricCanvas) return;
            const scale = Math.min(CANVAS_SIZE / img.width, CANVAS_SIZE / img.height);
            img.set({
                originX: 'center',
                originY: 'center',
                left: CANVAS_SIZE / 2,
                top: CANVAS_SIZE / 2,
                scaleX: scale,
                scaleY: scale,
                selectable: false,
                evented: false
            });
            this._fabricCanvas.setBackgroundImage(
                img,
                this._fabricCanvas.renderAll.bind(this._fabricCanvas)
            );
        });
    }

    syncTextObject() {
        if (!this._fabricCanvas || !window.fabric) return;
        const trimmed = this.text;
        const font = FONT_OPTIONS.find((f) => f.value === this.selectedFont) || FONT_OPTIONS[0];

        if (!trimmed) {
            if (this._textObj) {
                this._fabricCanvas.remove(this._textObj);
                this._textObj = null;
            }
            return;
        }

        if (!this._textObj) {
            this._textObj = new window.fabric.Textbox(trimmed, {
                left: CANVAS_SIZE / 2,
                top: CANVAS_SIZE * 0.78,
                originX: 'center',
                originY: 'center',
                width: 320,
                textAlign: 'center',
                fontSize: 40,
                fontFamily: font.family,
                fontWeight: font.weight,
                fill: this.selectedColor,
                shadow: new window.fabric.Shadow({ color: 'rgba(0,0,0,0.25)', blur: 2 }),
                cornerColor: '#002F6C',
                borderColor: '#002F6C',
                cornerSize: 10,
                transparentCorners: false
            });
            this._fabricCanvas.add(this._textObj);
            this._fabricCanvas.setActiveObject(this._textObj);
        } else {
            this._textObj.set({
                text: trimmed,
                fontFamily: font.family,
                fontWeight: font.weight,
                fill: this.selectedColor
            });
        }
        this._fabricCanvas.requestRenderAll();
    }

    addOrReplaceIconObject() {
        if (!this._fabricCanvas || !window.fabric || !this.selectedIconKey) return;
        const icon = this.icons.find((i) => i.key === this.selectedIconKey);
        if (!icon) return;

        if (this._iconObj) {
            this._fabricCanvas.remove(this._iconObj);
            this._iconObj = null;
        }

        // SVGs look best loaded via loadSVGFromURL so they stay crisp when scaled.
        window.fabric.loadSVGFromURL(icon.url, (objects, options) => {
            const group = window.fabric.util.groupSVGElements(objects, options);
            group.set({
                left: CANVAS_SIZE / 2,
                top: CANVAS_SIZE * 0.6,
                originX: 'center',
                originY: 'center',
                scaleX: 80 / (group.width || 24),
                scaleY: 80 / (group.height || 24),
                cornerColor: '#002F6C',
                borderColor: '#002F6C',
                cornerSize: 10,
                transparentCorners: false
            });
            this._iconObj = group;
            this._fabricCanvas.add(group);
            this._fabricCanvas.setActiveObject(group);
            this._fabricCanvas.requestRenderAll();
        });
    }

    removeIconObject() {
        if (this._iconObj && this._fabricCanvas) {
            this._fabricCanvas.remove(this._iconObj);
            this._iconObj = null;
            this._fabricCanvas.requestRenderAll();
        }
    }

    buildPayload() {
        const state = {
            text: this.text,
            font: this.selectedFont,
            color: this.selectedColor,
            iconKey: this.selectedIconKey
        };
        if (this._textObj) {
            state.textLayer = {
                left: this._textObj.left,
                top: this._textObj.top,
                scaleX: this._textObj.scaleX,
                scaleY: this._textObj.scaleY,
                angle: this._textObj.angle
            };
        }
        if (this._iconObj) {
            state.iconLayer = {
                left: this._iconObj.left,
                top: this._iconObj.top,
                scaleX: this._iconObj.scaleX,
                scaleY: this._iconObj.scaleY,
                angle: this._iconObj.angle
            };
        }
        return state;
    }

    disconnectedCallback() {
        this.destroyCanvas();
    }
}
