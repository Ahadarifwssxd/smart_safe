import 'package:flutter/material.dart';

/// Responsive layout helpers.
///
/// The app is phone-first: on phones (< [tabletBreakpoint]) every helper here
/// is a no-op passthrough, so existing layouts are completely untouched. On
/// wider screens (tablets / foldables / desktop) content is centered with a
/// sensible max width so the UI doesn't stretch edge-to-edge and look empty.

/// Breakpoints (in logical pixels / dp).
const double kPhoneMaxWidth = 600;
const double kTabletMaxWidth = 1024;

/// Above this width we start centering scrollable content. Kept a little above
/// the 600dp tablet line so large phones/foldables in portrait stay full width.
const double kCenterContentBreakpoint = 700;

/// Default max width for centered scrollable content.
const double kMaxContentWidth = 600;

/// True when the screen is at least tablet-sized.
bool isTablet(BuildContext context) =>
    MediaQuery.of(context).size.width >= kPhoneMaxWidth;

/// True for large tablets / desktop.
bool isLargeScreen(BuildContext context) =>
    MediaQuery.of(context).size.width >= kTabletMaxWidth;

/// Centers [child] within a [maxWidth]-wide column on screens wider than
/// [breakpoint]; on phones it returns the child unchanged (full width).
///
/// Wrap the MAIN scrollable body of content pages with this. It is safe to wrap
/// a scroll view directly — the constraint applies to the content, and the
/// scroll view still fills the height.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double breakpoint;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = kMaxContentWidth,
    this.breakpoint = kCenterContentBreakpoint,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width <= breakpoint) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Returns scroll-view padding that keeps content within [maxWidth] and
/// centered on wide screens, while behaving exactly like
/// `EdgeInsets.symmetric(horizontal:, vertical:)` on phones.
///
/// Use this on the MAIN scrollable body of pages where wrapping the scroll
/// view in [ResponsiveCenter] is awkward (e.g. deeply-nested layouts). It
/// achieves the same tablet centering with a single-line edit.
EdgeInsets responsiveScrollPadding(
  BuildContext context, {
  double horizontal = 20,
  double vertical = 16,
  double maxWidth = kMaxContentWidth,
}) {
  final width = MediaQuery.of(context).size.width;
  if (width <= kCenterContentBreakpoint) {
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }
  final side = ((width - maxWidth) / 2).clamp(horizontal, double.infinity);
  return EdgeInsets.only(
    left: side.toDouble(),
    right: side.toDouble(),
    top: vertical,
    bottom: vertical,
  );
}

/// Returns the horizontal side inset needed to keep content within [maxWidth]
/// and centered on wide screens; equals [base] on phones. Use with
/// `EdgeInsets.fromLTRB` when top/bottom padding differ.
double responsiveHInset(
  BuildContext context, {
  double base = 20,
  double maxWidth = kMaxContentWidth,
}) {
  final width = MediaQuery.of(context).size.width;
  if (width <= kCenterContentBreakpoint) return base;
  return ((width - maxWidth) / 2).clamp(base, double.infinity).toDouble();
}

/// Picks an adaptive column count for grids based on the available [width].
///
/// Defaults roughly double the column count on tablets while staying
/// conservative. Pass the values that make sense for the specific grid.
int responsiveColumns(
  double width, {
  int phone = 2,
  int tablet = 3,
  int large = 4,
}) {
  if (width >= kTabletMaxWidth) return large;
  if (width >= kPhoneMaxWidth) return tablet;
  return phone;
}
