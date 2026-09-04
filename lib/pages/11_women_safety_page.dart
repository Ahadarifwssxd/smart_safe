import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../Dashboard/services/firebase_service.dart';
import '../models/app_structure.dart' show iconFromName;
import '../models/hand_signal.dart';
import '../models/women_safety_item.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../utils/emoji_icon.dart';
import '../widgets/widgets.dart';
import '../widgets/responsive.dart';

/// Dials a number directly (used by the tappable emergency helplines).
Future<void> _dial(String number) async {
  try {
    await FlutterPhoneDirectCaller.callNumber(number);
  } catch (_) {}
}

class WomenSafetyPage extends StatelessWidget {
  const WomenSafetyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
            child: SingleChildScrollView(
          padding: responsiveScrollPadding(context, horizontal: 20, vertical: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                if (Navigator.canPop(context)) ...[
                  GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: C.textPrimary, size: 18)),
                  const SizedBox(width: 12),
                ],
                DynText('women_safety', 'title', 'Women Safety',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ]),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: C.accent.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: C.accent.withValues(alpha: .4))),
                  child: DynText('women_safety', 'badge', 'GUIDE',
                      style: TextStyle(
                          color: C.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
            ]),

            const SizedBox(height: 6),
            DynText('women_safety', 'subtitle',
                'Know the signs, stay alert, stay safe',
                style: TextStyle(color: C.textMuted, fontSize: 12)),
            const SizedBox(height: 20),

            // Motivational hero — empowerment, not fear.
            const SlideUpFade(child: _MotivationHero()),
            const SizedBox(height: 20),

            // All admin-managed sections (helplines, warning signs, prevention,
            // self-defense, what-to-carry, worst-case steps) — live from
            // Firestore with a built-in offline fallback so it's never blank.
            const _DynamicSections(),
          ]),
        )),
      );
}

