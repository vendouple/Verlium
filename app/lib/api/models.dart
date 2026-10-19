DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class Notebook {
  final String id;
  String title;
  String? emoji;
  String? summary;
  Map<String, dynamic> chatConfig;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int sourceCount;

  Notebook.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'] ?? 'Untitled notebook',
        emoji = j['emoji'],
        summary = j['summary'],
        chatConfig = Map<String, dynamic>.from(j['chat_config'] ?? {}),
        createdAt = _dt(j['created_at']),
        updatedAt = _dt(j['updated_at']),
        sourceCount = (j['source_count'] as num?)?.toInt() ?? 0;
}

class Source {
  final String id;
  final String notebookId;
  final String kind;
  String title;
  final String? url;
  final String status; // queued | processing | ready | error
  final String? error;
  final String? summary;
  final List<String> keyTopics;
  bool selected;
  final int? charCount;
  String? content;
  final DateTime? createdAt;

  Source.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        notebookId = j['notebook_id'],
        kind = j['kind'],
        title = j['title'] ?? 'Untitled source',
        url = j['url'],
        status = j['status'],
        error = j['error'],
        summary = j['summary'],
        keyTopics = List<String>.from(j['key_topics'] ?? const []),
        selected = (j['selected'] ?? 1) == 1 || j['selected'] == true,
        charCount = (j['char_count'] as num?)?.toInt(),
        content = j['content'],
        createdAt = _dt(j['created_at']);

  bool get busy => status == 'queued' || status == 'processing';
}

class Citation {
  final int n;
  final String chunkId, sourceId, sourceTitle, quote;
  final int charStart, charEnd;
  final int? page;

  Citation.fromJson(Map<String, dynamic> j)
      : n = (j['n'] as num).toInt(),
        chunkId = j['chunk_id'],
        sourceId = j['source_id'],
        sourceTitle = j['source_title'] ?? 'Source',
        quote = j['quote'] ?? '',
        charStart = (j['char_start'] as num).toInt(),
        charEnd = (j['char_end'] as num).toInt(),
        page = (j['page'] as num?)?.toInt();

  Map<String, dynamic> toJson() => {
        'n': n,
        'chunk_id': chunkId,
        'source_id': sourceId,
        'source_title': sourceTitle,
        'quote': quote,
        'char_start': charStart,
        'char_end': charEnd,
        'page': page,
      };
}

class ChatStep {
  final String type, label, detail;
  ChatStep.fromJson(Map<String, dynamic> j)
      : type = j['type'] ?? '',
        label = j['label'] ?? '',
        detail = j['detail'] ?? '';
}

class ChatMessage {
  final String id;
  final String role;
  String content;
  String thinking;
  List<Citation> citations;
  List<ChatStep> steps;
  List<ChatAttachment> attachments;
  final DateTime createdAt;
  bool streaming;
  String? error;
  DateTime? thinkingStarted;
  Duration? thoughtFor;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thinking = '',
    this.citations = const [],
    List<ChatStep>? steps,
    this.attachments = const [],
    DateTime? createdAt,
    this.streaming = false,
  })  : steps = steps ?? [],
        createdAt = createdAt ?? DateTime.now();

  ChatMessage.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        role = j['role'],
        content = j['content'] ?? '',
        thinking = j['thinking'] ?? '',
        citations = [for (final c in (j['citations'] ?? const [])) Citation.fromJson(Map<String, dynamic>.from(c))],
        steps = [for (final s in (j['steps'] ?? const [])) ChatStep.fromJson(Map<String, dynamic>.from(s))],
        attachments = [
          for (final a in (j['attachments'] ?? const [])) ChatAttachment.fromJson(Map<String, dynamic>.from(a))
        ],
        createdAt = _dt(j['created_at']) ?? DateTime.now(),
        streaming = false;
}

/// An image or video attached to a chat message (served from /attachments/{id}/media|thumb).
class ChatAttachment {
  final String id, kind, mime, name;
  final int? width, height;
  final double? duration;
  ChatAttachment.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        kind = j['kind'] ?? 'image',
        mime = j['mime'] ?? '',
        name = j['name'] ?? '',
        width = (j['width'] as num?)?.toInt(),
        height = (j['height'] as num?)?.toInt(),
        duration = (j['duration_s'] as num?)?.toDouble();

  bool get isVideo => kind == 'video';
  double get aspect => (width ?? 0) > 0 && (height ?? 0) > 0 ? width! / height! : (isVideo ? 16 / 9 : 1);
}

class ChatThread {
  final String id;
  String title;
  final DateTime? updatedAt;
  final int messageCount;

  ChatThread.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'] ?? 'New chat',
        updatedAt = _dt(j['updated_at']),
        messageCount = (j['message_count'] as num?)?.toInt() ?? 0;
}

class StudioOutput {
  final String id;
  final String type; // audio | report | flashcards | quiz | mindmap | table
  String title;
  final String status; // queued | running | ready | error
  final int progress;
  final String? error;
  final String prompt;
  final Map<String, dynamic> options;
  final List<String> sourceIds;
  final Map<String, dynamic> content;
  final bool hasMedia;
  final double? durationS;
  bool unread;
  final DateTime? createdAt;

  StudioOutput.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        type = j['type'],
        title = j['title'] ?? '',
        status = j['status'] ?? 'queued',
        progress = (j['progress'] as num?)?.toInt() ?? 0,
        error = j['error'],
        prompt = j['prompt'] ?? '',
        options = Map<String, dynamic>.from(j['options'] ?? {}),
        sourceIds = List<String>.from(j['source_ids'] ?? const []),
        content = Map<String, dynamic>.from(j['content'] ?? {}),
        hasMedia = (j['has_media'] ?? 0) == 1,
        durationS = (j['duration_s'] as num?)?.toDouble(),
        unread = (j['unread'] ?? 0) == 1,
        createdAt = _dt(j['created_at']);

  bool get busy => status == 'queued' || status == 'running';
}

class Note {
  final String id;
  final String kind;
  String title;
  String content;
  final List<Citation> citations;
  int version;
  final DateTime? updatedAt;

  Note.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        kind = j['kind'] ?? 'note',
        title = j['title'] ?? 'New note',
        content = j['content'] ?? '',
        citations = [for (final c in (j['citations'] ?? const [])) Citation.fromJson(Map<String, dynamic>.from(c))],
        version = (j['version'] as num?)?.toInt() ?? 1,
        updatedAt = _dt(j['updated_at']);
}
