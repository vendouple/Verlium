import 'package:flutter/material.dart';

import '../state/notebook_store.dart';
import '../theme.dart';
import 'common.dart';

/// Studio types that can be generated now (others show "coming soon").
const implementedStudio = {
  StudioType.audio: 'audio',
  StudioType.report: 'report',
  StudioType.flashcards: 'flashcards',
  StudioType.quiz: 'quiz',
  StudioType.mindmap: 'mindmap',
  StudioType.table: 'table',
  StudioType.slides: 'slides',
  StudioType.infographic: 'infographic',
  StudioType.video: 'video',
};

Future<void> showStudioDialog(BuildContext context, NotebookStore store, StudioType type) async {
  final key = implementedStudio[type];
  if (key == null) return;
  if (store.selectedSources.isEmpty) {
    toast(context, 'Select at least one processed source first.');
    return;
  }
  await showDialog(context: context, builder: (_) => _CustomizeDialog(store: store, type: type, apiType: key));
}

class _Choice {
  final String value, label, description;
  const _Choice(this.value, this.label, [this.description = '']);
}

const _audioFormats = [
  _Choice('deep_dive', 'Deep Dive', 'A lively conversation between two hosts, unpacking and connecting topics in your sources'),
  _Choice('brief', 'Brief', 'A bite-sized overview to help you grasp the core ideas from your sources quickly'),
  _Choice('critique', 'Critique', 'An expert review of your sources, offering constructive feedback to help you improve your material'),
  _Choice('debate', 'Debate', 'A thoughtful debate between two hosts, illuminating different perspectives on your sources'),
];

const _reportTemplates = [
  _Choice('custom', 'Create Your Own', 'Craft reports your way by specifying structure, style, tone, and more'),
  _Choice('briefing', 'Briefing Doc', 'Overview of your sources featuring key insights and quotes'),
  _Choice('study_guide', 'Study Guide', 'Short-answer quiz, suggested essay questions, and glossary of key terms'),
  _Choice('blog', 'Blog Post', 'Insightful takeaways distilled into a highly readable article'),
  _Choice('faq', 'FAQ', 'The most important questions and answers about your sources'),
  _Choice('timeline', 'Timeline', 'Chronological events plus a cast of characters'),
];

const _slideFormats = [
  _Choice('detailed', 'Detailed Deck', 'A comprehensive deck with full text and details, perfect for emailing or reading on its own'),
  _Choice('presenter', 'Presenter Slides', 'Clean, visual slides with key talking points to support you while you speak'),
];

const _videoFormats = [
  _Choice('short', 'Short (9:16)', 'A 60–90 second vertical video, TikTok/Reels style, with big captions'),
  _Choice('explainer', 'Explainer (16:9)', 'A structured, comprehensive overview like a polished tutorial'),
  _Choice('cinematic', 'Cinematic', 'Generated video clips with narration. Needs a Video model and costs more'),
];

const _infoStyles = {
  'auto': 'Auto-select', 'kawaii': 'Kawaii', 'clay': 'Clay', 'sketch note': 'Sketch Note', 'anime': 'Anime',
  'editorial': 'Editorial', 'instructional': 'Instructional', 'bento grid': 'Bento Grid', 'bricks': 'Bricks',
  'scientific': 'Scientific', 'professional': 'Professional',
};

class _CustomizeDialog extends StatefulWidget {
  final NotebookStore store;
  final StudioType type;
  final String apiType;
  const _CustomizeDialog({required this.store, required this.type, required this.apiType});

  @override
  State<_CustomizeDialog> createState() => _CustomizeDialogState();
}

class _CustomizeDialogState extends State<_CustomizeDialog> {
  final _prompt = TextEditingController();
  final _language = TextEditingController();
  String _format = 'deep_dive', _length = 'default', _template = 'briefing';
  String _count = 'standard', _difficulty = 'medium';
  String _slideFormat = 'detailed', _slideLength = 'default', _render = 'designed', _theme = 'dark';
  String _videoFormat = 'explainer';
  String _orientation = 'landscape', _infoStyle = 'auto', _detail = 'standard';
  bool _busy = false;

  String get _promptLabel => switch (widget.apiType) {
        'audio' => 'What should the AI hosts focus on in this episode?',
        'report' => _template == 'custom' ? 'Describe the report you want to create' : 'Anything to focus on? (optional)',
        'flashcards' || 'quiz' => 'What should the topic be?',
        'mindmap' => 'What should the topic be?',
        'table' => 'Describe the data table you want to create',
        'slides' => 'Describe the slide deck you want to create',
        'video' => 'What should the video focus on?',
        'infographic' => 'Describe the infographic you want to create',
        _ => 'Focus',
      };

  String get _promptHint => switch (widget.apiType) {
        'audio' => 'Things to try\n• Focus on a specific source ("only cover the article about Italy")\n'
            '• Focus on a specific topic ("just discuss the novel\'s main character")\n'
            '• Target a specific audience ("explain to someone new to biology")',
        'table' => 'e.g. "Compare each method by cost, accuracy and year introduced"',
        _ => 'Leave empty for the whole notebook',
      };

