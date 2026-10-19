import 'package:flutter/material.dart';

import '../state/notebook_store.dart';
import '../theme.dart';

Future<void> showConfigureChat(BuildContext context, NotebookStore store) =>
    showDialog(context: context, builder: (_) => _ConfigureChatDialog(store: store));

/// Configure Chat (UI-SPEC §3.4): goal Default / Learning Guide / Custom (10,000 chars) + response length.
class _ConfigureChatDialog extends StatefulWidget {
  final NotebookStore store;
  const _ConfigureChatDialog({required this.store});

  @override
  State<_ConfigureChatDialog> createState() => _ConfigureChatDialogState();
}

class _ConfigureChatDialogState extends State<_ConfigureChatDialog> {
  late final cfg = widget.store.notebook!.chatConfig;
  late String _goal = cfg['goal'] ?? 'default';
  late String _length = cfg['length'] ?? 'default';
  late final _custom = TextEditingController(text: cfg['custom_prompt'] ?? '');

  static const goals = {
    'default': ('Default', 'Best for general purpose research and brainstorming tasks.'),
    'learning_guide': ('Learning Guide', 'Best for educational content, helping you grasp new concepts and skills efficiently.'),
    'custom': ('Custom', 'Write your own instructions for how the chat should behave.'),
  };

  Widget _segment<T>(T value, Map<T, String> options, ValueChanged<T> onChanged) => SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.tune_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text('Configure Chat', style: vText(20, 24, weight: FontWeight.w500, color: v.textTitle))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            Text('Notebooks can be customized to help you achieve different goals.',
                style: vText(14, 20, color: v.textMuted)),
            const SizedBox(height: 20),
            Text('Define your conversational goal, style, or role',
                style: vText(16, 20, weight: FontWeight.w500, color: v.textStrong)),
            const SizedBox(height: 12),
            _segment(_goal, {for (final e in goals.entries) e.key: e.value.$1}, (g) => setState(() => _goal = g)),
            const SizedBox(height: 8),
            Text(goals[_goal]!.$2, style: vText(13, 18, color: v.textMuted)),
            if (_goal == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _custom,
                maxLength: 10000,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                    hintText: 'e.g. Act as a debate coach. Challenge my arguments using the sources.'),
              ),
            ],
            const SizedBox(height: 20),
            Text('Choose your response length', style: vText(16, 20, weight: FontWeight.w500, color: v.textStrong)),
            const SizedBox(height: 12),
            _segment(_length, const {'default': 'Default', 'longer': 'Longer', 'shorter': 'Shorter'},
                (l) => setState(() => _length = l)),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  await widget.store.setChatConfig({
                    'goal': _goal,
                    'length': _length,
                    if (_goal == 'custom') 'custom_prompt': _custom.text,
                  });
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
