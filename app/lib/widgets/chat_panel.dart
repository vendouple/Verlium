import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../state/notebook_store.dart';
import '../theme.dart';
import 'add_sources_dialog.dart';
import 'chat_attachments.dart';
import 'common.dart';
import 'configure_chat_dialog.dart';
import 'markdown.dart';
import 'rich_content.dart';

/// Chat column (UI-SPEC §3.4) with ChatGPT/Claude-style threads, thinking, incognito and personalisation.
class ChatPanel extends StatefulWidget {
  final NotebookStore store;
  final bool compact;
  const ChatPanel({super.key, required this.store, this.compact = false});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  int _lastLen = 0, _lastCount = 0;
  bool _dropping = false;
  Timer? _dropTimer;

  /// Drag events keep arriving while something is dragged over the chat; if they stop without an
  /// exit/drop (e.g. a drag that started inside an embedded WebView), hide the overlay anyway.
  void _showDrop() {
    if (!_dropping) setState(() => _dropping = true);
    _dropTimer?.cancel();
    _dropTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _dropping = false);
    });
  }
  bool _stickToBottom = true;

  NotebookStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_autoScroll);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _stickToBottom = _scroll.position.maxScrollExtent - _scroll.offset < 120;
    });
    _focus.onKeyEvent = (node, e) {
      // Enter sends, Shift+Enter inserts a newline.
      if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _dropTimer?.cancel();
    store.removeListener(_autoScroll);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _autoScroll() {
    final len = store.messages.fold<int>(0, (a, m) => a + m.content.length + m.thinking.length);
    final count = store.messages.length;
    if (len == _lastLen && count == _lastCount) return;
    final newMessage = count != _lastCount; // a new question always jumps to the bottom
    _lastLen = len;
    _lastCount = count;
    if (!_stickToBottom && !newMessage) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? text]) {
    final q = text ?? _input.text;
    if ((q.trim().isEmpty && store.readyAttachments.isEmpty) || store.responding || store.attachmentsUploading) return;
    _stickToBottom = true;
    store.ask(q);
    _input.clear();
  }

  void _openCitation(Citation c) => store.showSource(c.sourceId, start: c.charStart, end: c.charEnd);

  Future<void> _saveToNote(String content, List<Citation> cites) async {
    final title = content.split('\n').first.replaceAll(RegExp(r'[#*\[\]\d]'), '').trim();
    await store.createNote(
      title: title.length > 60 ? '${title.substring(0, 60)}…' : title,
      content: content,
      kind: 'saved_response',
      citations: cites,
    );
    if (mounted) toast(context, 'Saved to notes');
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final hasSources = store.sources.isNotEmpty;
        return Column(
          children: [
            _ChatHeader(store: store, compact: widget.compact),
            if (store.incognito) const _IncognitoBanner(),
            Expanded(
              child: DropTarget(
                enable: hasSources,
                onDragEntered: (_) => _showDrop(),
                onDragUpdated: (_) => _showDrop(),
                onDragExited: (_) => setState(() => _dropping = false),
                onDragDone: (d) {
                  setState(() => _dropping = false);
                  if (d.files.isNotEmpty) attachDropped(context, store, d.files);
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: hasSources
                          ? _conversation(context)
                          : _ZeroState(onAdd: () => showAddSources(context, store)),
                    ),
                    if (_dropping)
                      Positioned.fill(
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: v.primary.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: v.primary, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, size: 40, color: v.primary),
                              const SizedBox(height: 8),
                              Text('Drop images or videos to attach', style: vText(15, 22, color: v.textStrong)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _QueryBox(controller: _input, focus: _focus, store: store, enabled: hasSources, onSend: _send),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                store.incognito
                    ? 'Incognito: this chat is not saved and not used to personalise Verlium.'
                    : 'Verlium can make mistakes, so double-check it.',
                style: vText(12, 16, color: v.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _conversation(BuildContext context) {
    final v = context.v;
    final nb = store.notebook!;
    final ready = store.sources.where((s) => s.status == 'ready').length;
    final fresh = store.messages.isEmpty;
    final items = <Widget>[
      const SizedBox(height: 16),
      if (fresh) ...[
        Text(nb.emoji ?? '📓', style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text(
          nb.title,
          style: vText(36, 44, weight: FontWeight.w300, color: v.textTitle),
        ),
        const SizedBox(height: 8),
        Text(
          '${store.sources.length} source${store.sources.length == 1 ? '' : 's'}'
          '${nb.createdAt != null ? ' · ${DateFormat('MMM d, y').format(nb.createdAt!)}' : ''}',
          style: vText(14, 20, color: v.textMuted),
        ),
        const SizedBox(height: 16),
        if (nb.summary != null) ...[
          VMarkdown(data: nb.summary!, fontSize: 15, lineHeight: 24),
          _Actions(onSave: () => _saveToNote(nb.summary!, const []), copyText: nb.summary!),
        ] else if (ready == 0)
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text('Reading your sources…', style: vText(15, 24, color: v.textMuted)),
            ],
          ),
        if (store.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final q in store.suggestions) _SuggestionCard(text: q, onTap: () => _send(q)),
        ],
      ],
    ];

    DateTime? prev;
    for (final m in store.messages) {
      if (prev == null || m.createdAt.difference(prev).inMinutes > 30) items.add(_DateSeparator(m.createdAt));
      prev = m.createdAt;
      items.add(m.role == 'user' ? _UserBubble(message: m, store: store, key: ValueKey(m.id)) : _answer(m));
    }
    items.add(const SizedBox(height: 24));

    return LayoutBuilder(
      builder: (context, c) {
        final pad = widget.compact ? 16.0 : ((c.maxWidth - 760) / 2).clamp(32.0, double.infinity);
        return SelectionArea(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.symmetric(horizontal: pad),
            children: items,
          ),
        );
      },
    );
  }

  Widget _answer(ChatMessage m) {
    final v = context.v;
    final thinkingNow = m.streaming && m.content.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.steps.isNotEmpty || m.thinking.isNotEmpty || thinkingNow)
            _ThoughtProcess(message: m, active: thinkingNow),
          if (m.content.isNotEmpty) RichContent(data: m.content, citations: m.citations, onCitation: _openCitation),
          if (m.streaming && m.content.isNotEmpty) const _Cursor(),
          if (m.error != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: v.error.withValues(alpha: .5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: v.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m.error!, style: TextStyle(color: v.error)),
                  ),
                ],
              ),
            ),
          if (!m.streaming && m.content.isNotEmpty)
            _Actions(onSave: () => _saveToNote(m.content, m.citations), copyText: m.content),
        ],
      ),
    );
  }
}

