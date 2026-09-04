import 'package:flutter/material.dart';
import 'package:smartsafe/services/subscription_service.dart';
import 'package:smartsafe/theme/colors.dart';

/// Modal bottom sheet allowing users to test purchasing SmartSafe PRO
/// using simulated mock payment methods (Credit Card, JazzCash, EasyPaisa, Raast).
class FakePaymentSheet extends StatefulWidget {
  final String planName;
  final String priceText;
  final int durationDays;
  final VoidCallback? onSuccess;

  const FakePaymentSheet({
    super.key,
    required this.planName,
    required this.priceText,
    this.durationDays = 365,
    this.onSuccess,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String planName,
    required String priceText,
    int durationDays = 365,
    VoidCallback? onSuccess,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FakePaymentSheet(
        planName: planName,
        priceText: priceText,
        durationDays: durationDays,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<FakePaymentSheet> createState() => _FakePaymentSheetState();
}

class _FakePaymentSheetState extends State<FakePaymentSheet> {
  int _selectedMethodIndex = 0; // 0: Card, 1: JazzCash, 2: EasyPaisa, 3: Raast

  // Card controllers
  final _cardNumberController =
      TextEditingController(text: '4242 4242 4242 4242');
  final _cardExpiryController = TextEditingController(text: '12/28');
  final _cardCvvController = TextEditingController(text: '888');
  final _cardNameController = TextEditingController(text: 'SmartSafe VIP User');

  // JazzCash controllers
  final _jazzPhoneController = TextEditingController(text: '0301-7654321');
  final _jazzPinController = TextEditingController(text: '1234');

  // EasyPaisa controllers
  final _easyPhoneController = TextEditingController(text: '0345-1234567');

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _cardNameController.dispose();
    _jazzPhoneController.dispose();
    _jazzPinController.dispose();
    _easyPhoneController.dispose();
    super.dispose();
  }

  String get _currentPaymentMethodName {
    switch (_selectedMethodIndex) {
      case 0:
        return 'Credit/Debit Card (Visa •••• 4242)';
      case 1:
        return 'JazzCash (${_jazzPhoneController.text})';
      case 2:
        return 'EasyPaisa (${_easyPhoneController.text})';
      case 3:
      default:
        return 'Raast Instant Pay (Direct)';
    }
  }

  Future<void> _processPayment() async {
    // Show realistic simulated processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _PaymentProcessingDialog(
        methodName: _currentPaymentMethodName,
        amount: widget.priceText,
      ),
    );

    // Simulated network processing latency
    await Future.delayed(const Duration(milliseconds: 2200));

    if (!mounted) return;

    // Activate subscription in service (saves locally + cloud sync)
    await SubscriptionService.instance.activateFakeSubscription(
      planName: widget.planName,
      paymentMethod: _currentPaymentMethodName,
      durationDays: widget.durationDays,
    );

    // Close processing dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;

    // Close payment bottom sheet
    Navigator.of(context).pop(true);

    // Show celebration modal
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _PaymentSuccessDialog(
        planName: widget.planName,
        methodName: _currentPaymentMethodName,
      ),
    );

