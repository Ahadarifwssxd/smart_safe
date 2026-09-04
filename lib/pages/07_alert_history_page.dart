import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../models/sos_history_entry.dart';
import '../services/app_firestore_service.dart';
import '../widgets/widgets.dart';

class AlertHistoryPage extends StatefulWidget {
  const AlertHistoryPage({super.key});

  @override
  State<AlertHistoryPage> createState() => _AlertHistoryPageState();
}

class _AlertHistoryPageState extends State<AlertHistoryPage> {
  final List<String> _filters = ['All', 'SOS', 'Crash', 'Safe'];
  int _selectedFilter = 0;

  /// Buckets an entry into a category for filtering + colour.
  String _cat(SosHistoryEntry e) {
    final a = '${e.alertType} ${e.source} ${e.status}'.toLowerCase();
    if (a.contains('crash')) return 'crash';
    if (a.contains('safe') || a.contains('cancel')) return 'safe';
    return 'sos';
  }

  Color _color(String cat) => cat == 'crash'
      ? C.red
      : cat == 'safe'
          ? AppColors.success
          : C.red;

  IconData _icon(String cat) => cat == 'crash'
      ? Icons.car_crash_rounded
      : cat == 'safe'
          ? Icons.check_circle_rounded
          : Icons.sos_rounded;

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: StreamBuilder<List<SosHistoryEntry>>(
              stream: AppFirestoreService.instance.watchMySosHistory(),
              builder: (context, snap) {
                final all = snap.data ?? [];
                final sosCnt = all.where((e) => _cat(e) == 'sos').length;
                final crashCnt = all.where((e) => _cat(e) == 'crash').length;
                final safeCnt = all.where((e) => _cat(e) == 'safe').length;
                final f = _filters[_selectedFilter].toLowerCase();
                final filtered = _selectedFilter == 0
                    ? all
                    : all.where((e) => _cat(e) == f).toList();
                return Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      responsiveHInset(context), 16, responsiveHInset(context), 8),
                  child: SlideUpFade(
                    child: Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back_ios_new_rounded, color: C.textPrimary, size: 18),
                          ),
                          const SizedBox(width: 12),
                        ],
                        DynText('alert_history', 'title', 'Alert History', style: TextStyle(color: C.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                      ],
                    ),
                  ),
                ),

                // Stats row
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: responsiveHInset(context)),
                  child: SlideUpFade(
                    delay: const Duration(milliseconds: 80),
                    child: Row(
                      children: [
                        _MiniStat('Total', '${all.length}',
                            C.textPrimary),
                        const SizedBox(width: 8),
                        _MiniStat('SOS', '$sosCnt', AppColors.accent),
                        const SizedBox(width: 8),
                        _MiniStat('Crash', '$crashCnt', C.red),
                        const SizedBox(width: 8),
                        _MiniStat('Safe', '$safeCnt', AppColors.success),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Filter chips
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: responsiveHInset(context)),
                  child: SlideUpFade(
                    delay: const Duration(milliseconds: 120),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filters.asMap().entries.map((e) {
                          final sel = e.key == _selectedFilter;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedFilter = e.key),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.accent.withValues(alpha: 0.15)
                                    : AppColors.bg2,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel
                                      ? AppColors.accent.withValues(alpha: 0.4)
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(e.value,
                                  style: TextStyle(
                                    color: sel
                                        ? AppColors.accent
                                        : AppColors.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_rounded,
                                  color: AppColors.textMuted, size: 48),
                              const SizedBox(height: 12),
                              Text('No alerts found',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          cacheExtent: 500,
                          padding: EdgeInsets.symmetric(
                              horizontal: responsiveHInset(context)),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final ev = filtered[i];
                            final cat = _cat(ev);
                            final col = _color(cat);
                            return SlideUpFade(
                              delay:
                                  Duration(milliseconds: 160 + i * 50),
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: DCard(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: col.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: col.withValues(alpha: 0.3)),
                                        ),
                                        child: Icon(_icon(cat),
                                            color: col, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(ev.alertType,
                                                      style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                                ),
                                                Text(_timeAgo(ev.createdAt),
                                                    style: TextStyle(
                                                        color:
                                                            AppColors.textMuted,
                                                        fontSize: 11)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                    Icons.location_on_rounded,
                                                    color: AppColors.textMuted,
                                                    size: 12),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                      ev.location.isNotEmpty ? ev.location : '${ev.formattedDate} · ${ev.formattedTime}',
                                                      style: TextStyle(
                                                          color: AppColors.textMuted,
                                                          fontSize: 11),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis),
                                                ),
                                              ],
                                            ),
                                            if (ev.status.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              StatusBadge(
                                                  label: ev.status,
                                                  color: col),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                )),
            Text(label,
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