// ---- header: threads, new chat, incognito ---------------------------------------------

class _ChatHeader extends StatelessWidget {
  final NotebookStore store;
  final bool compact;
  const _ChatHeader({required this.store, required this.compact});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final current = store.threads.where((t) => t.id == store.threadId).firstOrNull;
    final title = store.incognito ? 'Incognito chat' : (current?.title ?? 'New chat');
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(width: compact ? 8 : 12),
          // Title takes the free space (left-aligned); the action icons sit flush right.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: 'Chat history',
                position: PopupMenuPosition.under,
                constraints: const BoxConstraints(minWidth: 300, maxWidth: 360, maxHeight: 480),
                onOpened: store.refreshThreads,
                onSelected: (id) => store.openThread(id),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 32,
                    child: Text('Chats in this notebook', style: vText(12, 16, color: v.textMuted)),
                  ),
                  if (store.threads.isEmpty)
                    PopupMenuItem<String>(enabled: false, child: Text('No saved chats yet', style: vText(14, 20))),
                  for (final t in store.threads)
                    PopupMenuItem<String>(
                      value: t.id,
                      child: _ThreadRow(store: store, thread: t, selected: t.id == store.threadId),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (store.incognito) ...[
                        Icon(Icons.visibility_off_outlined, size: 18, color: v.textStrong),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: vText(15, 20, weight: FontWeight.w500, color: v.textStrong),
                        ),
                      ),
                      Icon(Icons.expand_more_rounded, size: 20, color: v.iconMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _HeaderIcon(
            tooltip: store.incognito ? 'Leave incognito' : 'Incognito chat (not saved)',
            icon: Icons.visibility_off_outlined,
            active: store.incognito,
            onPressed: () => store.setIncognito(!store.incognito),
          ),
          _HeaderIcon(
            tooltip: 'New chat',
            icon: Icons.add_comment_outlined,
            onPressed: store.messages.isEmpty && !store.incognito ? null : () => store.newChat(),
          ),
          _ChatMenu(store: store),
          SizedBox(width: compact ? 4 : 8),
        ],
      ),
    );
  }
}

