/**
 * Apex backend for the Product Personalizer LWC.
 *
 * Because commerce/cartApi.addItemToCart() does not accept custom fields on CartItem,
 * the LWC calls addItemToCart() first (OOTB) and then invokes
 * updateCartItemCustomization() to persist the personalization JSON
 * into CartItem.Customization__c.
 */
public with sharing class ProductPersonalizerController {

    @AuraEnabled(cacheable=true)
    public static ProductInfo getProductInfo(Id productId) {
        if (productId == null) {
            throw new AuraHandledException('productId is required');
        }
        Product2 p = [
            SELECT Id, Name, IsCustomizable__c, DisplayUrl, Image_URL__c
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
        ProductInfo info = new ProductInfo();
        info.productId = p.Id;
        info.name = p.Name;
        info.isCustomizable = p.IsCustomizable__c;
        info.displayUrl = p.DisplayUrl;
        info.imageUrl = pickImageUrl(p);
        return info;
    }

    private static String pickImageUrl(Product2 p) {
        if (String.isNotBlank(p.Image_URL__c)) {
            return p.Image_URL__c;
        }
        if (String.isNotBlank(p.DisplayUrl) && p.DisplayUrl.startsWithIgnoreCase('http')) {
            return p.DisplayUrl;
        }
        return resolveProductImageUrl(p.Id, p.DisplayUrl);
    }

    // Resolves a public media URL. Buyer users don't typically share access to ProductMedia
    // and ManagedContent SObjects via SOQL even when they can render the images through
    // the site's CMS delivery endpoint. Uses a without-sharing helper to look up the
    // ContentKey — the URL itself is public via the storefront's CDN.
    private static String resolveProductImageUrl(Id productId, String displayUrl) {
        if (String.isNotBlank(displayUrl) && displayUrl.startsWithIgnoreCase('http')) {
            return displayUrl;
        }
        String contentKey = new MediaLookup().getPrimaryContentKey(productId);
        if (String.isBlank(contentKey)) {
            return null;
        }
        return '/cms/delivery/media/' + contentKey;
    }

    private without sharing class MediaLookup {
        public String getPrimaryContentKey(Id productId) {
            List<ProductMedia> media = [
                SELECT ElectronicMediaId, SortOrder
                FROM ProductMedia
                WHERE ProductId = :productId
                ORDER BY SortOrder ASC NULLS LAST
                LIMIT 1
            ];
            if (media.isEmpty()) {
                return null;
            }
            List<ManagedContent> contents = [
                SELECT ContentKey
                FROM ManagedContent
                WHERE Id = :media[0].ElectronicMediaId
                LIMIT 1
            ];
            return contents.isEmpty() ? null : contents[0].ContentKey;
        }
    }

    @AuraEnabled
    public static void updateCartItemCustomization(Id cartItemId, String customizationJson) {
        if (cartItemId == null) {
            throw new AuraHandledException('cartItemId is required');
        }
        if (String.isBlank(customizationJson)) {
            throw new AuraHandledException('customizationJson is required');
        }
        try {
            JSON.deserializeUntyped(customizationJson);
        } catch (Exception e) {
            throw new AuraHandledException('customizationJson is not valid JSON: ' + e.getMessage());
        }
        CartItem ci = new CartItem(Id = cartItemId, Customization__c = customizationJson);
        update as user ci;
    }

    public class ProductInfo {
        @AuraEnabled public Id productId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isCustomizable;
        @AuraEnabled public String displayUrl;
        @AuraEnabled public String imageUrl;
    }
}