// ─────────── All Firestore-backed Women Safety sections (single stream) ──────
//
// Every section below is driven by [FirebaseService.getWomenSafetyStream],
// filtered by category in-memory and sorted by sortOrder, falling back to
// [defaultWomenSafetyItems] when there's no data / it's empty / on error — so
// the page renders identically offline. The hand-signals section keeps its own
// stream & state and is left untouched.
class _DynamicSections extends StatelessWidget {
  const _DynamicSections();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.getWomenSafetyStream(),
      builder: (context, snap) {
        List<WomenSafetyItem> all;
        if (snap.hasData) {
          final fromDocs = snap.data!.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .where((m) => m['active'] != false)
              .map(WomenSafetyItem.fromMap)
              .toList();
          // Dedupe against any duplicate seed copies in Firestore.
          final seen = <String>{};
          final unique = <WomenSafetyItem>[];
          for (final w in fromDocs) {
            if (seen.add('${w.category}|${w.title.trim().toLowerCase()}')) {
              unique.add(w);
            }
          }
          all = unique.isNotEmpty ? unique : defaultWomenSafetyItems;
        } else {
          all = defaultWomenSafetyItems;
        }

        List<WomenSafetyItem> byCat(String c) =>
            all.where((w) => w.category == c).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        final helplines = byCat(kWsHelpline);
        final warnings = byCat(kWsWarning);
        final prevention = byCat(kWsPrevention);
        final defense = byCat(kWsDefense);
        final carry = byCat(kWsCarry);
        final worst = byCat(kWsWorst);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tap-to-call emergency helplines (real calls).
            SlideUpFade(
                delay: const Duration(milliseconds: 40),
                child: _QuickHelplines(helplines: helplines)),
            const SizedBox(height: 24),

            // Live, admin-managed safety resources (fetched from Firestore).
            const SlideUpFade(
                delay: Duration(milliseconds: 60), child: _AdminSafetyTips()),

            // Hand signals (symbols) — moved up so they're seen first.
            const _HandSignalsSection(),
            const SizedBox(height: 24),

            // Warning Signs Section
            SlideUpFade(
                child: _CollapsibleSection(
                    title: 'Warning Signs — Trust Your Instincts',
                    icon: Icons.warning_amber_rounded,
                    initiallyOpen: true,
                    children: _warningCards(warnings))),

            const SizedBox(height: 24),

            // Prevention Tips
            SlideUpFade(
                delay: const Duration(milliseconds: 80),
                child: _CollapsibleSection(
                    title: 'Prevention — Before You Leave',
                    icon: Icons.shield_rounded,
                    children: _preventionCards(prevention))),

            const SizedBox(height: 24),

            // Self-Defense Basics
            SlideUpFade(
                delay: const Duration(milliseconds: 140),
                child: _CollapsibleSection(
                    title: 'Self-Defense Basics',
                    icon: Icons.sports_mma_rounded,
                    children: [_defenseCard(defense)])),

            const SizedBox(height: 24),

            // What to carry
            SlideUpFade(
                delay: const Duration(milliseconds: 200),
                child: _carrySection(carry)),

            const SizedBox(height: 24),

            // If worst happens
            SlideUpFade(
                delay: const Duration(milliseconds: 260),
                child: _CollapsibleSection(
                    title: 'If Worst Happens — Immediate Actions',
                    icon: Icons.emergency_rounded,
                    children: [_worstCard(worst)])),

            const SizedBox(height: 24),

            // Quick SOS reminder
            SlideUpFade(
                delay: const Duration(milliseconds: 320),
                child: DCard(
                    borderColor: C.accent,
                    child: Row(children: [
                      Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: C.accent),
                          child: Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 24)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('SmartSafe Silent SOS',
                                style: TextStyle(
                                    color: C.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                            Text(
                                'Shake phone 3× to alert all contacts without sound or screen. Attacker won\'t notice.',
                                style:
                                    TextStyle(color: C.textMuted, fontSize: 11)),
                          ])),
                    ]))),

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── Warning signs → _SignCard list ──
  List<Widget> _warningCards(List<WomenSafetyItem> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final w = items[i];
      out.add(_SignCard(
        color: Color(w.colorHex),
        title: w.title,
        signs: w.items,
        action: w.subtitle,
      ));
      if (i != items.length - 1) out.add(const SizedBox(height: 12));
    }
    return out;
  }

  // ── Prevention tips → _TipCard list ──
  List<Widget> _preventionCards(List<WomenSafetyItem> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final w = items[i];
      out.add(_TipCard(
        icon: iconFromName(w.iconName),
        color: Color(w.colorHex),
        title: w.title,
        tip: w.subtitle,
      ));
      if (i != items.length - 1) out.add(const SizedBox(height: 8));
    }
    return out;
  }

  // ── Self-defense → one DCard with the moves ("Target vulnerable spots"
  //    header and the "FIRE" tip stay static). ──
  Widget _defenseCard(List<WomenSafetyItem> items) {
    return DCard(
        borderColor: C.accent,
        child: Column(children: [
          Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: C.accent.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.back_hand_rounded, color: C.accent, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Target vulnerable spots',
                      style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('Eyes, nose, throat, groin — these hurt the most',
                      style: TextStyle(color: C.textMuted, fontSize: 11)),
                ])),
          ]),
          const SizedBox(height: 12),
          for (final w in items)
            _DefenseMove(move: w.title, detail: w.subtitle),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: C.accent.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.local_fire_department_rounded,
                  color: C.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Scream "FIRE!" not "HELP!" — People react faster to fire than someone in danger.',
                      style: TextStyle(
                          color: C.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ]));
  }

  // ── What to carry → SecHeader + 2-per-row grid of _CarryItem ──
  Widget _carrySection(List<WomenSafetyItem> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final first = items[i];
      final hasSecond = i + 1 < items.length;
      rows.add(Row(children: [
        Expanded(
            child: _CarryItem(
                emoji: first.emoji, item: first.title, detail: first.subtitle)),
        const SizedBox(width: 8),
        if (hasSecond)
          Expanded(
              child: _CarryItem(
                  emoji: items[i + 1].emoji,
                  item: items[i + 1].title,
                  detail: items[i + 1].subtitle))
        else
          const Expanded(child: SizedBox.shrink()),
      ]));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 8));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SecHeader('What to Carry', icon: Icons.backpack_rounded),
          const SizedBox(height: 4),
          ...rows,
        ]);
  }

  // ── If worst happens → one DCard with the steps (the Pakistan Helplines box
  //    stays static). ──
  Widget _worstCard(List<WomenSafetyItem> items) {
    return DCard(
        borderColor: C.accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DO THIS IMMEDIATELY:',
              style: TextStyle(
                  color: C.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final w in items) _Step(num: w.title, text: w.subtitle),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: C.accent.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pakistan Helplines',
                      style: TextStyle(
                          color: C.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('• Madadgar: 1099',
                      style: TextStyle(color: C.textMuted, fontSize: 11)),
                  Text('• Police Emergency: 15',
                      style: TextStyle(color: C.textMuted, fontSize: 11)),
                  Text('• Rozan Helpline: 0800-22444 (counseling)',
                      style: TextStyle(color: C.textMuted, fontSize: 11)),
                  Text('• Aurat Foundation: 042-111-002-882',
                      style: TextStyle(color: C.textMuted, fontSize: 11)),
                ]),
          ),
        ]));
  }
}

