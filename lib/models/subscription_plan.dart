/// Subscription plan types and feature definitions for SmartSafe.
///
/// This file defines the two-tier subscription model:
/// - **Free**: Basic SOS, panic toolkit, safe route (limited)
/// - **Premium**: Everything in free + unlimited contacts, crash detection,
///   live tracking history, unlimited chatbot, danger-zone alerts
///
/// The [PlanFeature] enum maps each feature to the plans that include it,
/// making it easy to check access with [PlanFeature.isAvailableFor].
enum PlanType {
  /// Free tier — basic emergency features, no subscription required.
  free,

  /// Premium tier — all features unlocked. Requires active subscription.
  premium,
}

/// Individual features that can be gated behind a subscription plan.
///
/// Each feature has a display name, description (for the paywall), and a set
/// of plans that include it. Use [isAvailableFor] to check if a user with a
/// given plan can access the feature.
enum PlanFeature {
  /// Basic one-tap SOS trigger (always free — never gate emergency features).
  sosBasic(
    name: 'SOS Alert',
    description: 'One-tap emergency alert to trusted contacts',
    includedIn: {PlanType.free, PlanType.premium},
  ),

  /// Panic toolkit: siren, flashlight, fake call, distress timer.
  panicToolkit(
    name: 'Panic Toolkit',
    description: 'Siren, flashlight, fake call, distress timer',
    includedIn: {PlanType.free, PlanType.premium},
  ),

  /// Safe route navigation (basic).
  safeRoute(
    name: 'Safe Route',
    description: 'Navigate using the safest path',
    includedIn: {PlanType.free, PlanType.premium},
  ),

  /// Crash detection — premium only.
  crashDetection(
    name: 'Crash Detection',
    description: 'Auto-trigger SOS on detected vehicle crash',
    includedIn: {PlanType.premium},
  ),

  /// Live tracking history playback — premium only.
  liveTrackingHistory(
    name: 'Live Tracking History',
    description: 'Replay your location history on the map',
    includedIn: {PlanType.premium},
  ),

  /// Unlimited emergency contacts (free capped at 3) — premium only.
  unlimitedContacts(
    name: 'Unlimited Contacts',
    description: 'Add unlimited trusted emergency contacts',
    includedIn: {PlanType.premium},
    freeLimit: 3,
  ),

  /// Unlimited chatbot messages (free capped at 20/day) — premium only.
  unlimitedChatbot(
    name: 'Unlimited Chatbot',
    description: 'Ask SafeBot anything, no daily limit',
    includedIn: {PlanType.premium},
    freeLimit: 20,
  ),

  /// Danger-zone alerts on safe routes — premium only.
  dangerZoneAlerts(
    name: 'Danger Zone Alerts',
    description: 'Get warned when entering flagged danger areas',
    includedIn: {PlanType.premium},
  );

  const PlanFeature({
    required this.name,
    required this.description,
    required this.includedIn,
    this.freeLimit,
  });

  /// Human-readable feature name (shown on paywall).
  final String name;

  /// Short description of what the feature does.
  final String description;

  /// Set of plans that include this feature.
  final Set<PlanType> includedIn;

  /// For features with a free-tier limit (e.g., 3 contacts, 20 chatbot
  /// messages/day). Null means unlimited even on free.
  final int? freeLimit;

  /// Returns true if this feature is available for the given [plan].
  bool isAvailableFor(PlanType plan) => includedIn.contains(plan);

  /// Returns all features included in the given [plan].
  static List<PlanFeature> featuresFor(PlanType plan) =>
      PlanFeature.values.where((f) => f.isAvailableFor(plan)).toList();

  /// Returns features that are premium-only (not in free).
  static List<PlanFeature> get premiumOnly =>
      PlanFeature.values.where((f) => !f.isAvailableFor(PlanType.free)).toList();

  /// Route keys that represent PRO/Premium features.
  static const Set<String> proRouteKeys = {
    'crash_detection',
    'danger_zone',
    'family_radar',
    'evidence',
    'emergency_will',
    'driving_safety',
  };

  /// Check if a given route key is a PRO feature.
  static bool isProRoute(String routeKey) => proRouteKeys.contains(routeKey);
}

