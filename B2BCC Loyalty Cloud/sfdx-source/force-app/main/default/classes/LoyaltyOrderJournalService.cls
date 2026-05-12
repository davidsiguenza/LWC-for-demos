/**
 * On Order activation, creates:
 *   - one TransactionJournal (Redemption) per Order that carried
 *     Loyalty-tagged OrderItemAdjustmentLineItem rows
 *   - one TransactionJournal (Accrual) computed from Order.TotalAmount net of redemption,
 *     using LoyaltySiteMapping__mdt.AccrualRatio__c (default: 1 pt per $100)
 *
 * Deliberately kept in one class so the trigger stays a one-liner. The class can
 * later be superseded by a Platform Event + Flow without touching the trigger.
 */
public without sharing class LoyaltyOrderJournalService {

    public static final String JOURNAL_TYPE_ACCRUAL = 'Accrual';
    public static final String JOURNAL_TYPE_REDEMPTION = 'Redemption';
    public static final Decimal DEFAULT_ACCRUAL_RATIO = 0.01; // pts per monetary unit (1 pt / $100)

    @InvocableMethod(label='Create loyalty journals for activated orders')
    public static void createJournalsFor(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;
        processOrders(orderIds);
    }

    public static void processOrders(List<Id> orderIds) {
        Map<String, Id> journalTypeByName = journalTypeIdsByName();
        if (journalTypeByName.isEmpty()) return;
        Map<String, Id> journalSubTypeByTypeName = journalSubTypeIdsByTypeName();

        List<Order> orders = [
            SELECT Id, AccountId, TotalAmount, SalesStoreId,
                   BillToContactId, ShipToContactId, CurrencyIsoCode
            FROM Order WHERE Id IN :orderIds
        ];
        if (orders.isEmpty()) return;

        // Aggregate loyalty redemption amounts from OrderItemAdjustmentLineItem.
        Map<Id, Decimal> redemptionByOrder = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT OrderItem.OrderId orderId, SUM(Amount) total
            FROM OrderItemAdjustmentLineItem
            WHERE OrderItem.OrderId IN :orderIds AND Name = :LoyaltyRedemptionController.ADJUSTMENT_NAME
            GROUP BY OrderItem.OrderId
        ]) {
            redemptionByOrder.put((Id) ar.get('orderId'), (Decimal) ar.get('total'));
        }

        // Resolve program/ratios per Order (keyed by SalesStoreId).
        Set<Id> storeIds = new Set<Id>();
        for (Order o : orders) if (o.SalesStoreId != null) storeIds.add(o.SalesStoreId);
        Map<Id, ProgramConfig> configByStore = loadProgramConfigs(storeIds);

        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Map<Id, Id> contactByOrder = new Map<Id, Id>();
        for (Order o : orders) {
            if (o.AccountId != null) accountIds.add(o.AccountId);
            Id cid = o.BillToContactId != null ? o.BillToContactId : o.ShipToContactId;
            if (cid != null) {
                contactIds.add(cid);
                contactByOrder.put(o.Id, cid);
            }
        }

        // For each program present across orders, resolve members once.
        Set<Id> programIds = new Set<Id>();
        for (ProgramConfig pc : configByStore.values()) if (pc.programId != null) programIds.add(pc.programId);
        if (programIds.isEmpty()) {
            ProgramConfig primary = primaryProgramConfig();
            if (primary != null && primary.programId != null) programIds.add(primary.programId);
        }

        // Also look up every Contact on every buyer Account, so we can link an
        // Order (which only has AccountId) to a member enrolled by ContactId.
        Map<Id, List<Id>> contactsByAccount = new Map<Id, List<Id>>();
        if (!accountIds.isEmpty()) {
            for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
                if (!contactsByAccount.containsKey(c.AccountId)) contactsByAccount.put(c.AccountId, new List<Id>());
                contactsByAccount.get(c.AccountId).add(c.Id);
                contactIds.add(c.Id);
            }
        }

        Map<Id, Map<Id, Id>> memberByProgramThenAccount = new Map<Id, Map<Id, Id>>();
        Map<Id, Map<Id, Id>> memberByProgramThenContact = new Map<Id, Map<Id, Id>>();
        if (!programIds.isEmpty()) {
            for (LoyaltyProgramMember m : [
                SELECT Id, ProgramId, AccountId, ContactId
                FROM LoyaltyProgramMember
                WHERE ProgramId IN :programIds
                  AND (AccountId IN :accountIds OR ContactId IN :contactIds)
            ]) {
                if (m.AccountId != null) {
                    if (!memberByProgramThenAccount.containsKey(m.ProgramId)) memberByProgramThenAccount.put(m.ProgramId, new Map<Id, Id>());
                    memberByProgramThenAccount.get(m.ProgramId).put(m.AccountId, m.Id);
                }
                if (m.ContactId != null) {
                    if (!memberByProgramThenContact.containsKey(m.ProgramId)) memberByProgramThenContact.put(m.ProgramId, new Map<Id, Id>());
                    memberByProgramThenContact.get(m.ProgramId).put(m.ContactId, m.Id);
                }
            }
        }

        List<TransactionJournal> toInsert = new List<TransactionJournal>();
        for (Order o : orders) {
            ProgramConfig pc = configByStore.get(o.SalesStoreId);
            if (pc == null) pc = primaryProgramConfig();
            if (pc == null || pc.programId == null) continue;

            Id memberId = null;
            Map<Id, Id> byAcc = memberByProgramThenAccount.get(pc.programId);
            if (byAcc != null) memberId = byAcc.get(o.AccountId);
            if (memberId == null) {
                Map<Id, Id> byCon = memberByProgramThenContact.get(pc.programId);
                Id contactId = contactByOrder.get(o.Id);
                if (byCon != null && contactId != null) memberId = byCon.get(contactId);
            }
            if (memberId == null && contactsByAccount.containsKey(o.AccountId)) {
                Map<Id, Id> byCon = memberByProgramThenContact.get(pc.programId);
                if (byCon != null) {
                    for (Id cid : contactsByAccount.get(o.AccountId)) {
                        if (byCon.containsKey(cid)) { memberId = byCon.get(cid); break; }
                    }
                }
            }
            if (memberId == null) continue;

            Decimal redemptionAmount = redemptionByOrder.containsKey(o.Id) ? redemptionByOrder.get(o.Id) : null;
            if (redemptionAmount != null && redemptionAmount < 0) {
                // redemptionAmount is negative; points canjeados = |amount| * redemptionRatio
                Decimal ratio = pc.redemptionRatio == null ? 10 : pc.redemptionRatio;
                Decimal pointsRedeemed = ((-1 * redemptionAmount) * ratio).setScale(0);
                if (pointsRedeemed > 0) {
                    toInsert.add(new TransactionJournal(
                        MemberId = memberId,
                        LoyaltyProgramId = pc.programId,
                        JournalTypeId = journalTypeByName.get(JOURNAL_TYPE_REDEMPTION),
                        JournalSubTypeId = journalSubTypeByTypeName.get(JOURNAL_TYPE_REDEMPTION),
                        ActivityDate = System.now(),
                        JournalDate = System.today(),
                        TransactionAmount = -1 * pointsRedeemed,
                        Status = 'Pending',
                        OrderId = o.Id,
                        CurrencyIsoCode = o.CurrencyIsoCode,
                        Comment = 'Order ' + o.Id + ' — redeemed ' + pointsRedeemed.setScale(0) + ' pts'
                    ));
                }
            }

            Decimal accrualBase = nz(o.TotalAmount);
            Decimal accrualRatio = pc.accrualRatio == null ? DEFAULT_ACCRUAL_RATIO : pc.accrualRatio;
            Decimal pointsEarned = (accrualBase * accrualRatio).setScale(0);
            if (pointsEarned > 0) {
                toInsert.add(new TransactionJournal(
                    MemberId = memberId,
                    LoyaltyProgramId = pc.programId,
                    JournalTypeId = journalTypeByName.get(JOURNAL_TYPE_ACCRUAL),
                    JournalSubTypeId = journalSubTypeByTypeName.get(JOURNAL_TYPE_ACCRUAL),
                    ActivityDate = System.now(),
                    JournalDate = System.today(),
                    TransactionAmount = pointsEarned,
                    Status = 'Pending',
                    OrderId = o.Id,
                    CurrencyIsoCode = o.CurrencyIsoCode,
                    Comment = 'Order ' + o.Id + ' — accrued ' + pointsEarned.setScale(0) + ' pts on ' + accrualBase.setScale(2) + ' ' + o.CurrencyIsoCode
                ));
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;

        // Intentionally leave journals in Status='Pending'. `LoyaltyAccountController`
        // reads the delta from Pending journals to show an up-to-date balance while
        // `LoyaltyProgramProcess` is not configured. When an admin enables the
        // Program Process later, it will flip journals to Processed and update
        // `LoyaltyMemberCurrency.PointsBalance` natively — the display-time delta
        // automatically drops those journals, preventing double-counting.
    }

    // -----------------------------------------------------------------------
    // Config / lookups
    // -----------------------------------------------------------------------

    public class ProgramConfig {
        public Id programId;
        public Decimal accrualRatio;    // pts per monetary unit
        public Decimal redemptionRatio; // pts per 1.0 monetary unit (to reverse-engineer points from discount $)
    }

    private static Map<Id, ProgramConfig> loadProgramConfigs(Set<Id> storeIds) {
        Map<Id, ProgramConfig> out = new Map<Id, ProgramConfig>();
        if (storeIds == null || storeIds.isEmpty()) return out;
        for (LoyaltySiteMapping__mdt m : [
            SELECT WebStoreId__c, LoyaltyProgramId__c, AccrualRatio__c, RedemptionRatio__c
            FROM LoyaltySiteMapping__mdt
            WHERE WebStoreId__c IN :toStringSet(storeIds)
        ]) {
            ProgramConfig pc = new ProgramConfig();
            pc.programId = String.isBlank(m.LoyaltyProgramId__c) ? null : (Id) m.LoyaltyProgramId__c;
            pc.accrualRatio = m.AccrualRatio__c;
            pc.redemptionRatio = m.RedemptionRatio__c;
            out.put((Id) m.WebStoreId__c, pc);
        }
        return out;
    }

    private static ProgramConfig primaryProgramConfig() {
        List<LoyaltyProgram> lps = [SELECT Id FROM LoyaltyProgram WHERE IsPrimary = true LIMIT 1];
        if (lps.isEmpty()) return null;
        ProgramConfig pc = new ProgramConfig();
        pc.programId = lps[0].Id;
        pc.accrualRatio = DEFAULT_ACCRUAL_RATIO;
        pc.redemptionRatio = 10;
        return pc;
    }

    private static Map<String, Id> journalTypeIdsByName() {
        Map<String, Id> out = new Map<String, Id>();
        for (JournalType t : [
            SELECT Id, Name FROM JournalType WHERE Name IN ('Accrual', 'Redemption')
        ]) {
            out.put(t.Name, t.Id);
        }
        return out;
    }

    // Returns a map of JournalType.Name -> JournalSubType.Id for the 'Purchase' subtype
    // of each type. Keyed by type name so callers use the same JOURNAL_TYPE_* constants.
    private static Map<String, Id> journalSubTypeIdsByTypeName() {
        Map<String, Id> out = new Map<String, Id>();
        for (JournalSubType st : [
            SELECT Id, Name, JournalType.Name
            FROM JournalSubType
            WHERE Name = 'Purchase'
              AND JournalType.Name IN ('Accrual', 'Redemption')
        ]) {
            out.put(st.JournalType.Name, st.Id);
        }
        return out;
    }

    private static Set<String> toStringSet(Set<Id> ids) {
        Set<String> out = new Set<String>();
        for (Id i : ids) out.add(String.valueOf(i));
        return out;
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
}