// ───────────────────────── Motivation hero ─────────────────────────

class _MotivationHero extends StatelessWidget {
  const _MotivationHero();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          // Deep, refined rose→crimson diagonal — warm and empowering.
          gradient: const LinearGradient(
            colors: [Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF4338CA)],
            stops: [0.0, 0.55, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.38),
                blurRadius: 30,
                offset: const Offset(0, 14)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Soft radial highlight top-right for a gentle sheen (no hard blobs).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(1.05, -1.0),
                      radius: 1.1,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Unique, procedurally-drawn "aurora silk" artwork — flowing
              // ribbon waves, a soft corner glow and scattered sparkles. Fully
              // offline, crisp at any size, and never needs the network.
              Positioned.fill(
                child: CustomPaint(painter: _HeroPatternPainter()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        // Clean glass badge with a crisp empowerment icon.
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.32),
                                Colors.white.withValues(alpha: 0.10),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.45),
                                width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: const Icon(Icons.shield_rounded,
                              color: Colors.white, size: 27),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: DynText('women_safety', 'heroTitle',
                              'You are stronger than you think',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  height: 1.22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 1)),
                                  ])),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      // Gradient accent divider under the title.
                      Container(
                        width: 52,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.white.withValues(alpha: 0.85),
                            Colors.white.withValues(alpha: 0.15),
                          ]),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DynText(
                        'women_safety',
                        'heroBody',
                        'Your safety is your right — not a favour. Trust your '
                            'instincts, stay aware, and remember: help is one tap '
                            'away. SmartSafe is with you, everywhere you go.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 12.5,
                            height: 1.55),
                      ),
                      const SizedBox(height: 16),
                      // Reassurance chip — grounded, calming call-out.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28)),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 15),
                          SizedBox(width: 6),
                          Text('Help is one tap away',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
              ),
            ],
          ),
        ),
      );
}

