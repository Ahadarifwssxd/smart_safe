import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_firestore_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

// Persisted so an active check-in survives leaving the page or restarting the
// app — the timer resumes on reopen and fires the SOS if it expired meanwhile.
const _kCheckinDeadline = 'active_checkin_deadline_ms';
const _kCheckinMins = 'active_checkin_mins';
const _kCheckinDest = 'active_checkin_dest';

class SafeCheckInPage extends StatefulWidget {
  final VoidCallback onSOSTap;
  const SafeCheckInPage({super.key, required this.onSOSTap});
  @override State<SafeCheckInPage> createState() => _SafeCheckInPageState();
}

class _SafeCheckInPageState extends State<SafeCheckInPage> {
  bool _active = false;
  int _secsLeft = 0;
  int _selectedMins = 30;
  int _deadlineMs = 0;
  Timer? _t;
  final _options = [10, 15, 20, 30, 45, 60, 90, 120];
  final _destCtrl = TextEditingController();
  String _activeDest = '';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Resumes a check-in that is still running (survives leaving the page or
  /// restarting the app), or fires the SOS if it expired while we were away.
  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    final deadline = p.getInt(_kCheckinDeadline) ?? 0;
    if (deadline == 0) return;
    _selectedMins = p.getInt(_kCheckinMins) ?? _selectedMins;
    _activeDest = p.getString(_kCheckinDest) ?? '';
    final remaining = deadline - DateTime.now().millisecondsSinceEpoch;
    if (remaining > 0) {
      _deadlineMs = deadline;
      if (mounted) {
        setState(() {
          _active = true;
          _secsLeft = (remaining / 1000).ceil();
        });
      }
      _tick();
    } else {
      await _clearActive();
      AppFirestoreService.instance.recordCheckIn(
          mins: _selectedMins, status: 'expired', destination: _activeDest);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSOSTap();
        });
      }
    }
  }

  Future<void> _persistActive() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCheckinDeadline, _deadlineMs);
    await p.setInt(_kCheckinMins, _selectedMins);
    await p.setString(_kCheckinDest, _activeDest);
  }

  Future<void> _clearActive() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kCheckinDeadline);
    await p.remove(_kCheckinMins);
    await p.remove(_kCheckinDest);
  }

  void _start() {
    _deadlineMs =
        DateTime.now().millisecondsSinceEpoch + _selectedMins * 60 * 1000;
    setState(() {
      _active = true;
      _secsLeft = _selectedMins * 60;
      _activeDest = _destCtrl.text.trim();
    });
    _persistActive();
    _tick();
  }

  /// Ticks every second off the absolute deadline (not a plain counter), so the
  /// countdown stays accurate after resuming.
  void _tick() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining =
          ((_deadlineMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (remaining > 0) {
        setState(() => _secsLeft = remaining);
      } else {
        _t?.cancel();
        setState(() {
          _active = false;
          _secsLeft = 0;
        });
        _clearActive();
        // Timer expired → record it and fire the real SOS.
        AppFirestoreService.instance.recordCheckIn(
            mins: _selectedMins, status: 'expired', destination: _activeDest);
        widget.onSOSTap();
      }
    });
  }

  void _checkIn() {
    _t?.cancel();
    setState(() { _active = false; _secsLeft = 0; });
    _clearActive();
    AppFirestoreService.instance.recordCheckIn(
        mins: _selectedMins, status: 'safe', destination: _activeDest);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: C.success, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text('Checked in safely — recorded.', style: TextStyle(color: C.textPrimary))));
  }

  String get _display {
    final m = _secsLeft ~/ 60; final s = _secsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress => _active ? _secsLeft / (_selectedMins * 60) : 1.0;

  String _fmt(DateTime? t) {
    if (t == null) return 'Just now';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${months[t.month - 1]} ${t.day}, $h12:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  void dispose() { _t?.cancel(); _destCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (Navigator.canPop(context)) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
            ),
            const SizedBox(width: 12),
          ],
          DynText('safe_checkin', 'title', 'Safe Check-In', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        ]),
        const SizedBox(height: 4),
        Text('Auto SOS if you don\'t respond in time', style: TextStyle(color: C.textMuted, fontSize: 12)),
        const SizedBox(height: 24),

        // Timer display
        Center(child: SlideUpFade(child: Column(children: [
          SizedBox(width: 160, height: 160, child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 160, height: 160, child: CircularProgressIndicator(
              value: _progress, strokeWidth: 10,
              color: _active ? (_secsLeft < 60 ? C.red : C.accent) : C.textDim,
              backgroundColor: C.border)),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_active) ...[
                Text(_display, style: TextStyle(color: C.textPrimary, fontSize: 36, fontWeight: FontWeight.w800)),
                Text('remaining', style: TextStyle(color: C.textMuted, fontSize: 11)),
              ] else ...[
                Icon(Icons.check_circle_outline_rounded, color: C.accent, size: 48),
                const SizedBox(height: 4),
                Text('Set timer', style: TextStyle(color: C.textMuted, fontSize: 12)),
              ],
            ]),
          ])),
        ]))),

        const SizedBox(height: 24),

        if (!_active) ...[
          const SecHeader('Where are you going? (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _destCtrl,
            style: TextStyle(color: C.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'e.g. Mama\'s house, DHA',
              hintStyle: TextStyle(color: C.textMuted),
              prefixIcon: Icon(Icons.place_rounded, color: C.textMuted, size: 18),
            ),
          ),
          const SizedBox(height: 16),
          const SecHeader('Set arrival time'),
          Wrap(spacing: 8, runSpacing: 8, children: _options.map((m) {
            final sel = m == _selectedMins;
            return GestureDetector(onTap: () => setState(() => _selectedMins = m),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: sel ? C.accent : C.bg2, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? C.accent : C.textDim)),
                child: Text('$m min', style: TextStyle(color: sel ? Colors.white : C.textMuted, fontSize: 13,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.normal))));
          }).toList()),
          const SizedBox(height: 24),
          DCard(borderColor: C.warning, child: Row(children: [
            Icon(Icons.info_outline_rounded, color: C.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('If you don\'t press "I\'m Safe" before time runs out, SOS will be sent automatically to all contacts.',
              style: TextStyle(color: C.textMuted, fontSize: 11))),
          ])),
          const SizedBox(height: 16),
          BigBtn(label: 'Start $_selectedMins min Check-In', color: C.accent, icon: Icons.timer_rounded, onTap: _start),
        ],

        if (_active) ...[
          DCard(borderColor: _secsLeft < 60 ? C.red : C.accent, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_secsLeft < 60 ? 'Almost out of time!' : 'Timer running...', style: TextStyle(color: _secsLeft < 60 ? C.red : C.accent, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Press "I\'m Safe" when you arrive safely. SOS sends automatically if timer expires.',
              style: TextStyle(color: C.textMuted, fontSize: 11)),
          ])),
          const SizedBox(height: 16),
          BigBtn(label: 'I\'m Safe — Check In Now', icon: Icons.check_circle_rounded, color: C.success, onTap: _checkIn),
        ],

        const SizedBox(height: 24),

        // History — LIVE from Firestore
        const SecHeader('Check-in history'),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: AppFirestoreService.instance.watchMyCheckIns(),
          builder: (context, snap) {
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No check-ins yet — your records will appear here.',
                    style: TextStyle(color: C.textMuted, fontSize: 12)),
              );
            }
            return Column(children: items.map((h) {
              final isSafe = h['status'] == 'safe';
              final ts = (h['createdAt'] as Timestamp?)?.toDate();
              final dest = (h['destination'] ?? '').toString();
              return Padding(padding: const EdgeInsets.only(bottom: 8),
                child: DCard(child: Row(children: [
                  Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: isSafe ? C.success.withValues(alpha: .15) : C.warning.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(isSafe ? Icons.check_circle_rounded : Icons.timer_off_rounded,
                      color: isSafe ? C.success : C.warning, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dest.isEmpty ? 'Check-in' : dest, style: TextStyle(color: C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('${h['mins']} min · ${_fmt(ts)}', style: TextStyle(color: C.textMuted, fontSize: 11)),
                  ])),
                  StatusChip(label: isSafe ? 'Safe' : 'Expired', color: isSafe ? C.success : C.warning),
                ])));
            }).toList());
          },
        ),

        const SizedBox(height: 24),
      ]),
    )),
  );
}