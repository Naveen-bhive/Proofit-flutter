import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../core/constants/app_constants.dart';

/// iOS-only in-app purchase layer (Android keeps the existing Razorpay flow).
/// The RevenueCat app_user_id is always our own org id (see [logIn]), so the
/// backend's webhook/sync-iap endpoints can map a purchase straight back to
/// an Organisation without any extra bookkeeping.
class RevenueCatService {
  static bool _configured = false;

  static Future<void> configure() async {
    if (!Platform.isIOS || _configured) return;
    try {
      await Purchases.setLogLevel(LogLevel.warn);
      await Purchases.configure(
        PurchasesConfiguration(AppConstants.revenueCatApiKeyIos),
      );
      _configured = true;
    } catch (e) {
      debugPrint('RevenueCat configure failed: $e');
    }
  }

  /// Ties this device's purchases to the given org so RevenueCat webhooks and
  /// the sync-iap endpoint can identify which Organisation to activate.
  static Future<void> logIn(String orgId) async {
    if (!Platform.isIOS || !_configured || orgId.isEmpty) return;
    try {
      await Purchases.logIn(orgId);
    } catch (e) {
      debugPrint('RevenueCat logIn failed: $e');
    }
  }

  static Future<void> logOut() async {
    if (!Platform.isIOS || !_configured) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('RevenueCat logOut failed: $e');
    }
  }

  /// Fetches the exact store product for a plan's revenueCatProductId. Looks
  /// products up directly by identifier rather than via RevenueCat Offerings,
  /// since the plan-to-product mapping already lives on the Plan document.
  static Future<StoreProduct?> getProduct(String revenueCatProductId) async {
    if (revenueCatProductId.isEmpty) return null;
    final products = await Purchases.getProducts([revenueCatProductId]);
    for (final p in products) {
      if (p.identifier == revenueCatProductId) return p;
    }
    return products.isNotEmpty ? products.first : null;
  }

  /// Purchases [product] and returns the resulting CustomerInfo. Throws a
  /// [PlatformException] on failure/cancellation — callers should inspect it
  /// with [PurchasesErrorHelper.getErrorCode] to distinguish user-cancelled
  /// from a real failure.
  static Future<CustomerInfo> purchase(StoreProduct product) async {
    final result = await Purchases.purchase(PurchaseParams.storeProduct(product));
    return result.customerInfo;
  }

  /// True if the CustomerInfo already reflects the target product as active —
  /// used for optimistic local UI feedback before the backend sync confirms it.
  static bool hasActiveEntitlement(CustomerInfo info) {
    final entitlement = info.entitlements.active[AppConstants.revenueCatEntitlementId];
    return entitlement != null && entitlement.isActive;
  }
}
