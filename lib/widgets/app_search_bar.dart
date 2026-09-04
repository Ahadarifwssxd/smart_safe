import 'package:flutter/material.dart';
import 'package:smartsafe/services/app_search_service.dart';
import 'package:smartsafe/theme/colors.dart';

/// Home screen search — features, contacts, SOS history, tips.
class AppSearchBar extends StatefulWidget {
  final VoidCallback? onSOSTap;

  const AppSearchBar({super.key, this.onSOSTap});

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  final _ctrl = TextEditingController();
  String _query = '';
  List<AppSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    // Warm the in-memory index so results are instant from the first keystroke.
    AppSearchService.instance.start();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final q = value.trim();
    // Filter synchronously in memory — instant, from the very first letter.
    setState(() {
      _query = q;
      _results =
          q.isEmpty ? const [] : AppSearchService.instance.searchSync(q);
    });
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _query = '';
      _results = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          style: TextStyle(color: C.textPrimary, fontSize: 14),
          onChanged: _onQueryChanged,
          onSubmitted: _onQueryChanged,
          decoration: InputDecoration(
            hintText: 'Search…',
            hintStyle: TextStyle(color: C.textMuted, fontSize: 13),
            filled: true,
            fillColor: C.bg2,
            prefixIcon: Icon(Icons.search_rounded, color: C.accent, size: 22),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded, color: C.textMuted, size: 20),
                    onPressed: _clear,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              borderSide: BorderSide(color: C.border.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              borderSide: BorderSide(color: C.accent.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              borderSide: BorderSide(color: C.accent.withValues(alpha: 0.6)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        if (_query.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No results for "$_query"',
                style: TextStyle(color: C.textMuted, fontSize: 13),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: C.bg2,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: C.border.withValues(alpha: 0.35)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: C.border.withValues(alpha: 0.2)),
                itemBuilder: (context, i) {
                  final r = _results[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.arrow_forward_ios_rounded,
                        color: C.accent, size: 14),
                    title: Text(
                      r.title,
                      style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                    subtitle: Text(
                      '${r.type} · ${r.subtitle}',
                      style: TextStyle(color: C.textMuted, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      _clear();
                      AppSearchService.openResult(
                        context,
                        r,
                        onSOSTap: widget.onSOSTap,
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}
