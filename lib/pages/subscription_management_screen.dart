import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/subscription_plan.dart';
import '../services/subscription_service.dart';
import '../theme/colors.dart';
import 'paywall_screen.dart';

/// Screen for managing an existing subscription (viewing details, cancellation, renewal).
class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  bool _isCancelling = false;

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: C.red, size: 24),
            const SizedBox(width: 10),
            Text(
              'Cancel Subscription?',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel your SmartSafe PRO membership? You will immediately lose access to Vehicle Crash Detection, Live Family Radar, Danger Zone Alerts, and Cloud Evidence Vault.',
          style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep Protection',
              style: TextStyle(color: C.accent, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, Cancel Plan'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isCancelling = true);
      try {
        await SubscriptionService.instance.cancelSubscription();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Subscription cancelled. Your account is now on the Free tier.'),
            backgroundColor: C.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _isCancelling = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg2,
        elevation: 0,
        title: Text(
          'Manage Subscription',
          style: TextStyle(
            color: C.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: StreamBuilder<SubscriptionInfo>(
        stream: SubscriptionService.instance.subscriptionInfoStream,
        initialData: SubscriptionService.instance.currentInfo,
        builder: (context, snap) {
          final info = snap.data ?? SubscriptionInfo.free;
          final isPremium =
              info.isActive && info.plan == PlanType.premium;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Current plan card ───────────────────────────────
                _buildPlanCard(info, isPremium),
                const SizedBox(height: 24),

                // ── Action Buttons ──────────────────────────────────
                if (isPremium) ...[
                  _buildCancelButton(),
                  const SizedBox(height: 12),
                ] else ...[
                  _buildUpgradeButton(),
                  const SizedBox(height: 12),
                ],

                // ── Active Features Checklist ───────────────────────
                _buildFeaturesList(isPremium),
                const SizedBox(height: 24),

                // ── Subscription Details Box ────────────────────────
                _buildDetailsBox(info, isPremium),
                const SizedBox(height: 24),

                // ── Support section ─────────────────────────────────
                _buildSupportSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionInfo info, bool isPremium) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? [
                  C.accent.withValues(alpha: 0.25),
                  C.bg2,
                ]
              : [
                  C.bg2,
                  C.bg3,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPremium
              ? C.accent.withValues(alpha: 0.4)
              : C.border.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: isPremium
            ? [
                BoxShadow(
                  color: C.accent.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // Crown / Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isPremium
                  ? C.accent.withValues(alpha: 0.2)
                  : C.bg3,
              shape: BoxShape.circle,
              border: Border.all(
                color: isPremium ? C.accent : C.border,
                width: 2,
              ),
            ),
            child: Icon(
              isPremium
                  ? Icons.workspace_premium_rounded
                  : Icons.shield_outlined,
              color: isPremium ? C.accent : C.textMuted,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),

          // Title & Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                info.displayName,
                style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPremium
                      ? C.success.withValues(alpha: 0.2)
                      : C.textMuted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPremium ? C.success : C.textMuted,
                    width: 1,
                  ),
                ),
                child: Text(
                  isPremium ? 'ACTIVE' : 'FREE',
                  style: TextStyle(
                    color: isPremium ? C.success : C.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            isPremium
                ? 'All 6 PRO safety tools are active and unlocked'
                : 'Limited to basic emergency dial and panic alarm',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.textMuted, fontSize: 13),
          ),

          if (isPremium && info.expiresAt != null) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: C.bg.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_rounded,
                      color: C.accent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Valid until: ${DateFormat('dd MMM yyyy').format(info.expiresAt!)}',
                    style: TextStyle(
                      color: C.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (info.daysRemaining != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${info.daysRemaining} days left)',
                      style: TextStyle(color: C.accent, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return OutlinedButton.icon(
      onPressed: _isCancelling ? null : _confirmCancel,
      icon: _isCancelling
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.red),
            )
          : Icon(Icons.cancel_outlined, color: C.red, size: 20),
      label: Text(
        'Cancel Subscription',
        style: TextStyle(
          color: C.red,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: C.red.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildUpgradeButton() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
      },
      icon: const Icon(Icons.flash_on_rounded, color: Colors.black, size: 20),
      label: const Text(
        'Upgrade to SmartSafe PRO',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: C.accent,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildFeaturesList(bool isPremium) {
    final features = [
      {'title': 'Crash Detection (Auto-SOS)', 'isPro': true},
      {'title': 'Danger Zone Perimeter Warnings', 'isPro': true},
      {'title': 'Family Radar & Live GPS History', 'isPro': true},
      {'title': 'Evidence Cloud Locker Vault', 'isPro': true},
      {'title': 'Digital Emergency Will Vault', 'isPro': true},
      {'title': 'AI Driving Safety Analytics', 'isPro': true},
      {'title': 'Basic SOS Alerts & Siren', 'isPro': false},
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FEATURE ACCESS STATUS',
            style: TextStyle(
              color: C.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          ...features.map((f) {
            final isPro = f['isPro'] as bool;
            final isUnlocked = isPremium || !isPro;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    isUnlocked
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    color: isUnlocked ? C.success : C.textMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f['title'] as String,
                      style: TextStyle(
                        color: isUnlocked ? C.textPrimary : C.textMuted,
                        fontSize: 13,
                        fontWeight: isUnlocked ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    isUnlocked ? 'Unlocked' : 'PRO Required',
                    style: TextStyle(
                      color: isUnlocked ? C.success : C.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDetailsBox(SubscriptionInfo info, bool isPremium) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _detailRow('Payment Method', info.displayPaymentMethod),
          const Divider(height: 16),
          _detailRow('Transaction ID', info.transactionId ?? 'N/A'),
          const Divider(height: 16),
          _detailRow(
            'Subscribed On',
            info.subscribedAt != null
                ? DateFormat('dd MMM yyyy, hh:mm a').format(info.subscribedAt!)
                : 'N/A',
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: C.textMuted, fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: C.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection() {
    return Center(
      child: Text(
        'Need billing support? Contact support@smartsafe.app',
        style: TextStyle(color: C.textMuted, fontSize: 11),
      ),
    );
  }
}
