import 'package:flutter/material.dart';
import 'package:smartsafe/theme/colors.dart';

/// Professional delete confirmation for admin dashboard.
Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? itemName,
  bool isFolder = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: C.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFolder ? Icons.folder_delete_rounded : Icons.delete_forever_rounded,
              color: C.accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: C.textMuted, fontSize: 14, height: 1.4)),
          if (itemName != null && itemName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.label_rounded, color: C.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      itemName,
                      style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'This action cannot be undone.',
            style: TextStyle(color: C.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: C.textMuted, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: C.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result == true;
}
