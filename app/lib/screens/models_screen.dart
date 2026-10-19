import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings → Models & providers (RESEARCH.md §6). Keys go to the server and are stored encrypted there.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

const roleInfo = <String, (String, String, IconData)>{
  'chat': ('Chat', 'Answers questions and writes Studio content. Required.', Icons.chat_bubble_outline),
  'vision': ('Vision', 'Reads images and scanned pages. Leave empty to reuse the chat model.', Icons.visibility_outlined),
  'embeddings': ('Embeddings', 'Finds relevant passages in large notebooks.', Icons.hub_outlined),
  'tts': ('Text to speech', 'Voices for Audio and Video Overviews (two hosts).', Icons.record_voice_over_outlined),
  'stt': ('Speech to text', 'Transcribes audio sources and voice questions.', Icons.mic_none_rounded),
  'image': ('Image generation', 'Infographics, slide decks and explainer visuals. Optional.', Icons.image_outlined),
  'video': ('Video generation', 'Cinematic video overviews. Optional, expensive.', Icons.movie_outlined),
  'realtime': ('Realtime voice', 'Interactive audio: join the hosts and talk. Optional.', Icons.graphic_eq_rounded),
};

class _ModelsScreenState extends State<ModelsScreen> {
  List<Map<String, dynamic>> _providers = [];
  Map<String, Map<String, dynamic>> _roles = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.I.get('/settings/providers'), Api.I.get('/settings/roles')]);
      setState(() {
        _providers = List<Map<String, dynamic>>.from(r[0]);
        _roles = {for (final x in r[1]) x['role'] as String: Map<String, dynamic>.from(x)};
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
    setState(() => _loading = false);
  }

  Future<void> _editProvider([Map<String, dynamic>? p]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _ProviderDialog(provider: p));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Scaffold(
      appBar: AppBar(title: const Text('Models & providers'), backgroundColor: v.bg, surfaceTintColor: Colors.transparent),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_error != null) ErrorBox(message: _error!, onRetry: _load),
                      Row(children: [
                        Text('Providers', style: vText(22, 28, color: v.textTitle)),
                        const Spacer(),
                        FilledButton.icon(
                            onPressed: () => _editProvider(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add provider')),
                      ]),
                      const SizedBox(height: 4),
                      Text('Any OpenAI-compatible base URL. Keys are encrypted on your Verlium server and never stored on this device.',
                          style: vText(14, 20, color: v.textMuted)),
                      const SizedBox(height: 12),
                      if (_providers.isEmpty)
                        _Hint(
                            text:
                                'Tip: Pollinations covers every role with one key. Base URL https://gen.pollinations.ai/v1, key from enter.pollinations.ai.'),
                      for (final p in _providers)
                        Card(
                          color: v.panel,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: const Icon(Icons.cloud_outlined),
                            title: Text(p['name']),
                            subtitle: Text('${p['base_url']}  ·  key ${p['api_key_hint'] ?? 'none'}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _editProvider(p)),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  if (await confirm(context,
                                      title: 'Delete provider?',
                                      body: 'Roles using "${p['name']}" will be cleared.',
                                      action: 'Delete')) {
                                    await Api.I.delete('/settings/providers/${p['id']}');
                                    _load();
                                  }
                                },
                              ),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text('Models', style: vText(22, 28, color: v.textTitle)),
                      const SizedBox(height: 12),
                      for (final role in roleInfo.keys)
                        _RoleCard(
                          key: ValueKey(role),
                          role: role,
                          config: _roles[role] ?? {},
                          providers: _providers,
                          onSaved: _load,
                        ),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.v.sourceGuide, borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: vText(14, 20)),
      );
}

class _ProviderDialog extends StatefulWidget {
  final Map<String, dynamic>? provider;
  const _ProviderDialog({this.provider});

  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  late final _name = TextEditingController(text: widget.provider?['name'] ?? 'Pollinations');
  late final _url = TextEditingController(text: widget.provider?['base_url'] ?? 'https://gen.pollinations.ai/v1');
  final _key = TextEditingController();
  String? _error;

