import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/config/app_content_defaults.dart';
import 'package:smartsafe/services/page_content_service.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/utils/error_message.dart';

/// Admin editor for every page's headings / subtitles / hero copy / buttons.
///
/// Reads the field list straight from [kPageContentDefaults] so any page added
/// to that one file automatically appears here — nothing else to wire up. Edits
/// are written to the `page_content` collection and go live in the app instantly
/// through [PageContentService] / DynText.
class PageContentScreen extends StatelessWidget {
  const PageContentScreen({super.key});

  static String _pretty(String key) {
    final s = key.replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final pages = kPageContentKeys;
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(defaultPadding),
            child: Header(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: defaultPadding),
            child: PageHeaderBar(
              icon: Icons.edit_note_rounded,
              title: 'Page Content',
              subtitle:
                  'Har page ki headings, subtitles aur hero text yahan se edit karein '
                  '— app me foran live ho jayega.',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedBuilder(
              animation: PageContentService.instance,
              builder: (context, _) => ListView.builder(
                cacheExtent: 600,
                padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
                itemCount: pages.length,
                itemBuilder: (context, i) {
                  final page = pages[i];
                  final fields = PageContentService.instance.fieldsFor(page);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: secondaryColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.border),
                    ),
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        iconColor: C.accent,
                        collapsedIconColor: C.textMuted,
                        title: Text(
                          _pretty(page),
                          style: TextStyle(
                              color: C.textPrimary,
                              fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${fields.length} fields',
                          style: TextStyle(color: C.textMuted, fontSize: 12),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          _PageEditor(page: page, fields: fields),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageEditor extends StatefulWidget {
  final String page;
  final Map<String, String> fields;
  const _PageEditor({required this.page, required this.fields});

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  late Map<String, TextEditingController> _ctrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final e in widget.fields.entries)
        e.key: TextEditingController(text: e.value),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = {for (final e in _ctrls.entries) e.key: e.value.text};
      await PageContentService.instance.updatePage(widget.page, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved — live in the app now')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    try {
      await PageContentService.instance.resetPage(widget.page);
      final defaults = kPageContentDefaults[widget.page] ?? {};
      for (final e in defaults.entries) {
        _ctrls[e.key]?.text = e.value;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in _ctrls.keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _ctrls[key],
              style: TextStyle(color: C.textPrimary),
              maxLines: null,
              decoration: InputDecoration(
                labelText: key,
                labelStyle: TextStyle(color: C.textMuted),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: C.border),
                ),
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: C.accent),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
            TextButton.icon(
              onPressed: _saving ? null : _reset,
              icon: Icon(Icons.restore, size: 18, color: C.textMuted),
              label: Text('Reset to default',
                  style: TextStyle(color: C.textMuted)),
            ),
          ],
        ),
      ],
    );
  }
}
