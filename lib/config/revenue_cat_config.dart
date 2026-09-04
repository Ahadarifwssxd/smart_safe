/// RevenueCat API keys for SmartSafe subscriptions.
///
/// Setup steps:
/// 1. Create a free account at https://app.revenuecat.com
/// 2. Create a new project → add Android app (package: com.example.smartSafe)
/// 3. Go to Project Settings → API Keys → copy the **Android** key
/// 4. Paste it below (replace the placeholder)
/// 5. In RevenueCat, create an entitlement called "premium"
/// 6. Create two products in Google Play Console:
///    - smartsafe_premium_monthly (PKR 299/month with 7-day trial)
///    - smartsafe_premium_yearly (PKR 2,999/year with 7-day trial)
/// 7. In RevenueCat, attach both products to the "premium" entitlement
/// 8. Connect Google Play to RevenueCat (Project → Integrations → Google Play)
///
/// See BILLING_SETUP.md for the complete walkthrough.
class RevenueCatConfig {
  /// RevenueCat API key for Android.
  /// Get this from: https://app.revenuecat.com → Project → API Keys → Android
  static const String androidApiKey =
      'REPLACE_WITH_YOUR_REVENUECAT_ANDROID_API_KEY';

  /// Entitlement ID configured in RevenueCat dashboard.
  /// This must match exactly what you create in RevenueCat → Entitlements.
  static const String premiumEntitlementId = 'premium';

  /// Product IDs as created in Google Play Console.
  /// These must match exactly what you create in Play Console → Products.
  static const String monthlyProductId = 'smartsafe_premium_monthly';
  static const String yearlyProductId = 'smartsafe_premium_yearly';

  /// Whether RevenueCat is configured (API key is not the placeholder).
  static bool get isConfigured =>
      androidApiKey != 'REPLACE_WITH_YOUR_REVENUECAT_ANDROID_API_KEY' &&
      androidApiKey.isNotEmpty;
}
