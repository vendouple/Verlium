import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';

void _download(StudioOutput o) =>
    launchUrl(Uri.parse(Api.I.mediaUrl('/studio/${o.id}/media')), mode: LaunchMode.externalApplication);

// ---- slide deck (UI-SPEC §5: 16:9 slides, thumbnails, notes) -----------------------------------

class SlidesView extends StatefulWidget {
  final StudioOutput output;
  const SlidesView({super.key, required this.output});

  @override
  State<SlidesView> createState() => _SlidesViewState();
}

class _SlidesViewState extends State<SlidesView> {
  final _page = PageController();
  int _i = 0;
  bool _notes = false;

  List<Map> get _slides => List<Map>.from(widget.output.content['slides'] ?? const []);
  String _img(int i) => Api.I.mediaUrl('/studio/${widget.output.id}/asset/$i');

  void _go(int i) {
    if (i < 0 || i >= _slides.length) return;
    _page.animateToPage(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final slides = _slides;
    if (slides.isEmpty) return const Center(child: Text('No slides'));
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          _go(_i + 1);
        } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _go(_i - 1);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PageView.builder(
                    controller: _page,
                    itemCount: slides.length,
                    onPageChanged: (i) => setState(() => _i = i),
                    itemBuilder: (_, i) => Image.network(_img(i), fit: BoxFit.contain,
                        loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator())),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_notes && (slides[_i]['notes'] ?? '').toString().isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 140),
            decoration: BoxDecoration(color: v.tonal, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(child: Text(slides[_i]['notes'].toString(), style: vText(13, 20))),
          ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: slides.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _go(i),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: i == _i ? v.primary : Colors.transparent, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AspectRatio(aspectRatio: 16 / 9, child: Image.network(_img(i), fit: BoxFit.cover)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(children: [
            IconButton(onPressed: _i > 0 ? () => _go(_i - 1) : null, icon: const Icon(Icons.chevron_left)),
            Text('${_i + 1} / ${slides.length}', style: vText(13, 18, color: v.textStrong)),
            IconButton(onPressed: _i < slides.length - 1 ? () => _go(_i + 1) : null, icon: const Icon(Icons.chevron_right)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _notes = !_notes),
              icon: Icon(_notes ? Icons.speaker_notes : Icons.speaker_notes_outlined, size: 18),
              label: const Text('Notes'),
            ),
            TextButton.icon(
              onPressed: () => _download(widget.output),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---- infographic --------------------------------------------------------------------------------

class InfographicView extends StatelessWidget {
  final StudioOutput output;
  const InfographicView({super.key, required this.output});

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.network(Api.I.mediaUrl('/studio/${output.id}/media'),
                  loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator())),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Text('Scroll or pinch to zoom', style: vText(12, 16, color: context.v.textMuted)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _download(output),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
            ),
          ]),
        ),
      ]);
}

// ---- video ----------------------------------------------------------------------------------------

class VideoView extends StatefulWidget {
  final StudioOutput output;
  const VideoView({super.key, required this.output});

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final _player = Player();
  late final _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(Api.I.mediaUrl('/studio/${widget.output.id}/media')), play: false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final vertical = widget.output.content['aspect'] == '9:16';
    final lines = List<Map>.from(widget.output.content['transcript'] ?? const []);
    return Column(children: [
      Expanded(
        flex: 3,
        child: Center(
          child: AspectRatio(
            aspectRatio: vertical ? 9 / 16 : 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Video(controller: _controller, controls: MaterialVideoControls),
            ),
          ),
        ),
      ),
      if (lines.isNotEmpty)
        Expanded(
          flex: 2,
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
            for (final l in lines)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: l['start'] == null
                    ? null
                    : () => _player.seek(Duration(milliseconds: ((l['start'] as num) * 1000).round())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Text.rich(TextSpan(children: [
                    if (l['title'] != null)
                      TextSpan(text: '${l['title']}  ', style: TextStyle(fontWeight: FontWeight.w600, color: v.textStrong)),
                    TextSpan(text: l['text'].toString()),
                  ]), style: vText(13, 20, color: v.text)),
                ),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _download(widget.output),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download MP4'),
          ),
        ),
      ),
    ]);
  }
}
