import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api.dart';
import '../api/models.dart';

const _uuid = Uuid();

const _imageExt = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'};
const _videoExt = {'mp4', 'mov', 'webm', 'mkv', 'm4v', 'avi'};

/// 'image' | 'video' | null (not attachable), from the file name.
String? attachmentKind(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return _imageExt.contains(ext) ? 'image' : (_videoExt.contains(ext) ? 'video' : null);
}

/// A file picked/dropped/pasted into the chat box, uploading or ready to send.
class PendingAttachment {
  final String localId = _uuid.v4();
  final String name, kind;
  final Uint8List bytes; // kept for the instant local preview (images)
  ChatAttachment? uploaded;
  String? error;
  PendingAttachment(this.name, this.kind, this.bytes);
  bool get uploading => uploaded == null && error == null;
}

/// State for one open notebook: sources, chat threads, notes, Studio outputs.
/// Polls while sources are processing or Studio outputs are generating.
class NotebookStore extends ChangeNotifier {
  final String id;
  NotebookStore(this.id);

  Notebook? notebook;
  List<Source> sources = [];
  List<Note> notes = [];
  List<StudioOutput> outputs = [];
  List<String> suggestions = [];
  String? error;
  bool loading = true;
  Timer? _poll;

  // ---- chat state
  List<ChatThread> threads = [];
  String? threadId; // null = a fresh chat that has no thread yet
  List<ChatMessage> messages = [];
  bool incognito = false;
  String? reasoningEffort; // null = model default | none | low | medium | high
  StreamSubscription<ChatEvent>? _answer;

  /// Bumped when something (topic chip, mind-map node, flashcard "Explain") posts to chat,
  /// so the narrow layout can switch to the Chat tab.
  final chatRequests = ValueNotifier<int>(0);

  /// Source opened in the Sources panel viewer, if any.
  Source? openSource;
  ({int start, int end})? highlight;

  /// Note or Studio output opened in the Studio panel, if any.
  Note? openNote;
  StudioOutput? openOutput;

  bool get responding => _answer != null;

  // ---- chat attachments ---------------------------------------------------------
  final List<PendingAttachment> pending = [];
  bool get attachmentsUploading => pending.any((p) => p.uploading);
  List<ChatAttachment> get readyAttachments => [for (final p in pending) if (p.uploaded != null) p.uploaded!];

  /// Returns an error message for files that can't be attached (wrong type / too big / too many).
  String? attach(String name, Uint8List bytes) {
    final kind = attachmentKind(name);
    if (kind == null) return '$name: only images and videos can be attached to chat';
    if (pending.length >= 10) return 'Up to 10 attachments per message';
    final max = kind == 'image' ? 25 : 300;
    if (bytes.length > max * 1024 * 1024) return '$name is larger than $max MB';
    final p = PendingAttachment(name, kind, bytes);
    pending.add(p);
    notifyListeners();
    Api.I.upload('/notebooks/$id/attachments', name, bytes).then((r) {
      p.uploaded = ChatAttachment.fromJson(Map<String, dynamic>.from(r));
    }, onError: (Object e) {
      p.error = e.toString();
    }).whenComplete(notifyListeners);
    return null;
  }

  void removeAttachment(PendingAttachment p) {
    pending.remove(p);
    notifyListeners();
  }
  bool get viewerOpen => openNote != null || openOutput != null;
  List<Source> get selectedSources => sources.where((s) => s.selected && !s.busy && s.status == 'ready').toList();

