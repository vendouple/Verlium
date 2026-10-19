import 'package:flutter/material.dart';

import '../theme.dart';

class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const MenuRow(this.icon, this.label, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: context.v.iconMuted),
        const SizedBox(width: 12),
        Text(label, style: vText(14, 20)),
      ]);
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorBox({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.error_outline, color: context.v.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: context.v.error))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

Future<String?> promptText(BuildContext context,
    {required String title, String initial = '', String label = '', int maxLines = 1, String action = 'Save'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(c, v) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(action)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, required String body, String action = 'OK'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// Rounded side panel surface (UI-SPEC §2.2: bg panel, radius 32, padding 8).
class PanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PanelCard({super.key, required this.child, this.padding = const EdgeInsets.all(8)});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: context.v.panel, borderRadius: BorderRadius.circular(32)),
        padding: padding,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// "Sources  [⇤]" style panel header.
class PanelHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final List<Widget> actions;
  const PanelHeader({super.key, required this.title, this.leading, this.actions = const []});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Row(children: [
          const SizedBox(width: 8),
          if (leading != null) leading!,
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: vText(15, 20, weight: FontWeight.w500, color: context.v.textStrong)),
          ),
          ...actions,
        ]),
      );
}

String relTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
