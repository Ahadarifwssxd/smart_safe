import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/widgets.dart';
import '../services/location_service.dart';
import '../services/sim_sos_service.dart';
import '../services/sos_recording_service.dart';
import '../services/whatsapp_service.dart';
import '10_add_contact_page.dart';

class AlertPage extends StatefulWidget {
  /// When set (e.g. '1122'), the SIM call goes to emergency services first.
  final String? emergencyNumber;

  /// How the alert was triggered: 'sos' (button), 'shake', or 'crash'.
  final String kind;
  const AlertPage({super.key, this.emergencyNumber, this.kind = 'sos'});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Timer _timer;
  int _seconds = 30;
  late AnimationController _arcCtrl;
  bool _isCancelling = false;
  SimSosResult? _result; // real dispatch outcome shown in the UI

  // WhatsApp auto-open: once the SIM call is placed the dialer takes over; when
  // the call ends the user returns to this page (lifecycle → resumed) and we
  // pop open WhatsApp for the primary contact with the message pre-typed — they
  // just tap Send. Fires once.
  bool _readyForWhatsApp = false;
  bool _whatsappAutoOpened = false;

  final List<_Step> _steps = [
    _Step(Icons.location_on_rounded, 'GPS Location Acquired', AppColors.red, true),
    _Step(Icons.people_rounded, 'Notifying contacts…', AppColors.red, false),
    _Step(Icons.phone_rounded, 'Calling first contact', AppColors.red, false),
    _Step(Icons.message_rounded, 'App alert · SMS · WhatsApp', AppColors.red, false),
  ];

