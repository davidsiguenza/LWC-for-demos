/**
 * Fires loyalty journals when an Order transitions into Activated.
 * Kept intentionally thin; business logic lives in LoyaltyOrderJournalService.
 */
trigger LoyaltyOrderTrigger on Order (after update) {
    List<Id> activated = new List<Id>();
    for (Order o : Trigger.new) {
        Order old = Trigger.oldMap.get(o.Id);
        if (o.Status == 'Activated' && old.Status != 'Activated') {
            activated.add(o.Id);
        }
    }
    if (!activated.isEmpty()) {
        LoyaltyOrderJournalService.processOrders(activated);
    }
}