/// 36px header icon button (UI-SPEC §1.5): muted outline icon, tonal fill when active.
class _HeaderIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  const _HeaderIcon({required this.tooltip, required this.icon, this.active = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 20,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: active ? v.tonal : null,
        side: active ? BorderSide(color: v.outline) : null,
      ),
      icon: Icon(icon, color: active ? v.textTitle : v.iconMuted),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final NotebookStore store;
  final ChatThread thread;
  final bool selected;
  const _ThreadRow({required this.store, required this.thread, required this.selected});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Row(
      children: [
        Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline, size: 16, color: v.iconMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                thread.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: vText(14, 20, color: v.textStrong),
              ),
              Text(
                '${relTime(thread.updatedAt)} · ${thread.messageCount ~/ 2} turns',
                style: vText(12, 16, color: v.textMuted),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          iconSize: 18,
          icon: Icon(Icons.more_horiz, color: v.iconMuted),
          onSelected: (a) async {
            Navigator.of(context).pop(); // close the history menu
            if (a == 'rename') {
              final t = await promptText(context, title: 'Rename chat', initial: thread.title);
              if (t != null && t.trim().isNotEmpty) store.renameThread(thread, t.trim());
            } else if (a == 'delete') {
              store.deleteThread(thread);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: MenuRow(Icons.edit_outlined, 'Rename')),
            PopupMenuItem(value: 'delete', child: MenuRow(Icons.delete_outline, 'Delete')),
          ],
        ),
      ],
    );
  }
}

class _IncognitoBanner extends StatelessWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: v.tonal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: v.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: v.textStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're in an incognito chat. It won't be saved to history or used to personalise future chats.",
              style: vText(13, 18, color: v.textStrong),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- thinking + steps ----------------------------------------------------------------------

class _ThoughtProcess extends StatefulWidget {
  final ChatMessage message;
  final bool active;
  const _ThoughtProcess({required this.message, required this.active});

  @override
  State<_ThoughtProcess> createState() => _ThoughtProcessState();
}

class _ThoughtProcessState extends State<_ThoughtProcess> with SingleTickerProviderStateMixin {
  bool? _open; // null = automatic: open while thinking, closed after
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String get _label {
    final m = widget.message;
    if (widget.active)
      return m.thinking.isNotEmpty ? 'Thinking…' : (m.steps.isEmpty ? 'Searching your sources…' : 'Thinking…');
    final secs = m.thoughtFor?.inSeconds;
    if (m.thinking.isNotEmpty) return secs != null && secs > 0 ? 'Thought for ${secs}s' : 'Thoughts';
    return m.steps.isNotEmpty ? m.steps.first.label : 'Thoughts';
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final m = widget.message;
    final open = _open ?? widget.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => _open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.active
                      ? FadeTransition(
                          opacity: Tween(begin: .35, end: 1.0).animate(_pulse),
                          child: Icon(Icons.auto_awesome, size: 16, color: v.link),
                        )
                      : Icon(Icons.auto_awesome_outlined, size: 16, color: v.iconMuted),
                  const SizedBox(width: 8),
                  Text(
                    _label,
                    style: vText(14, 20, weight: FontWeight.w500, color: widget.active ? v.textStrong : v.textMuted),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: v.iconMuted),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topLeft,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4, left: 7),
                    padding: const EdgeInsets.only(left: 16),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: v.divider, width: 2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in m.steps)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  s.type == 'memory' ? Icons.person_outline : Icons.search_rounded,
                                  size: 16,
                                  color: v.iconMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: s.label,
                                          style: TextStyle(fontWeight: FontWeight.w600, color: v.textStrong),
                                        ),
                                        if (s.detail.isNotEmpty) TextSpan(text: '  ${s.detail}'),
                                      ],
                                    ),
                                    style: vText(13, 18, color: v.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (m.thinking.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: SingleChildScrollView(
                              reverse: widget.active,
                              child: Text(m.thinking.trim(), style: vText(13, 20, color: v.textMuted)),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(color: context.v.textStrong, shape: BoxShape.circle),
    ),
  );
}

// ---- pieces ------------------------------------------------------------------------------

