import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Star-rating + optional message feedback, like other apps. Saves to the
/// Firestore `app_feedback` collection so the admin dashboard can list ratings.
Future<void> showFeedbackSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.bg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _FeedbackSheet(),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();
  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  int _rating = 0;
  final _msg = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      _snack('Please tap a star to rate first');
      return;
    }
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('app_feedback').add({
        'userId': user?.uid ?? '',
        'name': user?.displayName ?? '',
        'email': user?.email ?? '',
        'rating': _rating,
        'message': _msg.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        _snack('Thank you for your feedback!', ok: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not send feedback. Check your connection.');
      }
    }
  }

  void _snack(String m, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? C.success : C.accent,
      content: Text(m, style: TextStyle(color: C.textPrimary)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: C.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Rate SmartSafe',
              style: TextStyle(
                  color: C.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('How is your experience so far?',
              style: TextStyle(color: C.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          // Stars
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  onTap: () => setState(() => _rating = i + 1),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled ? C.warning : C.textMuted,
                      size: 40,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _msg,
            style: TextStyle(color: C.textPrimary),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Tell us more (optional)…',
              hintStyle: TextStyle(color: C.textMuted),
              filled: true,
              fillColor: C.bg3,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: C.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: C.border),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _saving ? null : _submit,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _saving ? C.textDim : C.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Submit feedback',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
