import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../widgets/settings_menu.dart';
import 'notebook_screen.dart';

final dateFmt = DateFormat('MMM d, y');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Notebook>? _notebooks;
  String? _error;
  bool _grid = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Api.I.get('/notebooks') as List;
      setState(() {
        _notebooks = [for (final n in list) Notebook.fromJson(n)];
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _create() async {
    final nb = Notebook.fromJson(await Api.I.post('/notebooks', {}));
    if (!mounted) return;
    await _open(nb, addSources: true);
  }

  Future<void> _open(Notebook nb, {bool addSources = false}) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => NotebookScreen(notebookId: nb.id, openAddSources: addSources)));
    _load();
  }

  Future<void> _rename(Notebook nb) async {
    final t = await promptText(context, title: 'Edit title', initial: nb.title, label: 'Title');
    if (t == null || t.trim().isEmpty) return;
    await Api.I.patch('/notebooks/${nb.id}', {'title': t.trim()});
    _load();
  }

  Future<void> _delete(Notebook nb) async {
    final ok = await confirm(context,
        title: 'Delete notebook?', body: 'You will no longer have access to "${nb.title}".', action: 'Delete');
    if (!ok) return;
    await Api.I.delete('/notebooks/${nb.id}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final w = MediaQuery.sizeOf(context).width;
    final grid = _grid && w >= 600;
    final items = (_notebooks ?? [])
        .where((n) => _query.isEmpty || n.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const VerliumLogo(size: 32, showText: true),
                const Spacer(),
                if (w >= 700)
                  SizedBox(
                    width: 256,
                    height: 36,
                    child: TextField(
                      onChanged: (q) => setState(() => _query = q),
                      style: vText(14, 20),
                      decoration: InputDecoration(
                        hintText: 'Search notebooks',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: v.outline)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: v.outline)),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (w >= 600)
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded, size: 18)),
                      ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded, size: 18)),
                    ],
                    selected: {_grid},
                    onSelectionChanged: (s) => setState(() => _grid = s.first),
                  ),
                const SettingsButton(),
              ]),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: w >= 600 ? 48 : 16, vertical: 16),
                children: [
                  Row(children: [
                    Text('Recent notebooks', style: vText(24, 32, color: v.textTitle)),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: v.primaryTonal, foregroundColor: v.onPrimaryTonal, minimumSize: const Size(0, 40)),
                      onPressed: _create,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('New notebook'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  if (_error != null) ErrorBox(message: _error!, onRetry: _load),
                  if (_notebooks == null && _error == null)
                    const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                  if (_notebooks != null && _notebooks!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(
                          child: Text('Create your first notebook to get started.',
                              style: vText(15, 20, color: v.textMuted))),
                    ),
                  if (grid)
                    LayoutBuilder(builder: (context, c) {
                      final cols = (c.maxWidth / 300).floor().clamp(1, 6);
                      final cardW = (c.maxWidth - 8 * (cols - 1)) / cols;
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        _NewCard(width: cardW, onTap: _create),
                        for (final nb in items)
                          SizedBox(
                            width: cardW,
                            child: _NotebookCard(
                                nb: nb, onOpen: () => _open(nb), onRename: () => _rename(nb), onDelete: () => _delete(nb)),
                          ),
                      ]);
                    })
                  else
                    for (final nb in items)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Text(nb.emoji ?? '📓', style: const TextStyle(fontSize: 24)),
                        title: Text(nb.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(15, 20)),
                        subtitle: Text(_meta(nb), style: vText(12, 16, color: v.textMuted)),
                        trailing: _NotebookMenu(onRename: () => _rename(nb), onDelete: () => _delete(nb)),
                        onTap: () => _open(nb),
                      ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

String _meta(Notebook nb) =>
    '${nb.createdAt != null ? dateFmt.format(nb.createdAt!) : ''} · ${nb.sourceCount} source${nb.sourceCount == 1 ? '' : 's'}';

class _NewCard extends StatelessWidget {
  final double width;
  final VoidCallback onTap;
  const _NewCard({required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return SizedBox(
      width: width,
      height: 185,
      child: Material(
        color: v.tonal,
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(
                radius: 32, backgroundColor: v.primaryTonal, child: Icon(Icons.add, size: 32, color: v.onPrimaryTonal)),
            const SizedBox(height: 16),
            Text('Create new notebook', style: vText(17, 24, color: v.textStrong)),
          ]),
        ),
      ),
    );
  }
}

class _NotebookCard extends StatelessWidget {
  final Notebook nb;
  final VoidCallback onOpen, onRename, onDelete;
  const _NotebookCard({required this.nb, required this.onOpen, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return SizedBox(
      height: 185,
      child: Material(
        color: v.tonal,
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(nb.emoji ?? '📓', style: const TextStyle(fontSize: 36)),
                ),
                const Spacer(),
                _NotebookMenu(onRename: onRename, onDelete: onDelete),
              ]),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(nb.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: vText(20, 24, weight: FontWeight.w500, color: v.textTitle)),
              ),
              const SizedBox(height: 8),
              Text(_meta(nb), style: vText(15, 20, color: v.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NotebookMenu extends StatelessWidget {
  final VoidCallback onRename, onDelete;
  const _NotebookMenu({required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: context.v.iconMuted),
        onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: MenuRow(Icons.edit_outlined, 'Edit title')),
          PopupMenuItem(value: 'delete', child: MenuRow(Icons.delete_outline, 'Delete')),
        ],
      );
}
