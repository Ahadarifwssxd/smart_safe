import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/theme/colors.dart';

/// Screen title (+ optional icon / subtitle) with optional trailing actions.
///
/// Layout-only helper used by every dashboard screen:
///  * tablet / desktop — title on the left, actions on the right (unchanged look)
///  * mobile           — actions drop below the title so the row can never
///                       overflow and the title is never squeezed to nothing
///
/// Actions are laid out in a [Wrap] so several buttons still fit on any width.
class PageHeaderBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final List<Widget> actions;

  const PageHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: C.textPrimary,
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: TextStyle(color: C.textMuted, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    final titleRow = Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor ?? C.accent, size: 26),
          const SizedBox(width: 12),
        ],
        Expanded(child: titleBlock),
      ],
    );

    if (actions.isEmpty) return titleRow;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow,
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleRow),
        const SizedBox(width: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    );
  }
}

/// Comfortable [DataTable.columnSpacing] for the current width — tighter on
/// phones so horizontally-scrolling tables need less panning.
double dataTableColumnSpacing(BuildContext context) =>
    Responsive.isMobile(context) ? 12.0 : 16.0;
