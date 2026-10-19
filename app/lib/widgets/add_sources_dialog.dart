import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state/notebook_store.dart';
import '../theme.dart';
import 'common.dart';

const supportedExt = ['pdf', 'txt', 'md', 'markdown', 'csv', 'json'];

Future<void> showAddSources(BuildContext context, NotebookStore store) =>
    showDialog(context: context, builder: (_) => AddSourcesDialog(store: store));

/// Add sources dialog (UI-SPEC §3.3): 700 wide, pills, drop zone, Websites and Copied text sub-views.
class AddSourcesDialog extends StatefulWidget {
  final NotebookStore store;
  const AddSourcesDialog({super.key, required this.store});

  @override
  State<AddSourcesDialog> createState() => _AddSourcesDialogState();
}

enum _View { main, links, text }

class _AddSourcesDialogState extends State<AddSourcesDialog> {
  _View _view = _View.main;
  bool _drag = false, _busy = false;
  final _links = TextEditingController();
  final _text = TextEditingController();
  String? _error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: supportedExt);
    if (files.isEmpty) return;
    await _run(() async {
      for (final f in files) {
        await widget.store.uploadFile(f.name, await f.readAsBytes());
      }
    });
  }

  Future<void> _dropped(DropDoneDetails d) async {
    await _run(() async {
      for (final f in d.files) {
        final ext = f.name.split('.').last.toLowerCase();
        if (!supportedExt.contains(ext)) throw Exception('Unsupported file type: .$ext');
        await widget.store.uploadFile(f.name, await f.readAsBytes());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (_view != _View.main)
                IconButton(onPressed: () => setState(() => _view = _View.main), icon: const Icon(Icons.arrow_back)),
              Expanded(
                child: _view == _View.main
                    ? Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Create Audio and Video Overviews from\n'),
                        TextSpan(text: 'your documents', style: TextStyle(color: v.link)),
                      ]), style: vText(24, 32, color: v.textTitle))
                    : Text(_view == _View.links ? 'Website and YouTube URLs' : 'Paste copied text',
                        style: vText(20, 24, weight: FontWeight.w500, color: v.textTitle)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 20),
            if (_view == _View.main) ...[
              DropTarget(
                onDragEntered: (_) => setState(() => _drag = true),
                onDragExited: (_) => setState(() => _drag = false),
                onDragDone: (d) {
                  setState(() => _drag = false);
                  _dropped(d);
                },
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _busy ? null : _pickFiles,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: _drag ? const Color(0x14C3CAFF) : null,
                      border: Border.all(color: v.outline, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.upload_file_outlined, size: 32, color: v.iconMuted),
                      const SizedBox(height: 12),
                      Text('Drag & drop your files to upload', style: vText(16, 24, color: v.textStrong)),
                      const SizedBox(height: 4),
                      Text('Supported file types: ${supportedExt.join(', ')}', style: vText(13, 18, color: v.textMuted)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _pill(Icons.upload_rounded, 'Upload files', _busy ? null : _pickFiles),
                _pill(Icons.link_rounded, 'Websites', () => setState(() => _view = _View.links)),
                _pill(Icons.content_paste_rounded, 'Copied text', () => setState(() => _view = _View.text)),
              ]),
            ],
            if (_view == _View.links) ...[
              TextField(
                controller: _links,
                autofocus: true,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Paste any links'),
              ),
              const SizedBox(height: 12),
              for (final rule in const [
                'To add multiple URLs, separate them with a space or a new line.',
                'Only the visible text on the website will be imported.',
                'Paid articles are not supported.',
                'Only the text transcript of YouTube videos is imported for now.',
                'Only public YouTube videos are supported.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('•  $rule', style: vText(13, 18, color: v.textMuted)),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.store.addLinks(
                          _links.text.split(RegExp(r'\s+')).where((s) => s.startsWith('http')).toList())),
                  child: const Text('Insert'),
                ),
              ),
            ],
            if (_view == _View.text) ...[
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(hintText: 'Paste text here'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : () => _run(() => widget.store.addText(_text.text)),
                  child: const Text('Insert'),
                ),
              ),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_error != null) ErrorBox(message: _error!),
          ]),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, VoidCallback? onTap) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
