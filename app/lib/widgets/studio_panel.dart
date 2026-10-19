import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/notebook_store.dart';
import '../theme.dart';
import 'common.dart';
import 'studio_dialogs.dart';
import 'studio_viewers.dart';

/// Studio panel (UI-SPEC §3.5): 9 tiles, output list (notes for now), floating "Add note", note editor.
class StudioPanel extends StatelessWidget {
  final NotebookStore store;
  final bool collapsed;
  final VoidCallback? onToggle;
  const StudioPanel({super.key, required this.store, this.collapsed = false, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    if (collapsed) {
      return PanelCard(
        child: Column(children: [
          IconButton(tooltip: 'Expand studio', onPressed: onToggle, icon: const Icon(Icons.view_sidebar_outlined)),
          for (final t in StudioType.values)
            IconButton(
                tooltip: t.label,
                onPressed: () => showStudioDialog(context, store, t),
                icon: Icon(t.icon, color: t.tint(context))),
        ]),
      );
    }
    if (store.openNote != null) return PanelCard(child: _NoteEditor(store: store, note: store.openNote!));
    if (store.openOutput != null) {
      return PanelCard(child: StudioViewer(key: ValueKey(store.openOutput!.id), store: store, output: store.openOutput!));
    }

    // Outputs and notes share one list, newest first (UI-SPEC §3.5).
    final items = <(DateTime, Widget)>[
      for (final o in store.outputs) (o.createdAt ?? DateTime.now(), _OutputItem(store: store, output: o)),
      for (final n in store.notes) (n.updatedAt ?? DateTime.now(), _NoteItem(store: store, note: n)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    return PanelCard(
      child: Stack(children: [
        CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: PanelHeader(title: 'Studio', actions: [
              if (onToggle != null)
                IconButton(
                    tooltip: 'Collapse', onPressed: onToggle, icon: Icon(Icons.view_sidebar_outlined, color: v.iconMuted)),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.9,
              children: [
                for (final t in StudioType.values) _Tile(type: t, onTap: () => showStudioDialog(context, store, t))
              ],
            ),
          ),
          SliverToBoxAdapter(child: Divider(height: 24, indent: 8, endIndent: 8, color: v.divider)),
          if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 96),
                child: Column(children: [
                  Icon(Icons.auto_awesome_outlined, color: v.iconMuted),
                  const SizedBox(height: 12),
                  Text('Studio output will be saved here.',
                      textAlign: TextAlign.center, style: vText(14, 20, weight: FontWeight.w500, color: v.textStrong)),
                  const SizedBox(height: 6),
                  Text('After adding sources, click to add Audio Overview, Study Guide, Mind Map, and more!',
                      textAlign: TextAlign.center, style: vText(13, 18, color: v.textMuted)),
                ]),
              ),
            )
          else
            SliverList.list(children: [
              for (final i in items) i.$2,
              const SizedBox(height: 80),
            ]),
        ]),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: v.textStrong,
                foregroundColor: v.bg,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () async => store.showNote(await store.createNote()),
              icon: const Icon(Icons.sticky_note_2_outlined, size: 20),
              label: const Text('Add note'),
            ),
          ),
        ),
      ]),
    );
  }
}

