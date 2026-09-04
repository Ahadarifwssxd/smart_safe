import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../Dashboard/services/firebase_service.dart';
import '../models/safety_guide.dart';
import '../theme/colors.dart';

/// Renders the admin-managed safety guides for one [category]
/// ('driving' | 'child' | 'first_aid'). Reads live from Firestore and falls
/// back to the built-in [defaultSafetyGuides] when the collection is empty or
/// offline before the first sync — so the page is never blank.
class SafetyGuidesView extends StatelessWidget {
  final String category;
  const SafetyGuidesView({super.key, required this.category});

  List<SafetyGuide> _fallback() =>
      defaultSafetyGuides.where((g) => g.category == category).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<SafetyGuide> _fromDocs(List<QueryDocumentSnapshot> docs) {
    final list = docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((m) => m['category'] == category && m['active'] != false)
        .map(SafetyGuide.fromMap)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.getSafetyGuidesStream(),
      builder: (context, snap) {
        List<SafetyGuide> guides;
        if (snap.hasData) {
          final fromDocs = _fromDocs(snap.data!.docs);
          guides = fromDocs.isNotEmpty ? fromDocs : _fallback();
        } else {
          guides = _fallback();
        }

        if (guides.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.bg2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border),
            ),
            child: Text('No guides yet. Check back soon.',
                style: TextStyle(color: C.textMuted, fontSize: 12)),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < guides.length; i++) ...[
              _GuideCard(guide: guides[i]),
              if (i != guides.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _GuideCard extends StatefulWidget {
  final SafetyGuide guide;
  const _GuideCard({required this.guide});

  @override
  State<_GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<_GuideCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.guide;
    final color = Color(g.colorHex);
    return Container(
      decoration: BoxDecoration(
        color: C.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: g.urgent ? color.withValues(alpha: 0.55) : C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(g.emoji, style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(g.title,
                                  style: TextStyle(
                                      color: C.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (g.urgent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('URGENT',
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ],
                        ),
                        if (g.detail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(g.detail,
                                style: TextStyle(
                                    color: C.textMuted, fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                  if (g.steps.isNotEmpty)
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: C.textMuted,
                    ),
                ],
              ),
            ),
          ),
          if (_open && g.steps.isNotEmpty) ...[
            Divider(color: C.border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < g.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(g.steps[i],
                                style: TextStyle(
                                    color: C.textPrimary,
                                    fontSize: 12.5,
                                    height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
