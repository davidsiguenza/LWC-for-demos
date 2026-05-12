# Product Personalizer

LWC reutilizable que añade un personalizador de productos (texto + icono) sobre una imagen del producto en la PDP de un Commerce store (B2B / D2C / Enhanced LWR). El comprador puede arrastrar, rotar y redimensionar las capas de texto e icono, y al añadir al carrito la personalización se persiste como JSON en `CartItem.Customization__c`.

Pensado para ser empaquetable y reusable entre demos: el LWC, el Apex, los static resources y el permission set usan nombres genéricos (`productPersonalizer`, `ProductPersonalizerController`, `ProductPersonalizer_*`).

## Capacidades

- Botón de "Personalizar" condicional: solo aparece si `Product2.IsCustomizable__c = true`.
- Modal con dos pestañas (**TEXTO** / **ICONO**) y vista previa en canvas con [Fabric.js](http://fabricjs.com/) — drag, rotate y scale interactivos.
- Texto con tipografías y colores configurables (paleta limitada).
- Iconos SVG cargados desde un static resource ZIP (`ProductPersonalizer_Icons`).
- Imagen del producto resuelta automáticamente del producto actual (desde `Product2.Image_URL__c`, `DisplayUrl` o `ProductMedia/ManagedContent`).
- Add-to-cart en dos pasos: `commerce/cartApi.addItemToCart` + Apex `updateCartItemCustomization` para persistir el JSON de personalización (porque `cartApi` no acepta campos custom OOTB).

## Arquitectura

```
PDP (Experience Builder, LWR)
  └── LWC: productPersonalizer
        ├── @wire CurrentPageReference → recordId del producto
        ├── @wire Apex getProductInfo(productId) → {isCustomizable, displayUrl, imageUrl, name}
        ├── (si IsCustomizable__c) Botón "Personalizar tu producto"
        └── Modal
              ├── Tab TEXTO: input texto, fuente, color
              ├── Tab ICONO: grid de iconos del static resource
              ├── Canvas Fabric.js con imagen de fondo + capas drag/rotate/scale
              └── Add to cart
                    1. cartApi.addItemToCart(productId, 1)
                    2. Apex updateCartItemCustomization(cartItemId, JSON)
                       → CartItem.Customization__c
```

## Componentes

| Tipo | Nombre | Descripción |
|---|---|---|
| LightningComponentBundle | `productPersonalizer` | LWC principal. Master Label: **Product Personalizer**. |
| ApexClass | `ProductPersonalizerController` | `getProductInfo` (cacheable) y `updateCartItemCustomization`. |
| StaticResource | `ProductPersonalizer_Fabric` | Librería [Fabric.js](http://fabricjs.com/) (canvas interactivo). |
| StaticResource | `ProductPersonalizer_Icons` | ZIP con `icons.json` + SVGs (phone, whatsapp, email, heart, star, check). |
| PermissionSet | `ProductPersonalizer` | Acceso a la clase Apex y FLS sobre los campos custom. |
| CustomField | `Product2.IsCustomizable__c` (Checkbox) | Marca productos personalizables. |
| CustomField | `Product2.Image_URL__c` (URL, opcional) | URL pública alternativa de la imagen del producto. |
| CustomField | `CartItem.Customization__c` (LongTextArea 32k) | JSON con la personalización (texto, fuente, color, icono, transformaciones). |

## Instalación

### 1. Pre-requisitos en el org
- WebStore B2B o D2C Enhanced LWR ya creado y publicado.
- Productos cargados en el store.

### 2. Deploy

```bash
sf project deploy start --target-org <alias> --source-dir force-app
```

### 3. Asignar Permission Set
Asigna `ProductPersonalizer` al Buyer User (o al perfil Guest si el storefront es público) y al admin que vaya a marcar productos:

```bash
sf org assign permset --target-org <alias> --name ProductPersonalizer
```

Si tu Buyer usa un Profile en lugar de un Permission Set Group, añádele manualmente:
- **Apex Class Access**: `ProductPersonalizerController`
- **Field-Level Security**: `Product2.IsCustomizable__c` (R/W), `Product2.Image_URL__c` (R), `CartItem.Customization__c` (R/W).

### 4. Marcar productos como personalizables

```sql
-- Opción 1: por SKU
UPDATE Product2 SET IsCustomizable__c = true WHERE StockKeepingUnit = 'TU-SKU'
```

O usando un script Apex:
```apex
Product2 p = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TU-SKU' LIMIT 1];
p.IsCustomizable__c = true;
update p;
```

### 5. Añadir el componente a la PDP del Builder

1. **Setup → Digital Experiences → All Sites** → tu site Enhanced LWR → **Builder**.
2. Navega a la página **Product** (Product Detail).
3. En el panel **Components**, busca **Product Personalizer** bajo "Custom Components".
4. Arrástralo a la sección donde quieras el botón "Personalizar".
5. **Properties** del componente:
   - `Button label` — texto del botón (default: `Personalizar tu producto`).
   - `Primary color` — color hex del botón y los handles (default: `#002F6C`).
   - `Product ID (deprecated)` — déjalo vacío. El componente lee el producto del contexto de la página automáticamente.
6. **Publish** el site.

> **Nota sobre los targets**: los LWCs custom en un site Enhanced LWR Commerce solo aparecen en el palette si **ambos targets** están en el meta:
> ```xml
> <target>lightningCommunity__Page</target>
> <target>lightningCommunity__Default</target>
> ```

## Estructura del JSON persistido

`CartItem.Customization__c` guarda algo como:

```json
{
  "text": "DR RECASENS",
  "font": "sans-bold",
  "color": "#002F6C",
  "iconKey": "whatsapp",
  "textLayer": { "left": 240, "top": 374, "scaleX": 1, "scaleY": 1, "angle": 0 },
  "iconLayer": { "left": 240, "top": 288, "scaleX": 3.3, "scaleY": 3.3, "angle": 0 }
}
```

Los `textLayer` / `iconLayer` permiten reconstruir el diseño en otra vista (Cart line item, OMS, packing slip) si se desarrolla en una iteración futura.

## Cómo extender los iconos disponibles

1. Edita `force-app/main/default/staticresources/ProductPersonalizer_Icons/icons.json` y añade entradas:
   ```json
   { "key": "twitter", "label": "Twitter", "file": "twitter.svg" }
   ```
2. Añade el SVG correspondiente en la misma carpeta.
3. Re-deploy.

## Personalización por marca

Para reusar el componente en otra demo (p.ej. otro retailer) basta con cambiar:
- `primaryColor` desde el panel del Builder (no requiere re-deploy).
- La paleta de colores y fuentes del usuario, ambas constantes al inicio de `productPersonalizer.js`.
- `icons.json` y los SVGs.

## Limitaciones conocidas

- La imagen del producto puede tener CORS bloqueado (p.ej. `shop.dentaid.es`). En ese caso el canvas queda "tainted" y no se puede exportar a PNG, pero el render funciona correctamente. Como persistimos JSON (no PNG), no es bloqueante.
- La personalización **no se muestra en el carrito ni en el checkout** OOTB en esta versión; solo se guarda. Renderizarla en otras páginas es una iteración futura (Fase 6 del plan original).
- El componente no soporta upload de iconos por parte del usuario — solo selección de la librería pre-aprobada.

## Demo

Probado en una org B2B Commerce Enhanced (Dentaid) con el producto **Cepillo Eléctrico VITIS Sonic S20**.

## Licencia

MIT.
