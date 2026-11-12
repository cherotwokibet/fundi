import 'package:flutter/material.dart';

import '../models/service_provider.dart';
import 'theme.dart';

enum ButtonKind { lime, forest, tint, outline }

/// The app's big button. One lime button per screen: the main action.
/// It grows with its text, so large text never spills out.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.lime,
    this.icon,
    this.trailingIcon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, side) = switch (kind) {
      ButtonKind.lime => (lime, forest, BorderSide.none),
      ButtonKind.forest => (forest, Colors.white, BorderSide.none),
      ButtonKind.tint => (tint, ink, const BorderSide(color: hairline)),
      ButtonKind.outline => (
        Colors.white,
        forest,
        const BorderSide(color: forest, width: 1.5),
      ),
    };
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.6),
        disabledForegroundColor: fg.withValues(alpha: 0.6),
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: side,
        ),
      ),
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 10),
                  Icon(trailingIcon, size: 20),
                ],
              ],
            ),
    );
  }
}

/// Status in words on a soft fill, with how fresh it is when we know.
/// Never colour alone: the words carry the meaning.
class StatusPill extends StatelessWidget {
  const StatusPill(this.availability, {super.key, this.setAt});
  final Availability availability;
  final DateTime? setAt;

  @override
  Widget build(BuildContext context) {
    final a = availability;
    final fresh = a == Availability.available || a == Availability.busy;
    final ago = fresh ? agoText(setAt) : '';
    final text = ago.isEmpty ? a.label : '${a.label} · Updated $ago';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: a.pillFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a == Availability.available) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: a.pillText,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: a.pillText,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "✓ ID and experience checked"
class CheckedLine extends StatelessWidget {
  const CheckedLine(this.provider, {super.key});
  final ServiceProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.check, size: 18, color: Color(0xFF135C37)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            checkedText(provider),
            style: const TextStyle(fontSize: 14, color: ink),
          ),
        ),
      ],
    );
  }
}

/// Big screen title with one quiet line under it.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key, this.subtitle});
  final String title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: heading(32)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            style: const TextStyle(color: muted, fontSize: 15),
            child: subtitle!,
          ),
        ],
      ],
    );
  }
}
