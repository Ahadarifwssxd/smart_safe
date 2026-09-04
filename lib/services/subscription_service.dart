import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/revenue_cat_config.dart';
import '../models/subscription_plan.dart';

/// Manages SmartSafe subscriptions via RevenueCat (Google Play Billing)
/// with support for offline storage, local mock/simulated payments, and Firestore sync.
///
/// Singleton — access via [SubscriptionService.instance].
class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._internal();
  SubscriptionService._internal();

  // ── State ──────────────────────────────────────────────────────────────
  String? _userId;
  bool _initialized = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _firestoreSub;

  // Cached subscription info stream (rebuilt if userId changes).
  final _subscriptionController =
      StreamController<SubscriptionInfo>.broadcast();

  // Current subscription info (sync read).
  SubscriptionInfo _currentInfo = SubscriptionInfo.free;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Current subscription info (sync snapshot).
  SubscriptionInfo get currentInfo => _currentInfo;

  /// Stream of subscription info updates.
  Stream<SubscriptionInfo> get subscriptionInfoStream =>
      _subscriptionController.stream;

  /// Convenience stream: true if user has active premium subscription.
  Stream<bool> get isPremium =>
      subscriptionInfoStream.map((info) => info.isActive && info.plan == PlanType.premium);

  /// Current premium status (sync snapshot).
  bool get isPremiumNow =>
      _currentInfo.isActive && _currentInfo.plan == PlanType.premium;

  /// Initializes SubscriptionService. Loads cached status from SharedPreferences,
  /// syncs with Firestore for [userId], and optionally initializes RevenueCat.
  Future<void> init(String? userId) async {
    _userId = userId;

    // 1. Immediately restore locally cached subscription from SharedPreferences
    await _loadFromPreferences();

    // 2. If user is logged in, sync subscription from Firestore
    if (userId != null && userId.isNotEmpty) {
      _listenToFirestoreUser(userId);
    }

    // 3. Initialize RevenueCat if configured
    if (RevenueCatConfig.isConfigured) {
      try {
        await Purchases.configure(
          PurchasesConfiguration(RevenueCatConfig.androidApiKey),
        );
        if (userId != null && userId.isNotEmpty) {
          await Purchases.logIn(userId);
        }
        Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
        final initialInfo = await Purchases.getCustomerInfo();
        _onCustomerInfoUpdated(initialInfo);
        debugPrint('SubscriptionService: RevenueCat initialized');
      } catch (e) {
        debugPrint('SubscriptionService: RevenueCat init error: $e');
      }
    }

    _initialized = true;
  }

  /// Listens to real-time subscription updates in Firestore for this user.
  void _listenToFirestoreUser(String userId) {
    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final planString = data['plan'] as String?;
      if (planString != null) {
        final cloudInfo = SubscriptionInfo.fromFirestore(data);
        if (cloudInfo.isActive != _currentInfo.isActive ||
            cloudInfo.plan != _currentInfo.plan ||
            cloudInfo.planName != _currentInfo.planName) {
          _currentInfo = cloudInfo;
          _subscriptionController.add(_currentInfo);
          _saveToPreferences(_currentInfo);
        }
      }
    }, onError: (e) {
      debugPrint('SubscriptionService: Firestore subscription listener error: $e');
    });
  }

  /// Activates a simulated / mock subscription (e.g. via JazzCash, EasyPaisa, Card).
  Future<bool> activateFakeSubscription({
    required String planName,
    required String paymentMethod,
    int durationDays = 30,
    String? transactionId,
  }) async {
    final now = DateTime.now();
    final expiry = now.add(Duration(days: durationDays));
    final txnId = transactionId ??
        'SS-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    final newInfo = SubscriptionInfo(
      plan: PlanType.premium,
      planName: planName,
      paymentMethod: paymentMethod,
      transactionId: txnId,
      subscribedAt: now,
      expiresAt: expiry,
      isCancelled: false,
    );

    _currentInfo = newInfo;
    _subscriptionController.add(_currentInfo);

    await _saveToPreferences(newInfo);
    _syncToFirestore(newInfo);

    debugPrint(
        'SubscriptionService: Fake subscription activated: $planName via $paymentMethod');
    return true;
  }

  /// Cancels the current premium subscription and reverts to Free tier.
  Future<bool> cancelSubscription() async {
    final cancelledInfo = SubscriptionInfo(
      plan: PlanType.free,
      planName: 'SmartSafe Basic (Free)',
      paymentMethod: _currentInfo.paymentMethod,
      transactionId: _currentInfo.transactionId,
      subscribedAt: _currentInfo.subscribedAt,
      expiresAt: DateTime.now(),
      isCancelled: true,
    );

    _currentInfo = cancelledInfo;
    _subscriptionController.add(_currentInfo);

    await _saveToPreferences(cancelledInfo);
    _syncToFirestore(cancelledInfo);

    debugPrint('SubscriptionService: Subscription cancelled successfully');
    return true;
  }

  /// Clears cached state on logout.
  Future<void> reset() async {
    _firestoreSub?.cancel();
    _firestoreSub = null;
    _userId = null;
    _currentInfo = SubscriptionInfo.free;
    _subscriptionController.add(_currentInfo);
    _initialized = false;

    if (RevenueCatConfig.isConfigured) {
      try {
        await Purchases.logOut();
      } catch (e) {
        debugPrint('SubscriptionService: Logout failed: $e');
      }
    }
    debugPrint('SubscriptionService: Reset');
  }

  /// Fetches available offerings from RevenueCat (or returns mock packages).
  Future<Offerings?> getOfferings() async {
    if (RevenueCatConfig.isConfigured && _initialized) {
      try {
        return await Purchases.getOfferings();
      } catch (e) {
        debugPrint('SubscriptionService: Failed to fetch RevenueCat offerings: $e');
      }
    }
    return null;
  }

  /// Purchases a package via Google Play (RevenueCat).
  Future<CustomerInfo> purchasePackage(Package package) async {
    if (!RevenueCatConfig.isConfigured) {
      throw Exception('In-app purchase not configured. Please use mock payment.');
    }
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      return customerInfo;
    } on PurchasesError catch (e) {
      debugPrint('SubscriptionService: Purchase failed: ${e.message}');
      rethrow;
    }
  }

  /// Restores previous purchases.
  Future<CustomerInfo?> restorePurchases() async {
    if (!RevenueCatConfig.isConfigured) {
      // If mock subscription exists, keep it
      if (_currentInfo.isActive && _currentInfo.plan == PlanType.premium) {
        _subscriptionController.add(_currentInfo);
        return null;
      }
      return null;
    }
    try {
      return await Purchases.restorePurchases();
    } catch (e) {
      debugPrint('SubscriptionService: Restore failed: $e');
      return null;
    }
  }

  /// Opens the Google Play subscription management screen.
  Future<bool> manageSubscription() async {
    final url = Uri.parse(
        'https://play.google.com/store/account/subscriptions?sku=${RevenueCatConfig.monthlyProductId}&package=com.example.smartSafe');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('SubscriptionService: Failed to open Play Store: $e');
    }
    return false;
  }

  // ── Local Storage Helpers ──────────────────────────────────────────────

  static const _kPlan = 'smartsafe_subscription_plan';
  static const _kPlanName = 'smartsafe_subscription_plan_name';
  static const _kExpiry = 'smartsafe_subscription_expires_at';
  static const _kMethod = 'smartsafe_subscription_payment_method';
  static const _kTxnId = 'smartsafe_subscription_transaction_id';
  static const _kSubscribedAt = 'smartsafe_subscription_subscribed_at';
  static const _kIsCancelled = 'smartsafe_subscription_is_cancelled';

  Future<void> _saveToPreferences(SubscriptionInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPlan, info.plan.name);
      if (info.planName != null) {
        await prefs.setString(_kPlanName, info.planName!);
      } else {
        await prefs.remove(_kPlanName);
      }
      if (info.expiresAt != null) {
        await prefs.setString(_kExpiry, info.expiresAt!.toIso8601String());
      } else {
        await prefs.remove(_kExpiry);
      }
      if (info.paymentMethod != null) {
        await prefs.setString(_kMethod, info.paymentMethod!);
      } else {
        await prefs.remove(_kMethod);
      }
      if (info.transactionId != null) {
        await prefs.setString(_kTxnId, info.transactionId!);
      } else {
        await prefs.remove(_kTxnId);
      }
      if (info.subscribedAt != null) {
        await prefs.setString(_kSubscribedAt, info.subscribedAt!.toIso8601String());
      } else {
        await prefs.remove(_kSubscribedAt);
      }
      await prefs.setBool(_kIsCancelled, info.isCancelled);
    } catch (e) {
      debugPrint('SubscriptionService: Save to prefs error: $e');
    }
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final planStr = prefs.getString(_kPlan);
      if (planStr == null) return;

      final plan = planStr == 'premium' ? PlanType.premium : PlanType.free;
      final planName = prefs.getString(_kPlanName);
      final expiryStr = prefs.getString(_kExpiry);
      final expiresAt = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
      final paymentMethod = prefs.getString(_kMethod);
      final txnId = prefs.getString(_kTxnId);
      final subAtStr = prefs.getString(_kSubscribedAt);
      final subscribedAt = subAtStr != null ? DateTime.tryParse(subAtStr) : null;
      final isCancelled = prefs.getBool(_kIsCancelled) ?? false;

      final restored = SubscriptionInfo(
        plan: plan,
        planName: planName,
        expiresAt: expiresAt,
        paymentMethod: paymentMethod,
        transactionId: txnId,
        subscribedAt: subscribedAt,
        isCancelled: isCancelled,
      );

      _currentInfo = restored;
      _subscriptionController.add(_currentInfo);
    } catch (e) {
      debugPrint('SubscriptionService: Load from prefs error: $e');
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  void _onCustomerInfoUpdated(CustomerInfo customerInfo) {
    final entitlements = customerInfo.entitlements.active;
    final isPremium =
        entitlements.containsKey(RevenueCatConfig.premiumEntitlementId);

    DateTime? expiresAt;
    bool isInTrial = false;
    if (isPremium) {
      final entitlement =
          entitlements[RevenueCatConfig.premiumEntitlementId];
      if (entitlement != null) {
        final expirationDate = entitlement.expirationDate;
        if (expirationDate != null) {
          expiresAt = DateTime.parse(expirationDate);
        }
        final purchaseDate = entitlement.latestPurchaseDate;
        final purchase = DateTime.parse(purchaseDate);
        final daysSincePurchase = expiresAt!.difference(purchase).inDays;
        isInTrial = daysSincePurchase > 365 || daysSincePurchase > 30;
      }
    }

    _currentInfo = SubscriptionInfo(
      plan: isPremium ? PlanType.premium : PlanType.free,
      planName: isPremium ? 'SmartSafe PRO' : 'SmartSafe Free',
      expiresAt: expiresAt,
      isInTrial: isInTrial,
    );

    _subscriptionController.add(_currentInfo);
    _saveToPreferences(_currentInfo);
    _syncToFirestore(_currentInfo);
  }

  void _syncToFirestore(SubscriptionInfo info) {
    if (_userId == null) return;
    try {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .set(info.toFirestoreMap(), SetOptions(merge: true))
          .catchError((e) {
        debugPrint('SubscriptionService: Firestore sync failed: $e');
      });
    } catch (e) {
      debugPrint('SubscriptionService: Firestore sync error: $e');
    }
  }
}
