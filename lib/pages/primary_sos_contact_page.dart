import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_firestore_service.dart';
import '../models/models.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

/// A page where the user can select a specific contact as their
/// PRIMARY SOS contact — the one who gets the FIRST call during an emergency.
class PrimarySosContactPage extends StatefulWidget {
  const PrimarySosContactPage({super.key});

  /// SharedPreferences key for storing the primary contact's Firestore doc ID.
  static const String prefKey = 'primary_sos_contact_id';

  @override
  State<PrimarySosContactPage> createState() => _PrimarySosContactPageState();
}

class _PrimarySosContactPageState extends State<PrimarySosContactPage> {
  List<Contact> _contacts = [];
  String? _selectedId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await AppFirestoreService.instance.getEmergencyContacts();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _selectedId = prefs.getString(PrimarySosContactPage.prefKey);
      _loading = false;
    });
  }

  Future<void> _select(Contact contact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrimarySosContactPage.prefKey, contact.id);
    if (!mounted) return;
    setState(() => _selectedId = contact.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: C.accent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${contact.name} set as Primary SOS Contact',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrimarySosContactPage.prefKey);
    if (!mounted) return;
    setState(() => _selectedId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App Bar ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.only(left: 12),
                alignment: Alignment.center,
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: C.textPrimary, size: 18),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Text(
                'Primary SOS Contact',
                style: TextStyle(
                  color: C.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
              background: Stack(
                children: [
                  // Subtle gradient from top
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          C.accent.withValues(alpha: 0.12),
                          C.bg,
                        ],
                      ),
                    ),
                  ),
                  // Dot grid overlay
                  RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Info Banner ───────────────────────────────
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        C.accent.withValues(alpha: 0.12),
                        C.accentLight.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: C.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.star_rounded, color: C.accent, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'First Contact Alert',
                              style: TextStyle(
                                color: C.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'The selected contact will be called FIRST when you trigger SOS. All other contacts still receive SMS and app notifications simultaneously.',
                              style: TextStyle(
                                color: C.textMuted,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Loading / Empty State ─────────────────────
                if (_loading) ...[
                  const SizedBox(height: 60),
                  Center(child: CircularProgressIndicator(color: C.accent, strokeWidth: 2)),
                ] else if (_contacts.isEmpty) ...[
                  const SizedBox(height: 60),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: C.accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_add_rounded,
                              color: C.accent, size: 32),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No SOS Contacts Yet',
                          style: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add emergency contacts first\nfrom the Contacts tab.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: C.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // ── "None (all contacts)" option ─────────────
                  _ContactTile(
                    icon: Icons.people_rounded,
                    name: 'All Contacts (Default)',
                    subtitle: 'SOS alert goes to everyone simultaneously',
                    isSelected: _selectedId == null,
                    color: C.accent,
                    onTap: _clear,
                  ),
                  const SizedBox(height: 8),
                  Divider(color: C.border, height: 24),

                  // ── Contact list header ───────────────────────
                  Text(
                    'Choose Primary Contact',
                    style: TextStyle(
                      color: C.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Individual contacts ───────────────────────
                  ...List.generate(_contacts.length, (i) {
                    final c = _contacts[i];
                    final isSelected = _selectedId == c.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ContactTile(
                        avatar: c.initials,
                        avatarColor: c.color,
                        name: c.name,
                        subtitle: c.role.isNotEmpty
                            ? '${c.role}  ·  ${c.phone}'
                            : c.phone,
                        isSelected: isSelected,
                        color: c.color,
                        onTap: () => _select(c),
                      ),
                    );
                  }),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contact Tile Widget ───────────────────────────────────────────────────
class _ContactTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final String? avatar;
  final Color? avatarColor;
  final IconData? icon;

  const _ContactTile({
    required this.name,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
    this.avatar,
    this.avatarColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.08)
            : C.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? color.withValues(alpha: 0.5) : C.border,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: color.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar / Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (avatarColor ?? color).withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: icon != null
                        ? Icon(icon, color: avatarColor ?? color, size: 22)
                        : Text(
                            avatar ?? '?',
                            style: TextStyle(
                              color: avatarColor ?? color,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(color: C.textMuted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Selected radio indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? color : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? color : C.border,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 13)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
