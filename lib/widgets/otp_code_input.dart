import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

/// Six separate boxes for OTP — responsive, fits any screen size.
class OtpCodeInput extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final ValueChanged<String>? onCompleted;

  const OtpCodeInput({
    super.key,
    required this.controllers,
    required this.focusNodes,
    this.onCompleted,
  });

  void _onChanged(int index, String value, List<TextEditingController> ctrls, List<FocusNode> nodes) {
    final digits = value.replaceAll(RegExp(r'\D'), '');

    // Paste / SMS-autofill: a full (or partial) code lands in one box → spread.
    if (digits.length > 1) {
      for (int i = 0; i < ctrls.length; i++) {
        final ch = i < digits.length ? digits[i] : '';
        ctrls[i].text = ch;
        ctrls[i].selection = TextSelection.collapsed(offset: ch.length);
      }
      final filled = (digits.length.clamp(1, 6)) - 1;
      nodes[filled].requestFocus();
      _emitIfComplete(ctrls);
      return;
    }

    // Single digit typing — force exactly ONE digit per box so the joined
    // code is never longer than 6 (this caused "invalid" before).
    final single = digits.isEmpty ? '' : digits.characters.last;
    if (ctrls[index].text != single) {
      ctrls[index].text = single;
      ctrls[index].selection = TextSelection.collapsed(offset: single.length);
    }

    if (single.isNotEmpty && index < 5) {
      nodes[index + 1].requestFocus();
    } else if (single.isEmpty && index > 0) {
      nodes[index - 1].requestFocus();
    }
    _emitIfComplete(ctrls);
  }

  void _emitIfComplete(List<TextEditingController> ctrls) {
    final code = ctrls.map((c) => c.text).join();
    if (code.length == 6) onCompleted?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: total 6 boxes + 5 gaps. Leave 0px margin (parent has 28px padding each side).
        final availableWidth = constraints.maxWidth;
        const gapCount = 5;
        const gapSize = 8.0;
        final boxWidth = ((availableWidth - (gapSize * gapCount)) / 6).clamp(28.0, 60.0);
        final boxHeight = (boxWidth * 1.25).clamp(50.0, 75.0);
        final fontSize = (boxWidth * 0.55).clamp(22.0, 32.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Row(
              children: [
                SizedBox(
                  width: boxWidth,
                  height: boxHeight,
                  child: TextField(
                    controller: controllers[i],
                    focusNode: focusNodes[i],
                    maxLength: 6, // Allow 6 for paste-handling
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    cursorColor: C.accent,
                    style: TextStyle(
                      color: C.textPrimary,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: C.bg2,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: C.textDim),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: C.textDim),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: C.accent, width: 2),
                      ),
                    ),
                    onChanged: (v) => _onChanged(i, v, controllers, focusNodes),
                  ),
                ),
                if (i < 5) const SizedBox(width: gapSize),
              ],
            );
          }),
        );
      },
    );
  }
}
