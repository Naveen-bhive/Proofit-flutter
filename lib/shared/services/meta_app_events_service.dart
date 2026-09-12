import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

class MetaAppEventsService {
  MetaAppEventsService._();

  static final FacebookAppEvents _events = FacebookAppEvents();

  static Future<void> configure() async {
    try {
      await _events.setAutoLogAppEventsEnabled(true);
      await _events.setAdvertiserIdCollectionEnabled(true);
      await _events.activateApp();
      debugPrint('Meta App Events configured and activateApp triggered');
    } catch (e) {
      debugPrint('Meta App Events configure failed: $e');
    }
  }

  static Future<void> logCheckoutStarted({
    required String planSlug,
    required String planName,
    required double amount,
    String currency = 'INR',
  }) async {
    try {
      await _events.logInitiatedCheckout(
        totalPrice: amount,
        currency: currency,
        contentType: 'subscription',
        contentId: planSlug,
        numItems: 1,
        paymentInfoAvailable: true,
        parameters: {
          'plan_slug': planSlug,
          'plan_name': planName,
        },
      );
      debugPrint(
        'Meta test event triggered: InitiatedCheckout '
        'plan=$planSlug amount=$amount $currency',
      );
    } catch (e) {
      debugPrint('Meta checkout event failed: $e');
    }
  }

  static Future<void> logSubscriptionPurchased({
    required String planSlug,
    required String planName,
    required double amount,
    required String orderId,
    String currency = 'INR',
  }) async {
    try {
      final parameters = {
        'plan_slug': planSlug,
        'plan_name': planName,
        FacebookAppEvents.paramNameContentType: 'subscription',
        FacebookAppEvents.paramNameContentId: planSlug,
      };
      await _events.logSubscribe(
        price: amount,
        currency: currency,
        orderId: orderId,
        parameters: parameters,
      );
      debugPrint(
        'Meta test event triggered: Subscribe '
        'plan=$planSlug orderId=$orderId amount=$amount $currency',
      );
      await _events.logPurchase(
        amount: amount,
        currency: currency,
        parameters: parameters,
      );
      debugPrint(
        'Meta test event triggered: Purchase '
        'plan=$planSlug orderId=$orderId amount=$amount $currency',
      );
      await _events.flush();
      debugPrint('Meta test events flushed');
    } catch (e) {
      debugPrint('Meta purchase event failed: $e');
    }
  }
}
