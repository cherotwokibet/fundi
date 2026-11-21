import 'package:flutter/material.dart';

import '../models/service_provider.dart';
import 'theme.dart';

/// From this width up the app uses its desktop layouts.
const wideBreakpoint = 900.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// Keeps a screen's content at a readable width and centred on wide
/// windows. On a phone it changes nothing.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.max = 560});
  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}

/// Bottom sheets stay phone-sized on wide windows.
const sheetConstraints = BoxConstraints(maxWidth: 560);

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

/// A big action with an icon, a title, one line saying what happens, and an
/// arrow. Used for the two actions on the home screen.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// The lime tile: the one main action. Otherwise a quiet tint tile.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? lime : tint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: primary ? BorderSide.none : const BorderSide(color: hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: primary ? forest : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: primary ? lime : forest),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: forest,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: forest,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: forest),
              ],
            ),
          ),
        ),
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
