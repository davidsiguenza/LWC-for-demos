public without sharing class CsvCartUploaderController {

    @AuraEnabled(cacheable=true)
    // CHANGE 1: The map now returns the full Product2 object, not just an Id
    public static Map<String, Product2> getProductIdsBySkus(List<String> skus) {
        
        // CHANGE 2: Initialize the map with the new type
        Map<String, Product2> skuToProductMap = new Map<String, Product2>();
        
        // CHANGE 3: Add 'Name' to the query
        for (Product2 prod : [
            SELECT Id, StockKeepingUnit, Name 
            FROM Product2 
            WHERE StockKeepingUnit IN :skus
        ]) {
            // CHANGE 4: Store the whole 'prod' object in the map
            skuToProductMap.put(prod.StockKeepingUnit, prod);
        }
        
        return skuToProductMap;
    }
}