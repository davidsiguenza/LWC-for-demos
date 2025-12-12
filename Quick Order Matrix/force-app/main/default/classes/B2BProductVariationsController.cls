public without sharing class B2BProductVariationsController {

    // ------------------------------------------------------------------------
    // METHOD 1: LIST VARIATIONS (Kept as is)
    // ------------------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<VariationWrapper> getProductVariations(String productId) {
        if (String.isBlank(productId)) return new List<VariationWrapper>();

        String masterId = productId;
        
        try {
            List<ProductAttribute> childCheck = [SELECT VariantParentId FROM ProductAttribute WHERE ProductId = :productId LIMIT 1];
            if (!childCheck.isEmpty()) {
                masterId = childCheck[0].VariantParentId;
            }

            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.ProductAttribute.fields.getMap();
            List<String> customFields = new List<String>();
            Map<String, String> fieldLabels = new Map<String, String>();

            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
                if (dfr.isCustom() && dfr.getType() != Schema.DisplayType.REFERENCE) {
                    customFields.add(fieldName);
                    fieldLabels.put(fieldName, dfr.getLabel());
                }
            }

            String query = 'SELECT Id, ProductId, Product.Name, Product.StockKeepingUnit';
            if (!customFields.isEmpty()) {
                query += ', ' + String.join(customFields, ',');
            }
            query += ' FROM ProductAttribute WHERE VariantParentId = :masterId ORDER BY Product.Name ASC';

            List<SObject> records = Database.query(query);
            List<VariationWrapper> results = new List<VariationWrapper>();

            for (SObject rec : records) {
                VariationWrapper wrapper = new VariationWrapper();
                wrapper.id = (String)rec.get('Id'); 
                wrapper.productId = (String)rec.get('ProductId'); 
                
                SObject prod = rec.getSObject('Product');
                wrapper.productName = (String)prod.get('Name');
                wrapper.sku = (String)prod.get('StockKeepingUnit');
                wrapper.isCurrent = (wrapper.productId == productId);

                // Default values if no custom attribute is found
                wrapper.value = 'Standard'; 
                wrapper.label = 'Option';

                // New logic: Capture ALL attributes
                wrapper.attributeMap = new Map<String, String>();
                
                // Keep keeping legacy simple value/label for single-attribute scenarios (backwards compat)
                // We will populate them with the "first" found attribute just in case
                Boolean firstFound = false;

                for (String field : customFields) {
                    Object val = rec.get(field);
                    if (val != null) {
                        String sVal = String.valueOf(val);
                        String sLabel = fieldLabels.get(field);
                        
                        // Store in the map: "Color" -> "Red"
                        wrapper.attributeMap.put(sLabel, sVal);

                        if (!firstFound) {
                            wrapper.value = sVal;      
                            wrapper.label = sLabel; 
                            firstFound = true;
                        }
                    }
                }
                results.add(wrapper);
            }
            return results;

        } catch (Exception e) {
            throw new AuraHandledException('Error loading variations: ' + e.getMessage());
        }
    }

    // ------------------------------------------------------------------------
    // METHOD 2: ADD TO CART (FIXED - ERROR 500)
    // ------------------------------------------------------------------------
    @AuraEnabled
    public static void addItemsToCart(List<Object> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        try {
            String networkId = Network.getNetworkId();
            String webStoreId = [SELECT WebStoreId FROM WebStoreNetwork WHERE NetworkId = :networkId LIMIT 1].WebStoreId;
            String effectiveAccountId = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].AccountId;

            // CRITICAL STEP: Get (or create) the cart ONCE before the loop.
            // This prevents the error "Active carts can be created only when there are no current carts"
            // occurring when trying to resolve 'active' multiple times simultaneously.
            ConnectApi.CartSummary cartSummary = ConnectApi.CommerceCart.getOrCreateActiveCartSummary(
                webStoreId, 
                effectiveAccountId, 
                'active'
            );
            
            String activeCartId = cartSummary.cartId;

            // Now we iterate using the specific cart ID, not the word 'active'
            for (Object itemObj : items) {
                Map<Object, Object> itemMap = (Map<Object, Object>)itemObj;
                
                ConnectApi.CartItemInput input = new ConnectApi.CartItemInput();
                input.productId = (String)itemMap.get('productId');
                input.quantity = String.valueOf(itemMap.get('quantity'));
                input.type = ConnectApi.CartItemType.Product;
                
                // We use activeCartId (real ID) instead of 'active'
                ConnectApi.CommerceCart.addItemToCart(webStoreId, effectiveAccountId, activeCartId, input);
            }

        } catch (Exception e) {
            System.debug('Error adding to cart: ' + e.getMessage());
            throw new AuraHandledException('Error processing order: ' + e.getMessage());
        }
    }

    public class VariationWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public String value;
        @AuraEnabled public String label; // Kept only one

        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public Map<String, String> attributeMap; // New: Stores all attributes
    }
}