  Map<String, dynamic> get _options => {
        if (_language.text.trim().isNotEmpty) 'language': _language.text.trim(),
        if (widget.apiType == 'audio') ...{'format': _format, 'length': _length},
        if (widget.apiType == 'report') 'template': _template,
        if (widget.apiType == 'flashcards' || widget.apiType == 'quiz') ...{'count': _count, 'difficulty': _difficulty},
        if (widget.apiType == 'slides')
          ...{'format': _slideFormat, 'length': _slideLength, 'render': _render, 'theme': _theme},
        if (widget.apiType == 'video') 'format': _videoFormat,
        if (widget.apiType == 'infographic') ...{'orientation': _orientation, 'style': _infoStyle, 'detail': _detail},
      };

  Future<void> _generate() async {
    if (widget.apiType == 'report' && _template == 'custom' && _prompt.text.trim().isEmpty) {
      toast(context, 'Describe the report you want first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.store.generate(widget.apiType, prompt: _prompt.text.trim(), options: _options);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString());
      setState(() => _busy = false);
    }
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: vText(16, 20, weight: FontWeight.w500, color: context.v.textStrong)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _segments(String value, Map<String, String> options, ValueChanged<String> onChanged) => SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  Widget _cards(List<_Choice> choices, String value, ValueChanged<String> onChanged, {double width = 200}) {
    final v = context.v;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in choices)
        SizedBox(
          width: width,
          child: Material(
            color: value == c.value ? v.primaryTonal : v.tonal,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => onChanged(c.value)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(c.label,
                          style: vText(14, 20,
                              weight: FontWeight.w600, color: value == c.value ? v.onPrimaryTonal : v.textStrong)),
                    ),
                    if (value == c.value) Icon(Icons.check_circle, size: 18, color: v.onPrimaryTonal),
                  ]),
                  if (c.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.description,
                        style: vText(12, 16, color: value == c.value ? v.onPrimaryTonal.withValues(alpha: .8) : v.textMuted)),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final t = widget.type;
    final n = widget.store.selectedSources.length;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
            child: Row(children: [
              Icon(t.icon, color: t.tint(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Customize ${t.label}', style: vText(20, 24, weight: FontWeight.w500, color: v.textTitle)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.apiType == 'audio') ...[
                  _section('Format', _cards(_audioFormats, _format, (x) => _format = x, width: 160)),
                  if (_format != 'brief')
                    _section('Length', _segments(_length, const {'short': 'Shorter', 'default': 'Default', 'long': 'Longer'},
                        (x) => setState(() => _length = x))),
                ],
                if (widget.apiType == 'report')
                  _section('Format', _cards(_reportTemplates, _template, (x) => _template = x)),
                if (widget.apiType == 'flashcards' || widget.apiType == 'quiz') ...[
                  _section(
                      widget.apiType == 'quiz' ? 'Number of questions' : 'Number of cards',
                      _segments(_count, const {'fewer': 'Fewer', 'standard': 'Standard (default)', 'more': 'More'},
                          (x) => setState(() => _count = x))),
                  _section('Level of difficulty',
                      _segments(_difficulty, const {'easy': 'Easy', 'medium': 'Medium (default)', 'hard': 'Hard'},
                          (x) => setState(() => _difficulty = x))),
                ],
                if (widget.apiType == 'slides') ...[
                  _section('Format', _cards(_slideFormats, _slideFormat, (x) => _slideFormat = x, width: 300)),
                  _section('Length', _segments(_slideLength, const {'short': 'Short', 'default': 'Default'},
                      (x) => setState(() => _slideLength = x))),
                  _section('Rendering', _segments(_render, const {'designed': 'Designed (crisp text)', 'ai': 'AI-rendered'},
                      (x) => setState(() => _render = x))),
                  _section('Theme', _segments(_theme, const {'dark': 'Dark', 'light': 'Light'},
                      (x) => setState(() => _theme = x))),
                ],
                if (widget.apiType == 'video')
                  _section('Format', _cards(_videoFormats, _videoFormat, (x) => _videoFormat = x, width: 210)),
                if (widget.apiType == 'infographic') ...[
                  _section('Orientation', _segments(_orientation,
                      const {'landscape': 'Landscape', 'portrait': 'Portrait', 'square': 'Square'},
                      (x) => setState(() => _orientation = x))),
                  _section('Visual style', Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in _infoStyles.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _infoStyle == e.key,
                        onSelected: (_) => setState(() => _infoStyle = e.key),
                      ),
                  ])),
                  _section('Level of detail', _segments(_detail,
                      const {'concise': 'Concise', 'standard': 'Standard', 'detailed': 'Detailed'},
                      (x) => setState(() => _detail = x))),
                ],
                _section('Choose language',
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _language,
                        decoration: const InputDecoration(hintText: 'Default (English)', isDense: true),
                      ),
                    )),
                _section(
                    _promptLabel,
                    TextField(
                      controller: _prompt,
                      minLines: widget.apiType == 'audio' ? 4 : 2,
                      maxLines: 8,
                      maxLength: 5000,
                      decoration: InputDecoration(hintText: _promptHint),
                    )),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(children: [
              Icon(Icons.description_outlined, size: 16, color: v.iconMuted),
              const SizedBox(width: 6),
              Text('Based on $n source${n == 1 ? '' : 's'}', style: vText(13, 18, color: v.textMuted)),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                onPressed: _busy ? null : _generate,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Generate'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