/// A unique, procedurally-generated "aurora silk" backdrop for the hero:
///   • three flowing ribbon waves (smooth cubic curves),
///   • two soft radial glows in opposite corners,
///   • a scatter of sparkle dots.
/// Fully offline and resolution-independent — no image asset or network.
class _HeroPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Soft corner glows (blurred blobs) ──────────────────────────────
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);
    canvas.drawCircle(Offset(w * 0.08, h * 0.98), 70,
        glow..color = Colors.white.withValues(alpha: 0.10));
    canvas.drawCircle(Offset(w * 0.96, h * 0.10), 60,
        glow..color = Colors.white.withValues(alpha: 0.12));

    // ── Flowing ribbon waves ───────────────────────────────────────────
    void wave(double yBase, double amp, double alpha, double stroke) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: alpha);
      final path = Path()..moveTo(-10, yBase);
      path.cubicTo(
        w * 0.28, yBase - amp,
        w * 0.42, yBase + amp,
        w * 0.62, yBase,
      );
      path.cubicTo(
        w * 0.80, yBase - amp,
        w * 0.92, yBase + amp * 0.6,
        w + 10, yBase - amp * 0.4,
      );
      canvas.drawPath(path, paint);
    }

    wave(h * 0.30, h * 0.16, 0.09, 2.2);
    wave(h * 0.52, h * 0.20, 0.06, 2.6);
    wave(h * 0.74, h * 0.15, 0.05, 2.0);

    // ── Sparkle dots (deterministic — no flicker between repaints) ──────
    const dots = <List<double>>[
      [0.80, 0.20, 2.4],
      [0.90, 0.36, 1.6],
      [0.72, 0.14, 1.4],
      [0.86, 0.58, 2.0],
      [0.63, 0.30, 1.5],
      [0.94, 0.70, 1.7],
      [0.55, 0.16, 1.2],
    ];
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.30);
    for (final d in dots) {
      canvas.drawCircle(Offset(w * d[0], h * d[1]), d[2], dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────── Tap-to-call emergency helplines ───────────────────

class _QuickHelplines extends StatelessWidget {
  final List<WomenSafetyItem> helplines;
  const _QuickHelplines({required this.helplines});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SecHeader('Emergency — Tap to Call', icon: Icons.call_rounded),
      const SizedBox(height: 4),
      Row(
        children: [
          for (final l in helplines)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => _dial(l.number.replaceAll(' ', '')),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: C.bg2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.accent.withValues(alpha: 0.4)),
                    ),
                    child: Column(children: [
                      Icon(iconForEmoji(l.emoji), color: C.accent, size: 24),
                      const SizedBox(height: 4),
                      Text(l.title,
                          style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l.number,
                            style: TextStyle(
                                color: C.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    ]);
  }
}

// ───────────── Admin-managed safety resources (live from Firestore) ─────────────

class _AdminSafetyTips extends StatelessWidget {
  const _AdminSafetyTips();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.getSafetyTipsStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs.where((d) {
          final m = d.data() as Map<String, dynamic>;
          return m['active'] != false;
        }).toList()
          ..sort((a, b) {
            final am = (a.data() as Map<String, dynamic>)['sortOrder'] ?? 0;
            final bm = (b.data() as Map<String, dynamic>)['sortOrder'] ?? 0;
            return (am as num).compareTo(bm as num);
          });
        if (docs.isEmpty) return const SizedBox.shrink();

        bool isWomen(DocumentSnapshot d) =>
            (d.data() as Map<String, dynamic>)['category']?.toString() ==
            'women';
        final womenDocs = docs.where(isWomen).toList();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (womenDocs.isNotEmpty) ...[
            const SecHeader('For Women — From SmartSafe',
                icon: Icons.diversity_1_rounded),
            const SizedBox(height: 4),
            ...womenDocs.map(_tipCard),
            const SizedBox(height: 20),
          ],
          // The general "SmartSafe Safety Resources" list was removed here — it
          // duplicated the Home screen's Safety Tips and made this page feel
          // text-heavy. Women-specific tips above are what belong on this page.
        ]);
      },
    );
  }

  Widget _tipCard(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    final emoji = m['emoji']?.toString() ?? '💡';
    final title = m['title']?.toString() ?? '';
    final body = m['body']?.toString() ?? '';
    final colorHex = m['colorHex'];
    final color = colorHex is int ? Color(colorHex) : C.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(iconForEmoji(emoji), color: C.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(color: C.textMuted, fontSize: 11)),
                  ],
                ]),
          ),
        ]),
      ),
    );
  }
}

/// Collapsible section — keeps all the guidance but hides it behind a tappable
/// header so the page isn't one overwhelming scroll.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;
  final bool initiallyOpen;
  const _CollapsibleSection({
    required this.title,
    this.icon,
    required this.children,
    this.initiallyOpen = false,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: SecHeader(widget.title, icon: widget.icon)),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded,
                      color: C.textMuted, size: 22),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const SizedBox(height: 8), ...widget.children],
          ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 240),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}

class _SignCard extends StatelessWidget {
  final Color color;
  final String title;
  final List<String> signs;
  final String action;
  const _SignCard(
      {required this.color,
      required this.title,
      required this.signs,
      required this.action});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          ...signs.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: .6))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(s,
                              style:
                                  TextStyle(color: C.textMuted, fontSize: 12))),
                    ]),
              )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_rounded, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(action,
                      style: TextStyle(
                          color: C.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ]),
      );
}

class _TipCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, tip;
  const _TipCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.tip});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: color, width: 3))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        color: C.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(tip, style: TextStyle(color: C.textMuted, fontSize: 11)),
              ])),
        ]),
      );
}

