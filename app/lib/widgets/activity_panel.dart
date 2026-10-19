import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/activity_store.dart';
import '../theme.dart';

const _mono = TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Cascadia Mono', 'Roboto Mono', 'monospace']);

Color _levelColor(BuildContext c, String level) => switch (level) {
      'success' => c.v.success,
      'error' => c.v.error,
      'warn' => const Color(0xFFF6C344),
      'debug' => c.v.textMuted,
      _ => c.v.link,
    };

IconData _kindIcon(String? kind) => switch (kind) {
      'ingest' => Icons.description_outlined,
      'studio' => Icons.auto_awesome_outlined,
      'summarize_thread' => Icons.forum_outlined,
      _ => Icons.bolt_rounded,
    };

String _hms(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// Wraps the whole app: a slim activity rail on the left edge (desktop) or a floating pill (phone),
/// a slide-out debug panel with jobs + live log, and toast notifications for finished/failed work.
class ActivityShell extends StatefulWidget {
  final Widget child;
  const ActivityShell({super.key, required this.child});

  @override
  State<ActivityShell> createState() => _ActivityShellState();
}

class _ActivityShellState extends State<ActivityShell> {
  final store = ActivityStore.I;
  final _toasts = <ActivityEvent>[];
  StreamSubscription<ActivityEvent>? _sub;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    store.start();
    _sub = store.toasts.stream.listen(_toast);
    SharedPreferences.getInstance().then((p) {
      if (mounted && (p.getBool('activity_open') ?? false)) _setOpen(true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _setOpen(bool v) {
    setState(() => _open = v);
    store.panelOpen = v;
    SharedPreferences.getInstance().then((p) => p.setBool('activity_open', v));
  }

  void _toast(ActivityEvent e) {
    if (!mounted) return;
    setState(() {
      _toasts.add(e);
      if (_toasts.length > 3) _toasts.removeAt(0);
    });
    Future.delayed(Duration(seconds: e.level == 'error' ? 8 : 5), () {
      if (mounted) setState(() => _toasts.remove(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final panelW = wide ? 380.0 : MediaQuery.sizeOf(context).width;
    return Material(
      color: context.v.bg,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide) _Rail(store: store, open: _open, onTap: () => _setOpen(!_open)),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: widget.child),
              // slide-out panel
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: _open ? 0 : -panelW - 24,
                top: 0,
                bottom: 0,
                width: panelW,
                child: _Panel(store: store, onClose: () => _setOpen(false)),
              ),
              if (!wide && !_open && (store.activeCount > 0 || store.unseenErrors > 0))
                Positioned(left: 12, bottom: 12, child: _Pill(store: store, onTap: () => _setOpen(true))),
              Positioned(
                left: _open && wide ? panelW + 12 : 12,
                bottom: !wide && !_open && store.activeCount > 0 ? 64 : 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in _toasts)
                      _Toast(
                        key: ObjectKey(t),
                        event: t,
                        onTap: () {
                          setState(() => _toasts.remove(t));
                          _setOpen(true);
                        },
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---- left rail ------------------------------------------------------------------------------------

class _Rail extends StatelessWidget {
  final ActivityStore store;
  final bool open;
  final VoidCallback onTap;
  const _Rail({required this.store, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final health = !store.serverOk ? v.error : (!store.dbOk ? const Color(0xFFF6C344) : v.success);
    return Container(
      width: 48,
      decoration: BoxDecoration(color: v.tonal, border: Border(right: BorderSide(color: v.outline))),
      child: Column(children: [
        const SizedBox(height: 12),
        Tooltip(
          message: open ? 'Hide activity' : 'Activity & debug log',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(alignment: Alignment.center, children: [
                if (store.busy)
                  SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2, color: v.primary)),
                Icon(Icons.terminal_rounded, size: 20, color: open ? v.primary : v.iconMuted),
                if (store.unseenErrors > 0 || store.activeCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _Badge(
                      text: store.unseenErrors > 0 ? '!' : '${store.activeCount}',
                      color: store.unseenErrors > 0 ? v.error : v.primary,
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // one icon per active job, so you can see at a glance what's working
        for (final j in store.jobs.take(6))
          Tooltip(
            message: '${j.label} · ${j.status == 'running' ? '${j.progress}%' : 'queued'}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 30,
                height: 30,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: j.status == 'running' ? (j.progress / 100).clamp(.04, 1) : 0,
                    strokeWidth: 2.5,
                    backgroundColor: v.outline,
                    color: v.primary,
                  ),
                  Icon(_kindIcon(j.kind), size: 14, color: v.iconMuted),
                ]),
              ),
            ),
          ),
        const Spacer(),
        Tooltip(
          message: !store.serverOk
              ? 'Server unreachable'
              : (!store.dbOk ? 'Server up · database unreachable' : 'Server & database OK'),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: health, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: health.withValues(alpha: .5), blurRadius: 6),
            ]),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 16),
        height: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

class _Pill extends StatelessWidget {
  final ActivityStore store;
  final VoidCallback onTap;
  const _Pill({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final err = store.unseenErrors > 0;
    return Material(
      color: v.panel,
      elevation: 6,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (store.busy)
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: v.primary))
            else
              Icon(err ? Icons.error_outline : Icons.terminal_rounded, size: 18, color: err ? v.error : v.iconMuted),
            const SizedBox(width: 8),
            Text(err ? 'Something failed' : '${store.activeCount} working…', style: vText(13, 18, color: v.textStrong)),
          ]),
        ),
      ),
    );
  }
}

// ---- panel ----------------------------------------------------------------------------------------

class _Panel extends StatefulWidget {
  final ActivityStore store;
  final VoidCallback onClose;
  const _Panel({required this.store, required this.onClose});

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  final _scroll = ScrollController();
  String _filter = 'all'; // all | notable | errors
  bool _follow = true;
  int _lastLen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final atEnd = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
      if (atEnd != _follow) setState(() => _follow = atEnd);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<ActivityEvent> get _events => widget.store.events.where((e) => switch (_filter) {
        'errors' => e.level == 'error' || e.level == 'warn',
        'notable' => e.level != 'debug',
        _ => true,
      }).toList();

  void _copy() {
    final text = widget.store.events
        .map((e) => '${_hms(e.time)} ${e.level.toUpperCase().padRight(7)} ${e.kind ?? '-'}  ${e.message}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final s = widget.store;
    final events = _events;
    if (_follow && events.length != _lastLen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    _lastLen = events.length;

    return Material(
      color: v.panel,
      elevation: 12,
      shadowColor: Colors.black,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Icon(Icons.terminal_rounded, size: 20, color: v.primary),
              const SizedBox(width: 8),
              Text('Activity', style: vText(16, 24, weight: FontWeight.w600, color: v.textTitle)),
              const SizedBox(width: 12),
              _Health(label: 'server', ok: s.serverOk),
              const SizedBox(width: 6),
              _Health(label: 'db', ok: s.serverOk && s.dbOk),
              const Spacer(),
              IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
          ),
          // jobs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(s.jobs.isEmpty ? 'NOTHING RUNNING' : 'WORKING ON (${s.jobs.length})',
                style: vText(11, 16, weight: FontWeight.w600, color: v.textMuted).copyWith(letterSpacing: .8)),
          ),
          for (final j in s.jobs) _JobRow(job: j),
          const SizedBox(height: 8),
          Divider(height: 1, color: v.divider),
          // log toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              for (final f in const [('all', 'All'), ('notable', 'No debug'), ('errors', 'Problems')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _filter == f.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _filter = f.$1),
                  ),
                ),
              const Spacer(),
              IconButton(tooltip: 'Copy log', onPressed: _copy, icon: const Icon(Icons.copy_rounded, size: 18)),
              IconButton(tooltip: 'Clear', onPressed: s.clear, icon: const Icon(Icons.delete_sweep_outlined, size: 18)),
            ]),
          ),
          // log
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              decoration: BoxDecoration(color: v.bg, borderRadius: BorderRadius.circular(12)),
              child: Stack(children: [
                events.isEmpty
                    ? Center(child: Text('No events yet', style: vText(13, 18, color: v.textMuted)))
                    : SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(10),
                          itemCount: events.length,
                          itemBuilder: (_, i) => _LogLine(event: events[i]),
                        ),
                      ),
                if (!_follow)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      tooltip: 'Jump to latest',
                      onPressed: () {
                        setState(() => _follow = true);
                        _scroll.animateTo(_scroll.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                      },
                      child: const Icon(Icons.arrow_downward_rounded, size: 18),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Health extends StatelessWidget {
  final String label;
  final bool ok;
  const _Health({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final c = ok ? context.v.success : context.v.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: _mono.copyWith(fontSize: 11, color: c)),
      ]),
    );
  }
}

