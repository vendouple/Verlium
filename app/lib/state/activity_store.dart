import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api.dart';

class ActivityJob {
  final String id, kind, label, status;
  final String? notebookId, error;
  final int progress, attempts;
  ActivityJob.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        kind = j['kind'],
        label = j['label'] ?? j['kind'],
        status = j['status'],
        notebookId = j['notebook_id'],
        error = j['error'],
        progress = (j['progress'] as num? ?? 0).round(),
        attempts = (j['attempts'] as num? ?? 0).round();
}

class ActivityEvent {
  final int seq;
  final DateTime time;
  final String level, message; // level: debug | info | success | warn | error
  final String? jobId, kind;
  ActivityEvent(this.seq, this.time, this.level, this.message, {this.jobId, this.kind});
  ActivityEvent.fromJson(Map<String, dynamic> j)
      : seq = j['seq'],
        time = DateTime.fromMillisecondsSinceEpoch(((j['ts'] as num) * 1000).round()),
        level = j['level'],
        message = j['message'],
        jobId = j['job_id'],
        kind = j['kind'];

  bool get notable => level == 'success' || level == 'error' || level == 'warn';
}

/// App-wide live feed of background work (GET /activity), for the debug dock and toasts.
/// Polls fast while something is running, slowly when idle.
class ActivityStore extends ChangeNotifier {
  ActivityStore._();
  static final ActivityStore I = ActivityStore._();

  final List<ActivityEvent> events = [];
  List<ActivityJob> jobs = const [];
  bool serverOk = true, dbOk = true;
  int unseenErrors = 0;

  /// Toasts: notable events that arrived after the app started.
  final toasts = StreamController<ActivityEvent>.broadcast();

  int _seq = 0, _local = -1;
  bool _primed = false, _panelOpen = false;
  Timer? _timer;

  bool get busy => jobs.any((j) => j.status == 'running');
  int get activeCount => jobs.length;

  void start() {
    if (_timer != null) return;
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fetch now (e.g. right after the user starts a job), instead of waiting for the next tick.
  void poke() {
    _timer?.cancel();
    _tick();
  }

  set panelOpen(bool v) {
    _panelOpen = v;
    if (v && unseenErrors > 0) {
      unseenErrors = 0;
      notifyListeners();
    }
  }

  void clear() {
    events.clear();
    unseenErrors = 0;
    notifyListeners();
  }

  void _addLocal(String level, String message) {
    final e = ActivityEvent(_local--, DateTime.now(), level, message);
    events.add(e);
    if (_primed) toasts.add(e);
  }

  Future<void> _tick() async {
    if (!Api.I.configured) {
      _timer = Timer(const Duration(seconds: 3), _tick);
      return;
    }
    try {
      final r = await Api.I.get('/activity', {'since': '$_seq'}) as Map<String, dynamic>;
      // Server restarted: its sequence starts over, so start over too.
      if ((r['seq'] as num) < _seq) _seq = 0;
      if (!serverOk) _addLocal('success', 'Server connection restored');
      serverOk = true;
      final db = r['db_ok'] != false;
      if (dbOk && !db) _addLocal('error', 'Server can’t reach the database');
      if (!dbOk && db) _addLocal('success', 'Database connection restored');
      dbOk = db;
      jobs = [for (final j in r['jobs'] as List) ActivityJob.fromJson(j)];
      for (final j in r['events'] as List) {
        final e = ActivityEvent.fromJson(j);
        _seq = e.seq > _seq ? e.seq : _seq;
        events.add(e);
        if (_primed && e.notable) {
          toasts.add(e);
          if (e.level == 'error' && !_panelOpen) unseenErrors++;
        }
      }
      if (events.length > 400) events.removeRange(0, events.length - 400);
    } catch (e) {
      if (serverOk) _addLocal('error', 'Server unreachable: $e');
      serverOk = false;
      jobs = const [];
    }
    _primed = true;
    notifyListeners();
    final wait = !serverOk ? 6 : (jobs.isNotEmpty ? 1 : 4);
    _timer = Timer(Duration(seconds: wait), _tick);
  }
}
