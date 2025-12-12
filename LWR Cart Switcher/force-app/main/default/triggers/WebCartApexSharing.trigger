trigger WebCartApexSharing on WebCart (after insert, after update) {
    List<WebCartShare> wcShareList  = new List<WebCartShare>();

    /*
    * FOR NOW WE JUST SHARE MANUALLY FROM THE COMPONENT
    *
	if(trigger.isInsert){        
        //take all the external managed accounts for the same account for the cart
        //take the user that is managing that account
        //share the cart with that user in r/w
        WebCartShare wcShare;
        for(WebCart wc : trigger.new){
    		List<DelegatedAccount> daList = 
                [SELECT ManagedById FROM DelegatedAccount
                 WHERE TargetId = :wc.AccountId];
            
            for (Integer i=0; i<daList.size(); i++) {
                String userId = daList[i].ManagedById;
                //String userType = [SELECT Type__c FROM User WHERE Id = :userId][0].Type__c;
                if (userId != wc.OwnerId) {
                    //we want to add the sharing rules for users different from the
                    //actual owner of the cart
                    wcShare = new WebCartShare();
                    wcShare.ParentId = wc.Id;
                    wcShare.AccessLevel = 'edit';
                    wcShare.UserOrGroupId = userId;
                    wcShare.RowCause = Schema.WebCartShare.RowCause.Manual;
                    wcShareList.add(wcShare);
                }
                
            }
        }
            
        Database.SaveResult[] lsr = Database.insert(wcShareList,false);
            
        // Create counter
        Integer c=0;
        
        // Process the save results
        for(Database.SaveResult sr : lsr){
            if(!sr.isSuccess()){
                // Get the first save result error
                Database.Error err = sr.getErrors()[0];
                
                // Check if the error is related to a trivial access level
                // Access levels equal or more permissive than the object's default 
                // access level are not allowed. 
                // These sharing records are not required and thus an insert exception is 
                // acceptable. 
                if(!(err.getStatusCode() == StatusCode.FIELD_FILTER_VALIDATION_EXCEPTION  
                                               &&  err.getMessage().contains('AccessLevel'))){
                    // Throw an error when the error is not related to trivial access level.
                    trigger.newMap.get(wcShareList[c].ParentId).
                      addError(
                       'Unable to grant sharing access due to following exception: '
                       + err.getMessage());
                }
            }
            c++;
        }      
    }
    */

    if(trigger.isUpdate){
        WebCart wcOld = trigger.old[0];
        WebCart wcNew = trigger.new[0];
        if (wcOld.SDO_SCOM_Shared__c == false && wcNew.SDO_SCOM_Shared__c == true) {
            List<DelegatedAccount> daList = 
                [SELECT ManagedById FROM DelegatedAccount
                 WHERE TargetId = :wcNew.AccountId];
            
            for (Integer i=0; i<daList.size(); i++) {
                String userId = daList[i].ManagedById;
                //String userType = [SELECT Type__c FROM User WHERE Id = :userId][0].Type__c;
                if (userId != wcNew.OwnerId) {
                    //we want to add the sharing rules for users different from the
                    //actual owner of the cart
                    WebCartShare wcShare = new WebCartShare();
                    wcShare.ParentId = wcNew.Id;
                    wcShare.AccessLevel = 'edit';
                    wcShare.UserOrGroupId = userId;
                    wcShare.RowCause = Schema.WebCartShare.RowCause.Manual;
                    wcShareList.add(wcShare);
                }
            }
            Database.SaveResult[] lsr = Database.insert(wcShareList,false);
            
            // Create counter
            Integer c=0;
            
            // Process the save results
            for(Database.SaveResult sr : lsr){
                if(!sr.isSuccess()){
                    // Get the first save result error
                    Database.Error err = sr.getErrors()[0];
                    
                    // Check if the error is related to a trivial access level
                    // Access levels equal or more permissive than the object's default 
                    // access level are not allowed. 
                    // These sharing records are not required and thus an insert exception is 
                    // acceptable. 
                    if(!(err.getStatusCode() == StatusCode.FIELD_FILTER_VALIDATION_EXCEPTION  
                                                &&  err.getMessage().contains('AccessLevel'))){
                        // Throw an error when the error is not related to trivial access level.
                        trigger.newMap.get(wcShareList[c].ParentId).
                        addError(
                        'Unable to grant sharing access due to following exception: '
                        + err.getMessage());
                    }
                }
                c++;
            }      
        }
    }
}