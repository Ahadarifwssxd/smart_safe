import 'package:smartsafe/Dashboard/controllers/menu_app_controller.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/services/admin_profile_service.dart';
import 'package:smartsafe/Dashboard/services/dashboard_search_service.dart';
import 'package:smartsafe/Dashboard/screens/admin/admin_edit_profile_dialog.dart';
import 'package:smartsafe/user_app_shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartsafe/theme/colors.dart';

import '../../../constants.dart';

class Header extends StatelessWidget {
  const Header({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    // On phones the menu button, title and profile stay on one row and the
    // search field moves to its own full-width row underneath — squeezing all
    // four into a single row overflows / clips on narrow screens.
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: context.read<MenuAppController>().controlMenu,
              ),
              Expanded(
                child: Text(
                  "SmartSafe Admin",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: C.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const ProfileCard(),
            ],
          ),
          const SizedBox(height: defaultPadding / 2),
          const SearchField(),
          const _SearchResultsPanel(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // No menu button here: from tablet up MainScreen shows the side
            // menu permanently and registers no drawer.
            Flexible(
              child: Text(
                "SmartSafe Admin Panel",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: C.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _OpenAppButton(),
            ),
            const Expanded(flex: 3, child: SearchField()),
            const ProfileCard(),
          ],
        ),
        const _SearchResultsPanel(),
      ],
    );
  }
}

class _OpenAppButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: C.accent.withValues(alpha: 0.2),
        foregroundColor: C.accentLight,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: C.accent.withValues(alpha: 0.5)),
        ),
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserAppShell()),
        );
      },
      icon: const Icon(Icons.phone_android_rounded, size: 18),
      label: const Text('Open App', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class _SearchResultsPanel extends StatelessWidget {
  const _SearchResultsPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<MenuAppController>(
      builder: (context, menu, _) {
        final q = menu.searchQuery.trim();
        if (q.length < 2) return const SizedBox.shrink();
        return FutureBuilder<List<SearchResultItem>>(
          future: DashboardSearchService.instance.search(q),
          builder: (context, snap) {
            final items = snap.data ?? [];
            if (snap.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(color: C.accent, backgroundColor: C.bg2),
              );
            }
            return Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: secondaryColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border.withValues(alpha: 0.4)),
              ),
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('No results for "$q"', style: TextStyle(color: C.textMuted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final r = items[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.search_rounded, color: C.accent, size: 18),
                          title: Text(r.title, style: TextStyle(color: C.textPrimary, fontSize: 13)),
                          subtitle: Text('${r.type} · ${r.subtitle}', style: TextStyle(color: C.textMuted, fontSize: 11)),
                          onTap: () {
                            menu.clearSearch();
                            menu.setSelectedRoute(r.routeKey);
                          },
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminDisplayProfile>(
      stream: AdminProfileService.instance.profileStream(),
      builder: (context, snapshot) {
        final profile = snapshot.data ??
            const AdminDisplayProfile(name: 'Admin', email: '', photoUrl: '');

        return PopupMenuButton<String>(
          offset: const Offset(0, 48),
          color: C.bg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (value) {
            if (value == 'edit') {
              showAdminEditProfileDialog(context, profile);
            } else if (value == 'logout') {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: C.bg2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: C.border),
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.logout_rounded, color: C.accent, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Sign Out',
                        style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  content: Text(
                    'Are you sure you want to logout from the admin panel?',
                    style: TextStyle(color: C.textMuted),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('No', style: TextStyle(color: C.textMuted)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        FirebaseAuth.instance.signOut();
                        context.read<MenuAppController>().setSelectedRoute('dashboard');
                      },
                      child: const Text('Yes, Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, color: C.accent, size: 20),
                  const SizedBox(width: 10),
                  Text('Edit profile', style: TextStyle(color: C.textPrimary)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: C.accent, size: 20),
                  const SizedBox(width: 10),
                  Text('Sign Out', style: TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          child: Container(
            margin: const EdgeInsets.only(left: defaultPadding),
            padding: const EdgeInsets.symmetric(
              horizontal: defaultPadding,
              vertical: defaultPadding / 2,
            ),
            decoration: BoxDecoration(
              color: secondaryColor,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: Border.all(color: C.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AdminAvatar(profile: profile),
                if (!Responsive.isMobile(context))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: defaultPadding / 2),
                    // Capped so a long admin name can never push the header row
                    // (search field, title) into an overflow.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        profile.name,
                        style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminAvatar extends StatelessWidget {
  final AdminDisplayProfile profile;
  const _AdminAvatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = profile.photoUrl.isNotEmpty;
    return CircleAvatar(
      key: ValueKey('${profile.uid ?? "legacy"}-${profile.photoUrl}-${profile.name}'),
      radius: 16,
      backgroundColor: C.accent.withValues(alpha: 0.15),
      backgroundImage: hasPhoto ? NetworkImage(profile.photoUrl) : null,
      onBackgroundImageError: hasPhoto ? (_, __) {} : null,
      child: hasPhoto
          ? null
          : Text(
              profile.initials,
              style: TextStyle(color: C.accent, fontSize: 12, fontWeight: FontWeight.w800),
            ),
    );
  }
}

class SearchField extends StatefulWidget {
  const SearchField({Key? key}) : super(key: key);

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      style: const TextStyle(color: Colors.white),
      onChanged: (v) {
        context.read<MenuAppController>().setSearchQuery(v);
        setState(() {});
      },
      onSubmitted: (v) => context.read<MenuAppController>().setSearchQuery(v),
      decoration: InputDecoration(
        hintText: "Search users, SOS, contacts…",
        hintStyle: TextStyle(color: C.textMuted),
        fillColor: secondaryColor,
        filled: true,
        border: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_ctrl.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, color: C.textMuted, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  context.read<MenuAppController>().clearSearch();
                  setState(() {});
                },
              ),
            InkWell(
              onTap: () => context.read<MenuAppController>().setSearchQuery(_ctrl.text),
              child: Container(
                padding: const EdgeInsets.all(defaultPadding * 0.75),
                margin: const EdgeInsets.symmetric(horizontal: defaultPadding / 2),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: const Icon(Icons.search, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
