import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/notebook_store.dart';
import '../theme.dart';
import '../widgets/add_sources_dialog.dart';
import '../widgets/chat_panel.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../widgets/settings_menu.dart';
import '../widgets/sources_panel.dart';
import '../widgets/studio_panel.dart';

/// Notebook page: 3 resizable panels at ≥1051 px, tabs [Sources | Chat | Studio] below (UI-SPEC §2).
class NotebookScreen extends StatefulWidget {
  final String notebookId;
  final bool openAddSources;
  const NotebookScreen({super.key, required this.notebookId, this.openAddSources = false});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

// Panel width limits (px). Defaults match the measured Gemini Notebook layout (314 / 314, 480 with a viewer).
const _minSide = 220.0, _maxSide = 760.0, _minChat = 360.0, _rail = 56.0;
const _defLeft = 314.0, _defRight = 314.0, _defRightViewer = 480.0;

class _NotebookScreenState extends State<NotebookScreen> with SingleTickerProviderStateMixin {
  late final store = NotebookStore(widget.notebookId);
  late final _tabs = TabController(length: 3, vsync: this, initialIndex: 1);
  bool _sourcesCollapsed = false, _studioCollapsed = false;
  double _left = _defLeft, _right = _defRight, _rightViewer = _defRightViewer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _loadWidths();
    store.chatRequests.addListener(() => _gotoTab(1));
    store.load().then((_) {
      if (widget.openAddSources && mounted) showAddSources(context, store);
    });
  }

  Future<void> _loadWidths() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _left = p.getDouble('panel_left') ?? _defLeft;
      _right = p.getDouble('panel_right') ?? _defRight;
      _rightViewer = p.getDouble('panel_right_viewer') ?? _defRightViewer;
    });
  }

  Future<void> _saveWidths() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('panel_left', _left);
    await p.setDouble('panel_right', _right);
    await p.setDouble('panel_right_viewer', _rightViewer);
  }

  @override
  void dispose() {
    store.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _gotoTab(int i) {
    if (mounted && MediaQuery.sizeOf(context).width <= 1050) _tabs.animateTo(i);
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final wide = MediaQuery.sizeOf(context).width >= 1051;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final nb = store.notebook;
        return Scaffold(
          body: SafeArea(
            child: Column(children: [
              SizedBox(
                height: 64,
                child: Row(children: [
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Home',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const VerliumLogo(size: 32),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: nb == null
                        ? const SizedBox()
                        : InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final t = await promptText(context, title: 'Notebook title', initial: nb.title);
                              if (t != null && t.trim().isNotEmpty) store.rename(t.trim());
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(nb.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(22, 36, color: v.textTitle)),
                            ),
                          ),
                  ),
                  if (wide)
                    OutlinedButton.icon(
                      onPressed: () => showAddSources(context, store),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add sources'),
                    ),
                  const SizedBox(width: 4),
                  const SettingsButton(),
                  const SizedBox(width: 8),
                ]),
              ),
              if (store.loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (store.error != null)
                Expanded(child: ErrorBox(message: store.error!, onRetry: store.load))
              else if (wide)
                Expanded(child: _wideLayout())
              else
                Expanded(
                  child: Column(children: [
                    _PillTabs(controller: _tabs),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(controller: _tabs, children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SourcesPanel(store: store),
                        ),
                        ChatPanel(store: store, compact: true),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: StudioPanel(store: store),
                        ),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _wideLayout() => LayoutBuilder(builder: (context, c) {
        final total = c.maxWidth - 24; // 12px page gutters
        final viewer = store.viewerOpen;
        double left = _sourcesCollapsed ? _rail : _left;
        double right = _studioCollapsed ? _rail : (viewer ? _rightViewer : _right);
        // Keep the chat column usable when the window shrinks.
        final overflow = left + right + 16 + _minChat - total;
        if (overflow > 0) {
          final shrinkable = (left > _minSide ? left - _minSide : 0) + (right > _minSide ? right - _minSide : 0);
          if (shrinkable > 0) {
            final k = (overflow / shrinkable).clamp(0.0, 1.0);
            if (!_sourcesCollapsed) left -= (left - _minSide) * k;
            if (!_studioCollapsed) right -= (right - _minSide) * k;
          }
        }
        final anim = _dragging ? Duration.zero : const Duration(milliseconds: 200);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedContainer(
              duration: anim,
              width: left,
              child: SourcesPanel(
                store: store,
                collapsed: _sourcesCollapsed,
                onToggle: () => setState(() => _sourcesCollapsed = !_sourcesCollapsed),
              ),
            ),
            _ResizeHandle(
              enabled: !_sourcesCollapsed,
              onStart: () => setState(() => _dragging = true),
              onDrag: (dx) => setState(() {
                final maxLeft = (total - right - 16 - _minChat).clamp(_minSide, _maxSide);
                _left = (_left + dx).clamp(_minSide, maxLeft);
              }),
              onEnd: () {
                setState(() => _dragging = false);
                _saveWidths();
              },
              onReset: () {
                setState(() => _left = _defLeft);
                _saveWidths();
              },
            ),
            Expanded(child: ChatPanel(store: store)),
            _ResizeHandle(
              enabled: !_studioCollapsed,
              onStart: () => setState(() => _dragging = true),
              onDrag: (dx) => setState(() {
                final maxRight = (total - left - 16 - _minChat).clamp(_minSide, _maxSide);
                if (viewer) {
                  _rightViewer = (_rightViewer - dx).clamp(_minSide, maxRight);
                } else {
                  _right = (_right - dx).clamp(_minSide, maxRight);
                }
              }),
              onEnd: () {
                setState(() => _dragging = false);
                _saveWidths();
              },
              onReset: () {
                setState(() => viewer ? _rightViewer = _defRightViewer : _right = _defRight);
                _saveWidths();
              },
            ),
            AnimatedContainer(
              duration: anim,
              width: right,
              child: StudioPanel(
                store: store,
                collapsed: _studioCollapsed,
                onToggle: () => setState(() => _studioCollapsed = !_studioCollapsed),
              ),
            ),
          ]),
        );
      });
}

/// The 8px gap between panels. Drag to resize, double-click to reset. Shows a pill grip on hover.
class _ResizeHandle extends StatefulWidget {
  final bool enabled;
  final VoidCallback onStart, onEnd, onReset;
  final ValueChanged<double> onDrag;
  const _ResizeHandle(
      {required this.enabled, required this.onStart, required this.onDrag, required this.onEnd, required this.onReset});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false, _active = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox(width: 8);
    final v = context.v;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          setState(() => _active = true);
          widget.onStart();
        },
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _active = false);
          widget.onEnd();
        },
        onDoubleTap: widget.onReset,
        child: Tooltip(
          message: 'Drag to resize · double-click to reset',
          waitDuration: const Duration(seconds: 1),
          child: SizedBox(
            width: 8,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 4,
                height: _hover || _active ? 48 : 0,
                decoration: BoxDecoration(
                  color: _active ? v.primary : v.iconMuted.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillTabs extends StatelessWidget {
  final TabController controller;
  const _PillTabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Container(
      width: 343,
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: v.tonal, borderRadius: BorderRadius.circular(999)),
      child: TabBar(
        controller: controller,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: v.panel, borderRadius: BorderRadius.circular(999)),
        labelColor: v.textTitle,
        unselectedLabelColor: v.textMuted,
        labelStyle: vText(14, 20, weight: FontWeight.w500),
        tabs: const [Tab(text: 'Sources'), Tab(text: 'Chat'), Tab(text: 'Studio')],
      ),
    );
  }
}