    widget.onSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: C.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: C.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header summary
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        C.accent.withValues(alpha: 0.25),
                        C.accent.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.accent.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.verified_user_rounded, color: C.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unlock SmartSafe PRO',
                        style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widget.planName} • ${widget.priceText}',
                        style: TextStyle(
                          color: C.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: C.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: C.success.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'TEST MODE',
                    style: TextStyle(
                      color: C.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Method Selector Tabs
            Text(
              'CHOOSE PAYMENT METHOD',
              style: TextStyle(
                color: C.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _methodTab(
                    index: 0,
                    icon: Icons.credit_card_rounded,
                    label: 'Card (Visa/MC)',
                  ),
                  const SizedBox(width: 8),
                  _methodTab(
                    index: 1,
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'JazzCash',
                  ),
                  const SizedBox(width: 8),
                  _methodTab(
                    index: 2,
                    icon: Icons.phone_android_rounded,
                    label: 'EasyPaisa',
                  ),
                  const SizedBox(width: 8),
                  _methodTab(
                    index: 3,
                    icon: Icons.bolt_rounded,
                    label: 'Raast Pay',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Active payment input fields
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.bg3,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.border.withValues(alpha: 0.4)),
              ),
              child: _buildSelectedMethodBody(),
            ),
            const SizedBox(height: 18),

            // Security note
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, color: C.textMuted, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Simulated Sandbox • 100% Free Testing',
                  style: TextStyle(color: C.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Pay button
            ElevatedButton(
              onPressed: _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flash_on_rounded, size: 20, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(
                    'Pay ${widget.priceText} & Unlock PRO',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodTab({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedMethodIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedMethodIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? C.accent.withValues(alpha: 0.18) : C.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? C.accent : C.border.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? C.accent : C.textMuted, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? C.accent : C.textMuted,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedMethodBody() {
    switch (_selectedMethodIndex) {
      case 0:
        return _buildCardInput();
      case 1:
        return _buildJazzCashInput();
      case 2:
        return _buildEasyPaisaInput();
      case 3:
      default:
        return _buildRaastInput();
    }
  }

  Widget _buildCardInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CARD DETAILS',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            InkWell(
              onTap: () {
                _cardNumberController.text = '4242 4242 4242 4242';
                _cardExpiryController.text = '12/28';
                _cardCvvController.text = '888';
                _cardNameController.text = 'SmartSafe Pro Member';
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test card details filled!'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Text(
                'Autofill Test Card',
                style: TextStyle(
                  color: C.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _cardNumberController,
          label: 'Card Number',
          icon: Icons.credit_card,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: _cardExpiryController,
                label: 'Expiry (MM/YY)',
                icon: Icons.calendar_today_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _textField(
                controller: _cardCvvController,
                label: 'CVV',
                icon: Icons.lock_outline_rounded,
                isPassword: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _cardNameController,
          label: 'Cardholder Name',
          icon: Icons.person_outline_rounded,
        ),
      ],
    );
  }

  Widget _buildJazzCashInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'JAZZCASH MOBILE ACCOUNT',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            InkWell(
              onTap: () {
                _jazzPhoneController.text = '0300-1234567';
                _jazzPinController.text = '1234';
              },
              child: Text(
                'Autofill Demo Account',
                style: TextStyle(
                  color: C.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _jazzPhoneController,
          label: 'JazzCash Mobile Number (03XX-XXXXXXX)',
          icon: Icons.phone_iphone_rounded,
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _jazzPinController,
          label: '4-Digit MPIN',
          icon: Icons.pin_rounded,
          isPassword: true,
        ),
      ],
    );
  }

  Widget _buildEasyPaisaInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'EASYPAISA WALLET',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            InkWell(
              onTap: () {
                _easyPhoneController.text = '0345-9876543';
              },
              child: Text(
                'Autofill Demo Number',
                style: TextStyle(
                  color: C.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _easyPhoneController,
          label: 'EasyPaisa Mobile Number (03XX-XXXXXXX)',
          icon: Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(height: 6),
        Text(
          'A simulated instant approval prompt will be accepted automatically.',
          style: TextStyle(color: C.textMuted, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildRaastInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, color: C.accent, size: 22),
            const SizedBox(width: 8),
            Text(
              'Raast Instant Pay (P2M)',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '1-Tap direct test checkout. No credentials required in test mode.',
          style: TextStyle(color: C.textMuted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: TextStyle(color: C.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: C.textMuted, fontSize: 12),
          prefixIcon: Icon(icon, color: C.textMuted, size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

/// Simulated processing animation
class _PaymentProcessingDialog extends StatefulWidget {
  final String methodName;
  final String amount;

  const _PaymentProcessingDialog({
    required this.methodName,
    required this.amount,
  });

  @override
  State<_PaymentProcessingDialog> createState() =>
      _PaymentProcessingDialogState();
}

class _PaymentProcessingDialogState extends State<_PaymentProcessingDialog> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _step = 1);
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _step = 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    String stepLabel = 'Connecting to secure gateway...';
    if (_step == 1) stepLabel = 'Verifying credentials with ${widget.methodName.split(' ').first}...';
    if (_step == 2) stepLabel = 'Authorizing ${widget.amount} & unlocking PRO...';

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  color: C.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Processing Payment',
                style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  stepLabel,
                  key: ValueKey<int>(_step),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Celebration modal on unlock
class _PaymentSuccessDialog extends StatelessWidget {
  final String planName;
  final String methodName;

  const _PaymentSuccessDialog({
    required this.planName,
    required this.methodName,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [C.accent, C.success],
                ),
                boxShadow: [
                  BoxShadow(
                    color: C.accent.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.black, size: 38),
            ),
            const SizedBox(height: 18),
            Text(
              '🎉 Welcome to SmartSafe PRO!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your $planName has been activated successfully via $methodName.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.bg3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.accent.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  _benefitRow('Crash Detection & Auto-SOS'),
                  _benefitRow('Live Family Radar & History'),
                  _benefitRow('Danger Zone Pro Alerts'),
                  _benefitRow('Encrypted Evidence Cloud Locker'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Start Using PRO Features',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _benefitRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: C.success, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: C.textPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