class _DefenseMove extends StatelessWidget {
  final String move, detail;
  const _DefenseMove({required this.move, required this.detail});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 50,
              child: Text(move, style: const TextStyle(fontSize: 16))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(detail,
                  style: TextStyle(color: C.textMuted, fontSize: 11))),
        ]),
      );
}

class _CarryItem extends StatelessWidget {
  final String emoji, item, detail;
  const _CarryItem(
      {required this.emoji, required this.item, required this.detail});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: C.bg2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.textPrimary.withValues(alpha: .06))),
        child: Column(children: [
          Icon(iconForEmoji(emoji), color: C.accent, size: 28),
          const SizedBox(height: 6),
          Text(item,
              style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          Text(detail, style: TextStyle(color: C.textMuted, fontSize: 10)),
        ]),
      );
}

class _Step extends StatelessWidget {
  final String num, text;
  const _Step({required this.num, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.accent),
            child: Center(
                child: Text(num,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(text, style: TextStyle(color: C.textMuted, fontSize: 12))),
        ]),
      );
}

// ───────────────────────── Hand Signals + Voice ─────────────────────────

class _HandSignalsSection extends StatefulWidget {
  const _HandSignalsSection();

  @override
  State<_HandSignalsSection> createState() => _HandSignalsSectionState();
}

class _HandSignalsSectionState extends State<_HandSignalsSection> {
  final FlutterTts _tts = FlutterTts();
  String _lang = 'en'; // 'en' | 'ur'
  int? _speakingIndex;
  int? _demoIndex; // which signal's in-app animated demo is open

  // Current signals rendered — live from Firestore, with the built-in
  // [defaultHandSignals] as the offline fallback. Cached here so TTS/demo
  // callbacks can look up a signal by index outside of build().
  List<HandSignal> _signals = defaultHandSignals;

  @override
  void initState() {
    super.initState();
    _tts.setVolume(1.0);
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingIndex = null);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(int i) async {
    if (i < 0 || i >= _signals.length) return;
    final s = _signals[i];
    final text = _lang == 'ur' ? s.speakUr : s.speakEn;
    try {
      await _tts.stop();
      await _tts.setLanguage(_lang == 'ur' ? 'ur-PK' : 'en-US');
      if (mounted) setState(() => _speakingIndex = i);
      await _tts.speak(text);
    } catch (e) {
      if (mounted) setState(() => _speakingIndex = null);
    }
  }

  /// Toggles the IN-APP animated demo for a signal (no YouTube). Opening it also
  /// plays the voice so the user sees the motion AND hears the guidance.
  void _toggleDemo(int i) {
    setState(() => _demoIndex = _demoIndex == i ? null : i);
    if (_demoIndex == i) _speak(i);
  }

