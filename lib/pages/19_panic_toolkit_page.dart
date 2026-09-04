import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/page_content_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show QuerySnapshot;
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../widgets/widgets.dart';
import '../models/app_structure.dart' show iconFromName;
import '../models/panic_tool.dart';
import '../Dashboard/services/firebase_service.dart';

class PanicToolkitPage extends StatefulWidget {
  final VoidCallback onSOSTap;
  const PanicToolkitPage({super.key, required this.onSOSTap});
  @override
  State<PanicToolkitPage> createState() => _PanicToolkitPageState();
}

class _PanicToolkitPageState extends State<PanicToolkitPage>
    with TickerProviderStateMixin {
  bool _flashOn = false;
  bool _sirenOn = false;
  bool _fakeCallActive = false;
  bool _timerRunning = false;
  int _timerSecs = 0;
  int _timerSet = 30;
  Timer? _timer;
  late AnimationController _sirenCtrl;

  // Audio players and sound selectors
  int _selectedSiren = 0;
  late AudioPlayer _sirenPlayer;
  late AudioPlayer _ringtonePlayer;

  // Fake call tracking
  bool _fakeCallAccepted = false;
  int _fakeCallDurationSecs = 0;
  Timer? _fakeCallTimer;
  Timer? _ringVibrateTimer; // iPhone-style buzz while the call rings

  final List<Map<String, String>> _sirens = [
    {
      'name': 'Police Siren',
      'asset': 'sounds/siren1.wav',
      'desc': 'Traditional police / ambulance wail'
    },
    {
      'name': 'Industrial Alarm',
      'asset': 'sounds/siren2.wav',
      'desc': 'Loud factory evacuation klaxon'
    },
    {
      'name': 'Loud Fire Bell',
      'asset': 'sounds/bell.wav',
      'desc': 'Continuous mechanical fire alarm bell'
    },
    {
      'name': 'High-Frequency Beeps',
      'asset': 'sounds/beep.wav',
      'desc': 'Fast, piercing emergency pulse'
    },
  ];

  @override
  void initState() {
    super.initState();
    _sirenCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _sirenPlayer = AudioPlayer();
    _ringtonePlayer = AudioPlayer();
    _configureLoudAudio();
  }

  /// Route audio through the ALARM stream at full volume so the siren and the
  /// call ringtone are LOUD — even on silent/vibrate, and over media volume.
  Future<void> _configureLoudAudio() async {
    try {
      final loudCtx = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      );
      await _sirenPlayer.setAudioContext(loudCtx);
      await _ringtonePlayer.setAudioContext(loudCtx);
      await _sirenPlayer.setVolume(1.0);
      await _ringtonePlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('Audio config error: $e');
    }
  }

  void _startRingVibration() {
    // iPhone-style: a strong buzz pattern repeated while the call rings.
    HapticFeedback.heavyImpact();
    _ringVibrateTimer?.cancel();
    _ringVibrateTimer =
        Timer.periodic(const Duration(milliseconds: 1400), (_) async {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 220));
      HapticFeedback.heavyImpact();
    });
  }

  void _stopRingVibration() {
    _ringVibrateTimer?.cancel();
    _ringVibrateTimer = null;
  }

  Future<void> _toggleFlash() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Flashlight control not supported on Web. Simulating flash on screen.'),
          backgroundColor: C.warning,
        ),
      );
      setState(() => _flashOn = !_flashOn);
      return;
    }
    try {
      final isAvailable = await TorchLight.isTorchAvailable();
      if (!isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Physical flashlight not available on this device.'),
            backgroundColor: C.accent,
          ),
        );
        setState(() => _flashOn = !_flashOn);
        return;
      }
      if (_flashOn) {
        await TorchLight.disableTorch();
        setState(() => _flashOn = false);
      } else {
        await TorchLight.enableTorch();
        setState(() => _flashOn = true);
      }
    } catch (e) {
      debugPrint('Flashlight error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Flashlight error: $e. Simulating in UI.'),
          backgroundColor: C.accent,
        ),
      );
      setState(() => _flashOn = !_flashOn);
    }
  }

  // Returns an AssetSource — works on both mobile and web, no internet needed
  Source _getAudioSource(String assetPath) {
    return AssetSource(assetPath);
  }

  Future<void> _toggleSiren() async {
    if (_sirenOn) {
      try {
        await _sirenPlayer.stop();
      } catch (e) {
        debugPrint('Error stopping siren: $e');
      }
      setState(() => _sirenOn = false);
    } else {
      setState(() => _sirenOn = true);
      try {
        await _sirenPlayer.setReleaseMode(ReleaseMode.loop);
        final source = _getAudioSource(_sirens[_selectedSiren]['asset']!);
        await _sirenPlayer.play(source);
      } catch (e) {
        debugPrint('Error playing siren: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Siren playback error: $e'), backgroundColor: C.accent),
        );
      }
    }
  }

  Future<void> _changeSiren(int index) async {
    setState(() {
      _selectedSiren = index;
    });
    if (_sirenOn) {
      try {
        await _sirenPlayer.stop();
        await _sirenPlayer.setReleaseMode(ReleaseMode.loop);
        final source = _getAudioSource(_sirens[index]['asset']!);
        await _sirenPlayer.play(source);
      } catch (e) {
        debugPrint('Error switching siren: $e');
      }
    }
  }

  Future<void> _startFakeCall() async {
    setState(() {
      _fakeCallActive = true;
      _fakeCallAccepted = false;
      _fakeCallDurationSecs = 0;
    });
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);
      final source = _getAudioSource('sounds/ringtone.wav');
      await _ringtonePlayer.play(source);
      _startRingVibration();
    } catch (e) {
      debugPrint('Error playing ringtone: $e');
    }
  }

  void _acceptFakeCall() {
    _ringtonePlayer.stop();
    _stopRingVibration();
    setState(() {
      _fakeCallAccepted = true;
      _fakeCallDurationSecs = 0;
    });
    _fakeCallTimer?.cancel();
    _fakeCallTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _fakeCallDurationSecs++;
      });
    });
  }

  void _endFakeCall() {
    _ringtonePlayer.stop();
    _stopRingVibration();
    _fakeCallTimer?.cancel();
    setState(() {
      _fakeCallActive = false;
      _fakeCallAccepted = false;
      _fakeCallDurationSecs = 0;
    });
  }

  String get _fakeCallDurationDisplay {
    final m = _fakeCallDurationSecs ~/ 60;
    final s = _fakeCallDurationSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _startTimer() {
    setState(() {
      _timerRunning = true;
      _timerSecs = _timerSet * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_timerSecs > 0) {
          _timerSecs--;
        } else {
          _timerRunning = false;
          _timer?.cancel();
          widget.onSOSTap();
        }
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _timerRunning = false;
      _timerSecs = 0;
    });
  }

  String get _timerDisplay {
    final m = _timerSecs ~/ 60;
    final s = _timerSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _sirenCtrl.dispose();
    _timer?.cancel();
    _fakeCallTimer?.cancel();
    _ringVibrateTimer?.cancel();
    _sirenPlayer.dispose();
    _ringtonePlayer.dispose();
    if (_flashOn && !kIsWeb) {
      TorchLight.disableTorch().catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: C.bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: responsiveScrollPadding(context, horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (Navigator.canPop(context)) ...[
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: C.textPrimary, size: 18),
                      ),
                      const SizedBox(width: 12),
                    ],
                    DynText('panic_toolkit', 'title', 'Panic Toolkit',
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Instant tools for dangerous situations',
                      style: TextStyle(color: C.textMuted, fontSize: 12)),
                  const SizedBox(height: 24),

                  // Simulation overlay helper for web flashlight
                  if (_flashOn && kIsWeb)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.8),
                            blurRadius: 20,
                            spreadRadius: 5,
                          )
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'SCREEN FLASHLIGHT SIMULATOR ON',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Grid of tools
                  GridView.count(
                    crossAxisCount:
                        MediaQuery.of(context).size.width < 600 ? 2 : 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.1,
                    children: [
                      // Flashlight
                      GestureDetector(
                        onTap: _toggleFlash,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                              color: _flashOn ? C.warning.withValues(alpha: .25) : C.bg2,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color:
                                      _flashOn ? C.warning.withValues(alpha: .6) : C.textDim,
                                  width: _flashOn ? 2 : 1)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.flashlight_on_rounded,
                                  color: _flashOn ? C.warning : C.textMuted,
                                  size: 44),
                              const SizedBox(height: 8),
                              Text('Flashlight',
                                  style: TextStyle(
                                      color: _flashOn ? C.warning : C.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  _flashOn
                                      ? 'ON — Tap to off'
                                      : 'Tap to turn on',
                                  style:
                                      TextStyle(color: C.textMuted, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),

                      // Siren
                      GestureDetector(
                        onTap: _toggleSiren,
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                          animation: _sirenCtrl,
                          builder: (_, child) => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                  color: _sirenOn
                                      ? Color.lerp(C.accent.withValues(alpha: .1),
                                          C.accent.withValues(alpha: .3), _sirenCtrl.value)
                                      : C.bg2,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: _sirenOn
                                          ? C.accent.withValues(alpha: .7)
                                          : C.textDim,
                                      width: _sirenOn ? 2 : 1)),
                              child: child!),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.campaign_rounded,
                                  color: _sirenOn ? C.accent : C.textMuted, size: 44),
                              const SizedBox(height: 8),
                              Text('Alarm Siren',
                                  style: TextStyle(
                                      color: _sirenOn ? C.accent : C.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  _sirenOn
                                      ? 'ACTIVE — Tap to stop'
                                      : 'Loud siren alarm',
                                  style:
                                      TextStyle(color: C.textMuted, fontSize: 10)),
                            ],
                          ),
                        ),
                        ),
                      ),

                      // Fake Call
                      GestureDetector(
                        onTap: _startFakeCall,
                        child: Container(
                          decoration: BoxDecoration(
                              color: C.bg2,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: _fakeCallActive
                                      ? C.success.withValues(alpha: .5)
                                      : C.textDim)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phone_in_talk_rounded,
                                  color: _fakeCallActive ? C.success : C.textMuted,
                                  size: 44),
                              const SizedBox(height: 8),
                              Text('Fake Call',
                                  style: TextStyle(
                                      color:
                                          _fakeCallActive ? C.success : C.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text('Trigger fake call screen',
                                  style:
                                      TextStyle(color: C.textMuted, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),

                      // SOS Shortcut
                      GestureDetector(
                        onTap: widget.onSOSTap,
                        child: Container(
                          decoration: BoxDecoration(
                              color: C.red.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: C.red.withValues(alpha: .6), width: 2)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: C.red, size: 44),
                              const SizedBox(height: 8),
                              Text('SOS Alert',
                                  style: TextStyle(
                                      color: C.red,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text('Alert all contacts now',
                                  style:
                                      TextStyle(color: C.textMuted, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Siren Sound Selector Configuration
                  const SecHeader('Siren Configuration', icon: Icons.campaign_rounded),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: C.bg2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.textDim),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: List.generate(_sirens.length, (index) {
                        final siren = _sirens[index];
                        final isSelected = _selectedSiren == index;
                        return InkWell(
                          onTap: () => _changeSiren(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: index < _sirens.length - 1
                                  ? Border(bottom: BorderSide(color: C.bg3))
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                  color: isSelected ? C.accent : C.textMuted,
                                  size: 20,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        siren['name']!,
                                        style: TextStyle(
                                          color: isSelected ? C.accent : C.textPrimary,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        siren['desc']!,
                                        style: TextStyle(color: C.textMuted, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected && _sirenOn)
                                  Icon(Icons.volume_up_rounded, color: C.accent, size: 18),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Distress timer
                  const SecHeader('Distress Timer — Auto SOS', icon: Icons.timer_rounded),
                  DCard(
                      borderColor: _timerRunning ? C.red : null,
                      child: Column(children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Auto-SOS timer',
                                        style: TextStyle(
                                            color: C.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        _timerRunning
                                            ? 'Sends SOS if you don\'t cancel'
                                            : 'Set minutes then start',
                                        style:
                                            TextStyle(color: C.textMuted, fontSize: 11)),
                                  ]),
                              if (_timerRunning)
                                Text(_timerDisplay,
                                    style: TextStyle(
                                        color: C.red,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800)),
                            ]),
                        if (!_timerRunning) ...[
                          const SizedBox(height: 12),
                          Row(
                              children: [15, 30, 45, 60].map((min) {
                            final sel = _timerSet == min;
                            return Expanded(
                                child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 3),
                                    child: GestureDetector(
                                        onTap: () => setState(() => _timerSet = min),
                                        child: AnimatedContainer(
                                            duration:
                                                const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                                color: sel ? C.red : C.bg3,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: sel ? C.red : C.textDim)),
                                            child: Text('${min}m',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: sel ? Colors.white : C.textMuted,
                                                    fontSize: 12,
                                                    fontWeight: sel
                                                        ? FontWeight.w700
                                                        : FontWeight.normal))))));
                          }).toList()),
                          const SizedBox(height: 12),
                          BigBtn(
                              label: 'Start $_timerSet min timer',
                              icon: Icons.play_arrow_rounded,
                              color: C.red,
                              onTap: _startTimer),
                        ],
                        if (_timerRunning) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: BigBtn(
                                    label: 'I\'m Safe — Cancel',
                                    icon: Icons.check_circle_rounded,
                                    color: C.success,
                                    onTap: _stopTimer)),
                          ]),
                        ],
                      ])),

                  // ── Firestore-backed informational guidance (admin-editable) ──
                  // Only the TEXT cards below are dynamic. Every interactive
                  // tool above (torch, siren, fake call, SOS, timer) stays wired.
                  _buildInfoTools(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),

        // FULL SCREEN FAKE CALL OVERLAY
        if (_fakeCallActive)
          Positioned.fill(
            child: Material(
              color: Colors.black,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black,
                        Colors.blueGrey.shade900.withValues(alpha: 0.8),
                        Colors.black,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top header & caller info
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        child: Column(
                          children: [
                            Text(
                              _fakeCallAccepted ? 'CONNECTED' : 'INCOMING CALL',
                              style: TextStyle(
                                color: _fakeCallAccepted ? C.success : C.textMuted,
                                letterSpacing: 3,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Papa',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _fakeCallAccepted ? _fakeCallDurationDisplay : 'Mobile +92 300 1234567',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Caller Avatar
                      const CircleAvatar(
                        radius: 64,
                        backgroundColor: Colors.white12,
                        child: Icon(Icons.person_rounded, size: 72, color: Colors.white60),
                      ),

                      // Bottom action controls
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
                        child: _fakeCallAccepted
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Grid of calling tools to make it look highly authentic
                                  GridView.count(
                                    crossAxisCount: 3,
                                    shrinkWrap: true,
                                    mainAxisSpacing: 20,
                                    crossAxisSpacing: 20,
                                    physics: const NeverScrollableScrollPhysics(),
                                    children: [
                                      _callOptionIcon(Icons.mic_off_rounded, 'mute'),
                                      _callOptionIcon(Icons.grid_3x3_rounded, 'keypad'),
                                      _callOptionIcon(Icons.volume_up_rounded, 'speaker'),
                                      _callOptionIcon(Icons.add_rounded, 'add call'),
                                      _callOptionIcon(Icons.videocam_rounded, 'FaceTime'),
                                      _callOptionIcon(Icons.contacts_rounded, 'contacts'),
                                    ],
                                  ),
                                  const SizedBox(height: 48),
                                  // Red Hang up Button
                                  GestureDetector(
                                    onTap: _endFakeCall,
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.redAccent,
                                      ),
                                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Decline
                                  Column(
                                    children: [
                                      GestureDetector(
                                        onTap: _endFakeCall,
                                        child: Container(
                                          width: 72,
                                          height: 72,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.redAccent,
                                          ),
                                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                    ],
                                  ),
                                  // Space
                                  const SizedBox(width: 40),
                                  // Accept
                                  Column(
                                    children: [
                                      GestureDetector(
                                        onTap: _acceptFakeCall,
                                        child: Container(
                                          width: 72,
                                          height: 72,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.green,
                                          ),
                                          child: const Icon(Icons.phone_rounded, color: Colors.white, size: 36),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text('Accept', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Informational guidance cards, driven by Firestore and grouped by category,
  /// falling back to [defaultPanicTools] when there's no data / empty / on error
  /// — so the page renders identically offline. Interactive tools are untouched.
  Widget _buildInfoTools() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.getPanicToolsStream(),
      builder: (context, snap) {
        List<PanicTool> all;
        if (snap.hasData) {
          final fromDocs = snap.data!.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .where((m) => m['active'] != false)
              .map(PanicTool.fromMap)
              .toList();
          all = fromDocs.isNotEmpty ? fromDocs : defaultPanicTools;
        } else {
          all = defaultPanicTools;
        }

        final sections = <Widget>[];

        void addGroup(String header, List<PanicTool> tools) {
          if (tools.isEmpty) return;
          tools.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          sections.add(const SizedBox(height: 24));
          sections.add(SecHeader(header));
          sections.addAll(tools.map(_infoCard));
        }

        for (final entry in kPanicToolCategories.entries) {
          // "What To Do Right Now" is intentionally hidden — the interactive
          // tools above already cover the immediate actions, so its text cards
          // were redundant clutter.
          if (entry.key == kPanicWhatToDo) continue;
          addGroup(entry.value,
              all.where((t) => t.category == entry.key).toList());
        }
        // Any items with an unknown category still show up under a generic head.
        final known = kPanicToolCategories.keys.toSet();
        addGroup('Safety Tips',
            all.where((t) => !known.contains(t.category)).toList());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sections,
        );
      },
    );
  }

  Widget _infoCard(PanicTool t) {
    final color = Color(t.colorHex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: t.emoji.isNotEmpty
                      ? Text(t.emoji, style: const TextStyle(fontSize: 20))
                      : Icon(iconFromName(t.iconName), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.title,
                      style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t.description,
                  style: TextStyle(
                      color: C.textMuted, fontSize: 12, height: 1.4)),
            ],
            if (t.steps.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...t.steps.map((s) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ',
                            style: TextStyle(
                                color: color,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        Expanded(
                          child: Text(s,
                              style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 12,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _callOptionIcon(IconData icon, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white30),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