/// Metadata about a user's current subscription, typically read from Firestore,
/// SharedPreferences, or derived from RevenueCat's purchaser info.
class SubscriptionInfo {
  final PlanType plan;
  final DateTime? expiresAt;
  final bool isInTrial;
  final String? planName;
  final String? paymentMethod;
  final String? transactionId;
  final DateTime? subscribedAt;
  final bool isCancelled;

  const SubscriptionInfo({
    required this.plan,
    this.expiresAt,
    this.isInTrial = false,
    this.planName,
    this.paymentMethod,
    this.transactionId,
    this.subscribedAt,
    this.isCancelled = false,
  });

  /// Route keys that represent PRO/Premium features.
  static const Set<String> proRouteKeys = PlanFeature.proRouteKeys;

  /// Check if a given route key is a PRO feature.
  static bool isProRoute(String routeKey) => PlanFeature.isProRoute(routeKey);

  /// Free-tier subscription (default for new users).
  static const free = SubscriptionInfo(
    plan: PlanType.free,
    planName: 'SmartSafe Basic (Free)',
  );

  /// Whether the subscription is currently active (not expired and not cancelled).
  bool get isActive {
    if (plan == PlanType.free) return true; // free never expires
    if (isCancelled) return false;
    if (expiresAt == null) return false;
    return expiresAt!.isAfter(DateTime.now());
  }

  /// Human-readable display name for the plan.
  String get displayName {
    if (planName != null && planName!.isNotEmpty) return planName!;
    return plan == PlanType.premium ? 'SmartSafe PRO' : 'SmartSafe Free';
  }

  /// Human-readable payment method.
  String get displayPaymentMethod {
    if (paymentMethod != null && paymentMethod!.isNotEmpty) {
      return paymentMethod!;
    }
    return plan == PlanType.premium ? 'Verified Method' : 'None';
  }

  /// Days remaining before expiration (null if free or no expiry).
  int? get daysRemaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Whether the user has access to a specific feature.
  bool hasAccess(PlanFeature feature) {
    if (!isActive) return feature.isAvailableFor(PlanType.free);
    return feature.isAvailableFor(plan);
  }

  /// Converts to a Firestore-compatible map (for writing to users/{uid}).
  Map<String, dynamic> toFirestoreMap() => {
        'plan': plan.name,
        'planName': planName,
        'planExpiresAt': expiresAt?.toIso8601String(),
        'isInTrial': isInTrial,
        'paymentMethod': paymentMethod,
        'transactionId': transactionId,
        'subscribedAt': subscribedAt?.toIso8601String(),
        'subscriptionStatus': isActive ? 'active' : (isCancelled ? 'cancelled' : 'expired'),
        'isCancelled': isCancelled,
      };

  /// Creates a [SubscriptionInfo] from a Firestore document snapshot.
  factory SubscriptionInfo.fromFirestore(Map<String, dynamic> data) {
    final planName = data['plan'] as String? ?? 'free';
    final plan = PlanType.values.firstWhere(
      (p) => p.name == planName,
      orElse: () => PlanType.free,
    );

    DateTime? expiresAt;
    final rawExpiry = data['planExpiresAt'];
    if (rawExpiry is String) {
      expiresAt = DateTime.tryParse(rawExpiry);
    } else if (rawExpiry is DateTime) {
      expiresAt = rawExpiry;
    }

    DateTime? subscribedAt;
    final rawSubscribed = data['subscribedAt'];
    if (rawSubscribed is String) {
      subscribedAt = DateTime.tryParse(rawSubscribed);
    } else if (rawSubscribed is DateTime) {
      subscribedAt = rawSubscribed;
    }

    final isInTrial = data['isInTrial'] as bool? ?? false;
    final isCancelled = data['isCancelled'] as bool? ?? false;
    final customPlanName = data['planName'] as String?;
    final paymentMethod = data['paymentMethod'] as String?;
    final transactionId = data['transactionId'] as String?;

    return SubscriptionInfo(
      plan: plan,
      expiresAt: expiresAt,
      isInTrial: isInTrial,
      planName: customPlanName,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      subscribedAt: subscribedAt,
      isCancelled: isCancelled,
    );
  }

  @override
  String toString() =>
      'SubscriptionInfo(plan: ${plan.name}, name: $planName, method: $paymentMethod, expiresAt: $expiresAt, isActive: $isActive)';
}
