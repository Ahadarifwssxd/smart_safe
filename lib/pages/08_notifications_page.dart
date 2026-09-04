import 'package:flutter/material.dart';
import '../services/app_firestore_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _markingAll = false;

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await AppFirestoreService.instance.markAllNotificationsRead();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _markRead(AppNotif notif) async {
    if (notif.isRead || notif.id == null) return;
    await AppFirestoreService.instance.markNotificationRead(notif.id!);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotif>>(
      stream: AppFirestoreService.instance.watchMyNotifications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(child: CircularProgressIndicator(color: C.accent)),
          );
        }

        final notifs = snapshot.data ?? [];
        final unreadCount = notifs.where((n) => !n.isRead).length;
        final newNotifs = notifs.where((n) => !n.isRead).toList();
        final oldNotifs = notifs.where((n) => n.isRead).toList();

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Stack(
            children: [
              RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          responsiveHInset(context), 16, responsiveHInset(context), 16),
                      child: SlideUpFade(
                        child: Row(
                          children: [
                            if (Navigator.canPop(context)) ...[
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                behavior: HitTestBehavior.opaque,
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    color: C.textPrimary, size: 20),
                              ),
                              const SizedBox(width: 12),
                            ],
                            DynText(
                              'notifications',
                              'title',
                              'Notifications',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (unreadCount > 0)
                              GestureDetector(
                                onTap: _markingAll ? null : _markAllRead,
                                child: Text(
                                  _markingAll ? 'Updating…' : 'Mark all read',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: notifs.isEmpty
                          ? Center(
                              child: Text(
                                'No notifications yet',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                              ),
                            )
                          : ListView(
                              padding: EdgeInsets.symmetric(horizontal: responsiveHInset(context)),
                              children: [
                                if (newNotifs.isNotEmpty) ...[
                                  SlideUpFade(
                                    delay: const Duration(milliseconds: 80),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        'New',
                                        style: TextStyle(
                                          color: C.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...newNotifs.asMap().entries.map(
                                        (e) => SlideUpFade(
                                          // Key → Flutter reuses the element so
                                          // marking one read doesn't re-animate
                                          // the whole list (smooth, no flicker).
                                          key: ValueKey(e.value.id ?? 'n${e.key}'),
                                          // Cap the stagger so long lists don't lag.
                                          delay: Duration(
                                            milliseconds:
                                                80 + (e.key.clamp(0, 6)) * 45,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: _NotifCard(
                                              notif: e.value,
                                              timeAgo: _timeAgo(e.value.time),
                                              onTap: () => _markRead(e.value),
                                            ),
                                          ),
                                        ),
                                      ),
                                  const SizedBox(height: 8),
                                ],
                                if (oldNotifs.isNotEmpty) ...[
                                  SlideUpFade(
                                    delay: const Duration(milliseconds: 200),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        'Earlier',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...oldNotifs.asMap().entries.map(
                                        (e) => SlideUpFade(
                                          key: ValueKey(e.value.id ?? 'o${e.key}'),
                                          delay: Duration(
                                            milliseconds:
                                                120 + (e.key.clamp(0, 6)) * 45,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: _NotifCard(
                                              notif: e.value,
                                              timeAgo: _timeAgo(e.value.time),
                                              onTap: null,
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                                const SizedBox(height: 24),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotifCard extends StatelessWidget {
  final AppNotif notif;
  final String timeAgo;
  final VoidCallback? onTap;

  const _NotifCard({
    required this.notif,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: notif.color.withValues(alpha: 0.12),
        highlightColor: notif.color.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: notif.isRead
                ? AppColors.bg2
                : notif.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: notif.isRead
                  ? AppColors.border
                  : notif.color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: notif.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(notif.icon, color: notif.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight:
                                notif.isRead ? FontWeight.w500 : FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif.body,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!notif.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: notif.color,
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