class _SuggestionCard extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SuggestionCard({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: v.tonal,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: v.iconMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: vText(14, 24, color: v.textStrong)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final VoidCallback onSave;
  final String copyText;
  const _Actions({required this.onSave, required this.copyText});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: onSave,
            icon: const Icon(Icons.push_pin_outlined, size: 16),
            label: Text('Save to note', style: vText(13, 18)),
          ),
          IconButton(
            tooltip: 'Copy',
            iconSize: 18,
            color: v.iconMuted,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyText.replaceAll(RegExp(r'\[\d+\]'), '')));
              toast(context, 'Copied');
            },
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatefulWidget {
  final ChatMessage message;
  final NotebookStore store;
  const _UserBubble({required this.message, required this.store, super.key});

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  TextEditingController? _edit; // non-null while editing

  ChatMessage get m => widget.message;
  NotebookStore get store => widget.store;

  @override
  void dispose() {
    _edit?.dispose();
    super.dispose();
  }

  void _startEdit() => setState(() => _edit = TextEditingController(text: m.content));

  void _cancelEdit() {
    _edit?.dispose();
    setState(() => _edit = null);
  }

  void _submitEdit() {
    final text = _edit!.text;
    if (text.trim().isEmpty && m.attachments.isEmpty) return;
    store.editMessage(m, text); // this bubble is replaced by the edited one
  }

  Future<void> _branch() async {
    try {
      await store.branchFrom(m);
      if (mounted) toast(context, 'Branched to a new chat');
    } catch (e) {
      if (mounted) toast(context, 'Could not branch: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final busy = store.responding;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, left: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (m.attachments.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: m.content.isEmpty && _edit == null ? 0 : 8),
              child: MessageAttachments(attachments: m.attachments),
            ),
          if (_edit != null)
            _editor(v)
          else ...[
            if (m.content.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: v.tonal, borderRadius: BorderRadius.circular(40)),
                child: Text(m.content, style: vText(16, 24, color: v.textStrong)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.content.isNotEmpty)
                    _MsgIcon(
                      tooltip: 'Copy',
                      icon: Icons.copy_rounded,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: m.content));
                        toast(context, 'Copied');
                      },
                    ),
                  _MsgIcon(tooltip: 'Edit message', icon: Icons.edit_outlined, onPressed: busy ? null : _startEdit),
                  if (!store.incognito)
                    _MsgIcon(
                      tooltip: 'Branch to new chat',
                      icon: Icons.call_split_rounded,
                      onPressed: busy ? null : _branch,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _editor(VTokens v) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    decoration: BoxDecoration(
      color: v.tonal,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: v.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): _submitEdit,
            const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
          },
          child: TextField(
            controller: _edit,
            autofocus: true,
            minLines: 1,
            maxLines: 10,
            style: vText(16, 24, color: v.textStrong),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: _cancelEdit, child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton(onPressed: store.responding ? null : _submitEdit, child: const Text('Send')),
          ],
        ),
      ],
    ),
  );
}

/// Small muted icon button in a message's action row.
class _MsgIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _MsgIcon({required this.tooltip, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 16,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    color: context.v.iconMuted,
    icon: Icon(icon),
  );
}

class _DateSeparator extends StatelessWidget {
  final DateTime t;
  const _DateSeparator(this.t);

  @override
  Widget build(BuildContext context) {
    final day = DateUtils.isSameDay(t, DateTime.now()) ? 'Today' : DateFormat('MMM d').format(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text('$day • ${DateFormat.jm().format(t)}', style: vText(12, 16, color: context.v.textMuted)),
      ),
    );
  }
}

