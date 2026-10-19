import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pasteboard/pasteboard.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../state/notebook_store.dart';
import '../theme.dart';
import 'common.dart';

String _thumb(ChatAttachment a) => Api.I.mediaUrl('/attachments/${a.id}/thumb');
String _media(ChatAttachment a) => Api.I.mediaUrl('/attachments/${a.id}/media');

String _dur(double? s) {
  if (s == null) return '';
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

void _attachAll(BuildContext context, NotebookStore store, Iterable<(String, List<int>)> files) {
  final errors = <String>[];
  for (final (name, bytes) in files) {
    final err = store.attach(name, bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (err != null) errors.add(err);
  }
  if (errors.isNotEmpty && context.mounted) toast(context, errors.join('\n'));
}

Future<void> pickChatAttachments(BuildContext context, NotebookStore store) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'mp4', 'mov', 'webm', 'mkv', 'm4v', 'avi'],
  );
  if (files.isEmpty) return;
  final read = [for (final f in files) (f.name, await f.readAsBytes())];
  if (context.mounted) _attachAll(context, store, read);
}

Future<void> attachDropped(BuildContext context, NotebookStore store, List<dynamic> xfiles) async {
  final read = <(String, List<int>)>[];
  for (final f in xfiles) {
    read.add((f.name as String, await f.readAsBytes() as List<int>));
  }
  if (context.mounted) _attachAll(context, store, read);
}

/// Ctrl+V with an image (screenshot) or copied files on the clipboard. Returns true if it attached something.
Future<bool> pasteChatAttachments(BuildContext context, NotebookStore store) async {
  try {
    final files = await Pasteboard.files();
    final media = files.where((f) => attachmentKind(f) != null).toList();
    if (media.isNotEmpty) {
      final read = <(String, List<int>)>[];
      for (final path in media) {
        read.add((path.split(RegExp(r'[\\/]')).last, await File(path).readAsBytes()));
      }
      if (context.mounted) _attachAll(context, store, read);
      return true;
    }
    final img = await Pasteboard.image;
    if (img != null && img.isNotEmpty) {
      final stamp = DateTime.now().toIso8601String().substring(11, 19).replaceAll(':', '');
      if (context.mounted) _attachAll(context, store, [('pasted-$stamp.png', img)]);
      return true;
    }
  } catch (_) {}
  return false;
}

/// Pending attachments shown inside the chat box while composing.
class PendingAttachmentStrip extends StatelessWidget {
  final NotebookStore store;
  const PendingAttachmentStrip({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    if (store.pending.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        itemCount: store.pending.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = store.pending[i];
          final tile = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: p.kind == 'image' ? 64 : 150,
              color: v.panel,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (p.kind == 'image')
                    Image.memory(
                      p.bytes,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      errorBuilder: (_, _, _) => Icon(Icons.image_outlined, color: v.iconMuted),
                    )
                  else if (p.uploaded != null)
                    Image.network(_thumb(p.uploaded!), fit: BoxFit.cover)
                  else
                    ColoredBox(color: v.tonal),
                  if (p.kind == 'video')
                    Container(
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xAA000000)],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.videocam_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              p.uploaded?.duration != null ? _dur(p.uploaded!.duration) : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (p.uploading)
                    Container(
                      color: const Color(0x88000000),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  if (p.error != null)
                    Tooltip(
                      message: p.error!,
                      child: Container(
                        color: v.error.withValues(alpha: .55),
                        alignment: Alignment.center,
                        child: const Icon(Icons.error_outline, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(message: p.name, child: tile),
              Positioned(
                right: -6,
                top: -6,
                child: Material(
                  color: v.panel,
                  shape: CircleBorder(side: BorderSide(color: v.outline)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => store.removeAttachment(p),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.close, size: 13, color: v.text),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Thumbnails inside a sent message; tap to view full size / play.
class MessageAttachments extends StatelessWidget {
  final List<ChatAttachment> attachments;
  const MessageAttachments({super.key, required this.attachments});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final single = attachments.length == 1;
    final h = single ? 220.0 : 120.0;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in attachments)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AttachmentViewer(attachment: a),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: h,
                width: (h * a.aspect).clamp(h * .6, single ? 420 : 220),
                color: v.panel,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      _thumb(a),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(a.isVideo ? Icons.videocam_outlined : Icons.image_outlined, color: v.iconMuted),
                    ),
                    if (a.isVideo) ...[
                      const Center(
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0x99000000),
                          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x99000000),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_dur(a.duration), style: const TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AttachmentViewer extends StatefulWidget {
  final ChatAttachment attachment;
  const AttachmentViewer({super.key, required this.attachment});

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isVideo) {
      _player = Player();
      _controller = VideoController(_player!);
      _player!.open(Media(_media(widget.attachment)));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: a.aspect,
            child: a.isVideo
                ? Video(controller: _controller!, controls: MaterialVideoControls)
                : InteractiveViewer(
                    maxScale: 6,
                    child: Image.network(
                      _media(a),
                      fit: BoxFit.contain,
                      loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: const Color(0x88000000), foregroundColor: Colors.white),
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
