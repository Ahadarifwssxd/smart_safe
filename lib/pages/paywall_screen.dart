import 'package:flutter/material.dart';
import '../models/subscription_plan.dart';
import '../services/subscription_service.dart';
import '../theme/colors.dart';
import '../widgets/fake_payment_sheet.dart';
import 'subscription_management_screen.dart';

/// Paywall screen where users can view and purchase premium subscriptions
/// with simulated real-world payment methods (JazzCash, EasyPaisa, Card, Raast).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  int _selectedPlanIndex = 1; // 0: Monthly, 1: Yearly (Recommended), 2: Lifetime

  final List<Map<String, dynamic>> _plans = [
    {
      'name': 'SmartSafe PRO Monthly',
      'price': 'Rs. 499',
      'period': '/ month',
      'badge': 'Flexible',
      'days': 30,
      'savings': null,
    },
    {
      'name': 'SmartSafe PRO Annual',
      'price': 'Rs. 3,499',
      'period': '/ year',
      'badge': 'BEST VALUE • 40% OFF',
      'days': 365,
      'savings': 'Includes 7-day free trial',
    },
    {
      'name': 'SmartSafe PRO Lifetime',
      'price': 'Rs. 7,999',
      'period': 'one-time',
      'badge': 'VIP FOREVER',
      'days': 3650,
      'savings': 'Pay once, protected forever',
    },
  ];

  void _openCheckout() {
    final plan = _plans[_selectedPlanIndex];
    FakePaymentSheet.show(
      context,
      planName: plan['name'] as String,
      priceText: plan['price'] as String,
      durationDays: plan['days'] as int,
      onSuccess: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('SmartSafe PRO Activated Successfully!'),
              ],
            ),
            backgroundColor: C.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg2,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SmartSafe PRO',
          style: TextStyle(
            color: C.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          StreamBuilder<SubscriptionInfo>(
            stream: SubscriptionService.instance.subscriptionInfoStream,
            initialData: SubscriptionService.instance.currentInfo,
            builder: (context, snap) {
              final info = snap.data ?? SubscriptionInfo.free;
              if (info.isActive && info.plan == PlanType.premium) {
                return TextButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const SubscriptionManagementScreen()),
                    );
                  },
                  icon: Icon(Icons.manage_accounts_rounded,
                      color: C.accent, size: 18),
                  label: Text('Manage',
                      style: TextStyle(
                          color: C.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Active Subscription Notice (if user is already PRO) ─────
            StreamBuilder<SubscriptionInfo>(
              stream: SubscriptionService.instance.subscriptionInfoStream,
              initialData: SubscriptionService.instance.currentInfo,
              builder: (context, snap) {
                final info = snap.data ?? SubscriptionInfo.free;
                if (info.isActive && info.plan == PlanType.premium) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          C.success.withValues(alpha: 0.25),
                          C.bg2,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: C.success.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: C.success.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_circle_rounded,
                              color: C.success, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'You are a PRO Member!',
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${info.displayName} • Unlocked',
                                style: TextStyle(
                                    color: C.success, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // ── Hero section ──────────────────────────────────────────
            _buildHero(),
            const SizedBox(height: 28),

            // ── Plan selector ─────────────────────────────────────────
            _buildPlanSelector(),
            const SizedBox(height: 24),

            // ── Checkout / Purchase button ─────────────────────────────
            _buildCheckoutButton(),
            const SizedBox(height: 14),

            // ── Payment methods summary badge ─────────────────────────
            _buildPaymentMethodsBadge(),
            const SizedBox(height: 28),

            // ── Feature comparison ────────────────────────────────────
            _buildFeatureComparison(),
            const SizedBox(height: 24),

            // ── Footer note ───────────────────────────────────────────
            Center(
              child: Text(
                'Cancel anytime with 1-tap in settings. No hidden fees.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.textMuted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    C.accent.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    C.accent,
                    C.accentLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: C.accent.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.black,
                size: 36,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'SmartSafe PRO Protection',
          style: TextStyle(
            color: C.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Unlock AI vehicle crash detection, live family radar, danger-zone alerts, and encrypted evidence vault.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: C.textMuted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(_plans.length, (index) {
        final plan = _plans[index];
        final isSelected = _selectedPlanIndex == index;
        final isPopular = index == 1;

        return GestureDetector(
          onTap: () => setState(() => _selectedPlanIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        C.accent.withValues(alpha: 0.22),
                        C.bg2,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : C.bg2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? C.accent
                    : C.border.withValues(alpha: 0.35),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: C.accent.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Radio indicator
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? C.accent : C.textMuted,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: C.accent,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),

                // Title and savings
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plan['name'] as String,
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (plan['badge'] != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPopular
                                    ? C.accent
                                    : C.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                plan['badge'] as String,
                                style: TextStyle(
                                  color:
                                      isPopular ? Colors.black : C.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (plan['savings'] != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          plan['savings'] as String,
                          style: TextStyle(
                            color: C.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan['price'] as String,
                      style: TextStyle(
                        color: isSelected ? C.accent : C.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      plan['period'] as String,
                      style: TextStyle(color: C.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCheckoutButton() {
    final selectedPlan = _plans[_selectedPlanIndex];
    return ElevatedButton(
      onPressed: _openCheckout,
      style: ElevatedButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 6,
        shadowColor: C.accent.withValues(alpha: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flash_on_rounded, color: Colors.black, size: 20),
          const SizedBox(width: 8),
          Text(
            'Unlock PRO with ${selectedPlan['price']}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.payment_rounded, color: C.accent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Supports Card • JazzCash • EasyPaisa • Raast',
            style: TextStyle(
              color: C.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureComparison() {
    final features = [
      {
        'title': 'Vehicle Crash Detection',
        'desc': 'Instant impact sensors trigger SOS automatically',
        'isPro': true,
      },
      {
        'title': 'Family Radar & Tracking',
        'desc': 'Live location history and circle status',
        'isPro': true,
      },
      {
        'title': 'Danger Zone Pro Alerts',
        'desc': 'Real-time hazard perimeter warnings on routes',
        'isPro': true,
      },
      {
        'title': 'Encrypted Evidence Vault',
        'desc': 'Tamper-proof cloud storage for incident recordings',
        'isPro': true,
      },
      {
        'title': 'Digital Emergency Will',
        'desc': 'Secure personal directives & testament vault',
        'isPro': true,
      },
      {
        'title': 'AI Driving Safety telemetry',
        'desc': 'Overspeed, braking & fatigue analytics',
        'isPro': true,
      },
      {
        'title': 'Basic SOS Alerts & Siren',
        'desc': 'Always free for all users worldwide',
        'isPro': false,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: C.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Everything Included in PRO',
                style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...features.map((f) {
            final isPro = f['isPro'] as bool;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(
                    isPro ? Icons.verified_rounded : Icons.check_circle_outline,
                    color: isPro ? C.accent : C.success,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['title'] as String,
                          style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          f['desc'] as String,
                          style: TextStyle(color: C.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPro
                          ? C.accent.withValues(alpha: 0.15)
                          : C.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPro ? 'PRO' : 'FREE',
                      style: TextStyle(
                        color: isPro ? C.accent : C.success,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
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
}