  Future<void> load() async {
    try {
      final r = await Future.wait([
        Api.I.get('/notebooks/$id'),
        Api.I.get('/notebooks/$id/sources'),
        Api.I.get('/notebooks/$id/threads'),
        Api.I.get('/notebooks/$id/notes'),
        Api.I.get('/notebooks/$id/studio'),
      ]);
      notebook = Notebook.fromJson(r[0]);
      sources = [for (final s in r[1]) Source.fromJson(s)];
      threads = [for (final t in r[2]) ChatThread.fromJson(t)];
      notes = [for (final n in r[3]) Note.fromJson(n)];
      outputs = [for (final o in r[4]) StudioOutput.fromJson(o)];
      error = null;
      if (threads.isNotEmpty) await openThread(threads.first.id, notify: false);
      _schedulePoll();
      if (notebook!.summary != null && suggestions.isEmpty) _loadSuggestions();
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadSuggestions() async {
    try {
      suggestions = List<String>.from(await Api.I.get('/notebooks/$id/suggestions'));
      notifyListeners();
    } catch (_) {}
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (sources.any((s) => s.busy) || outputs.any((o) => o.busy)) {
      _poll = Timer(const Duration(seconds: 3), _refresh);
    }
  }

  Future<void> _refresh() async {
    final wasBusy = sources.where((s) => s.busy).length;
    try {
      if (wasBusy > 0) {
        sources = [for (final s in await Api.I.get('/notebooks/$id/sources')) Source.fromJson(s)];
        if (sources.where((s) => s.busy).length < wasBusy) {
          notebook = Notebook.fromJson(await Api.I.get('/notebooks/$id'));
          if (!sources.any((s) => s.busy)) _loadSuggestions();
        }
      }
      if (outputs.any((o) => o.busy)) {
        outputs = [for (final o in await Api.I.get('/notebooks/$id/studio')) StudioOutput.fromJson(o)];
        if (openOutput != null) openOutput = outputs.where((o) => o.id == openOutput!.id).firstOrNull;
      }
      notifyListeners();
    } catch (_) {}
    _schedulePoll();
  }

  // ---- notebook ------------------------------------------------------------
  Future<void> rename(String title) async {
    notebook = Notebook.fromJson(await Api.I.patch('/notebooks/$id', {'title': title}));
    notifyListeners();
  }

  Future<void> setChatConfig(Map<String, dynamic> cfg) async {
    notebook = Notebook.fromJson(await Api.I.patch('/notebooks/$id', {'chat_config': cfg}));
    notifyListeners();
  }

  // ---- sources -------------------------------------------------------------
  void _addSource(dynamic json) {
    sources.add(Source.fromJson(json));
    _schedulePoll();
    notifyListeners();
  }

  Future<void> uploadFile(String name, Uint8List bytes) async =>
      _addSource(await Api.I.upload('/notebooks/$id/sources/upload', name, bytes, fields: {'id': _uuid.v4()}));

  Future<void> addLinks(List<String> urls) async {
    for (final u in urls) {
      _addSource(await Api.I.post('/notebooks/$id/sources/link', {'id': _uuid.v4(), 'url': u}));
    }
  }

  Future<void> addText(String text, {String? title}) async =>
      _addSource(await Api.I.post('/notebooks/$id/sources/text', {'id': _uuid.v4(), 'text': text, 'title': title}));

  Future<void> toggleSource(Source s, bool v) async {
    s.selected = v;
    notifyListeners();
    await Api.I.patch('/sources/${s.id}', {'selected': v});
  }

  Future<void> selectAll(bool v) async {
    for (final s in sources) {
      s.selected = v;
    }
    notifyListeners();
    await Api.I.post('/notebooks/$id/sources/select?selected=$v');
  }

  Future<void> renameSource(Source s, String title) async {
    s.title = title;
    notifyListeners();
    await Api.I.patch('/sources/${s.id}', {'title': title});
  }

  Future<void> removeSource(Source s) async {
    sources.remove(s);
    if (openSource?.id == s.id) openSource = null;
    notifyListeners();
    await Api.I.delete('/sources/${s.id}');
  }

  Future<void> retrySource(Source s) async {
    final i = sources.indexOf(s);
    sources[i] = Source.fromJson(await Api.I.post('/sources/${s.id}/retry'));
    _schedulePoll();
    notifyListeners();
  }

  Future<void> showSource(String sourceId, {int? start, int? end}) async {
    openSource = Source.fromJson(await Api.I.get('/sources/$sourceId', {'content': 'true'}));
    highlight = start != null && end != null ? (start: start, end: end) : null;
    notifyListeners();
  }

  void closeSource() {
    openSource = null;
    highlight = null;
    notifyListeners();
  }

  // ---- chat threads ---------------------------------------------------------
  Future<void> openThread(String tid, {bool notify = true}) async {
    if (responding) stop();
    incognito = false;
    threadId = tid;
    messages = [for (final m in await Api.I.get('/threads/$tid/messages')) ChatMessage.fromJson(m)];
    if (notify) notifyListeners();
  }

  /// "New chat": the thread is created on the first question (so empty chats don't pile up).
  /// Starting a new chat also makes the server recap the previous one for personalisation.
  void newChat({bool incognito = false}) {
    if (responding) stop();
    this.incognito = incognito;
    threadId = null;
    messages = [];
    notifyListeners();
  }

  void setIncognito(bool v) => newChat(incognito: v);

  void setReasoningEffort(String? e) {
    reasoningEffort = e;
    notifyListeners();
  }

  Future<void> refreshThreads() async {
    threads = [for (final t in await Api.I.get('/notebooks/$id/threads')) ChatThread.fromJson(t)];
    notifyListeners();
  }

  Future<void> renameThread(ChatThread t, String title) async {
    t.title = title;
    notifyListeners();
    await Api.I.patch('/threads/${t.id}', {'title': title});
  }

  Future<void> deleteThread(ChatThread t) async {
    threads.removeWhere((x) => x.id == t.id);
    if (threadId == t.id) newChat();
    notifyListeners();
    await Api.I.delete('/threads/${t.id}');
  }

  // ---- ask -------------------------------------------------------------------
  void ask(String question) {
    final atts = readyAttachments;
    if (responding || attachmentsUploading || (question.trim().isEmpty && atts.isEmpty)) return;
    chatRequests.value++;
    final history = [
      for (final m in messages.where((m) => !m.streaming && m.error == null && m.content.isNotEmpty))
        {'role': m.role, 'content': m.content}
    ];
    final userMsg = ChatMessage(id: _uuid.v4(), role: 'user', content: question.trim(), attachments: atts);
    pending.clear();
    final answer = ChatMessage(id: 'pending', role: 'assistant', content: '', streaming: true);
    messages.addAll([userMsg, answer]);
    notifyListeners();

    final isNewThread = threadId == null && !incognito;
    _answer = Api.I
        .ask(id, userMsg.content,
            messageId: userMsg.id,
            threadId: incognito ? null : threadId,
            incognito: incognito,
            history: history,
            reasoningEffort: reasoningEffort,
            attachmentIds: [for (final a in atts) a.id])
        .listen(
      (e) {
        switch (e.type) {
          case 'start':
            if (!incognito) threadId = e.data['thread_id'] as String?;
          case 'step':
            answer.steps.add(ChatStep.fromJson(e.data));
          case 'thinking':
            answer.thinkingStarted ??= DateTime.now();
            answer.thinking += e.data['text'] as String;
          case 'delta':
            if (answer.thinkingStarted != null && answer.thoughtFor == null) {
              answer.thoughtFor = DateTime.now().difference(answer.thinkingStarted!);
            }
            answer.content += e.data['text'] as String;
          case 'done':
            final done = ChatMessage.fromJson({...e.data, 'role': 'assistant'});
            done.thoughtFor = answer.thoughtFor;
            final i = messages.indexOf(answer);
            if (i >= 0) messages[i] = done;
          case 'error':
            answer.error = e.data['message']?.toString();
        }
        notifyListeners();
      },
      onError: (Object err) {
        answer.error = err.toString();
        _finishAnswer(answer);
      },
      onDone: () {
        _finishAnswer(answer);
        if (isNewThread || !incognito) refreshThreads();
      },
      cancelOnError: true,
    );
  }

  void _finishAnswer(ChatMessage answer) {
    answer.streaming = false;
    _answer = null;
    notifyListeners();
  }

  void stop() {
    _answer?.cancel();
    for (final m in messages.where((m) => m.streaming)) {
      m.streaming = false;
    }
    _answer = null;
    notifyListeners();
  }

  Future<void> clearChat() async {
    await Api.I.delete('/notebooks/$id/chat');
    threads.clear();
    newChat();
  }

  // ---- notes ---------------------------------------------------------------
  Future<Note> createNote(
      {String title = 'New note', String content = '', String kind = 'note', List<Citation> citations = const []}) async {
    final n = Note.fromJson(await Api.I.post('/notebooks/$id/notes', {
      'id': _uuid.v4(),
      'kind': kind,
      'title': title,
      'content': content,
      'citations': [for (final c in citations) c.toJson()],
    }));
    notes.insert(0, n);
    notifyListeners();
    return n;
  }

  Future<void> saveNote(Note n, {String? title, String? content}) async {
    final updated = Note.fromJson(await Api.I.patch('/notes/${n.id}', {
      'title': ?title,
      'content': ?content,
      'base_version': n.version,
    }));
    notes[notes.indexWhere((x) => x.id == n.id)] = updated;
    if (openNote?.id == n.id) openNote = updated;
    notifyListeners();
  }

  Future<void> deleteNote(Note n) async {
    notes.removeWhere((x) => x.id == n.id);
    if (openNote?.id == n.id) openNote = null;
    notifyListeners();
    await Api.I.delete('/notes/${n.id}');
  }

  void showNote(Note? n) {
    openNote = n;
    openOutput = null;
    notifyListeners();
  }

  // ---- studio ----------------------------------------------------------------
  Future<void> generate(String type, {String prompt = '', Map<String, dynamic> options = const {}}) async {
    final o = StudioOutput.fromJson(await Api.I.post('/notebooks/$id/studio', {
      'id': _uuid.v4(),
      'type': type,
      'prompt': prompt,
      'options': options,
      'source_ids': [for (final s in selectedSources) s.id],
    }));
    outputs.insert(0, o);
    _schedulePoll();
    notifyListeners();
  }

  void showOutput(StudioOutput? o) {
    openOutput = o;
    openNote = null;
    if (o != null && o.unread) {
      o.unread = false;
      Api.I.patch('/studio/${o.id}', {'unread': false});
    }
    notifyListeners();
  }

  Future<void> renameOutput(StudioOutput o, String title) async {
    o.title = title;
    notifyListeners();
    await Api.I.patch('/studio/${o.id}', {'title': title});
  }

  Future<void> retryOutput(StudioOutput o) async {
    final i = outputs.indexWhere((x) => x.id == o.id);
    outputs[i] = StudioOutput.fromJson(await Api.I.post('/studio/${o.id}/retry'));
    _schedulePoll();
    notifyListeners();
  }

  Future<void> deleteOutput(StudioOutput o) async {
    outputs.removeWhere((x) => x.id == o.id);
    if (openOutput?.id == o.id) openOutput = null;
    notifyListeners();
    await Api.I.delete('/studio/${o.id}');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _answer?.cancel();
    chatRequests.dispose();
    super.dispose();
  }
}
