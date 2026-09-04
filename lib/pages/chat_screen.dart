import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sms_sender.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/user_profile_service.dart';
import '../services/presence_service.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isOfflineMode = false;
  String _myPhone = '';
  bool _loadingProfile = true;
  bool _isUploading = false;
  Stream<List<ChatMessage>>? _messageStream;
  late String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = widget.contact.name;
    _loadAlias();
    _loadMyProfile();
  }

  /// Loads any custom name the user saved for this contact so the edit persists
  /// across opens (works even when this chat isn't a saved emergency contact).
  Future<void> _loadAlias() async {
    final alias = await ChatService.instance.getContactAlias(widget.contact.phone);
    if (alias != null && alias.isNotEmpty && mounted) {
      setState(() => _displayName = alias);
    }
  }

  /// Edit the contact's display name (also updates the saved emergency contact).
  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Edit name', style: TextStyle(color: C.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: C.textPrimary),
          decoration: InputDecoration(
            hintText: 'Contact name',
            hintStyle: TextStyle(color: C.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty || newName == _displayName) return;

    setState(() => _displayName = newName);
    // Persist as a per-user alias — reliable for ANY chat (saved or not).
    try {
      await ChatService.instance.setContactAlias(widget.contact.phone, newName);
    } catch (_) {}
    // Also update the saved emergency contact if this id points to one.
    if (widget.contact.id.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('emergency_contacts')
            .doc(widget.contact.id)
            .update({'name': newName});
      } catch (_) {}
    }
    if (mounted) {
      _showTopToast('Name updated',
          icon: Icons.check_circle_outline_rounded, color: C.success);
    }
  }

  /// Clears the whole conversation (deletes all messages for both sides).
  Future<void> _clearChat() async {
    if (_myPhone.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text('Clear chat?', style: TextStyle(color: C.textPrimary)),
        content: Text(
          'This permanently deletes all messages in this conversation for both sides.',
          style: TextStyle(color: C.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ChatService.instance.clearConversation(
        myPhone: _myPhone,
        otherPhone: widget.contact.phone,
      );
      if (mounted) {
        _showTopToast('Chat cleared',
            icon: Icons.delete_outline_rounded, color: C.accent);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not clear chat: $e')));
      }
    }
  }

  /// Long-press a message → option to delete it.
  Future<void> _onMessageLongPress(ChatMessage msg) async {
    HapticFeedback.mediumImpact();
    final delete = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.bg2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: C.accent),
              title: Text('Delete message',
                  style: TextStyle(color: C.textPrimary)),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: Icon(Icons.close_rounded, color: C.textMuted),
              title: Text('Cancel', style: TextStyle(color: C.textMuted)),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (delete == true) {
      try {
        await ChatService.instance.deleteMessage(msg.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMyProfile() async {
    final profile = await UserProfileService.instance.getCurrentProfile();
    if (mounted) {
      setState(() {
        _myPhone = profile?.phone.trim() ?? '';
        _loadingProfile = false;
        if (_myPhone.isNotEmpty) {
          _messageStream = ChatService.instance.watchChatMessages(
            myPhone: _myPhone,
            otherPhone: widget.contact.phone,
          );
        }
      });
      if (_myPhone.isNotEmpty) {
        print(
            'DEBUG ChatScreen: calling markMessagesAsRead immediately on profile load');
        ChatService.instance.markMessagesAsRead(
          myPhone: _myPhone,
          otherPhone: widget.contact.phone,
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// A small "sweet" toast that drops in at the TOP, then auto-dismisses (~1s) —
  /// it never blocks the message input like a bottom SnackBar did.
  void _showTopToast(String message,
      {IconData icon = Icons.sms_outlined, Color? color}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 12,
        left: 20,
        right: 20,
        child: _TopToast(
          message: message,
          icon: icon,
          color: color ?? C.warning,
          onDone: () => entry.remove(),
        ),
      ),
    );
    overlay.insert(entry);
  }

  /// True when the device has NO internet connection.
  Future<bool> _isOffline() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r == ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _myPhone.isEmpty) return;

    _inputCtrl.clear();
    _scrollToBottom();

    // Send via SMS if the user picked offline mode OR there's no internet at
    // all — so a safety message ALWAYS reaches the contact (100% over SIM).
    final bool autoOffline = !_isOfflineMode && await _isOffline();
    final bool sendViaSms = _isOfflineMode || autoOffline;

    await ChatService.instance.sendMessage(
      myPhone: _myPhone,
      otherPhone: widget.contact.phone,
      message: text,
      isOfflineSms: sendViaSms,
    );

    if (sendViaSms) {
      // Actually send over the SIM — works without internet.
      try {
        final granted = await Permission.sms.request();
        await sendSMS(
          message: text,
          recipients: [widget.contact.phone],
          sendDirect: granted.isGranted, // silent if allowed, else composer
        );
        if (mounted) {
          _showTopToast(
            !granted.isGranted
                ? 'Opening SMS to send…'
                : autoOffline
                    ? 'No internet — sent via SMS'
                    : 'Sent over SMS (offline)',
          );
        }
      } catch (e) {
        debugPrint('Offline SMS failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: C.accent,
              content: Text('Could not send SMS: $e',
                  style: const TextStyle(fontSize: 12)),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_myPhone.isEmpty) return;

    if (_isOfflineMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: C.bg2,
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: C.warning, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Image attachments are not available in Offline SMS mode. Switch online to send images.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (file == null) return;

      setState(() => _isUploading = true);

      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final extension =
          ['png', 'jpg', 'jpeg', 'gif'].contains(ext) ? ext : 'jpeg';

      final imageUrl =
          await ChatService.instance.uploadChatImage(bytes, extension);

      await ChatService.instance.sendImageMessage(
        myPhone: _myPhone,
        otherPhone: widget.contact.phone,
        imageUrl: imageUrl,
      );

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.accent.withValues(alpha: 0.9),
            content: Text('Upload failed: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _viewFullScreenImage(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          const DotGrid(),
          SafeArea(
            child: _loadingProfile
                ? Center(child: CircularProgressIndicator(color: C.accent))
                : Column(
                    children: [
                      if (_myPhone.isEmpty) _buildPhoneMissingBanner(),
                      Expanded(
                        child: _messageStream == null
                            ? _buildEmptyState()
                            : StreamBuilder<List<ChatMessage>>(
                                stream: _messageStream,
                                builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(color: C.accent),
                              );
                            }

                            final messages = snapshot.data ?? [];
                            if (messages.isEmpty) {
                              return _buildEmptyState();
                            }

                            // Trigger marking as read on frame update
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              print(
                                  'DEBUG ChatScreen: StreamBuilder post frame callback calling markMessagesAsRead');
                              ChatService.instance.markMessagesAsRead(
                                myPhone: _myPhone,
                                otherPhone: widget.contact.phone,
                              );
                            });

                            final displayMessages = messages.reversed.toList();

                            return ListView.builder(
                              cacheExtent: 500,
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.all(16),
                              itemCount: displayMessages.length,
                              itemBuilder: (context, i) {
                                final msg = displayMessages[i];
                                final isMe = msg.senderId != 'simulated_peer' &&
                                    msg.senderId != widget.contact.id;
                                return _buildMessageBubble(msg, isMe);
                              },
                            );
                          },
                        ),
                      ),
                      if (_isUploading) _buildUploadLoader(),
                      _buildInputBar(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Dial this contact directly using the phone's dialer.
  Future<void> _callContact() async {
    final raw = widget.contact.phone.trim();
    final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.bg2,
            content: Text('No phone number for this contact',
                style: TextStyle(color: C.textPrimary)),
          ),
        );
      }
      return;
    }
    try {
      await launchUrl(Uri.parse('tel:$cleaned'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: C.bg2,
            content: Text('Could not start the call',
                style: TextStyle(color: C.textPrimary)),
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: C.bg2,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_rounded, color: C.textPrimary, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: StreamBuilder<Map<String, dynamic>>(
        stream:
            PresenceService.instance.watchUserPresence(widget.contact.phone),
        builder: (context, presenceSnap) {
          final data =
              presenceSnap.data ?? {'isOnline': false, 'lastSeen': null};
          final isOnline = data['isOnline'] == true;
          final lastSeen = data['lastSeen'] as DateTime?;

          String statusText;
          if (isOnline) {
            statusText = 'Online';
          } else if (lastSeen != null) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final yesterday = today.subtract(const Duration(days: 1));
            final lsDate =
                DateTime(lastSeen.year, lastSeen.month, lastSeen.day);

            final hhmm =
                '${lastSeen.hour.toString().padLeft(2, '0')}:${lastSeen.minute.toString().padLeft(2, '0')}';
            if (lsDate == today) {
              statusText = 'Last seen at $hhmm';
            } else if (lsDate == yesterday) {
              statusText = 'Last seen yesterday at $hhmm';
            } else {
              statusText =
                  'Last seen ${lastSeen.day} ${_monthName(lastSeen.month)} at $hhmm';
            }
          } else {
            statusText = 'Offline';
          }

          return Row(
            children: [
              AvatarWidget(
                initials: widget.contact.initials,
                color: widget.contact.color,
                size: 38,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: TextStyle(
                      color: C.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      BlinkDot(
                        color: isOnline ? C.accent : C.textMuted,
                        size: 6,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: isOnline ? C.accent : C.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        StatusBadge(
          label: widget.contact.relation,
          color: widget.contact.color,
        ),
        // Direct call this contact (dials via the phone's dialer).
        IconButton(
          icon: Icon(Icons.call_rounded, color: C.accent, size: 20),
          tooltip: 'Call $_displayName',
          onPressed: _callContact,
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: C.textMuted, size: 20),
          color: C.bg2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: C.border)),
          onSelected: (v) {
            if (v == 'edit') _editName();
            if (v == 'clear') _clearChat();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_rounded, color: C.textPrimary, size: 18),
                const SizedBox(width: 10),
                Text('Edit name', style: TextStyle(color: C.textPrimary)),
              ]),
            ),
            PopupMenuItem(
              value: 'clear',
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, color: C.accent, size: 18),
                const SizedBox(width: 10),
                Text('Clear chat', style: TextStyle(color: C.accent)),
              ]),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: C.border.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildPhoneMissingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: C.warning.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: C.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your profile does not have a phone number. Add one to your profile to use chat.',
              style: TextStyle(color: C.textPrimary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, color: C.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: TextStyle(
                color: C.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Boliye aur safe rahiye. Chat online ya offline (SMS) dono tarah se chalegi!',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadLoader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: C.bg2.withValues(alpha: 0.6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: C.accent),
          ),
          const SizedBox(width: 10),
          Text(
            'Uploading file...',
            style: TextStyle(
                color: C.accent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    final timeStr =
        "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}";

    // ── Sent message (isMe) → RIGHT side, app-indigo highlight ─────────────
    // ── Received message    → LEFT side, grey/dark style ───────────────────

    // My messages: brand indigo gradient (matches the app theme).
    const Color myBubbleStart = Color(0xFF6366F1); // app indigo
    const Color myBubbleEnd = Color(0xFF4F46E5); // deeper indigo

    // Received messages: muted grey/dark
    final Color theirBubbleStart = C.bg2;
    final Color theirBubbleEnd = C.bg3;

    final borderColor = isMe
        ? (msg.isOfflineSms
            ? C.warning.withValues(alpha: 0.5)
            : const Color(0xFF22C55E).withValues(alpha: 0.45))
        : C.border.withValues(alpha: 0.35);

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
      bottomRight: isMe ? Radius.zero : const Radius.circular(18),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
        top: 3,
        bottom: 3,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: SlideUpFade(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: IntrinsicWidth(
              child: GestureDetector(
                onLongPress: () => _onMessageLongPress(msg),
                child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isMe
                        ? [myBubbleStart, myBubbleEnd]
                        : [theirBubbleStart, theirBubbleEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: borderRadius,
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: isMe
                      ? [
                          BoxShadow(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (msg.type == 'image' && msg.imageUrl != null)
                      GestureDetector(
                        onTap: () => _viewFullScreenImage(msg.imageUrl!),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: C.border.withValues(alpha: 0.4)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(
                              msg.imageUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 120,
                                  color: C.bg2,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        color: C.accent, strokeWidth: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    if (msg.type != 'image' || msg.message != '📷 Photo')
                      Text(
                        msg.message,
                        style: TextStyle(
                          color: isMe ? Colors.white : C.textPrimary,
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            color:
                                isMe ? Colors.white.withValues(alpha: 0.65) : C.textMuted,
                            fontSize: 9.5,
                          ),
                        ),
                        const SizedBox(width: 5),
                        if (isMe) ...[
                          Icon(
                            msg.isRead ? Icons.done_all : Icons.done,
                            color: msg.isRead
                                ? const Color(0xFF86EFB8)
                                : Colors.white.withValues(alpha: 0.55),
                            size: 13,
                          ),
                        ] else ...[
                          Icon(
                            msg.isOfflineSms ? Icons.sms : Icons.wifi,
                            color: msg.isOfflineSms ? C.warning : C.accent,
                            size: 10,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final disabled = _myPhone.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: C.bg2,
        border: Border(
          top: BorderSide(color: C.border.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: C.bg3,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: C.border),
              ),
              child: TextField(
                controller: _inputCtrl,
                enabled: !disabled,
                style: TextStyle(color: C.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: disabled
                      ? 'Add phone in Profile to chat...'
                      : 'Type a message...',
                  hintStyle: TextStyle(color: C.textMuted, fontSize: 13),
                  // No inner borders — the rounded container draws the outline.
                  // (Stops the theme's red focused border from showing.)
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: disabled ? null : _sendText,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: disabled
                    ? null
                    : (_isOfflineMode
                        ? LinearGradient(
                            colors: [C.warning, C.warning.withValues(alpha: 0.7)])
                        : AppTheme.tealGradient),
                color: disabled ? C.bg3 : null,
              ),
              child: Center(
                child: Icon(
                  Icons.send_rounded,
                  color: disabled ? C.textPrimary : Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top toast: slides+fades in, holds ~1s, then slides+fades out and removes
/// itself. Used for quick, non-blocking chat feedback.
class _TopToast extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onDone;
  const _TopToast({
    required this.message,
    required this.icon,
    required this.color,
    required this.onDone,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero)
        .animate(_fade);
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: C.bg2,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: widget.color.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: widget.color, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(widget.message,
                          style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