class _JobRow extends StatelessWidget {
  final ActivityJob job;
  const _JobRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final running = job.status == 'running';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(_kindIcon(job.kind), size: 16, color: v.iconMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(job.label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(13, 18, color: v.textStrong)),
          ),
          Text(running ? '${job.progress}%' : (job.attempts > 0 ? 'retry ${job.attempts + 1}' : 'queued'),
              style: _mono.copyWith(fontSize: 11, color: v.textMuted)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            minHeight: 3,
            value: running ? (job.progress == 0 ? null : job.progress / 100) : 0,
            backgroundColor: v.outline,
            color: v.primary,
          ),
        ),
        if (job.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('last error: ${job.error}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: _mono.copyWith(fontSize: 11, color: v.error)),
          ),
      ]),
    );
  }
}

class _LogLine extends StatelessWidget {
  final ActivityEvent event;
  const _LogLine({required this.event});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final c = _levelColor(context, event.level);
    final tag = switch (event.level) { 'success' => 'OK', 'warn' => 'WARN', 'error' => 'ERR', 'debug' => 'DBG', _ => 'INFO' };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${_hms(event.time)} ', style: TextStyle(color: v.textMuted)),
          TextSpan(text: tag.padRight(5), style: TextStyle(color: c, fontWeight: FontWeight.w700)),
          if (event.kind != null) TextSpan(text: '${event.kind} ', style: TextStyle(color: v.iconMuted)),
          TextSpan(text: event.message, style: TextStyle(color: event.level == 'debug' ? v.textMuted : v.text)),
        ]),
        style: _mono.copyWith(fontSize: 12, height: 1.45),
      ),
    );
  }
}

// ---- toast ----------------------------------------------------------------------------------------

class _Toast extends StatefulWidget {
  final ActivityEvent event;
  final VoidCallback onTap;
  const _Toast({super.key, required this.event, required this.onTap});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final e = widget.event;
    final c = _levelColor(context, e.level);
    final icon = switch (e.level) {
      'success' => Icons.check_circle_rounded,
      'error' => Icons.error_rounded,
      _ => Icons.warning_amber_rounded,
    };
    final anim = CurvedAnimation(parent: _a, curve: Curves.easeOutBack);
    return SlideTransition(
      position: Tween(begin: const Offset(-1.2, 0), end: Offset.zero).animate(anim),
      child: FadeTransition(
        opacity: _a,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: v.panel,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: c, width: 3)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 18, color: c),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(e.message,
                        maxLines: 3, overflow: TextOverflow.ellipsis, style: vText(13, 18, color: v.textStrong)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
