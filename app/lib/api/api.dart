import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// One SSE event from POST /notebooks/{id}/chat.
class ChatEvent {
  final String type; // start | delta | done | error
  final Map<String, dynamic> data;
  ChatEvent(this.type, this.data);
}

/// Thin client for the Verlium server. Provider API keys never live on the device;
/// the device only holds the server URL and the single-user Verlium token.
class Api {
  Api._();
  static final Api I = Api._();

  static const _storage = FlutterSecureStorage();
  final _http = http.Client();
  String baseUrl = '';
  String _token = '';

  bool get configured => baseUrl.isNotEmpty && _token.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('server_url') ?? '';
    _token = await _storage.read(key: 'api_token') ?? '';
  }

  Future<void> save(String url, String token) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    _token = token.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', baseUrl);
    await _storage.write(key: 'api_token', value: _token);
  }

  Future<void> signOut() async {
    _token = '';
    await _storage.delete(key: 'api_token');
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'};

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl/api$path').replace(queryParameters: q);

  /// URL with the token in the query string, for media players and image widgets.
  String mediaUrl(String path) => '$baseUrl/api$path?token=${Uri.encodeQueryComponent(_token)}';

  dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      final msg = detail is Map ? detail['message'] : detail;
      throw ApiException(r.statusCode, msg?.toString() ?? 'Request failed (${r.statusCode})');
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? q]) async =>
      _decode(await _http.get(_u(path, q), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) async =>
      _decode(await _http.post(_u(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> put(String path, Object body) async =>
      _decode(await _http.put(_u(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> patch(String path, Object body) async =>
      _decode(await _http.patch(_u(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> delete(String path) async => _decode(await _http.delete(_u(path), headers: _headers));

  Future<Map<String, dynamic>> health() async {
    final r = await _http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 10));
    return _decode(r) as Map<String, dynamic>;
  }

  Future<dynamic> upload(String path, String filename, Uint8List bytes, {Map<String, String>? fields}) async {
    final req = http.MultipartRequest('POST', _u(path))
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields.addAll(fields ?? {})
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(req);
    return _decode(await http.Response.fromStream(streamed));
  }

  /// Streams chat events. Cancel the subscription to stop generation client-side.
  Stream<ChatEvent> ask(
    String notebookId,
    String question, {
    String? messageId,
    String? threadId,
    bool incognito = false,
    List<Map<String, String>> history = const [],
    String? reasoningEffort,
    List<String> attachmentIds = const [],
  }) async* {
    final req = http.Request('POST', _u('/notebooks/$notebookId/chat'))
      ..headers.addAll(_headers)
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        'question': question,
        'id': ?messageId,
        'thread_id': ?threadId,
        'incognito': incognito,
        if (incognito) 'history': history,
        'reasoning_effort': ?reasoningEffort,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      });
    final resp = await _http.send(req);
    if (resp.statusCode >= 400) {
      _decode(await http.Response.fromStream(resp));
    }
    String event = 'message';
    final data = StringBuffer();
    await for (final line in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield ChatEvent(event, jsonDecode(data.toString()) as Map<String, dynamic>);
        }
        event = 'message';
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      }
    }
  }
}
