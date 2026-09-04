import 'package:flutter/material.dart';
import '../services/app_firestore_service.dart';
import '../services/presence_service.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import '10_add_contact_page.dart';
import 'chat_screen.dart';

class ContactsPage extends StatefulWidget {
  final VoidCallback? onAddContact;
  const ContactsPage({super.key, this.onAddContact});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  late final Stream<UserProfile?> _profileStream;
  late final Stream<List<Contact>> _contactsStream;

  @override
  void initState() {
    super.initState();
    PresenceService.instance.heartbeat();
    _profileStream = UserProfileService.instance.profileStream();
    _contactsStream = AppFirestoreService.instance.watchMyEmergencyContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: CustomPaint(painter: DotGridPainter(), size: Size.infinite)),
          SafeArea(
            child: StreamBuilder<List<Contact>>(
              stream: _contactsStream,
              builder: (context, contactsSnap) {
                final contacts = contactsSnap.data ?? [];
                final online = contacts.where((c) => c.isOnline).length;
                final isWaiting = contactsSnap.connectionState == ConnectionState.waiting;

                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          responsiveHInset(context), 16, responsiveHInset(context), 0),
                      child: SlideUpFade(
                        child: Row(
                          children: [
                            DynText('contacts', 'title', 'Emergency Contacts',
                                style: TextStyle(
                                  color: C.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                )),
                            const Spacer(),
                            GestureDetector(
                              onTap: widget.onAddContact ??
                                  () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const AddContactPage(),
                                      ),
                                    );
                                  },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  color: C.accent,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: AppTheme.glowShadow(C.accent, blur: 16),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.add_rounded,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text('Add',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<UserProfile?>(
                      stream: _profileStream,
                      builder: (context, profileSnap) {
                        final profilePhone = profileSnap.data?.phone.trim() ?? '';
                        final hasPhone = profilePhone.isNotEmpty;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: C.bg2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: hasPhone
                                    ? C.accent.withValues(alpha: 0.35)
                                    : C.warning.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasPhone
                                      ? Icons.check_circle_rounded
                                      : Icons.info_outline_rounded,
                                  color: hasPhone ? C.accent : C.warning,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    hasPhone
                                        ? "You're visible to your circle when online"
                                        : 'Add your phone number in Settings › Profile to appear online',
                                    style: TextStyle(
                                      color: hasPhone ? C.accent : C.warning,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SlideUpFade(
                        delay: const Duration(milliseconds: 80),
                        child: Row(
                          children: [
                            Text(
                              '${contacts.length} contacts will receive your SOS',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12),
                            ),
                            if (contacts.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              BlinkDot(color: AppColors.accent, size: 8),
                              const SizedBox(width: 4),
                              Text('$online Online',
                                  style: TextStyle(
                                      color: AppColors.accent, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Make the Call-selection feature discoverable.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: Row(
                        children: [
                          Icon(Icons.call_rounded, color: C.accent, size: 13),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Turn ON "Call" for the one person you want SmartSafe to auto-call on SOS. SMS, WhatsApp & Email go to everyone.',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isWaiting
                          ? Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.accent))
                          : contacts.isEmpty
                              ? EmptyState(
                                  icon: Icons.contact_phone_rounded,
                                  title: 'No contacts yet',
                                  message:
                                      'Add trusted people who will receive your SOS alerts, live location and safety updates.',
                                  actionLabel: 'Add Contact',
                                  onAction: widget.onAddContact ??
                                      () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => const AddContactPage()),
                                          ),
                                )
                              : ListView.builder(
                                  cacheExtent: 500,
                                  padding: EdgeInsets.symmetric(horizontal: responsiveHInset(context)),
                                  itemCount: contacts.length + 1,
                                  itemBuilder: (context, i) {
                                    if (i == contacts.length) {
                                      return SlideUpFade(
                                        delay: Duration(milliseconds: 100 + i * 60),
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12, bottom: 24),
                                          child: _SmsBackupCard(),
                                        ),
                                      );
                                    }
                                    final c = contacts[i];
                                    return SlideUpFade(
                                      delay: Duration(milliseconds: 100 + i * 60),
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: _ContactCard(contact: c),
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

class _ContactCard extends StatelessWidget {
  final Contact contact;

  const _ContactCard({required this.contact});

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: C.border),
        ),
        title: Text('Delete contact',
            style: TextStyle(
                color: C.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Remove ${contact.name} from your emergency contacts? '
          'They will no longer receive your SOS alerts.',
          style: TextStyle(color: C.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AppFirestoreService.instance
                    .deleteEmergencyContact(contact.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: C.bg2,
                      behavior: SnackBarBehavior.floating,
                      content: Text('${contact.name} deleted',
                          style: TextStyle(color: C.textPrimary)),
                    ),
                  );
                }
              } catch (_) {}
            },
            child: Text('Delete',
                style: TextStyle(
                    color: C.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(contact: contact),
          ),
        );
      },
      child: Row(
        children: [
          Stack(
            children: [
              AvatarWidget(
                initials: contact.initials,
                color: C.accent,
                size: 50,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bg2,
                    border: Border.all(color: AppColors.bg, width: 2),
                  ),
                  child: contact.isOnline
                      ? BlinkDot(color: AppColors.accent, size: 10)
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.textMuted,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name — softer than pure black (dark-grey) but still bold and
                // prominent. Leaves room on the right for the corner delete.
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Text(contact.name,
                      style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                const SizedBox(height: 3),
                Text(contact.phone,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                // Wrap, not Row: on a narrow card these three badges used to be
                // squeezed until the relation label broke one letter per line.
                // Now a badge that doesn't fit simply moves to the next line.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // The one auto-call contact = your PRIMARY emergency contact.
                    if (contact.callAlert)
                      StatusBadge(label: 'PRIMARY', color: C.accent),
                    // Relation is free-text from Firestore, so it can be long
                    // ("Best Friend from College") — the chip ellipsises it.
                    StatusBadge(label: contact.relation, color: C.textMuted),
                    if (contact.isOnline)
                      StatusBadge(label: 'Online', color: AppColors.accent)
                    else
                      StatusBadge(label: 'Away', color: AppColors.textMuted),
                  ],
                ),
              ],
            ),
          ),
          // Per-contact channel toggles — tap to choose what this contact
          // receives during an SOS (Call / SMS / Push). The Delete button now
          // sits in the opposite (top-left) corner, so these can stay centred.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Subtle delete — a muted trash icon above the toggles. Never
              // overlaps the avatar and reads as a clean, premium action.
              GestureDetector(
                onTap: () => _confirmDelete(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 8),
                  child: Icon(Icons.delete_outline_rounded,
                      color: C.textMuted, size: 18),
                ),
              ),
              _ChannelToggle(
                icon: Icons.call_rounded,
                label: 'Call',
                on: contact.callAlert,
                // Single-select: turning Call ON for this contact makes it the
                // ONE auto-call target (others turn OFF). Tap again to clear.
                onTap: () {
                  if (contact.callAlert) {
                    AppFirestoreService.instance
                        .updateContactChannel(contact.id, 'callAlert', false);
                  } else {
                    AppFirestoreService.instance.setCallContact(contact.id);
                  }
                },
              ),
              const SizedBox(height: 6),
              _ChannelToggle(
                icon: Icons.sms_rounded,
                label: 'SMS',
                on: contact.smsAlert,
                onTap: () => AppFirestoreService.instance
                    .updateContactChannel(contact.id, 'smsAlert', !contact.smsAlert),
              ),
              const SizedBox(height: 6),
              _ChannelToggle(
                icon: Icons.notifications_rounded,
                label: 'Push',
                on: contact.pushAlert,
                onTap: () => AppFirestoreService.instance
                    .updateContactChannel(contact.id, 'pushAlert', !contact.pushAlert),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ChannelToggle({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = on ? C.accent : C.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: on ? C.accent.withValues(alpha: 0.12) : C.bg3,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: on ? C.accent.withValues(alpha: 0.4) : C.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? icon : Icons.block_rounded, color: color, size: 12),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _SmsBackupCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(C.spaceMd),
      decoration: BoxDecoration(
        color: C.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      child: Row(
        children: [
          Icon(Icons.sms_rounded, color: C.accent, size: 22),
          const SizedBox(width: C.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SMS Backup Enabled',
                    style: TextStyle(
                        color: C.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Text('Alerts sent via SMS if internet is unavailable',
                    style: TextStyle(color: C.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