class _ZeroState extends StatelessWidget {
  final VoidCallback onAdd;
  const _ZeroState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👋', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text(
                "Let's start your notebook…",
                textAlign: TextAlign.center,
                style: vText(32, 40, color: v.textTitle),
              ),
              const SizedBox(height: 12),
              Text(
                'Add sources like PDFs, websites, YouTube videos or pasted text. Then ask questions, '
                'and Verlium will answer with citations from your sources.',
                textAlign: TextAlign.center,
                style: vText(15, 24, color: v.textMuted),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add sources')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thinking effort stops on the slider, lowest to highest; null (not on the slider) = the model's default.
const _effortLevels = ['none', 'low', 'medium', 'high', 'xhigh', 'max'];
const _effortNames = ['Off', 'Low', 'Medium', 'High', 'XHigh', 'Max'];

String _effortLabel(String? e) => e == null ? 'Auto' : _effortNames[_effortLevels.indexOf(e)];

/// Composer chip that opens a thinking-effort slider (Off → Max) with an "Auto" switch for the model default.
class _EffortControl extends StatelessWidget {
  final NotebookStore store;
  const _EffortControl({required this.store});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      menuChildren: [_EffortSlider(store: store)],
      builder: (context, controller, _) => Tooltip(
        message: 'Thinking effort',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: v.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_outlined, size: 16, color: v.iconMuted),
                const SizedBox(width: 4),
                Text(_effortLabel(store.reasoningEffort), style: vText(12, 16, color: v.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EffortSlider extends StatelessWidget {
  final NotebookStore store;
  const _EffortSlider({required this.store});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final effort = store.reasoningEffort;
        final auto = effort == null;
        final i = auto ? _effortLevels.indexOf('medium') : _effortLevels.indexOf(effort);
        return SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('Thinking effort', style: vText(14, 20, weight: FontWeight.w500, color: v.textStrong)),
                    const Spacer(),
                    Text(_effortLabel(effort), style: vText(14, 20, weight: FontWeight.w500, color: v.link)),
                  ],
                ),
                const SizedBox(height: 4),
                Opacity(
                  opacity: auto ? .45 : 1,
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          overlayShape: SliderComponentShape.noOverlay,
                          showValueIndicator: ShowValueIndicator.never,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Slider(
                            value: i.toDouble(),
                            max: _effortLevels.length - 1.0,
                            divisions: _effortLevels.length - 1,
                            // Dragging the slider while on Auto picks that level.
                            onChanged: (x) => store.setReasoningEffort(_effortLevels[x.round()]),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var k = 0; k < _effortNames.length; k++)
                            Expanded(
                              child: Text(
                                _effortNames[k],
                                textAlign: TextAlign.center,
                                style: vText(
                                  11,
                                  14,
                                  weight: !auto && k == i ? FontWeight.w600 : FontWeight.w400,
                                  color: !auto && k == i ? v.textStrong : v.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: v.divider),
                Row(
                  children: [
                    Expanded(
                      child: Text('Auto (model default)', style: vText(13, 18, color: v.textStrong)),
                    ),
                    Switch(
                      value: auto,
                      onChanged: (on) => store.setReasoningEffort(on ? null : _effortLevels[i]),
                    ),
                  ],
                ),
                Text(
                  'Higher effort thinks longer for harder questions. XHigh and Max only work on models that support them.',
                  style: vText(12, 16, color: v.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueryBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final NotebookStore store;
  final bool enabled;
  final void Function([String?]) onSend;
  const _QueryBox({
    required this.controller,
    required this.focus,
    required this.store,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final responding = store.responding;
    final n = store.selectedSources.length;
    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth > 700 ? ((c.maxWidth - 760) / 2).clamp(24.0, double.infinity) : 12.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.only(left: 8, right: 10, top: 6, bottom: 6),
            decoration: BoxDecoration(
              color: v.tonal,
              borderRadius: BorderRadius.circular(store.pending.isEmpty ? 32 : 24),
              border: Border.all(color: store.incognito ? v.textMuted : v.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: PendingAttachmentStrip(store: store),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Attach images or video (or paste / drop them)',
                      onPressed: enabled && !responding ? () => pickChatAttachments(context, store) : null,
                      icon: Icon(Icons.add_photo_alternate_outlined, size: 22, color: v.iconMuted),
                    ),
                    Expanded(
                      child: Focus(
                        // Ctrl/Cmd+V with an image or files on the clipboard attaches them; text paste still works.
                        onKeyEvent: (_, e) {
                          final mod =
                              HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                          if (e is KeyDownEvent && mod && e.logicalKey == LogicalKeyboardKey.keyV) {
                            pasteChatAttachments(context, store);
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: controller,
                          focusNode: focus,
                          enabled: enabled && !responding,
                          minLines: 1,
                          maxLines: 6,
                          style: vText(16, 24, color: v.textStrong),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: responding
                                ? 'Responding...'
                                : enabled
                                ? 'Ask a question or create something'
                                : 'Upload a source to get started',
                          ),
                        ),
                      ),
                    ),
                    _EffortControl(store: store),
                    const SizedBox(width: 8),
                    Text('$n source${n == 1 ? '' : 's'}', style: vText(12, 16, color: v.textMuted)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: v.primary, foregroundColor: Colors.white),
                        onPressed: !enabled || (!responding && store.attachmentsUploading)
                            ? null
                            : (responding ? store.stop : () => onSend()),
                        icon: Icon(responding ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatMenu extends StatelessWidget {
  final NotebookStore store;
  const _ChatMenu({required this.store});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'More',
    iconSize: 20,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 200),
    icon: Icon(Icons.more_vert, color: context.v.iconMuted),
    onSelected: (a) async {
      if (a == 'configure') showConfigureChat(context, store);
      if (a == 'clear' &&
          await confirm(
            context,
            title: 'Delete all chats?',
            body: 'This deletes every chat in this notebook. Chat history is private to you.',
            action: 'Delete',
          )) {
        store.clearChat();
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'configure', child: MenuRow(Icons.tune_rounded, 'Configure Chat')),
      PopupMenuItem(value: 'clear', child: MenuRow(Icons.delete_sweep_outlined, 'Delete chat history')),
    ],
  );
}