class _OutputItem extends StatelessWidget {
  final NotebookStore store;
  final StudioOutput output;
  const _OutputItem({required this.store, required this.output});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final t = studioTypeOf(output.type);
    final failed = output.status == 'error';
    final n = output.sourceIds.length;
    final meta = output.busy
        ? 'based on $n source${n == 1 ? '' : 's'}${output.type == 'audio' ? ' · Come back in a few minutes' : ''}'
        : failed
            ? (output.error ?? 'Failed')
            : '${t.label} · $n source${n == 1 ? '' : 's'} · ${relTime(output.createdAt)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: output.status == 'ready' ? () => store.showOutput(output) : null,
          child: SizedBox(
            height: 60,
            child: Row(children: [
              const SizedBox(width: 12),
              output.busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, value: output.progress > 5 ? output.progress / 100 : null, color: t.tint(context)))
                  : Icon(failed ? Icons.error_outline : t.icon, size: 20, color: failed ? v.error : t.tint(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(output.busy ? 'Generating ${t.label}...' : output.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(13, 17, color: v.textStrong)),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: vText(12, 16, color: failed ? v.error : v.textMuted)),
                ]),
              ),
              if (output.unread && output.status == 'ready')
                Container(width: 8, height: 8, decoration: BoxDecoration(color: v.unreadDot, shape: BoxShape.circle)),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: v.iconMuted, size: 20),
                onSelected: (a) async {
                  if (a == 'delete') store.deleteOutput(output);
                  if (a == 'retry') store.retryOutput(output);
                  if (a == 'rename') {
                    final title = await promptText(context, title: 'Rename', initial: output.title);
                    if (title != null && title.trim().isNotEmpty) store.renameOutput(output, title.trim());
                  }
                },
                itemBuilder: (_) => [
                  if (!output.busy) const PopupMenuItem(value: 'rename', child: MenuRow(Icons.edit_outlined, 'Rename')),
                  if (failed || output.status == 'ready')
                    const PopupMenuItem(value: 'retry', child: MenuRow(Icons.refresh, 'Re-run')),
                  const PopupMenuItem(value: 'delete', child: MenuRow(Icons.delete_outline, 'Delete')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final StudioType type;
  final VoidCallback onTap;
  const _Tile({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Material(
      color: v.tonal,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(type.icon, size: 20, color: type.tint(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(type.label,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: vText(13, 17, color: v.textStrong)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NoteItem extends StatelessWidget {
  final NotebookStore store;
  final Note note;
  const _NoteItem({required this.store, required this.note});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => store.showNote(note),
          child: SizedBox(
            height: 60,
            child: Row(children: [
              const SizedBox(width: 12),
              Icon(note.kind == 'saved_response' ? Icons.push_pin_outlined : Icons.article_outlined,
                  size: 20, color: v.textStrong),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(13, 17, color: v.textStrong)),
                  const SizedBox(height: 2),
                  Text('${note.kind == 'saved_response' ? 'Saved response' : 'Note'} · ${relTime(note.updatedAt)}',
                      style: vText(12, 16, color: v.textMuted)),
                ]),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: v.iconMuted, size: 20),
                onSelected: (a) {
                  if (a == 'delete') store.deleteNote(note);
                  if (a == 'source') _convert(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'source', child: MenuRow(Icons.description_outlined, 'Convert to source')),
                  PopupMenuItem(value: 'delete', child: MenuRow(Icons.delete_outline, 'Delete')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _convert(BuildContext context) async {
    await store.addText(note.content, title: note.title);
    if (context.mounted) toast(context, 'Added "${note.title}" as a source');
  }
}

class _NoteEditor extends StatefulWidget {
  final NotebookStore store;
  final Note note;
  const _NoteEditor({required this.store, required this.note});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _title = TextEditingController(text: widget.note.title);
  late final _body = TextEditingController(text: widget.note.content);
  bool _dirty = false;

  Future<void> _save() async {
    if (!_dirty) return;
    try {
      await widget.store.saveNote(widget.note, title: _title.text, content: _body.text);
      _dirty = false;
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 48,
        child: Row(children: [
          TextButton(
            onPressed: () async {
              await _save();
              widget.store.showNote(null);
            },
            child: Text('Studio  ›  Note', style: vText(14, 20, color: v.textMuted)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => widget.store.deleteNote(widget.note),
            icon: Icon(Icons.delete_outline, color: v.iconMuted),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () async {
              await _save();
              widget.store.showNote(null);
            },
            icon: Icon(Icons.close_fullscreen_rounded, color: v.iconMuted),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: _title,
          style: vText(22, 36, color: v.textTitle),
          decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none),
          onChanged: (_) => _dirty = true,
          onEditingComplete: _save,
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Focus(
            onFocusChange: (f) => f ? null : _save(),
            child: TextField(
              controller: _body,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: vText(15, 24),
              decoration: const InputDecoration(
                  hintText: 'Write your note (Markdown supported)',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none),
              onChanged: (_) => _dirty = true,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              await _save();
              await widget.store.addText(_body.text, title: _title.text);
              if (context.mounted) toast(context, 'Converted to source');
            },
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Convert to source'),
          ),
          const Spacer(),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      ),
    ]);
  }
}