  Future<void> _save() async {
    try {
      await Api.I.post('/settings/providers', {
        if (widget.provider != null) 'id': widget.provider!['id'],
        'name': _name.text.trim(),
        'base_url': _url.text.trim(),
        'adapter': 'openai',
        // Empty key field while editing = keep the stored key.
        'api_key': widget.provider != null && _key.text.isEmpty ? null : _key.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.provider == null ? 'Add provider' : 'Edit provider'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'Base URL')),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API key',
                helperText: widget.provider != null ? 'Leave empty to keep the saved key' : null,
              ),
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: context.v.error)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

class _RoleCard extends StatefulWidget {
  final String role;
  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> providers;
  final VoidCallback onSaved;
  const _RoleCard({super.key, required this.role, required this.config, required this.providers, required this.onSaved});

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  String? _providerId;
  late final _model = TextEditingController(text: widget.config['model_id'] ?? '');
  late final Map<String, dynamic> _params = Map<String, dynamic>.from(widget.config['params'] ?? {});
  List<Map<String, dynamic>> _models = [];
  bool _fetching = false, _testing = false, _dirty = false;
  Map<String, dynamic>? _result;
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _providerId = widget.config['provider_id'];
    if (_providerId == null && widget.providers.isNotEmpty) _providerId = widget.providers.first['id'];
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    if (_providerId == null) return;
    setState(() => _fetching = true);
    try {
      final list = await Api.I.get('/settings/providers/$_providerId/models', {'role': widget.role}) as List;
      setState(() => _models = List<Map<String, dynamic>>.from(list));
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    setState(() => _fetching = false);
  }

  void _pick(Map<String, dynamic> m) {
    setState(() {
      _model.text = m['id'];
      _dirty = true;
      if (widget.role == 'chat' && m['context_length'] != null) _params['context_window'] = m['context_length'];
    });
  }

  Map<String, dynamic> get _body => {'provider_id': _providerId, 'model_id': _model.text.trim(), 'params': _params};

  Future<void> _save() async {
    await Api.I.put('/settings/roles/${widget.role}', _body);
    setState(() => _dirty = false);
    widget.onSaved();
    if (mounted) toast(context, '${roleInfo[widget.role]!.$1} model saved');
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final r = Map<String, dynamic>.from(await Api.I.post('/settings/roles/${widget.role}/test', _body));
      setState(() => _result = r);
      final audio = r['audio_b64'];
      if (audio is Map && audio.isNotEmpty) {
        await _player.play(BytesSource(base64Decode(audio.values.first as String)));
      }
    } catch (e) {
      setState(() => _result = {'ok': false, 'detail': e.toString()});
    }
    setState(() => _testing = false);
  }

