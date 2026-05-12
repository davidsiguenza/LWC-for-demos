/**
 * Single Apex entry point for the four My Account LWCs (balance, tier progress,
 * transaction history, vouchers). Resolves the running buyer's LoyaltyProgramMember
 * from the site mapping and serves read-only projections to the UI.
 *
 * All methods are `@AuraEnabled cacheable=true`. The LWCs should call them via
 * @wire and re-wire when the buyer changes.
 *
 * B2B assumption: the running user's Contact.AccountId is the BuyerAccount; we
 * enrol LoyaltyProgramMember by AccountId (not ContactId). If a legacy program
 * uses ContactId enrolment, fall back to it.
 */
public without sharing class LoyaltyAccountController {

    /** One step in the tier stepper. */
    public class TierStep {
        @AuraEnabled public Id tierId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer sequenceNumber;
        @AuraEnabled public Decimal minPoints;
        @AuraEnabled public Decimal maxPoints;
        @AuraEnabled public String color;
        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public Boolean isCompleted; // true if sequence < current
        @AuraEnabled public Boolean isLocked;    // true if sequence > current
    }

    /** What the balance card renders. */
    public class MemberSummary {
        @AuraEnabled public Id memberId;
        @AuraEnabled public String membershipNumber;
        @AuraEnabled public String memberStatus;
        @AuraEnabled public Date enrollmentDate;
        @AuraEnabled public Decimal pointsBalance;
        @AuraEnabled public Decimal escrowPointsBalance;
        @AuraEnabled public Decimal pointsAvailableToRedeem; // balance - escrow
        @AuraEnabled public Decimal totalPointsAccrued;
        @AuraEnabled public Decimal totalPointsRedeemed;
        @AuraEnabled public String currencyName;
        @AuraEnabled public String currencyType;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public String currentTierName;
        @AuraEnabled public Integer currentTierSequence;
        @AuraEnabled public String tierGroupName;
        @AuraEnabled public String nextTierName;
        @AuraEnabled public Decimal progressToNextTier; // 0..1; null if at top tier
        @AuraEnabled public Decimal pointsToNextTier;   // null if at top tier
        @AuraEnabled public Decimal currentTierMinPoints;
        @AuraEnabled public Decimal nextTierMinPoints;
        @AuraEnabled public String currentTierColor;
        @AuraEnabled public List<TierStep> tierStepper; // ordered by SequenceNumber
    }

    public class TransactionDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String journalType;
        @AuraEnabled public String journalSubType;
        @AuraEnabled public Decimal transactionAmount;
        @AuraEnabled public Datetime activityDate;
        @AuraEnabled public String status;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String comment;
    }

    public class VoucherDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String voucherCode;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal faceValue;
        @AuraEnabled public Decimal remainingValue;
        @AuraEnabled public Integer discountPercent;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Date expirationDate;
    }

    /**
     * Full summary for the currently logged-in buyer against the given WebStore.
     * The WebStore → LoyaltyProgram mapping is resolved via LoyaltySiteMapping__mdt.
     */
    @AuraEnabled(cacheable=true)
    public static MemberSummary getMemberSummary(Id webStoreId) {
        Id programId = resolveProgramIdForStore(webStoreId);
        if (programId == null) return null;

        Id accountId = resolveBuyerAccountId();
        Id contactId = resolveBuyerContactId();
        if (accountId == null && contactId == null) return null;

        // B2B demos typically enrol by AccountId; the Cirrus seed pack uses ContactId.
        // We accept either so the connector works against both conventions.
        List<LoyaltyProgramMember> members = [
            SELECT Id, MembershipNumber, MemberStatus, EnrollmentDate
            FROM LoyaltyProgramMember
            WHERE ProgramId = :programId
              AND (AccountId = :accountId OR ContactId = :contactId)
            LIMIT 1
        ];
        if (members.isEmpty()) return null;

        LoyaltyProgramMember m = members[0];
        MemberSummary s = new MemberSummary();
        s.memberId = m.Id;
        s.membershipNumber = m.MembershipNumber;
        s.memberStatus = m.MemberStatus;
        s.enrollmentDate = m.EnrollmentDate;

        populateBalance(s, m.Id, programId);
        populateTier(s, m.Id);
        return s;
    }

    /** Transaction history — paginated by LIMIT/OFFSET. */
    @AuraEnabled(cacheable=true)
    public static List<TransactionDTO> getTransactions(Id memberId, Integer limitSize, Integer offsetSize) {
        if (memberId == null) return new List<TransactionDTO>();
        Integer lim = (limitSize == null || limitSize <= 0) ? 30 : Math.min(limitSize, 200);
        Integer off = (offsetSize == null || offsetSize < 0) ? 0 : offsetSize;
        List<TransactionJournal> journals = Database.query(
            'SELECT Id, JournalType.Name, JournalSubType.Name, TransactionAmount, ' +
            'ActivityDate, Status, OrderId, Comment ' +
            'FROM TransactionJournal ' +
            'WHERE MemberId = :memberId ' +
            'ORDER BY ActivityDate DESC NULLS LAST LIMIT :lim OFFSET :off'
        );
        List<TransactionDTO> out = new List<TransactionDTO>();
        for (TransactionJournal tj : journals) {
            TransactionDTO t = new TransactionDTO();
            t.id = tj.Id;
            t.journalType = tj.JournalType != null ? tj.JournalType.Name : null;
            t.journalSubType = tj.JournalSubType != null ? tj.JournalSubType.Name : null;
            t.transactionAmount = tj.TransactionAmount;
            t.activityDate = tj.ActivityDate;
            t.status = tj.Status;
            t.orderId = tj.OrderId;
            t.comment = tj.Comment;
            out.add(t);
        }
        return out;
    }

    /** Active vouchers for the member. */
    @AuraEnabled(cacheable=true)
    public static List<VoucherDTO> getVouchers(Id memberId) {
        if (memberId == null) return new List<VoucherDTO>();
        List<Voucher> vs = [
            SELECT Id, Name, VoucherCode, Status, FaceValue, RemainingValue,
                   DiscountPercent, EffectiveDate, ExpirationDate
            FROM Voucher
            WHERE LoyaltyProgramMemberId = :memberId
              AND Status IN ('Issued', 'Active')
            ORDER BY ExpirationDate ASC NULLS LAST
        ];
        List<VoucherDTO> out = new List<VoucherDTO>();
        for (Voucher v : vs) {
            VoucherDTO dto = new VoucherDTO();
            dto.id = v.Id;
            dto.voucherCode = v.VoucherCode;
            dto.name = v.Name;
            dto.status = v.Status;
            dto.faceValue = v.FaceValue;
            dto.remainingValue = v.RemainingValue;
            dto.discountPercent = v.DiscountPercent;
            dto.effectiveDate = v.EffectiveDate;
            dto.expirationDate = v.ExpirationDate;
            out.add(dto);
        }
        return out;
    }

    // -----------------------------------------------------------------------
    // internals
    // -----------------------------------------------------------------------

    /**
     * Buyer Account for the running user. In B2B Commerce Experience Cloud the
     * login Contact has AccountId set to the BuyerAccount.
     */
    @TestVisible
    private static Id resolveBuyerAccountId() {
        Id uid = UserInfo.getUserId();
        List<User> us = [
            SELECT Id, ContactId, Contact.AccountId, AccountId
            FROM User
            WHERE Id = :uid
            LIMIT 1
        ];
        if (us.isEmpty()) return null;
        User u = us[0];
        if (u.AccountId != null) return u.AccountId;
        if (u.Contact != null && u.Contact.AccountId != null) return u.Contact.AccountId;
        return null;
    }

    @TestVisible
    private static Id resolveBuyerContactId() {
        Id uid = UserInfo.getUserId();
        List<User> us = [SELECT Id, ContactId FROM User WHERE Id = :uid LIMIT 1];
        return us.isEmpty() ? null : us[0].ContactId;
    }

    /**
     * Resolve LoyaltyProgramId for a WebStore via LoyaltySiteMapping__mdt.
     * Falls back to the primary program if no mapping is configured.
     */
    @TestVisible
    private static Id resolveProgramIdForStore(Id webStoreId) {
        if (webStoreId != null) {
            List<LoyaltySiteMapping__mdt> maps = [
                SELECT LoyaltyProgramId__c
                FROM LoyaltySiteMapping__mdt
                WHERE WebStoreId__c = :String.valueOf(webStoreId)
                LIMIT 1
            ];
            if (!maps.isEmpty() && String.isNotBlank(maps[0].LoyaltyProgramId__c)) {
                return (Id) maps[0].LoyaltyProgramId__c;
            }
        }
        List<LoyaltyProgram> primary = [
            SELECT Id FROM LoyaltyProgram WHERE IsPrimary = true LIMIT 1
        ];
        return primary.isEmpty() ? null : primary[0].Id;
    }

    /**
     * Adds the signed sum of connector-inserted TransactionJournal rows that have
     * not yet been applied to LoyaltyMemberCurrency to the seed balance.
     *
     * Why this exists: in an SDO without LoyaltyProgramProcess rules configured,
     * `LoyaltyMemberCurrency.PointsBalance` is read-only and stays at its seed
     * value. The widget would show a stale balance every time a redemption or
     * order accrual happens. This delta bridges that gap for demos.
     *
     * Self-healing, via `LoyaltyLedger` existence: when a Program Process is
     * configured and runs (either automatically via the
     * `Loyalty_Run_Process_on_TJ_Pending` Flow, or manually), it creates a
     * `LoyaltyLedger` row linking back to the journal and updates
     * `LoyaltyMemberCurrency.PointsBalance` natively. Journals that already have
     * a ledger drop out of this sum, so there's no double-counting.
     *
     * Why not Status-based: the invocable action
     * `runProgramProcessForTransactionJournal` flips Status to `Processed` even
     * when no Program Process is configured (i.e. no ledger is created and the
     * balance is not updated). Status is an unreliable indicator; presence of a
     * ledger is the ground truth.
     */
    private static Decimal pendingJournalDelta(Id memberId) {
        AggregateResult[] rs = [
            SELECT SUM(TransactionAmount) total
            FROM TransactionJournal
            WHERE MemberId = :memberId
              AND OrderId != NULL
              AND Id NOT IN (SELECT TransactionJournalId FROM LoyaltyLedger)
        ];
        if (rs.isEmpty() || rs[0].get('total') == null) return 0;
        return (Decimal) rs[0].get('total');
    }

    private static void populateBalance(MemberSummary s, Id memberId, Id programId) {
        // LoyaltyProgramCurrencyId can be null in some seeded data (e.g. Cirrus demo).
        // Pick the row with the highest PointsBalance + TotalPointsAccrued as the "primary"
        // balance; for production programs with one Points currency, this collapses to the single row.
        List<LoyaltyMemberCurrency> rows = [
            SELECT Id, PointsBalance, EscrowPointsBalance, TotalPointsAccrued, TotalPointsRedeemed,
                   LoyaltyProgramCurrencyId,
                   LoyaltyProgramCurrency.Name, LoyaltyProgramCurrency.CurrencyType,
                   LoyaltyProgramCurrency.CurrencyIsoCode
            FROM LoyaltyMemberCurrency
            WHERE LoyaltyMemberId = :memberId
            ORDER BY PointsBalance DESC NULLS LAST, TotalPointsAccrued DESC NULLS LAST
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            s.pointsBalance = 0;
            s.escrowPointsBalance = 0;
            s.pointsAvailableToRedeem = 0;
            s.totalPointsAccrued = 0;
            s.totalPointsRedeemed = 0;
            return;
        }
        LoyaltyMemberCurrency lmc = rows[0];
        // Base balance from LoyaltyMemberCurrency + delta of journals still Pending
        // (i.e. not yet applied by LoyaltyProgramProcess). Self-healing:
        // when an admin later enables the Program Process, Processed journals
        // drop out of the delta automatically.
        Decimal delta = pendingJournalDelta(memberId);
        s.pointsBalance = nz(lmc.PointsBalance) + delta;
        s.escrowPointsBalance = nz(lmc.EscrowPointsBalance);
        s.pointsAvailableToRedeem = s.pointsBalance - s.escrowPointsBalance;
        s.totalPointsAccrued = nz(lmc.TotalPointsAccrued);
        s.totalPointsRedeemed = nz(lmc.TotalPointsRedeemed);
        // Reflect not-yet-ledgered accruals / redemptions in the running totals
        // so the UI (e.g. the tier progress widget's points-to-next calculation)
        // sees them before Program Process creates the ledger rows.
        AggregateResult[] accrualSum = [
            SELECT SUM(TransactionAmount) total FROM TransactionJournal
            WHERE MemberId = :memberId AND OrderId != NULL AND TransactionAmount > 0
              AND Id NOT IN (SELECT TransactionJournalId FROM LoyaltyLedger)
        ];
        if (!accrualSum.isEmpty() && accrualSum[0].get('total') != null) {
            s.totalPointsAccrued = s.totalPointsAccrued + (Decimal) accrualSum[0].get('total');
        }
        AggregateResult[] redemptionSum = [
            SELECT SUM(TransactionAmount) total FROM TransactionJournal
            WHERE MemberId = :memberId AND OrderId != NULL AND TransactionAmount < 0
              AND Id NOT IN (SELECT TransactionJournalId FROM LoyaltyLedger)
        ];
        if (!redemptionSum.isEmpty() && redemptionSum[0].get('total') != null) {
            Decimal r = (Decimal) redemptionSum[0].get('total');
            s.totalPointsRedeemed = s.totalPointsRedeemed + (-1 * r);
        }
        if (lmc.LoyaltyProgramCurrency != null) {
            s.currencyName = lmc.LoyaltyProgramCurrency.Name;
            s.currencyType = lmc.LoyaltyProgramCurrency.CurrencyType;
            s.currencyIsoCode = lmc.LoyaltyProgramCurrency.CurrencyIsoCode;
        } else {
            List<LoyaltyProgramCurrency> pc = [
                SELECT Name, CurrencyType, CurrencyIsoCode
                FROM LoyaltyProgramCurrency
                WHERE LoyaltyProgramId = :programId
                LIMIT 1
            ];
            if (!pc.isEmpty()) {
                s.currencyName = pc[0].Name;
                s.currencyType = pc[0].CurrencyType;
                s.currencyIsoCode = pc[0].CurrencyIsoCode;
            }
        }
    }

    private static void populateTier(MemberSummary s, Id memberId) {
        // Step 1 — resolve the member's assigned LoyaltyMemberTier (and therefore group).
        // Prefer rows where LoyaltyTierId is set; fall back to Name-only rows for seeded data.
        List<LoyaltyMemberTier> mts = [
            SELECT Id, Name, LoyaltyTierId, LoyaltyTierGroupId, EffectiveDate, Status,
                   LoyaltyTier.Name, LoyaltyTier.SequenceNumber,
                   LoyaltyTier.LoyaltyTierGroup.Name
            FROM LoyaltyMemberTier
            WHERE LoyaltyMemberId = :memberId
            ORDER BY LoyaltyTierId NULLS LAST, EffectiveDate DESC NULLS LAST
            LIMIT 1
        ];
        if (mts.isEmpty()) return;
        LoyaltyMemberTier mt = mts[0];

        Id tierGroupId = mt.LoyaltyTierGroupId;
        if (mt.LoyaltyTier != null) {
            s.currentTierName = mt.LoyaltyTier.Name;
            s.currentTierSequence = mt.LoyaltyTier.SequenceNumber;
            s.tierGroupName = mt.LoyaltyTier.LoyaltyTierGroup != null ? mt.LoyaltyTier.LoyaltyTierGroup.Name : null;
        } else if (String.isNotBlank(mt.Name)) {
            s.currentTierName = mt.Name;
        }

        if (tierGroupId == null) return;

        // Step 2 — load every tier in the group so the UI can render a stepper.
        List<LoyaltyTier> groupTiers = [
            SELECT Id, Name, SequenceNumber, MinimumEligibleBalance, MaximumEligibleBalance, Color
            FROM LoyaltyTier
            WHERE LoyaltyTierGroupId = :tierGroupId
            ORDER BY SequenceNumber ASC
        ];
        if (groupTiers.isEmpty()) return;

        // Step 3 — if the member's sequence is unknown (Name-only row), derive it from
        // TotalPointsAccrued using MinimumEligibleBalance thresholds.
        Decimal accrued = s.totalPointsAccrued == null ? 0 : s.totalPointsAccrued;
        if (s.currentTierSequence == null) {
            for (LoyaltyTier t : groupTiers) {
                if (t.MinimumEligibleBalance != null && accrued >= t.MinimumEligibleBalance) {
                    s.currentTierName = t.Name;
                    s.currentTierSequence = t.SequenceNumber;
                }
            }
            if (s.currentTierSequence == null) {
                s.currentTierSequence = groupTiers[0].SequenceNumber;
                s.currentTierName = groupTiers[0].Name;
            }
        }

        // Step 4 — build the stepper + pull colors / min thresholds for the current tier.
        List<TierStep> stepper = new List<TierStep>();
        LoyaltyTier currentTier;
        LoyaltyTier nextTier;
        for (LoyaltyTier t : groupTiers) {
            TierStep step = new TierStep();
            step.tierId = t.Id;
            step.name = t.Name;
            step.sequenceNumber = t.SequenceNumber;
            step.minPoints = t.MinimumEligibleBalance;
            step.maxPoints = t.MaximumEligibleBalance;
            step.color = t.Color;
            step.isCurrent = (t.SequenceNumber == s.currentTierSequence);
            step.isCompleted = (t.SequenceNumber < s.currentTierSequence);
            step.isLocked = (t.SequenceNumber > s.currentTierSequence);
            stepper.add(step);
            if (step.isCurrent) currentTier = t;
            if (nextTier == null && t.SequenceNumber > s.currentTierSequence) nextTier = t;
        }
        s.tierStepper = stepper;

        if (currentTier != null) {
            s.currentTierColor = currentTier.Color;
            s.currentTierMinPoints = currentTier.MinimumEligibleBalance;
        }
        if (nextTier == null) return; // top tier, nothing to progress to

        s.nextTierName = nextTier.Name;
        s.nextTierMinPoints = nextTier.MinimumEligibleBalance;

        // Step 5 — progress math. Needs both current.min and next.min.
        if (s.currentTierMinPoints == null || s.nextTierMinPoints == null) return;
        Decimal span = s.nextTierMinPoints - s.currentTierMinPoints;
        if (span <= 0) return;
        Decimal earnedInTier = accrued - s.currentTierMinPoints;
        if (earnedInTier < 0) earnedInTier = 0;
        Decimal pct = earnedInTier / span;
        if (pct > 1) pct = 1;
        if (pct < 0) pct = 0;
        s.progressToNextTier = pct.setScale(4);
        Decimal remaining = s.nextTierMinPoints - accrued;
        s.pointsToNextTier = remaining < 0 ? 0 : remaining;

        // Progress heuristic: use TotalPointsAccrued vs SequenceNumber gap.
        // Real tier thresholds live in LoyaltyProgramProcess rules, not directly on LoyaltyTier
        // in some releases. For the widget we expose a best-effort fraction; admins can refine.
        if (s.totalPointsAccrued != null && s.totalPointsAccrued > 0) {
            // Best-effort: we don't have the threshold per tier exposed here. Show null
            // rather than lying. The widget will hide the bar when this is null.
            s.progressToNextTier = null;
            s.pointsToNextTier = null;
        }
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
}
