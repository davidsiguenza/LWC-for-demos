// Mark the VITIS Sonic S20 toothbrush as customizable for the Product Personalizer demo.
// Run with: sf apex run --target-org dentaid --file scripts/apex/mark-customizable-products.apex

Id productId = '01tHn00000Y73xbIAB'; // Cepillo Electrico VITIS sonic S20

Product2 p = [SELECT Id, Name, IsCustomizable__c FROM Product2 WHERE Id = :productId LIMIT 1];
System.debug('Before: ' + p.Name + ' IsCustomizable__c=' + p.IsCustomizable__c);

p.IsCustomizable__c = true;
update p;

Product2 after = [SELECT Id, Name, IsCustomizable__c FROM Product2 WHERE Id = :productId LIMIT 1];
System.debug('After: ' + after.Name + ' IsCustomizable__c=' + after.IsCustomizable__c);