  Widget _langChip(String code, String label) {
    final sel = _lang == code;
    return GestureDetector(
      onTap: () => setState(() => _lang = code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? C.accent : C.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? C.accent : C.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : C.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SlideUpFade(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                  child: SecHeader('Hand Signals for Help (Voice)',
                      icon: Icons.sign_language_rounded)),
              _langChip('en', 'EN'),
              const SizedBox(width: 6),
              _langChip('ur', 'اردو'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _lang == 'ur'
                ? 'کسی بھی اشارے پر ٹیپ کریں — آواز چلے گی (اردو/انگلش)۔'
                : 'Tap any signal — it speaks out loud (English / Urdu).',
            style: TextStyle(color: C.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.getHandSignalsStream(),
            builder: (context, snap) {
              List<HandSignal> signals;
              if (snap.hasData) {
                final fromDocs = snap.data!.docs
                    .map((d) => d.data() as Map<String, dynamic>)
                    .where((m) => m['active'] != false)
                    .map(HandSignal.fromMap)
                    .toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                // Dedupe: an early seed race left duplicate copies in Firestore,
                // which showed every signal 3×. Keep one of each unique signal.
                final seen = <String>{};
                final unique = <HandSignal>[];
                for (final s in fromDocs) {
                  if (seen.add('${s.titleEn.trim().toLowerCase()}|${s.emoji}')) {
                    unique.add(s);
                  }
                }
                signals = unique.isNotEmpty ? unique : defaultHandSignals;
              } else {
                signals = defaultHandSignals;
              }
              _signals = signals;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < signals.length; i++)
                    _signalCard(i, signals[i]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _signalCard(int i, HandSignal s) {
    final speaking = _speakingIndex == i;
    final demoOpen = _demoIndex == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _speak(i),
            child: DCard(
              borderColor: speaking ? C.accent : C.border,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconForEmoji(s.emoji), color: C.accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_lang == 'ur' ? s.titleUr : s.titleEn,
                            style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(_lang == 'ur' ? s.descUr : s.descEn,
                            style:
                                TextStyle(color: C.textMuted, fontSize: 11)),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _toggleDemo(i),
                          child:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                                demoOpen
                                    ? Icons.visibility_off_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: C.accent,
                                size: 16),
                            const SizedBox(width: 4),
                            Text(
                                demoOpen
                                    ? (_lang == 'ur'
                                        ? 'ڈیمو بند کریں'
                                        : 'Hide demo')
                                    : (_lang == 'ur'
                                        ? 'ڈیمو دیکھیں'
                                        : 'Show demo'),
                                style: TextStyle(
                                    color: C.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _speak(i),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            speaking ? C.accent : C.accent.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        speaking
                            ? Icons.volume_up_rounded
                            : Icons.play_arrow_rounded,
                        color: speaking ? Colors.white : C.accent,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (demoOpen)
            _GestureDemo(
              emoji: s.emoji,
              motion: s.motion,
              caption: _lang == 'ur' ? s.descUr : s.descEn,
              onReplay: () => _speak(i),
              replayLabel: _lang == 'ur' ? 'دوبارہ آواز ▶' : 'Replay voice ▶',
            ),
        ],
      ),
    );
  }
}

/// In-app animated demonstration of a hand signal — a little looping "video"
/// (no YouTube). The emoji performs a gesture-appropriate motion; pairs with
/// the TTS voice that plays when the demo opens.
class _GestureDemo extends StatefulWidget {
  final String emoji;
  final String motion; // 'push'|'fold'|'raise'|'count'|'call'|'wave'|'cross'
  final String caption;
  final VoidCallback onReplay;
  final String replayLabel;
  const _GestureDemo({
    required this.emoji,
    required this.motion,
    required this.caption,
    required this.onReplay,
    required this.replayLabel,
  });

  @override
  State<_GestureDemo> createState() => _GestureDemoState();
}

class _GestureDemoState extends State<_GestureDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Maps the motion type to a transform driven by the animation value t(0..1).
  /// Every motion is intentionally VISUALLY DISTINCT so no two demos look alike.
  Transform _animate(double t, Widget child) {
    switch (widget.motion) {
      case 'wave': // side-to-side wave (rocks left↔right)
        return Transform.rotate(angle: (t - 0.5) * 0.9, child: child);
      case 'push': // push forward (grows straight on)
        return Transform.scale(scale: 1.0 + t * 0.35, child: child);
      case 'raise': // raise straight up (pure vertical lift)
        return Transform.translate(offset: Offset(0, -t * 26), child: child);
      case 'count': // 4-fingers-up: lift up + tilt + grow (clearly ≠ raise)
        return Transform.translate(
          offset: Offset(t * 10, -t * 16),
          child: Transform.rotate(
            angle: t * 0.4,
            child: Transform.scale(scale: 1.0 + t * 0.18, child: child),
          ),
        );
      case 'cross': // rotate like crossing wrists
        return Transform.rotate(angle: t * 0.7 - 0.35, child: child);
      case 'call': // tilt like a phone to ear
        return Transform.rotate(angle: t * 0.5, child: child);
      case 'fold': // pulse/fold (shrinks in place)
      default:
        return Transform.scale(scale: 1.0 - t * 0.18, child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 96,
            child: Center(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => _animate(
                    _c.value,
                    Text(widget.emoji, style: const TextStyle(fontSize: 64)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.caption,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: C.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: widget.onReplay,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: C.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: C.accent.withValues(alpha: 0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.volume_up_rounded, color: C.accent, size: 15),
                const SizedBox(width: 6),
                Text(widget.replayLabel,
                    style: TextStyle(
                        color: C.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
