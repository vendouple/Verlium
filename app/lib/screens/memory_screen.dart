import 'package:flutter/material.dart';

import '../api/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings → Personalisation: what Verlium remembers from past chats (like ChatGPT/Claude memory).
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool? _enabled;
  List<Map<String, dynamic>> _memories = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.get('/settings/memory') as Map<String, dynamic>;
      setState(() {
        _enabled = r['enabled'] == true;
        _memories = List<Map<String, dynamic>>.from(r['memories']);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Scaffold(
      appBar: AppBar(title: const Text('Personalisation'), backgroundColor: v.bg, surfaceTintColor: Colors.transparent),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_error != null) ErrorBox(message: _error!, onRetry: _load),
            Card(
              color: v.panel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: SwitchListTile(
                value: _enabled ?? true,
                onChanged: _enabled == null
                    ? null
                    : (b) async {
                        setState(() => _enabled = b);
                        await Api.I.put('/settings/memory', {'enabled': b});
                      },
                title: const Text('Personalise from past chats'),
                subtitle: const Text(
                    'When you start a new chat, Verlium recaps your previous one and remembers durable things about you '
                    '(goals, background, preferred style). Incognito chats are never used.'),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('Saved memories', style: vText(18, 24, color: v.textTitle)),
              const Spacer(),
              if (_memories.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    if (await confirm(context,
                        title: 'Clear all memories?', body: 'Verlium will forget everything it learned about you.', action: 'Clear')) {
                      await Api.I.delete('/settings/memory');
                      _load();
                    }
                  },
                  child: const Text('Clear all'),
                ),
            ]),
            const SizedBox(height: 8),
            if (_memories.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Nothing yet. Memories appear after you finish a chat and start a new one.',
                    textAlign: TextAlign.center, style: vText(14, 20, color: v.textMuted)),
              ),
            for (final m in _memories)
              Card(
                color: v.panel,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: Icon(Icons.person_outline, color: v.iconMuted),
                  title: Text(m['content'], style: vText(14, 20, color: v.textStrong)),
                  trailing: IconButton(
                    tooltip: 'Forget',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await Api.I.delete('/settings/memory/${m['id']}');
                      _load();
                    },
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
