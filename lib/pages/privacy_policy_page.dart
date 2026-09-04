import 'package:flutter/material.dart';
import '../config/app_content_defaults.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

/// Privacy Policy — fully dashboard-editable via the Page Content editor
/// (page key `privacy_policy`). Every heading/body reads live from Firestore
/// with the built-in text as the offline fallback.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const _page = 'privacy_policy';

  String _d(String field) => kPageContentDefaults[_page]?[field] ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          const DotGrid(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: C.textPrimary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      DynText(_page, 'title', 'Privacy Policy',
                          style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DynText(_page, 'updated', _d('updated'),
                            style: TextStyle(
                                color: C.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      for (var i = 1; i <= 8; i++)
                        _Section(
                            titlePage: _page,
                            titleField: 's${i}_title',
                            titleDefault: _d('s${i}_title'),
                            bodyField: 's${i}_body',
                            bodyDefault: _d('s${i}_body')),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: C.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: C.accent.withValues(alpha: 0.3)),
                        ),
                        child: DynText(_page, 'disclaimer', _d('disclaimer'),
                            style: TextStyle(
                                color: C.textMuted, fontSize: 12, height: 1.5)),
                      ),
                    ],
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

class _Section extends StatelessWidget {
  final String titlePage, titleField, titleDefault, bodyField, bodyDefault;
  const _Section({
    required this.titlePage,
    required this.titleField,
    required this.titleDefault,
    required this.bodyField,
    required this.bodyDefault,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DynText(titlePage, titleField, titleDefault,
                style: TextStyle(
                    color: C.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DynText(titlePage, bodyField, bodyDefault,
                style:
                    TextStyle(color: C.textMuted, fontSize: 13, height: 1.5)),
          ],
        ),
      );
}