  @override
  void initState() {
    super.initState();
    // Double heavy buzz as the emergency screen appears — reinforces that help
    // is being dispatched, even without looking at the screen.
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 220), HapticFeedback.heavyImpact);
    WidgetsBinding.instance.addObserver(this);
    _arcCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 30))
          ..forward();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_seconds > 0) _seconds--;
      });
    });

    // Real SOS dispatch: SIM call + SMS + WhatsApp + Email + self notification.
    _dispatchSos();

    // Shake SOS: after the call is placed the app returns here — quietly capture
    // 30 seconds of audio as automatic evidence of what's happening. Best-effort
    // (never blocks the SOS), so a denied mic permission simply skips it.
    if (widget.emergencyNumber == null && widget.kind == 'shake') {
      SosRecordingService.instance.startEmergencyRecording(
        seconds: 30,
        note: 'Shake SOS auto-recording',
      );
    }
  }

  Future<void> _dispatchSos() async {
    final emergency = widget.emergencyNumber;
    // A preset emergency number (e.g. 1122) means this came from crash detection.
    final result = await SimSosService.instance.triggerSos(
      emergencyNumber: emergency,
      kind: emergency != null ? 'crash' : widget.kind,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _steps[1] = _steps[1].copyWith(done: true, label: result.hasError
          ? 'No contacts found'
          : 'Notified contacts');
      _steps[2] = _steps[2].copyWith(
          done: result.callsMade > 0,
          label: emergency != null
              ? (result.callsMade > 0
                  ? 'Emergency call placed ($emergency)'
                  : 'Calling $emergency…')
              : (result.callsMade > 0 ? 'Call placed' : 'Calling first contact'));
      _steps[3] = _steps[3].copyWith(
          done: true,
          label:
              'App ${result.appAlertsSent} · SMS ${result.smsSent} · WhatsApp ${result.whatsappSent}');
    });
    _showTopToast(
      result.summaryMessage,
      result.hasError ? C.red : C.success,
    );

    // Arm WhatsApp auto-open only if a call actually went out and there's a
    // contact to message. It pops up when the call ends (app resumes).
    if (!result.hasError &&
        result.whatsappTargets.isNotEmpty &&
        result.callsMade > 0) {
      _readyForWhatsApp = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App came back to the foreground — most likely the SIM call just ended.
    // Open WhatsApp once with the SOS message pre-filled for the primary
    // contact; the user only has to tap Send.
    if (state == AppLifecycleState.resumed &&
        _readyForWhatsApp &&
        !_whatsappAutoOpened &&
        !_isCancelling) {
      final r = _result;
      if (r == null || r.whatsappTargets.isEmpty) return;
      _whatsappAutoOpened = true;
      final target = r.whatsappTargets.first;
      // Small delay so the app is fully resumed before launching WhatsApp.
      Future.delayed(const Duration(milliseconds: 400), () {
        WhatsAppService.instance.openChat(target.phone, r.messageBody);
      });
    }
  }

  /// Shows the dispatch result as a banner at the TOP (not bottom) so it never
  /// covers the SOS controls. Slides in, holds, then slides out.
  void _showTopToast(String message, Color color) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 10,
        left: 16,
        right: 16,
        child: _AlertTopToast(
          message: message,
          color: color,
          onDone: () => entry.remove(),
        ),
      ),
    );
    overlay.insert(entry);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _arcCtrl.dispose();
    // If a shake recording is still running when the user leaves, stop it and
    // upload whatever was captured so no evidence is lost.
    SosRecordingService.instance.stopAndUpload(note: 'Shake SOS auto-recording');
    super.dispose();
  }

  /// Shows exactly what happened: dispatching, no-contacts (with a fix button),
  /// or the real per-channel counts. No guessing for the user.
  Widget _buildResultPanel() {
    final r = _result;

    if (r == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: DesignTokens.space16),
        child: GlassCard(
          child: Row(
            children: [
              const SmartSafeLoader(dotSize: 5),
              const SizedBox(width: DesignTokens.space16),
              Expanded(
                child: Text('Sending alerts to your contacts…',
                    style: DesignTokens.body.copyWith(color: C.textPrimary)),
              ),
            ],
          ),
        ),
      );
    }

    // No contacts → big, actionable message.
    if (r.hasError) {
      return Padding(
        padding: const EdgeInsets.only(bottom: DesignTokens.space16),
        child: GlassCard(
          borderColor: AppColors.red.withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: AppColors.red, size: 22),
                  const SizedBox(width: DesignTokens.space12),
                  Expanded(
                    child: Text(
                      'No emergency contacts in this account',
                      style: DesignTokens.bodyStrong.copyWith(color: C.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space8),
              Text(
                'Add at least one family/friend with their phone & email, '
                'then SOS will call, SMS, WhatsApp and email them automatically. '
                'Contacts are per-account, so add them while signed in to THIS account.',
                style: DesignTokens.caption.copyWith(color: C.textMuted),
              ),
              const SizedBox(height: DesignTokens.space16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddContactPage()),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  label: const Text('Add Emergency Contact',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Success → real per-channel counts.
    Widget chip(IconData icon, String label, int n) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: (n > 0 ? AppColors.success : C.textMuted)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16, color: n > 0 ? AppColors.success : C.textMuted),
              const SizedBox(width: 6),
              Text('$label $n',
                  style: DesignTokens.caption.copyWith(
                      color: n > 0 ? C.textPrimary : C.textMuted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space16),
      child: GlassCard(
        borderColor: AppColors.success.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 22),
                const SizedBox(width: DesignTokens.space12),
                Text('Alerts dispatched',
                    style: DesignTokens.bodyStrong.copyWith(color: C.textPrimary)),
              ],
            ),
            const SizedBox(height: DesignTokens.space12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(Icons.notifications_active_rounded, 'App', r.appAlertsSent),
                chip(Icons.phone_rounded, 'Call', r.callsMade),
                chip(Icons.sms_rounded, 'SMS', r.smsSent),
                chip(Icons.chat_rounded, 'WhatsApp', r.whatsappSent),
              ],
            ),
            // Free WhatsApp: one tap per contact opens their chat with the SOS
            // message pre-filled — the user just presses Send.
            if (r.whatsappTargets.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.space16),
              Row(
                children: [
                  const Icon(Icons.chat_rounded,
                      color: Color(0xFF25D366), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Send on WhatsApp — tap a contact, then press Send',
                      style: DesignTokens.caption.copyWith(color: C.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space8),
              ...r.whatsappTargets.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => WhatsAppService.instance
                          .openChat(t.phone, r.messageBody),
                      icon: const Icon(Icons.chat_rounded,
                          size: 18, color: Color(0xFF25D366)),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'WhatsApp ${t.name}',
                          style: DesignTokens.body
                              .copyWith(color: C.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        side: const BorderSide(color: Color(0xFF25D366)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancelAlert() async {
    if (_isCancelling) return;
    HapticFeedback.heavyImpact();
    setState(() => _isCancelling = true);

    // Tell every contact it was a false alarm in the BACKGROUND. We must NOT
    // await it here — notifying all contacts (SMS + WhatsApp + Email) can take
    // many seconds, and awaiting it left the user stuck on the "SOS CANCELLED"
    // screen. Fire-and-forget so the screen always returns to the app.
    SimSosService.instance.cancelSos().then((result) {
      if (mounted && !result.hasError) {
        _showTopToast(result.summaryMessage, C.success);
      }
    });

    // Show the "marked safe" confirmation briefly, then ALWAYS return.
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isCancelling) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) => Transform.scale(
              scale: value,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(DesignTokens.space24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.success.withValues(alpha: 0.2),
                      boxShadow: AppTheme.glowShadow(C.success, blur: 40),
                    ),
                    child: Icon(Icons.check_rounded, color: C.success, size: 64),
                  ),
                  const SizedBox(height: DesignTokens.space24),
                  Text(
                    'SOS CANCELLED',
                    style: DesignTokens.h1.copyWith(color: C.success, letterSpacing: 2),
                  ),
                  const SizedBox(height: DesignTokens.space8),
                  Text(
                    'You are marked as safe.',
                    style: DesignTokens.body.copyWith(color: C.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Header
                  SlideUpFade(
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space12, vertical: DesignTokens.space12),
                      borderColor: AppColors.red.withValues(alpha: 0.4),
                      child: Row(
                        children: [
                          Tooltip(
                            message: 'Cancel SOS',
                            child: GestureDetector(
                              onTap: _cancelAlert,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.bg3,
                                  borderRadius: DesignTokens.borderRadius8,
                                  border: Border.all(color: AppColors.border),
                                ),
                                // Explicit close/cancel affordance — a back-arrow
                                // here reads as "navigate back", not "abort the
                                // live emergency". This removes that ambiguity.
                                child: Icon(Icons.close_rounded,
                                    color: C.textPrimary, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.space16),
                          Text('SOS ACTIVE',
                              style: DesignTokens.h2.copyWith(
                                color: AppColors.red,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              )),
                          const Spacer(),
                          BlinkDot(color: AppColors.red, size: 12),
                          const SizedBox(width: 6),
                          Text('LIVE',
                              style: DesignTokens.label.copyWith(
                                  color: AppColors.red,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space32),

                  // Pulse rings + countdown arc
                  SlideUpFade(
                    delay: const Duration(milliseconds: 100),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PulseRing(color: AppColors.red, size: 140),
                          // Arc
                          SizedBox(
                            width: 170,
                            height: 170,
                            child: AnimatedBuilder(
                              animation: _arcCtrl,
                              builder: (_, __) {
                                return CustomPaint(
                                  painter: _ArcPainter(
                                      1 - (_seconds / 30).clamp(0, 1)),
                                );
                              },
                            ),
                          ),
                          // SOS circle
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.sosGradient,
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.red.withValues(alpha: 0.5),
                                    blurRadius: 30,
                                    spreadRadius: 5),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_rounded, color: Colors.white, size: 32),
                                const SizedBox(height: 4),
                                Text(
                                  '$_seconds',
                                  style: DesignTokens.display.copyWith(
                                    color: Colors.white,
                                    fontSize: 32,
                                  ),
                                ),
                                Text('SEC',
                                    style: DesignTokens.label.copyWith(
                                        color: Colors.white70,
                                        letterSpacing: 1.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space16),
                  SlideUpFade(
                    delay: const Duration(milliseconds: 150),
                    child: Text('ALERT DISPATCHED',
                        style: DesignTokens.h3.copyWith(
                          color: AppColors.red,
                          letterSpacing: 2,
                        )),
                  ),
                  const SizedBox(height: DesignTokens.space32),

                  // GPS Broadcasting bar
                  SlideUpFade(
                    delay: const Duration(milliseconds: 200),
                    child: GlassCard(
                      borderColor: AppColors.border,
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.12),
                              borderRadius: DesignTokens.borderRadius12,
                            ),
                            child: Icon(Icons.location_on_rounded,
                                color: AppColors.red, size: 24),
                          ),
                          const SizedBox(width: DesignTokens.space16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('GPS Broadcasting',
                                    style: DesignTokens.bodyStrong.copyWith(color: C.textPrimary)),
                                const SizedBox(height: 4),
                                StreamBuilder<LocationData>(
                                  stream: LocationService.instance.onLocationChanged,
                                  builder: (context, snapshot) {
                                    final locStr = snapshot.hasData 
                                        ? '${snapshot.data!.latitude.toStringAsFixed(4)}, ${snapshot.data!.longitude.toStringAsFixed(4)}'
                                        : 'Acquiring high accuracy lock...';
                                    return Text(locStr,
                                        style: DesignTokens.caption.copyWith(
                                            color: AppColors.redLight));
                                  }
                                ),
                              ],
                            ),
                          ),
                          WaveBars(color: AppColors.redLight),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space24),

                  // Real dispatch result — clear feedback for the user
                  _buildResultPanel(),

                  // Steps checklist
                  SlideUpFade(
                    delay: const Duration(milliseconds: 250),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Command Center Log', style: DesignTokens.h3.copyWith(color: C.textPrimary)),
                          const SizedBox(height: DesignTokens.space16),
                          ..._steps.asMap().entries.map((e) => _StepRow(
                                step: e.value,
                                index: e.key + 1,
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space32),

                  // Cancel button
                  SlideUpFade(
                    delay: const Duration(milliseconds: 350),
                    child: AnimatedButton(
                      onTap: _cancelAlert,
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: DesignTokens.space16),
                        borderColor: AppColors.success.withValues(alpha: 0.5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                color: AppColors.success, size: 24),
                            const SizedBox(width: DesignTokens.space12),
                            Text(
                              'I AM SAFE — Cancel Alert',
                              style: DesignTokens.bodyStrong.copyWith(
                                color: AppColors.success,
                                fontSize: 15,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final String label;
  final Color color;
  final bool done;

  _Step(this.icon, this.label, this.color, this.done);

  _Step copyWith({bool? done, String? label}) =>
      _Step(icon, label ?? this.label, color, done ?? this.done);
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final int index;

  const _StepRow({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: step.done ? step.color.withValues(alpha: 0.15) : AppColors.bg3,
              borderRadius: DesignTokens.borderRadius8,
              border: Border.all(
                  color: step.done
                      ? step.color.withValues(alpha: 0.4)
                      : AppColors.border),
            ),
            child: Icon(
              step.done ? Icons.check_rounded : step.icon,
              color: step.done ? step.color : AppColors.textMuted,
              size: 18,
            ),
          ),
          const SizedBox(width: DesignTokens.space16),
          Text(
            step.label,
            style: DesignTokens.body.copyWith(
              color: step.done ? C.textPrimary : AppColors.textMuted,
              fontWeight: step.done ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          const Spacer(),
          if (step.done)
            AnimatedScale(
              scale: 1.0,
              duration: DesignTokens.durationNormal,
              child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
            )
          else if (!step.done && index == 3) // Example of a processing indicator for next step
             const SmartSafeLoader(dotSize: 4),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;

  const _ArcPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final bg = Paint()
      ..color = AppColors.border
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);

    final arc = Paint()
      ..color = AppColors.red
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.progress != progress;
}

/// Top banner toast for the SOS result — slides+fades in, holds, then leaves.
class _AlertTopToast extends StatefulWidget {
  final String message;
  final Color color;
  final VoidCallback onDone;
  const _AlertTopToast({
    required this.message,
    required this.color,
    required this.onDone,
  });

  @override
  State<_AlertTopToast> createState() => _AlertTopToastState();
}

class _AlertTopToastState extends State<_AlertTopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero)
        .animate(_fade);
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
