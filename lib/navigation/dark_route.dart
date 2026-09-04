import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/design_tokens.dart';

/// Push a new screen with a premium slide-up + fade transition.
Route<T> darkRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: true,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final slide = Tween<Offset>(
        begin: const Offset(0.0, 0.08),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));

      return Stack(
        children: [
          Container(color: C.bg),
          FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: child,
            ),
          ),
        ],
      );
    },
    transitionDuration: DesignTokens.durationNormal,
  );
}
