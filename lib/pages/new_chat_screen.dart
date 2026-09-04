import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/user_profile.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'chat_screen.dart';
import '03_contacts_page.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg2,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: C.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Contact',
          style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700),
        ),
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
          SafeArea(
            child: Column(
              children: [
                _buildSearchBar(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: C.accent),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildEmptyState('No registered users found.');
                      }

                      // Map and filter users
                      final usersList = snapshot.data!.docs
                          .map((doc) => UserProfile.fromFirestore(
                                doc.id,
                                doc.data() as Map<String, dynamic>,
                              ))
                          .where((u) => u.uid != myUid && u.phone.isNotEmpty)
                          .where((u) {
                            final q = _searchQuery.toLowerCase();
                            return u.name.toLowerCase().contains(q) ||
                                u.phone.contains(q) ||
                                u.email.toLowerCase().contains(q);
                          })
                          .toList();

                      return ListView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        children: [
                          _buildSpecialActionRow(),
                          const SizedBox(height: 16),
                          // MY saved emergency contacts — so anyone added in
                          // Settings/Contacts can be chatted with here too, even
                          // if they aren't a registered SmartSafe user.
                          _buildMyContactsSection(myUid),
                          SecHeader('All Users (${usersList.length})'),
                          if (usersList.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: _buildEmptyState('No users match "$_searchQuery"'),
                            )
                          else
                            ...List.generate(usersList.length, (i) {
                              final profile = usersList[i];
                              return SlideUpFade(
                                delay: Duration(milliseconds: i * 30),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildUserCard(profile),
                                ),
                              );
                            }),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
            hintText: 'Search name or phone number...',
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

  Widget _buildSpecialActionRow() {
    return DCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ContactsPage(),
          ),
        );
      },
      borderColor: C.accent,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: C.accent.withValues(alpha: 0.15),
              border: Border.all(color: C.accent.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Icon(Icons.security_rounded, color: C.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage Emergency Contacts',
                  style: TextStyle(
                    color: C.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add or configure SOS alerts for contacts',
                  style: TextStyle(color: C.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, color: C.textMuted, size: 14),
        ],
      ),
    );
  }

  /// Lists MY saved emergency contacts so they can be chatted with directly —
  /// even if they never registered a SmartSafe profile of their own.
  Widget _buildMyContactsSection(String? myUid) {
    if (myUid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('emergency_contacts')
          .where('userId', isEqualTo: myUid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final q = _searchQuery.toLowerCase();
        final docs = snap.data!.docs.where((d) {
          final m = d.data() as Map<String, dynamic>;
          final name = (m['name'] ?? '').toString().toLowerCase();
          final phone = (m['phone'] ?? '').toString();
          return q.isEmpty || name.contains(q) || phone.contains(q);
        }).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SecHeader('My Emergency Contacts (${docs.length})'),
            ...docs.map((d) {
              final m = d.data() as Map<String, dynamic>;
              final name = (m['name'] ?? 'Contact').toString();
              final phone = (m['phone'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildContactCard(name, phone),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildContactCard(String name, String phone) {
    final contact = Contact(
      id: '',
      name: name,
      phone: phone,
      role: 'User',
      color: C.accent,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: DCard(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(contact: contact)),
          );
        },
        child: Row(
          children: [
            AvatarWidget(initials: _initialsFrom(name), color: C.accent, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: C.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(phone,
                      style: TextStyle(color: C.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chat_bubble_outline_rounded, color: C.accent, size: 18),
          ],
        ),
      ),
    );
  }

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

  Widget _buildUserCard(UserProfile profile) {
    final avatarColors = [C.accent, C.accent, C.accent, C.warning, C.accent, C.accent];
    final avatarColor = avatarColors[profile.uid.hashCode % avatarColors.length];

    return DCard(
      onTap: () {
        final contact = Contact(
          id: profile.uid,
          name: profile.name,
          phone: profile.phone,
          role: profile.role == 'admin' ? 'Admin' : 'User',
          color: avatarColor,
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
          AvatarWidget(
            initials: profile.initials,
            color: avatarColor,
            size: 46,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: TextStyle(
                    color: C.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  profile.phone,
                  style: TextStyle(color: C.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(Icons.chat_bubble_outline_rounded, color: C.accent, size: 18),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded, color: C.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: C.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
