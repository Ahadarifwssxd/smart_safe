import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../services/chat_service.dart';
import '../services/user_profile_service.dart';
import '../services/presence_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../utils/phone_utils.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import '03_contacts_page.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Streams are created ONCE and cached. Creating them inside build() made
  // every rebuild (search typing, a presence ping, any emit) re-subscribe,
  // which flashed the loading spinner — the "baar baar reload" flicker.
  late final Stream<UserProfile?> _profileStream;
  Stream<List<ChatMessage>>? _messagesStream;
  String? _messagesPhone;

  // Per-user chat rename (alias) stream, built lazily once we know my uid.
  Stream<QuerySnapshot>? _aliasStream;
  String? _aliasUid;

  // MY saved emergency contacts — so a chat shows the name I gave someone
  // (WhatsApp-style) instead of a bare phone number when they have no SmartSafe
  // profile of their own.
  Stream<QuerySnapshot>? _myContactsStream;
  String? _myContactsUid;

  @override
  void initState() {
    super.initState();
    _profileStream = UserProfileService.instance.profileStream();
  }

  /// Watches the chat aliases I set (renames), keyed by my uid. Cached so the
  /// list doesn't re-subscribe on every rebuild.
  Stream<QuerySnapshot> _aliasStreamFor(String uid) {
    if (_aliasStream == null || _aliasUid != uid) {
      _aliasUid = uid;
      _aliasStream = FirebaseFirestore.instance
          .collection('contact_aliases')
          .where('ownerId', isEqualTo: uid)
          .snapshots();
    }
    return _aliasStream!;
  }

  /// Watches the emergency contacts I saved, so their names can be used in the
  /// chat list. Cached the same way as the alias stream.
  Stream<QuerySnapshot> _myContactsStreamFor(String uid) {
    if (_myContactsStream == null || _myContactsUid != uid) {
      _myContactsUid = uid;
      _myContactsStream = FirebaseFirestore.instance
          .collection('emergency_contacts')
          .where('userId', isEqualTo: uid)
          .snapshots();
    }
    return _myContactsStream!;
  }

  // Chat-partner profile + presence streams, cached per phone-set. They were
  // created inline in the build — every rebuild (a new message, a search
  // keystroke, any parent setState) re-subscribed fresh Firestore listeners
  // and re-flashed the loading spinner.
  String? _partnerPhonesKey;
  Stream<QuerySnapshot<Map<String, dynamic>>?>? _partnerUsersStream;
  Stream<Map<String, bool>>? _partnerPresenceStream;

  /// (Re)builds the users + presence streams only when the partner phone-set
  /// actually changes (a conversation appears/disappears).
  void _ensurePartnerStreams(List<String> phones) {
    final key = phones.join(',');
    if (_partnerPhonesKey == key) return;
    _partnerPhonesKey = key;
    if (phones.isEmpty) {
      _partnerUsersStream =
          Stream<QuerySnapshot<Map<String, dynamic>>?>.value(null);
      _partnerPresenceStream = Stream<Map<String, bool>>.value({});
    } else {
      // Covariance lets the non-nullable snapshot stream fill the nullable
      // slot below (Stream<A> is a subtype of Stream<A?>).
      _partnerUsersStream = FirebaseFirestore.instance
          .collection('users')
          .where('phoneNormalized', whereIn: phones)
          .snapshots();
      _partnerPresenceStream =
          PresenceService.instance.watchOnlineForPhones(phones);
    }
  }

  /// Initials from a free-text name (used when there's no profile to read them
  /// from, e.g. a renamed chat). Falls back to '?' for blank/numeric names.
  String _initialsFrom(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(p))
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// Returns a cached messages stream, only rebuilt if the phone changes.
  Stream<List<ChatMessage>> _messagesStreamFor(String phone) {
    if (_messagesStream == null || _messagesPhone != phone) {
      _messagesPhone = phone;
      _messagesStream = ChatService.instance.watchAllMyMessages(phone);
    }
    return _messagesStream!;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (msgDate == today) {
      return DateFormat('hh:mm a').format(dateTime);
    } else if (msgDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('dd/MM/yy').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: _profileStream,
      builder: (context, profileSnap) {
        final profilePhone = profileSnap.data?.phone.trim() ?? '';
        final myPhoneNormalized = normalizePhone(profilePhone);
        final myUid = profileSnap.data?.uid ?? '';

        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg2,
            elevation: 0,
            title: Text(
              'Chats',
              style: TextStyle(
                color: C.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.shield_rounded, color: C.accent, size: 22),
                tooltip: 'Emergency Contacts',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ContactsPage(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: C.border.withValues(alpha: 0.3),
              ),
            ),
          ),
          body: Stack(
            children: [
              const DotGrid(),
              // SizedBox.expand ensures the Column inside gets full height
              // so Expanded(ListView) can scroll properly
              SizedBox.expand(
                child: profilePhone.isEmpty
                    ? _buildPhoneMissingState()
                    : _buildChatsListContent(myPhoneNormalized, myUid),
              ),
            ],
          ),
          floatingActionButton: profilePhone.isNotEmpty
              ? FloatingActionButton(
                  onPressed: () async {
                    // Navigate to NewChatScreen and wait — it uses
                    // pushReplacement internally so we just push here
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NewChatScreen(),
                      ),
                    );
                  },
                  backgroundColor: C.accent,
                  elevation: 4,
                  tooltip: 'New Chat',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.chat_bubble_rounded, color: C.bg, size: 22),
                )
              : null,
        );
      },
    );
  }

  Widget _buildPhoneMissingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contact_phone_outlined, color: C.warning, size: 54),
            const SizedBox(height: 16),
            Text(
              'Phone Number Required',
              style: TextStyle(
                color: C.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your profile does not have a phone number. Add one in Settings > Profile to use chat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.textMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsListContent(String myPhoneNormalized, String myUid) {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: myUid.isEmpty ? null : _aliasStreamFor(myUid),
            builder: (context, aliasSnap) {
              // normalizedPhone -> user-set rename (alias).
              final aliasMap = <String, String>{};
              if (aliasSnap.hasData) {
                for (final doc in aliasSnap.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  final p = (d['phoneNormalized'] ?? '').toString();
                  final n = (d['name'] ?? '').toString().trim();
                  if (p.isNotEmpty && n.isNotEmpty) aliasMap[p] = n;
                }
              }
              return StreamBuilder<QuerySnapshot>(
                stream: myUid.isEmpty ? null : _myContactsStreamFor(myUid),
                builder: (context, contactsSnap) {
              // normalizedPhone -> the name I saved this person under.
              final contactNameMap = <String, String>{};
              if (contactsSnap.hasData) {
                for (final doc in contactsSnap.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  final raw = (d['phone'] ?? '').toString();
                  final p = (d['phoneNormalized'] ?? '').toString().isNotEmpty
                      ? d['phoneNormalized'].toString()
                      : normalizePhone(raw);
                  final n = (d['name'] ?? '').toString().trim();
                  if (p.isNotEmpty && n.isNotEmpty) contactNameMap[p] = n;
                }
              }
                        return StreamBuilder<List<ChatMessage>>(
                stream: _messagesStreamFor(myPhoneNormalized),
                builder: (context, messagesSnap) {
                  if (!messagesSnap.hasData &&
                      messagesSnap.connectionState ==
                          ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(color: C.accent));
                  }

                  final allMessages = messagesSnap.data ?? [];
                  if (allMessages.isEmpty) {
                    return _buildEmptyState();
                  }

                  // Group messages by conversation ID
                  final conversationGroups = <String, List<ChatMessage>>{};
                  for (final msg in allMessages) {
                    conversationGroups
                        .putIfAbsent(msg.conversationId, () => [])
                        .add(msg);
                  }

                  final List<_ConversationItem> conversations = [];
                  conversationGroups.forEach((conversationId, messages) {
                    final latestMsg = messages.first;
                    final otherPhone = normalizePhone(
                        normalizePhone(latestMsg.senderPhone) ==
                                myPhoneNormalized
                            ? latestMsg.receiverPhone
                            : latestMsg.senderPhone);
                    final unreadCount = messages
                        .where((m) =>
                            normalizePhone(m.receiverPhone) == myPhoneNormalized && !m.isRead)
                        .length;
                    conversations.add(_ConversationItem(
                      conversationId: conversationId,
                      otherPhone: otherPhone,
                      latestMessage: latestMsg,
                      unreadCount: unreadCount,
                    ));
                  });

                  final chatPartnerPhones = conversations
                      .map((c) => c.otherPhone)
                      .where((p) => p.isNotEmpty)
                      .toSet()
                      .toList();

                  final queryPhones = chatPartnerPhones.take(30).toList();
                  _ensurePartnerStreams(queryPhones);

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>?>(
                    stream: _partnerUsersStream,
                    builder: (context, usersSnap) {
                      if (!usersSnap.hasData &&
                          usersSnap.connectionState ==
                              ConnectionState.waiting &&
                          queryPhones.isNotEmpty) {
                        return Center(
                            child: CircularProgressIndicator(color: C.accent));
                      }

                      final usersMap = <String, UserProfile>{};
                      if (usersSnap.hasData && usersSnap.data != null) {
                        for (var doc in usersSnap.data!.docs) {
                          final up = UserProfile.fromFirestore(
                              doc.id, doc.data());
                          final norm = normalizePhone(up.phone);
                          if (norm.isNotEmpty) {
                            usersMap[norm] = up;
                          }
                        }
                      }

                      return StreamBuilder<Map<String, bool>>(
                        stream: _partnerPresenceStream,
                        builder: (context, presenceSnap) {
                          final presenceMap = presenceSnap.data ?? {};

                          final filteredConversations = conversations.where((c) {
                            final profile = usersMap[c.otherPhone];
                            final name = aliasMap[c.otherPhone] ??
                                contactNameMap[c.otherPhone] ??
                                profile?.name ??
                                c.otherPhone;
                            final query = _searchQuery.toLowerCase();
                            return name.toLowerCase().contains(query) ||
                                c.otherPhone.contains(query);
                          }).toList();

                          filteredConversations.sort((a, b) => b
                              .latestMessage.timestamp
                              .compareTo(a.latestMessage.timestamp));

                          if (filteredConversations.isEmpty) {
                            return _buildEmptyState();
                          }

                          return ListView.builder(
                            cacheExtent: 500,
                            key: const PageStorageKey('chats_list'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            itemCount: filteredConversations.length,
                            itemBuilder: (context, i) {
                              final item = filteredConversations[i];
                              final profile = usersMap[item.otherPhone];
                              final isOnline =
                                  presenceMap[item.otherPhone] == true;

                              return Padding(
                                key: ValueKey(item.conversationId),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildConversationCard(item, profile,
                                    isOnline, myPhoneNormalized,
                                    alias: aliasMap[item.otherPhone],
                                    contactName:
                                        contactNameMap[item.otherPhone]),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
              },
            );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      color: C.bg2.withValues(alpha: 0.3),
      child: Container(
        decoration: BoxDecoration(
          color: C.bg3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.border),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(color: C.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search chats...',
            hintStyle: TextStyle(color: C.textMuted, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded, color: C.textMuted, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: C.textMuted, size: 18),
                    onPressed: () {
                      setState(() {
                        _searchCtrl.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
            });
          },
        ),
      ),
    );
  }

  Widget _buildConversationCard(_ConversationItem item, UserProfile? profile,
      bool isOnline, String myPhoneNormalized,
      {String? alias, String? contactName}) {
    // Name priority, WhatsApp-style: my own rename (alias) → the name I saved
    // this person under in my contacts → their SmartSafe profile name → the raw
    // phone number. Saving someone as a contact now means their chat shows that
    // name instead of a bare number, even if they have no profile.
    final profileName = profile?.name.trim() ?? '';
    final savedName = contactName?.trim() ?? '';
    final displayName = (alias != null && alias.isNotEmpty)
        ? alias
        : savedName.isNotEmpty
            ? savedName
            : profileName.isNotEmpty
                ? profileName
                : item.otherPhone;
    final initials = (alias != null && alias.isNotEmpty)
        ? _initialsFrom(alias)
        : savedName.isNotEmpty
            ? _initialsFrom(savedName)
            : (profile != null && profileName.isNotEmpty)
                ? profile.initials
                : _initialsFrom(displayName);
    final avatarColors = [C.accent, C.accent, C.accent, C.warning, C.accent, C.accent];
    final avatarColor = profile != null
        ? avatarColors[profile.uid.hashCode % avatarColors.length]
        : C.textMuted;

    final latestMsg = item.latestMessage;
    final isMe = latestMsg.senderPhone == myPhoneNormalized;

    // Build contact model to navigate to ChatScreen
    final contact = Contact(
      id: profile?.uid ?? '',
      name: displayName,
      phone: item.otherPhone,
      role: profile?.role == 'admin' ? 'Admin' : 'User',
      color: avatarColor,
    );

    return GestureDetector(
      onLongPress: () =>
          _confirmDeleteChat(item, displayName, myPhoneNormalized),
      child: DCard(
      onTap: () {
        ChatService.instance.markMessagesAsRead(
          myPhone: myPhoneNormalized,
          otherPhone: item.otherPhone,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(contact: contact),
          ),
        );
      },
      child: Row(
        children: [
          Stack(
            children: [
              AvatarWidget(
                initials: initials,
                color: avatarColor,
                size: 48,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.bg2,
                    border: Border.all(color: C.bg, width: 2),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? C.accent : C.textMuted,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(latestMsg.timestamp),
                      style: TextStyle(color: C.textMuted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (isMe) ...[
                      Icon(
                        latestMsg.isRead ? Icons.done_all : Icons.done,
                        color: latestMsg.isRead ? C.accent : C.textMuted,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        latestMsg.type == 'image'
                            ? '📷 Photo'
                            : latestMsg.message,
                        style: TextStyle(
                          color: item.unreadCount > 0 ? C.textPrimary : C.textMuted,
                          fontSize: 12,
                          fontWeight: item.unreadCount > 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: C.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${item.unreadCount}',
                          style: TextStyle(
                            color: C.bg,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Long-press a chat → confirm and permanently delete the whole conversation.
  Future<void> _confirmDeleteChat(
      _ConversationItem item, String displayName, String myPhoneNormalized) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: C.accent.withValues(alpha: 0.3))),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: C.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Icon(Icons.delete_outline_rounded, color: C.red, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Delete chat with $displayName?',
                    style: TextStyle(
                      color: C.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This permanently removes every message in this conversation. This cannot be undone.',
              style: TextStyle(color: C.textMuted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        border: Border.all(color: C.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Cancel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: C.textPrimary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: C.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Delete',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await ChatService.instance.clearConversation(
        myPhone: myPhoneNormalized,
        otherPhone: item.otherPhone,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.bg2,
          behavior: SnackBarBehavior.floating,
          content: Text('Chat deleted',
              style: TextStyle(color: C.textPrimary)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.red,
          behavior: SnackBarBehavior.floating,
          content: Text('Could not delete chat: $e',
              style: TextStyle(color: C.textPrimary)),
        ));
      }
    }
  }

  Widget _buildEmptyState() {
    return const EmptyState(
      icon: Icons.forum_rounded,
      title: 'No active chats',
      message:
          'Tap the chat button to start a conversation with your contacts or anyone on SmartSafe.',
    );
  }
}

class _ConversationItem {
  final String conversationId;
  final String otherPhone;
  final ChatMessage latestMessage;
  final int unreadCount;

  const _ConversationItem({
    required this.conversationId,
    required this.otherPhone,
    required this.latestMessage,
    required this.unreadCount,
  });
}
