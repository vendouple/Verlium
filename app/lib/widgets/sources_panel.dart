import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/notebook_store.dart';
import '../theme.dart';
import 'add_sources_dialog.dart';
import 'common.dart';
import 'markdown.dart';

IconData sourceIcon(String kind) => switch (kind) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'youtube' => Icons.smart_display_outlined,
      'url' => Icons.language_rounded,
      'paste' => Icons.content_paste_rounded,
      'audio' => Icons.audio_file_outlined,
      'image' => Icons.image_outlined,
      _ => Icons.description_outlined,
    };

/// Sources panel (UI-SPEC §3.2): list with checkboxes, or the source viewer when one is open.
class SourcesPanel extends StatelessWidget {
  final NotebookStore store;
  final bool collapsed;
  final VoidCallback? onToggle;
  final VoidCallback? onAsk; // mobile: switch to the chat tab after asking from a topic chip
  const SourcesPanel({super.key, required this.store, this.collapsed = false, this.onToggle, this.onAsk});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    if (collapsed) {
      return PanelCard(
        child: Column(children: [
          IconButton(tooltip: 'Expand sources', onPressed: onToggle, icon: const Icon(Icons.view_sidebar_outlined)),
          IconButton(tooltip: 'Add sources', onPressed: () => showAddSources(context, store), icon: const Icon(Icons.add)),
        ]),
      );
    }
    if (store.openSource != null) return PanelCard(child: _SourceViewer(store: store, onAsk: onAsk));

    final all = store.sources;
    final allSelected = all.isNotEmpty && all.every((s) => s.selected);
    return PanelCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelHeader(title: 'Sources', actions: [
          if (onToggle != null)
            IconButton(tooltip: 'Collapse', onPressed: onToggle, icon: Icon(Icons.view_sidebar_outlined, color: v.iconMuted)),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: v.tonal, foregroundColor: v.textStrong, minimumSize: const Size.fromHeight(40)),
            onPressed: () => showAddSources(context, store),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add sources'),
          ),
        ),
        const SizedBox(height: 8),
        if (all.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.description_outlined, size: 40, color: v.iconMuted),
                const SizedBox(height: 16),
                Text('Saved sources will appear here',
                    textAlign: TextAlign.center, style: vText(15, 20, weight: FontWeight.w500, color: v.textStrong)),
                const SizedBox(height: 8),
                Text('Add files, websites, or more. Then ask questions or create things based on these sources.',
                    textAlign: TextAlign.center, style: vText(14, 20, color: v.textMuted)),
              ]),
            ),
          )
        else ...[
          SizedBox(
            height: 36,
            child: Row(children: [
              const SizedBox(width: 12),
              Expanded(child: Text('Select all sources', style: vText(14, 20, color: v.textMuted))),
              Checkbox(value: allSelected, onChanged: (b) => store.selectAll(b ?? false)),
            ]),
          ),
          Expanded(
            child: ListView(children: [for (final s in all) _SourceRow(store: store, source: s)]),
          ),
        ],
      ]),
    );
  }
}

