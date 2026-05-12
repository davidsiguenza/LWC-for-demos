/**
 * Applies (and removes) a points-based discount on a WebCart by creating
 * CartItemPriceAdjustment rows across the cart's items, prorated by item total.
 *
 * Exposed to the loyaltyCheckoutRedemption LWC. Adjusts use:
 *   AdjustmentSource    = 'Discretionary'   (shows as manual discount)
 *   AdjustmentTargetType= 'Item'            (CartItem-level; Cart-level needs a group)
 *   AdjustmentType      = 'AdjustmentAmount'
 *   AdjustmentAmountScope = 'Total'         (amount is the line total discount)
 *
 * The "marker" we use to find and remove our own adjustments later is a
 * fixed string prefix in Description (no custom field required on standard objects).
 */
public without sharing class LoyaltyRedemptionController {

    public static final String ADJUSTMENT_NAME = 'Loyalty Points Redemption';

    public class RedemptionQuote {
        @AuraEnabled public Id cartId;                        // resolved cart (echo back to LWC)
        @AuraEnabled public Id memberId;
        @AuraEnabled public Decimal availablePoints;          // PointsBalance - EscrowPointsBalance
        @AuraEnabled public Decimal currentlyReservedPoints;  // already applied on this cart
        @AuraEnabled public Decimal redemptionRatio;          // points per 1.0 monetary unit
        @AuraEnabled public Decimal minPointsToRedeem;        // lower bound (nullable)
        @AuraEnabled public String currencyName;
        @AuraEnabled public Decimal cartSubtotal;             // pre-adjustment total to cap discount
    }

    public class RedemptionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Decimal pointsApplied;
        @AuraEnabled public Decimal discountApplied;  // positive monetary value
        @AuraEnabled public Decimal remainingPoints;
    }

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    @AuraEnabled(cacheable=false)
    public static RedemptionQuote getQuote(Id cartId, Id webStoreId) {
        RedemptionQuote q = new RedemptionQuote();
        if (cartId == null) cartId = resolveActiveCartId(webStoreId);
        if (cartId == null) return q;

        WebCart cart = loadCart(cartId);
        q.cartId = cart.Id;
        q.cartSubtotal = nz(cart.TotalProductAmount);

        // Resolve LoyaltyProgram + mapping config.
        ProgramConfig pc = resolveProgramConfig(webStoreId == null ? cart.WebStoreId : webStoreId);
        if (pc == null) return q;
        q.redemptionRatio  = pc.redemptionRatio;
        q.minPointsToRedeem = pc.minPoints;

        // Resolve member.
        Id memberId = resolveMemberId(pc.programId, cart.AccountId);
        if (memberId == null) return q;
        q.memberId = memberId;

        // Balance.
        List<LoyaltyMemberCurrency> lmcs = [
            SELECT PointsBalance, EscrowPointsBalance, LoyaltyProgramCurrency.Name
            FROM LoyaltyMemberCurrency
            WHERE LoyaltyMemberId = :memberId
            ORDER BY PointsBalance DESC NULLS LAST LIMIT 1
        ];
        if (!lmcs.isEmpty()) {
            q.availablePoints = nz(lmcs[0].PointsBalance) - nz(lmcs[0].EscrowPointsBalance);
            if (lmcs[0].LoyaltyProgramCurrency != null) {
                q.currencyName = lmcs[0].LoyaltyProgramCurrency.Name;
            }
        }

        q.currentlyReservedPoints = sumLoyaltyAdjustments(cartId, pc.redemptionRatio);
        return q;
    }

    @AuraEnabled
    public static RedemptionResult applyRedemption(Id cartId, Id webStoreId, Decimal pointsToRedeem) {
        RedemptionResult r = new RedemptionResult();
        r.success = false;

        if (pointsToRedeem == null || pointsToRedeem <= 0) {
            r.message = 'Enter a positive number of points to redeem.';
            return r;
        }
        if (cartId == null) cartId = resolveActiveCartId(webStoreId);
        if (cartId == null) {
            r.message = 'No active cart found.';
            return r;
        }

        WebCart cart = loadCart(cartId);
        ProgramConfig pc = resolveProgramConfig(webStoreId == null ? cart.WebStoreId : webStoreId);
        if (pc == null) {
            r.message = 'No loyalty program configured for this storefront.';
            return r;
        }

        Id memberId = resolveMemberId(pc.programId, cart.AccountId);
        if (memberId == null) {
            r.message = 'You are not enrolled in the loyalty program for this store.';
            return r;
        }

        // Validations.
        LoyaltyMemberCurrency balance = loadBalance(memberId);
        Decimal available = balance == null ? 0 : (nz(balance.PointsBalance) - nz(balance.EscrowPointsBalance));
        if (pointsToRedeem > available) {
            r.message = 'You only have ' + available.setScale(0) + ' points available.';
            return r;
        }
        if (pc.minPoints != null && pointsToRedeem < pc.minPoints) {
            r.message = 'Minimum redemption is ' + pc.minPoints.setScale(0) + ' points.';
            return r;
        }
        if (pc.redemptionRatio == null || pc.redemptionRatio <= 0) {
            r.message = 'Loyalty program redemption ratio is not configured.';
            return r;
        }

        // Cap discount at cart subtotal (never more than the order).
        Decimal discount = (pointsToRedeem / pc.redemptionRatio).setScale(2);
        Decimal subtotal = nz(cart.TotalProductAmount);
        if (discount > subtotal) {
            discount = subtotal;
            pointsToRedeem = (discount * pc.redemptionRatio).setScale(0);
        }

        // Remove any previous loyalty adjustments on this cart before applying the new one.
        removeExistingLoyaltyAdjustments(cartId);

        // Prorate across items.
        List<CartItem> items = [
            SELECT Id, TotalLineAmount, CurrencyIsoCode
            FROM CartItem
            WHERE CartId = :cartId AND TotalLineAmount > 0
            ORDER BY TotalLineAmount DESC
        ];
        if (items.isEmpty()) {
            r.message = 'Cart is empty.';
            return r;
        }
        Decimal itemsTotal = 0;
        for (CartItem ci : items) itemsTotal += nz(ci.TotalLineAmount);
        if (itemsTotal <= 0) {
            r.message = 'Cart has no priced items.';
            return r;
        }

        List<CartItemPriceAdjustment> adjustments = new List<CartItemPriceAdjustment>();
        Decimal allocated = 0;
        for (Integer i = 0; i < items.size(); i++) {
            CartItem ci = items[i];
            Decimal share;
            if (i == items.size() - 1) {
                share = discount - allocated; // sweep remainder into last item to avoid rounding drift
            } else {
                share = ((nz(ci.TotalLineAmount) / itemsTotal) * discount).setScale(2);
                allocated += share;
            }
            if (share <= 0) continue;
            CartItemPriceAdjustment adj = new CartItemPriceAdjustment(
                Name = ADJUSTMENT_NAME,
                CartItemId = ci.Id,
                AdjustmentSource = 'Discretionary',
                AdjustmentTargetType = 'Item',
                AdjustmentType = 'AdjustmentAmount',
                AdjustmentAmountScope = 'Total',
                AdjustmentValue = -1 * share,
                TotalAmount = -1 * share,
                Priority = 1000,
                Description = 'Loyalty points redemption — ' + pointsToRedeem.setScale(0) + ' pts @ ' + pc.redemptionRatio + ':1 ratio'
            );
            adjustments.add(adj);
        }
        insert adjustments;

        // Commerce doesn't auto-recalc cart totals from CartItemPriceAdjustment inserts.
        // We patch the persisted aggregates so stock Cart Summary LWCs render correctly.
        rollUpAdjustmentsToCart(cartId);

        r.success = true;
        r.pointsApplied = pointsToRedeem;
        r.discountApplied = discount;
        r.remainingPoints = available - pointsToRedeem;
        r.message = 'Applied ' + pointsToRedeem.setScale(0) + ' points (' + discount.setScale(2) + ' off)';
        return r;
    }

    @AuraEnabled
    public static RedemptionResult removeRedemption(Id cartId) {
        RedemptionResult r = new RedemptionResult();
        if (cartId == null) cartId = resolveActiveCartId(null);
        if (cartId == null) {
            r.success = false;
            r.message = 'Cart not found.';
            return r;
        }
        Integer removed = removeExistingLoyaltyAdjustments(cartId);
        rollUpAdjustmentsToCart(cartId);
        r.success = true;
        r.pointsApplied = 0;
        r.discountApplied = 0;
        r.message = removed > 0 ? 'Loyalty discount removed.' : 'No loyalty discount to remove.';
        return r;
    }

    /**
     * Sums the CartItemPriceAdjustment rows per CartItem and writes the totals
     * back to CartItem.TotalAdjustmentAmount / AdjustmentAmount and the parent
     * WebCart.TotalAdjustmentAmount / GrandTotalAmount / TotalAmountAfterAllAdjustments.
     * Without this, Commerce stock LWCs render a cart summary without the discount
     * because the pricing engine only recalcs on certain events (quantity changes etc.).
     */
    private static void rollUpAdjustmentsToCart(Id cartId) {
        Map<Id, Decimal> adjByItem = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT CartItemId ciId, SUM(TotalAmount) total
            FROM CartItemPriceAdjustment
            WHERE CartItem.CartId = :cartId
            GROUP BY CartItemId
        ]) {
            adjByItem.put((Id) ar.get('ciId'), (Decimal) ar.get('total'));
        }

        // CartItem aggregate fields are writeable; Cart-level aggregates are read-only
        // and only the pricing engine (fired by Commerce actions) recalculates them.
        // Updating CartItem persisted totals is enough for most stock cart summary LWCs
        // that roll up from items.
        List<CartItem> items = [
            SELECT Id, TotalLineAmount, TotalAdjustmentAmount, AdjustmentAmount,
                   TotalPrice, TotalPriceAfterAllAdjustments
            FROM CartItem WHERE CartId = :cartId
        ];
        for (CartItem ci : items) {
            Decimal adj = adjByItem.containsKey(ci.Id) ? adjByItem.get(ci.Id) : 0;
            ci.TotalAdjustmentAmount = adj;
            ci.AdjustmentAmount = adj;
            Decimal baseLine = nz(ci.TotalLineAmount);
            ci.TotalPriceAfterAllAdjustments = baseLine + adj;
        }
        if (!items.isEmpty()) update items;
    }

    // -----------------------------------------------------------------------
    // Internals
    // -----------------------------------------------------------------------

    private class ProgramConfig {
        Id programId;
        Decimal redemptionRatio;
        Decimal minPoints;
    }

    private static ProgramConfig resolveProgramConfig(Id webStoreId) {
        ProgramConfig pc = new ProgramConfig();
        if (webStoreId != null) {
            List<LoyaltySiteMapping__mdt> maps = [
                SELECT LoyaltyProgramId__c, RedemptionRatio__c, MinPointsToRedeem__c
                FROM LoyaltySiteMapping__mdt
                WHERE WebStoreId__c = :String.valueOf(webStoreId) LIMIT 1
            ];
            if (!maps.isEmpty()) {
                if (String.isNotBlank(maps[0].LoyaltyProgramId__c)) pc.programId = (Id) maps[0].LoyaltyProgramId__c;
                pc.redemptionRatio = maps[0].RedemptionRatio__c;
                pc.minPoints = maps[0].MinPointsToRedeem__c;
            }
        }
        if (pc.programId == null) {
            List<LoyaltyProgram> lps = [SELECT Id FROM LoyaltyProgram WHERE IsPrimary = true LIMIT 1];
            if (lps.isEmpty()) return null;
            pc.programId = lps[0].Id;
        }
        if (pc.redemptionRatio == null) pc.redemptionRatio = 10; // sensible default: 10 pts = 1.00
        return pc;
    }

    private static Id resolveMemberId(Id programId, Id accountId) {
        Id contactId = resolveBuyerContactId();
        List<LoyaltyProgramMember> members = [
            SELECT Id FROM LoyaltyProgramMember
            WHERE ProgramId = :programId
              AND (AccountId = :accountId OR ContactId = :contactId)
            LIMIT 1
        ];
        return members.isEmpty() ? null : members[0].Id;
    }

    @TestVisible
    private static Id resolveBuyerContactId() {
        Id uid = UserInfo.getUserId();
        List<User> us = [SELECT ContactId FROM User WHERE Id = :uid LIMIT 1];
        return us.isEmpty() ? null : us[0].ContactId;
    }

    private static WebCart loadCart(Id cartId) {
        return [
            SELECT Id, AccountId, WebStoreId, Status, TotalProductAmount,
                   TotalAdjustmentAmount, TotalAmount, CurrencyIsoCode
            FROM WebCart WHERE Id = :cartId LIMIT 1
        ];
    }

    /**
     * Find the running user's active cart. Commerce LWR keeps one Active cart
     * per (WebStore, buyer Account) at a time. We prefer the most recently modified.
     */
    private static final Set<String> OPEN_CART_STATUSES = new Set<String>{ 'Active', 'Checkout' };

    @TestVisible
    private static Id resolveActiveCartId(Id webStoreId) {
        Id uid = UserInfo.getUserId();
        List<WebCart> carts;
        if (webStoreId != null) {
            carts = [
                SELECT Id FROM WebCart
                WHERE Status IN :OPEN_CART_STATUSES
                  AND WebStoreId = :webStoreId
                  AND OwnerId = :uid
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
        } else {
            carts = [
                SELECT Id FROM WebCart
                WHERE Status IN :OPEN_CART_STATUSES
                  AND OwnerId = :uid
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
        }
        return carts.isEmpty() ? null : carts[0].Id;
    }

    private static LoyaltyMemberCurrency loadBalance(Id memberId) {
        List<LoyaltyMemberCurrency> lmcs = [
            SELECT PointsBalance, EscrowPointsBalance
            FROM LoyaltyMemberCurrency
            WHERE LoyaltyMemberId = :memberId
            ORDER BY PointsBalance DESC NULLS LAST LIMIT 1
        ];
        return lmcs.isEmpty() ? null : lmcs[0];
    }

    private static Integer removeExistingLoyaltyAdjustments(Id cartId) {
        List<CartItemPriceAdjustment> prior = [
            SELECT Id FROM CartItemPriceAdjustment
            WHERE CartItem.CartId = :cartId AND Name = :ADJUSTMENT_NAME
        ];
        if (!prior.isEmpty()) delete prior;
        return prior.size();
    }

    private static Decimal sumLoyaltyAdjustments(Id cartId, Decimal ratio) {
        AggregateResult[] rs = [
            SELECT SUM(TotalAmount) total FROM CartItemPriceAdjustment
            WHERE CartItem.CartId = :cartId AND Name = :ADJUSTMENT_NAME
        ];
        if (rs.isEmpty() || rs[0].get('total') == null) return 0;
        Decimal total = (Decimal) rs[0].get('total');
        if (total == null || total == 0 || ratio == null) return 0;
        return (-1 * total * ratio).setScale(0);
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }
}
