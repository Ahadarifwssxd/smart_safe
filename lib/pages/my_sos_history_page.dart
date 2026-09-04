import 'package:flutter/material.dart';
import '../models/sos_history_entry.dart';
import '../services/app_firestore_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

/// User's own SOS press history — count, date, time, search.
class MySosHistoryPage extends StatefulWidget {
  const MySosHistoryPage({super.key});

  @override
  State<MySosHistoryPage> createState() => _MySosHistoryPageState();
}

class _MySosHistoryPageState extends State<MySosHistoryPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SosHistoryEntry> _filter(List<SosHistoryEntry> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) {
      return e.source.toLowerCase().contains(q) ||
          e.location.toLowerCase().contains(q) ||
          e.alertType.toLowerCase().contains(q) ||
          e.formattedDate.toLowerCase().contains(q) ||
          e.formattedTime.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      if (Navigator.canPop(context))
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: C.textPrimary, size: 18),
                        ),
                      if (Navigator.canPop(context)) const SizedBox(width: 12),
                      DynText(
                        'my_sos_history',
                        'title',
                        'My SOS History',
                        style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: C.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search date, time, location…',
                      hintStyle: TextStyle(color: C.textMuted),
                      prefixIcon: Icon(Icons.search_rounded, color: C.textMuted),
                      filled: true,
                      fillColor: C.bg2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: C.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<SosHistoryEntry>>(
                  stream: AppFirestoreService.instance.watchMySosHistory(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Expanded(
                        child: Center(
                            child: CircularProgressIndicator(color: C.accent)),
                      );
                    }
                    final all = snapshot.data ?? [];
                    final filtered = _filter(all);

                    return Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                _StatChip(
                                  label: 'Total SOS',
                                  value: '${all.length}',
                                  color: C.accent,
                                ),
                                const SizedBox(width: 10),
                                _StatChip(
                                  label: 'Showing',
                                  value: '${filtered.length}',
                                  color: C.accent,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (all.isEmpty)
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sos_rounded,
                                        color: C.textMuted, size: 48),
                                    const SizedBox(height: 12),
                                    Text('No SOS alerts yet',
                                        style: TextStyle(
                                            color: C.textPrimary,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Home par SOS dabane par yahan history dikhegi',
                                      style: TextStyle(
                                          color: C.textMuted, fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (filtered.isEmpty)
                            Expanded(
                              child: Center(
                                  child: Text('No matches found',
                                      style: TextStyle(color: C.textMuted))),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                cacheExtent: 500,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: filtered.length,
                                itemBuilder: (context, i) {
                                  final e = filtered[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: DCard(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: C.accent.withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(Icons.sos_rounded,
                                                color: C.accent, size: 24),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.alertType,
                                                  style: TextStyle(
                                                    color: C.textPrimary,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${e.formattedDate} · ${e.formattedTime}',
                                                  style: TextStyle(
                                                      color: C.accentLight,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  e.location,
                                                  style: TextStyle(
                                                      color: C.textMuted,
                                                      fontSize: 11),
                                                ),
                                                Text(
                                                  'Source: ${e.source}',
                                                  style: TextStyle(
                                                      color: C.textMuted,
                                                      fontSize: 10),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: C.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