class _SourceRow extends StatefulWidget {
  final NotebookStore store;
  final Source source;
  const _SourceRow({required this.store, required this.source});

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  // The menu covers the row, which ends the hover; keep the button mounted while it's open or the
  // selection is dropped (PopupMenuButton ignores results once unmounted).
  bool _hover = false, _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final s = widget.source;
    final failed = s.status == 'error';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: s.status == 'ready' ? () => widget.store.showSource(s.id) : null,
        child: SizedBox(
          height: 36,
          child: Row(children: [
            SizedBox(
              width: 40,
              child: _hover || _menuOpen
                  ? PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      icon: Icon(Icons.more_vert, color: v.iconMuted),
                      onOpened: () => setState(() => _menuOpen = true),
                      onCanceled: () => setState(() => _menuOpen = false),
                      onSelected: (a) async {
                        setState(() => _menuOpen = false);
                        if (a == 'remove') widget.store.removeSource(s);
                        if (a == 'retry') widget.store.retrySource(s);
                        if (a == 'rename') {
                          final t = await promptText(context, title: 'Rename source', initial: s.title);
                          if (t != null && t.trim().isNotEmpty) widget.store.renameSource(s, t.trim());
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'remove', child: MenuRow(Icons.delete_outline, 'Remove source')),
                        const PopupMenuItem(value: 'rename', child: MenuRow(Icons.edit_outlined, 'Rename source')),
                        if (failed) const PopupMenuItem(value: 'retry', child: MenuRow(Icons.refresh, 'Retry')),
                      ],
                    )
                  : Icon(failed ? Icons.error_outline : sourceIcon(s.kind),
                      size: 20, color: failed ? v.error : v.iconMuted),
            ),
            Expanded(
              child: Tooltip(
                message: failed ? (s.error ?? 'Failed') : s.title,
                waitDuration: const Duration(milliseconds: 600),
                child: Text(s.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(14, 24, color: v.textStrong)),
              ),
            ),
            SizedBox(
              width: 40,
              child: s.busy
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Checkbox(value: s.selected && !failed, onChanged: failed ? null : (b) => widget.store.toggleSource(s, b ?? false)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SourceViewer extends StatefulWidget {
  final NotebookStore store;
  final VoidCallback? onAsk;
  const _SourceViewer({required this.store, this.onAsk});

  @override
  State<_SourceViewer> createState() => _SourceViewerState();
}

class _SourceViewerState extends State<_SourceViewer> {
  bool _guideOpen = true;
  final _hlKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _SourceViewer old) {
    super.didUpdateWidget(old);
    _scrollToHighlight();
  }

  @override
  void initState() {
    super.initState();
    _scrollToHighlight();
  }

  void _scrollToHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _hlKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .2, duration: const Duration(milliseconds: 300));
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final s = widget.store.openSource!;
    final text = s.content ?? '';
    final hl = widget.store.highlight;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelHeader(
        title: 'Sources',
        leading: IconButton(onPressed: widget.store.closeSource, icon: const Icon(Icons.arrow_back)),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.title, style: vText(22, 30, color: v.textTitle)),
            const SizedBox(height: 12),
            if (s.summary != null)
              Container(
                decoration: BoxDecoration(color: v.sourceGuide, borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () => setState(() => _guideOpen = !_guideOpen),
                    child: Row(children: [
                      const Icon(Icons.auto_awesome, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Source guide', style: vText(14, 20, weight: FontWeight.w500))),
                      Icon(_guideOpen ? Icons.expand_less : Icons.expand_more),
                    ]),
                  ),
                  if (_guideOpen) ...[
                    const SizedBox(height: 8),
                    VMarkdown(data: s.summary!, fontSize: 14, lineHeight: 22),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in s.keyTopics)
                        ActionChip(
                          label: Text(t, style: vText(13, 18)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          onPressed: () {
                            widget.store.ask('Discuss what these sources say about $t');
                            widget.onAsk?.call();
                          },
                        ),
                    ]),
                  ],
                ]),
              ),
            const SizedBox(height: 16),
            if (hl != null && hl.end <= text.length)
              SelectableText.rich(TextSpan(style: vText(14, 24, color: v.text), children: [
                TextSpan(text: text.substring(0, hl.start)),
                WidgetSpan(child: SizedBox(key: _hlKey, width: 0, height: 0)),
                TextSpan(
                  text: text.substring(hl.start, hl.end),
                  style: TextStyle(backgroundColor: v.primary.withValues(alpha: .35), color: v.textTitle),
                ),
                TextSpan(text: text.substring(hl.end)),
              ]))
            else
              SelectableText(text, style: vText(14, 24, color: v.text)),
          ]),
        ),
      ),
    ]);
  }
}