  Widget _num(String key, String label, {int? hint}) => SizedBox(
        width: 180,
        child: TextFormField(
          initialValue: _params[key]?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, hintText: hint?.toString(), isDense: true),
          onChanged: (s) => setState(() {
            _dirty = true;
            final n = num.tryParse(s);
            n == null ? _params.remove(key) : _params[key] = n;
          }),
        ),
      );

  Widget _str(String key, String label, {String? hint}) => SizedBox(
        width: 180,
        child: TextFormField(
          initialValue: _params[key]?.toString() ?? '',
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
          onChanged: (s) => setState(() {
            _dirty = true;
            s.isEmpty ? _params.remove(key) : _params[key] = s;
          }),
        ),
      );

  List<Widget> _roleFields() => switch (widget.role) {
        'chat' => [
            _num('context_window', 'Context window (tokens)', hint: 128000),
            _num('max_tokens', 'Max output tokens', hint: 4096),
            _num('temperature', 'Temperature', hint: 1),
          ],
        'embeddings' => [_num('dimensions', 'Dimensions (optional)')],
        'tts' => [_str('voice_a', 'Host A voice', hint: 'onyx'), _str('voice_b', 'Host B voice', hint: 'nova')],
        'stt' => [_str('language', 'Language (optional)', hint: 'en')],
        'image' => [_str('size', 'Size', hint: '1024x1024')],
        'video' => [_num('duration', 'Duration (s)', hint: 5)],
        'realtime' => [_str('voice_a', 'Host A voice', hint: 'cedar'), _str('voice_b', 'Host B voice', hint: 'marin')],
        _ => [],
      };

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final (label, desc, icon) = roleInfo[widget.role]!;
    final ok = _result?['ok'] == true;
    final canTest = !['video', 'realtime'].contains(widget.role);
    return Card(
      color: v.panel,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: v.iconMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: vText(16, 22, weight: FontWeight.w500, color: v.textStrong)),
                Text(desc, style: vText(13, 18, color: v.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: widget.providers.any((p) => p['id'] == _providerId) ? _providerId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Provider', isDense: true),
                items: [
                  for (final p in widget.providers) DropdownMenuItem(value: p['id'] as String, child: Text(p['name'])),
                ],
                onChanged: (id) => setState(() {
                  _providerId = id;
                  _models = [];
                  _dirty = true;
                }),
              ),
            ),
            SizedBox(
              width: 320,
              child: Autocomplete<Map<String, dynamic>>(
                initialValue: TextEditingValue(text: _model.text),
                displayStringForOption: (m) => m['id'],
                optionsBuilder: (t) => _models.where((m) =>
                    (m['id'] as String).toLowerCase().contains(t.text.toLowerCase()) ||
                    (m['title'] ?? '').toString().toLowerCase().contains(t.text.toLowerCase())),
                onSelected: _pick,
                fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
                  controller: ctl,
                  focusNode: focus,
                  decoration: InputDecoration(
                    labelText: 'Model ID',
                    isDense: true,
                    // Voices/params alone don't configure a role; without a model it counts as "not set".
                    errorText: _providerId != null && ctl.text.trim().isEmpty ? 'Required: fetch ⤓ and pick a model' : null,
                    suffixIcon: IconButton(
                      tooltip: 'Fetch models',
                      icon: _fetching
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 20),
                      onPressed: _fetchModels,
                    ),
                  ),
                  onChanged: (s) => setState(() {
                    _model.text = s;
                    _dirty = true;
                  }),
                ),
              ),
            ),
            ..._roleFields(),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            if (canTest)
              OutlinedButton.icon(
                onPressed: _testing || _providerId == null || _model.text.isEmpty ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(widget.role == 'vision' ? 'Test vision' : 'Test'),
              ),
            const SizedBox(width: 8),
            FilledButton(
                onPressed: _dirty && (_providerId == null || _model.text.trim().isNotEmpty) ? _save : null,
                child: const Text('Save')),
            if (!canTest) ...[
              const SizedBox(width: 12),
              Text('Test arrives with the Studio phase', style: vText(12, 16, color: v.textMuted)),
            ],
          ]),
          if (_result != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: ok ? v.success : v.error),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? v.success : v.error, size: 18),
                  const SizedBox(width: 8),
                  Text(ok ? 'Passed' : 'Failed', style: TextStyle(color: ok ? v.success : v.error)),
                  if (_result!['latency_ms'] != null) Text('  ·  ${_result!['latency_ms']} ms'),
                  if (_result!['tokens_per_s'] != null) Text('  ·  ${_result!['tokens_per_s']} tok/s'),
                  if (_result!['dimensions'] != null) Text('  ·  ${_result!['dimensions']} dims'),
                ]),
                const SizedBox(height: 6),
                SelectableText(_result!['detail']?.toString() ?? '', style: vText(13, 18)),
                if (_result!['checks'] is Map)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 8, children: [
                      for (final e in (_result!['checks'] as Map).entries)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(e.value == true ? Icons.check : Icons.close, size: 16),
                          label: Text(e.key),
                        ),
                    ]),
                  ),
                if (_result!['image_b64'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(base64Decode(_result!['image_b64']), height: 160),
                    ),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
