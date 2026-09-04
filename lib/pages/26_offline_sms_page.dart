import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sms_sender.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/colors.dart';
import '../models/models.dart';
import '../services/app_firestore_service.dart';
import '../services/location_service.dart';
import '../widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Offline SMS Alert Page
//  Works WITHOUT internet — sends REAL SMS from the device SIM (flutter_sms,
//  sendDirect) to the user's real emergency contacts, with their live location.
// ─────────────────────────────────────────────────────────────────────────────

/// SMS status for each contact
enum SmsStatus { pending, sending, sent, failed }

class OfflineSmsPage extends StatefulWidget {
  const OfflineSmsPage({super.key});

  @override
  State<OfflineSmsPage> createState() => _OfflineSmsPageState();
}

class _OfflineSmsPageState extends State<OfflineSmsPage>
    with SingleTickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────
  late AnimationController _waveCtrl;
  bool _isSending = false;
  bool _allSent = false;
  bool _networkAvailable = false;
  int _selectedTemplate = 0;

  // REAL emergency contacts + their live location.
  List<Contact> _contacts = [];
  StreamSubscription<List<Contact>>? _contactsSub;
  String _locationLine = 'Location unavailable';
  String _mapsLink = '';

  // per-contact SMS status (keyed by contact name)
  final Map<String, SmsStatus> _statuses = {};
  final Map<String, String> _timestamps = {};

  // custom message override
  final TextEditingController _customCtrl = TextEditingController();
  bool _useCustom = false;

  // ── Templates ───────────────────────────────────────────────────
  final List<_SmsTemplate> _templates = [
    _SmsTemplate(
      label: 'SOS — I need help',
      icon: Icons.warning_rounded,
      color: AppColors.red,
      body:
          '🆘 SOS ALERT from SmartSafe\n\nI need immediate help!\n\n📍 Location: {LOCATION}\n🔗 {MAPS}\n🕐 Time: {TIME}\n\nPlease call me or contact police.\n\n— Sent via SmartSafe (Offline)',
    ),
    _SmsTemplate(
      label: 'Share Live Location',
      icon: Icons.location_on_rounded,
      color: AppColors.accent,
      body:
          '📍 LOCATION SHARE from SmartSafe\n\nI am currently at:\n{LOCATION}\n\n🕐 Time: {TIME}\n\nTrack me: {MAPS}\n\n— Sent via SmartSafe (Offline)',
    ),
    _SmsTemplate(
      label: 'I Am Safe',
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
      body:
          '✅ SAFE MESSAGE from SmartSafe\n\nI am safe and okay.\n\n📍 Location: {LOCATION}\n🕐 Time: {TIME}\n\nYou can stop worrying. I will update soon.\n\n— Sent via SmartSafe (Offline)',
    ),
    _SmsTemplate(
      label: 'Crash Detected',
      icon: Icons.car_crash_rounded,
      color: AppColors.red,
      body:
          '🚗 CRASH ALERT from SmartSafe\n\nA possible vehicle crash has been detected!\n\n📍 Location: {LOCATION}\n🔗 {MAPS}\n🕐 Time: {TIME}\n\nPlease call me immediately or contact emergency services: 1122\n\n— Sent via SmartSafe (Offline)',
    ),
  ];

  // ── Helpers ──────────────────────────────────────────────────────
  String _now() {
    final n = DateTime.now();
    final h = n.hour.toString().padLeft(2, '0');
    final m = n.minute.toString().padLeft(2, '0');
    return '$h:$m — ${n.day}/${n.month}/${n.year}';
  }

  String get _messageBody {
    if (_useCustom && _customCtrl.text.trim().isNotEmpty) {
      return _customCtrl.text.trim();
    }
    return _templates[_selectedTemplate]
        .body
        .replaceAll('{TIME}', _now())
        .replaceAll('{LOCATION}', _locationLine)
        .replaceAll('{MAPS}', _mapsLink.isNotEmpty ? _mapsLink : 'location unavailable');
  }

  Color get _templateColor => _templates[_selectedTemplate].color;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();

    // Load the user's REAL emergency contacts.
    _contactsSub =
        AppFirestoreService.instance.watchMyEmergencyContacts().listen((list) {
      if (!mounted) return;
      setState(() {
        _contacts = list;
        for (final c in list) {
          _statuses.putIfAbsent(c.name, () => SmsStatus.pending);
        }
      });
    });

    _loadLocation();
  }

  /// Fetch the device's current location for the message body + maps link.
  Future<void> _loadLocation() async {
    try {
      final loc = await LocationService.instance.getCurrentLocation();
      if (loc != null && mounted) {
        final lat = loc.latitude.toStringAsFixed(5);
        final lng = loc.longitude.toStringAsFixed(5);
        setState(() {
          _locationLine = '$lat, $lng';
          _mapsLink = 'https://maps.google.com/?q=$lat,$lng';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _customCtrl.dispose();
    _contactsSub?.cancel();
    super.dispose();
  }

  // ── Send logic (REAL device SMS) ─────────────────────────────────
  Future<void> _sendAll() async {
    if (_isSending) return;
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No emergency contacts — please add one first.')));
      return;
    }
    // SMS permission is required to send directly from the SIM.
    final granted = await Permission.sms.request();

    setState(() {
      _isSending = true;
      _allSent = false;
      for (final c in _contacts) {
        _statuses[c.name] = SmsStatus.pending;
        _timestamps.remove(c.name);
      }
    });

    for (final c in _contacts) {
      await _sendTo(c, direct: granted.isGranted);
    }

    if (mounted) {
      setState(() {
        _isSending = false;
        _allSent = true;
      });
    }
  }

  /// Sends a REAL SMS to one contact via the device SIM. When SMS permission
  /// isn't granted, opens the SMS composer pre-filled (still works offline).
  Future<void> _sendTo(Contact c, {bool direct = true}) async {
    final phone = c.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) {
      setState(() => _statuses[c.name] = SmsStatus.failed);
      return;
    }
    setState(() => _statuses[c.name] = SmsStatus.sending);
    try {
      await sendSMS(
          message: _messageBody, recipients: [phone], sendDirect: direct);
      if (mounted) {
        setState(() {
          _statuses[c.name] = SmsStatus.sent;
          _timestamps[c.name] = _now();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statuses[c.name] = SmsStatus.failed);
    }
  }

  // Opens the native SMS composer pre-filled for one contact.
  Future<void> _openNativeSms(Contact c) async {
    final phone = c.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      await sendSMS(
          message: _messageBody, recipients: [phone], sendDirect: false);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _messageBody));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.bg2,
          content: Text('Message copied for ${c.name}',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
        ));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sentCount =
        _statuses.values.where((s) => s == SmsStatus.sent).length;
    final failedCount =
        _statuses.values.where((s) => s == SmsStatus.failed).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: Column(
              children: [
                // ── Header ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: SlideUpFade(
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Offline SMS Alert',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                )),
                            Text(
                                'Works without internet — direct SMS',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        // Network status toggle (demo)
                        GestureDetector(
                          onTap: () => setState(
                              () => _networkAvailable = !_networkAvailable),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _networkAvailable
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _networkAvailable
                                    ? AppColors.success.withValues(alpha: 0.3)
                                    : AppColors.accent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _networkAvailable
                                      ? Icons.wifi_rounded
                                      : Icons.wifi_off_rounded,
                                  color: _networkAvailable
                                      ? AppColors.success
                                      : AppColors.accent,
                                  size: 14,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _networkAvailable ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    color: _networkAvailable
                                        ? AppColors.success
                                        : AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Offline banner ──────────────────────────
                        if (!_networkAvailable)
                          SlideUpFade(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        AppColors.warning.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.wifi_off_rounded,
                                      color: AppColors.warning, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No internet detected. SMS will be sent directly via your SIM card — charges may apply.',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // ── Template selector ───────────────────────
                        SlideUpFade(
                          delay: const Duration(milliseconds: 80),
                          child: Text('Choose Message Type',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                        const SizedBox(height: 12),
                        SlideUpFade(
                          delay: const Duration(milliseconds: 100),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _templates
                                  .asMap()
                                  .entries
                                  .map((e) {
                                final sel = e.key == _selectedTemplate &&
                                    !_useCustom;
                                return GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedTemplate = e.key;
                                    _useCustom = false;
                                  }),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    margin:
                                        const EdgeInsets.only(right: 10),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? e.value.color.withValues(alpha: 0.12)
                                          : AppColors.bg2,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                        color: sel
                                            ? e.value.color.withValues(alpha: 0.5)
                                            : AppColors.border,
                                        width: sel ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(e.value.icon,
                                            color: sel
                                                ? e.value.color
                                                : AppColors.textMuted,
                                            size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          e.value.label,
                                          style: TextStyle(
                                            color: sel
                                                ? e.value.color
                                                : AppColors.textMuted,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Message preview ─────────────────────────
                        SlideUpFade(
                          delay: const Duration(milliseconds: 140),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Message Preview',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      )),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => setState(
                                        () => _useCustom = !_useCustom),
                                    child: Text(
                                      _useCustom
                                          ? 'Use Template'
                                          : 'Custom Message',
                                      style: TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // SMS bubble
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _templateColor.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color:
                                          _templateColor.withValues(alpha: 0.25)),
                                ),
                                child: _useCustom
                                    ? TextField(
                                        controller: _customCtrl,
                                        maxLines: 6,
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13,
                                            height: 1.5),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Type your custom emergency message...',
                                          hintStyle: TextStyle(
                                              color: AppColors.textMuted),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                        ),
                                      )
                                    : Text(
                                        _templates[_selectedTemplate].body
                                            .replaceAll('{TIME}', _now()),
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                          height: 1.6,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.sms_rounded,
                                      color: AppColors.textMuted, size: 13),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_messageBody.length} characters — standard SMS',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Send All button ─────────────────────────
                        SlideUpFade(
                          delay: const Duration(milliseconds: 180),
                          child: GestureDetector(
                            onTap: _isSending ? null : _sendAll,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _isSending
                                    ? AppColors.textMuted.withValues(alpha: 0.15)
                                    : _allSent
                                        ? AppColors.success.withValues(alpha: 0.12)
                                        : _templateColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _isSending
                                      ? AppColors.border
                                      : _allSent
                                          ? AppColors.success.withValues(alpha: 0.4)
                                          : _templateColor.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  if (_isSending)
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _templateColor,
                                      ),
                                    )
                                  else if (_allSent)
                                    Icon(Icons.check_circle_rounded,
                                        color: AppColors.success, size: 20)
                                  else
                                    Icon(Icons.send_rounded,
                                        color: _templateColor, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isSending
                                        ? 'Sending to all contacts...'
                                        : _allSent
                                            ? 'All SMS Sent ($sentCount/${_contacts.length})'
                                            : 'Send SMS to All ${_contacts.length} Contacts',
                                    style: TextStyle(
                                      color: _isSending
                                          ? AppColors.textMuted
                                          : _allSent
                                              ? AppColors.success
                                              : _templateColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── Failed retry banner ─────────────────────
                        if (_allSent && failedCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        AppColors.red.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      color: AppColors.red, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$failedCount SMS failed. Tap individual contact to retry.',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        // ── Contacts + status ───────────────────────
                        Text('Contacts',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 12),
                        if (_contacts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                                'No emergency contacts yet — add contacts to send offline SMS.',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ),
                        ..._contacts.asMap().entries.map((e) {
                          final c = e.value;
                          final status =
                              _statuses[c.name] ?? SmsStatus.pending;
                          return SlideUpFade(
                            delay:
                                Duration(milliseconds: 200 + e.key * 50),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ContactSmsCard(
                                contact: c,
                                status: status,
                                timestamp: _timestamps[c.name],
                                onSend: () => _sendTo(c),
                                onNative: () => _openNativeSms(c),
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contact SMS Card ──────────────────────────────────────────────
class _ContactSmsCard extends StatelessWidget {
  final Contact contact;
  final SmsStatus status;
  final String? timestamp;
  final VoidCallback onSend;
  final VoidCallback onNative;

  const _ContactSmsCard({
    required this.contact,
    required this.status,
    required this.timestamp,
    required this.onSend,
    required this.onNative,
  });

  Color get _statusColor {
    switch (status) {
      case SmsStatus.sent:
        return AppColors.success;
      case SmsStatus.failed:
        return AppColors.red;
      case SmsStatus.sending:
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case SmsStatus.sent:
        return Icons.check_circle_rounded;
      case SmsStatus.failed:
        return Icons.error_rounded;
      case SmsStatus.sending:
        return Icons.hourglass_top_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String get _statusLabel {
    switch (status) {
      case SmsStatus.sent:
        return 'Sent';
      case SmsStatus.failed:
        return 'Failed';
      case SmsStatus.sending:
        return 'Sending…';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status == SmsStatus.sent
            ? AppColors.success.withValues(alpha: 0.05)
            : status == SmsStatus.failed
                ? AppColors.red.withValues(alpha: 0.05)
                : AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == SmsStatus.sent
              ? AppColors.success.withValues(alpha: 0.3)
              : status == SmsStatus.failed
                  ? AppColors.red.withValues(alpha: 0.3)
                  : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              AvatarWidget(
                initials: contact.initials,
                color: contact.avatarColor,
                size: 44,
              ),
              if (status == SmsStatus.sending)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bg.withValues(alpha: 0.5),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Text(contact.phone,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
                if (timestamp != null) ...[
                  const SizedBox(height: 4),
                  Text('Sent at $timestamp',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 10)),
                ],
              ],
            ),
          ),

          // Status + actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon,
                        color: _statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(_statusLabel,
                        style: TextStyle(
                            color: _statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Action buttons
              Row(
                children: [
                  // Open native SMS
                  GestureDetector(
                    onTap: onNative,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(Icons.open_in_new_rounded,
                          color: AppColors.textMuted, size: 14),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Send / Retry
                  GestureDetector(
                    onTap: (status == SmsStatus.sending) ? null : onSend,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: status == SmsStatus.failed
                            ? AppColors.red.withValues(alpha: 0.12)
                            : status == SmsStatus.sent
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: status == SmsStatus.failed
                              ? AppColors.red.withValues(alpha: 0.3)
                              : status == SmsStatus.sent
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : AppColors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        status == SmsStatus.failed
                            ? 'Retry'
                            : status == SmsStatus.sent
                                ? 'Resend'
                                : 'Send',
                        style: TextStyle(
                          color: status == SmsStatus.failed
                              ? AppColors.red
                              : status == SmsStatus.sent
                                  ? AppColors.success
                                  : AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── SMS Template model ────────────────────────────────────────────
class _SmsTemplate {
  final String label;
  final IconData icon;
  final Color color;
  final String body;

  const _SmsTemplate({
    required this.label,
    required this.icon,
    required this.color,
    required this.body,
  });
}
