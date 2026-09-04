import 'package:flutter/material.dart';
import '../models/subscription_plan.dart';
import '../services/subscription_service.dart';
import '../theme/colors.dart';
import '../navigation/dark_route.dart';
import '../pages/paywall_screen.dart';

/// A reusable widget that gates a feature behind a premium subscription.
///
/// If the user has access to [feature], renders [child]. Otherwise, renders
/// [fallback] (defaults to [PremiumUpgradePrompt]).
///
/// Example:
/// ```dart
/// PremiumGate(
///   feature: PlanFeature.crashDetection,
///   child: CrashDetectionToggle(),
/// )
/// ```
class PremiumGate extends StatelessWidget {
  /// The feature to check access for.
  final PlanFeature feature;

  /// The widget to show if the user has access (premium or free-eligible).
  final Widget child;

  /// Optional custom fallback widget when user doesn't have access.
  /// Defaults to [PremiumUpgradePrompt].
  final Widget? fallback;

  /// Optional callback when user taps "Upgrade" on the fallback.
  /// If null, the default [PremiumUpgradePrompt] handles navigation.
  final VoidCallback? onUpgradeTap;

  const PremiumGate({
    super.key,
    required this.feature,
    required this.child,
    this.fallback,
    this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: SubscriptionService.instance.isPremium,
      initialData: SubscriptionService.instance.isPremiumNow,
      builder: (context, snap) {
        final isPremium = snap.data ?? false;
        final hasAccess = feature.isAvailableFor(
            isPremium ? PlanType.premium : PlanType.free);

        if (hasAccess) {
          return child;
        }

        // User doesn't have access — show fallback or default prompt.
        return fallback ??
            PremiumUpgradePrompt(
              feature: feature,
              onTap: onUpgradeTap,
            );
      },
    );
  }
}

/// A compact upgrade prompt shown when a premium feature is locked.
///
/// Tapping navigates to the paywall screen (or calls [onTap] if provided).
class PremiumUpgradePrompt extends StatelessWidget {
  /// The feature the user tried to access.
  final PlanFeature feature;

  /// Custom tap handler. If null, navigates to PaywallScreen.
  final VoidCallback? onTap;

  /// Whether to show as a compact inline widget (true) or a full card (false).
  final bool compact;

  const PremiumUpgradePrompt({
    super.key,
    required this.feature,
    this.onTap,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildCard(context);
  }

  Widget _buildCompact(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => _navigateToPaywall(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              C.accent.withValues(alpha: 0.15),
              C.accent.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: C.accent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_rounded, color: C.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    feature.name,
                    style: TextStyle(
                      color: C.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Premium feature — tap to upgrade',
                    style: TextStyle(
                      color: C.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: C.accent, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => _navigateToPaywall(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              C.accent.withValues(alpha: 0.2),
              C.accent.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: C.accent.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded,
                color: C.accent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Unlock ${feature.name}',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              feature.description,
              style: TextStyle(
                color: C.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: C.accent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                'Upgrade to Premium',
                style: TextStyle(
                  color: C.bg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPaywall(BuildContext context) {
    Navigator.push(context, darkRoute(const PaywallScreen()));
  }
}
