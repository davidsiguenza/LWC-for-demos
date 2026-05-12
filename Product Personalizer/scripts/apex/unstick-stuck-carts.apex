// Utility: finds WebCart records stuck in a non-terminal status (Checkout, Processing)
// after a failed checkout attempt and moves them to Closed so the storefront can
// provision a fresh Active cart on the buyer's next interaction.
//
// Run with: sf apex run --target-org dentaid --file scripts/apex/unstick-stuck-carts.apex

List<WebCart> stuck = [
    SELECT Id, Status, OwnerId, LastModifiedDate
    FROM WebCart
    WHERE Status IN ('Checkout', 'Processing')
    ORDER BY LastModifiedDate DESC
];

System.debug('Found ' + stuck.size() + ' carts stuck in non-terminal status');
for (WebCart c : stuck) {
    System.debug('  - ' + c.Id + ' Owner=' + c.OwnerId + ' Status=' + c.Status);
    c.Status = 'Closed';
}

if (!stuck.isEmpty()) {
    try {
        update stuck;
        System.debug('Unstuck ' + stuck.size() + ' carts.');
    } catch (Exception e) {
        System.debug('Update failed: ' + e.getMessage());
    }
}
