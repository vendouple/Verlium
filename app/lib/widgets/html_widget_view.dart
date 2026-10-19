import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme.dart';

String _css(Color c) {
  final argb = c.toARGB32();
  return 'rgba(${(argb >> 16) & 255},${(argb >> 8) & 255},${argb & 255},${((argb >> 24) & 255) / 255})';
}

/// The page shell around a model-written widget: theme variables, base styles for inputs, and a
/// bridge that reports the content height (so the card fits it) and forwards wheel scrolling.
String widgetPage(String body, VTokens v, {required bool dark}) => '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:${_css(v.tonal)};--panel:${_css(v.panel)};--text:${_css(v.text)};--strong:${_css(v.textStrong)};
--muted:${_css(v.textMuted)};--primary:${_css(v.primary)};--accent:#F6A23A;--success:${_css(v.success)};
--warn:#F6C344;--danger:${_css(v.error)};--border:${_css(v.divider)};color-scheme:${dark ? 'dark' : 'light'}}
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:var(--bg);color:var(--text);
font:14px/1.5 "Segoe UI",Inter,system-ui,-apple-system,Roboto,sans-serif;overflow:hidden}
#root{padding:14px 16px}
h1,h2,h3,h4{color:var(--strong);margin:.2em 0 .5em;font-weight:600}
h1{font-size:18px}h2{font-size:16px}h3{font-size:15px}
input[type=range]{width:100%;accent-color:var(--primary);height:22px}
button{font:inherit;color:var(--strong);background:var(--panel);border:1px solid var(--border);border-radius:999px;
padding:6px 14px;cursor:pointer}button:hover{border-color:var(--primary)}
button.primary{background:var(--primary);border-color:var(--primary);color:#fff}
select,input[type=number],input[type=text]{font:inherit;color:var(--strong);background:var(--panel);
border:1px solid var(--border);border-radius:8px;padding:5px 8px}
label{color:var(--muted)}
svg text{fill:var(--text)}
canvas,svg{max-width:100%}
</style></head>
<body><div id="root">$body</div>
<script>
(function(){
  var post=function(n,v){try{window.flutter_inappwebview.callHandler(n,v)}catch(e){}};
  var last=0;
  function report(){var h=Math.ceil(document.getElementById('root').getBoundingClientRect().height);
    if(Math.abs(h-last)>1){last=h;post('height',h)}}
  window.addEventListener('flutterInAppWebViewPlatformReady',report);
  window.addEventListener('load',report);
  new ResizeObserver(report).observe(document.getElementById('root'));
  setTimeout(report,50);setTimeout(report,400);
  // The card is sized to its content, so wheel events belong to the chat list.
  window.addEventListener('wheel',function(e){if(!e.defaultPrevented)post('wheel',e.deltaY)},{passive:true});
  window.addEventListener('error',function(e){post('jserror',String(e.message||e))});
})();
</script></body></html>''';

/// Renders an AI-written HTML/SVG/JS widget inline, sandboxed: no navigation, sized to its content.
class HtmlWidgetView extends StatefulWidget {
  final String html;
  final bool fullscreen;
  const HtmlWidgetView({super.key, required this.html, this.fullscreen = false});

  @override
  State<HtmlWidgetView> createState() => _HtmlWidgetViewState();
}

class _HtmlWidgetViewState extends State<HtmlWidgetView> {
  double _height = 320;
  bool _source = false, _loaded = false;
  String? _jsError;
  int _reload = 0;

  String get _title {
    final m = RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>', dotAll: true).firstMatch(widget.html) ??
        RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(widget.html);
    final t = m?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return (t == null || t.isEmpty) ? 'Interactive visual' : t;
  }

  void _scrollChat(double dy) {
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == null) return;
    pos.jumpTo((pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  void _openFullscreen() => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 1100,
            child: SingleChildScrollView(child: HtmlWidgetView(html: widget.html, fullscreen: true)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: v.tonal,
        borderRadius: BorderRadius.circular(widget.fullscreen ? 0 : 16),
        border: widget.fullscreen ? null : Border.all(color: v.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
          child: Row(children: [
            Icon(Icons.auto_graph_rounded, size: 18, color: v.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(13, 18, weight: FontWeight.w600, color: v.textMuted)),
            ),
            if (_jsError != null)
              Tooltip(message: 'Script error: $_jsError', child: Icon(Icons.warning_amber_rounded, size: 18, color: v.error)),
            IconButton(
              tooltip: 'Restart',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _reload++;
                _jsError = null;
                _loaded = false;
              }),
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
            IconButton(
              tooltip: _source ? 'Show visual' : 'View code',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _source = !_source),
              icon: Icon(_source ? Icons.visibility_outlined : Icons.code_rounded, size: 18),
            ),
            if (!widget.fullscreen)
              IconButton(
                tooltip: 'Expand',
                visualDensity: VisualDensity.compact,
                onPressed: _openFullscreen,
                icon: const Icon(Icons.open_in_full_rounded, size: 17),
              ),
          ]),
        ),
        if (_source)
          Container(
            constraints: const BoxConstraints(maxHeight: 420),
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: v.bg, borderRadius: BorderRadius.circular(8)),
            child: Stack(children: [
              SingleChildScrollView(
                child: SelectableText(widget.html.trim(), style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: v.text)),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Copy',
                  onPressed: () => Clipboard.setData(ClipboardData(text: widget.html)),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                ),
              ),
            ]),
          )
        else
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: _height.clamp(60, widget.fullscreen ? 2000 : 900),
            child: Stack(children: [
              InAppWebView(
                key: ValueKey('$_reload$dark'),
                initialData: InAppWebViewInitialData(
                  data: widgetPage(widget.html, v, dark: dark),
                  baseUrl: WebUri('about:blank'),
                ),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  supportZoom: false,
                  disableContextMenu: true,
                  useShouldOverrideUrlLoading: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  verticalScrollBarEnabled: false,
                ),
                onWebViewCreated: (c) {
                  c.addJavaScriptHandler(
                    handlerName: 'height',
                    callback: (a) {
                      final h = (a.first as num).toDouble();
                      if (mounted) setState(() => _height = h + 2);
                    },
                  );
                  c.addJavaScriptHandler(handlerName: 'wheel', callback: (a) => _scrollChat((a.first as num).toDouble()));
                  c.addJavaScriptHandler(
                    handlerName: 'jserror',
                    callback: (a) {
                      if (mounted) setState(() => _jsError = a.first.toString());
                    },
                  );
                },
                onLoadStop: (_, _) {
                  if (mounted) setState(() => _loaded = true);
                },
                // Model-written content never navigates anywhere.
                shouldOverrideUrlLoading: (_, action) async {
                  final u = action.request.url?.toString() ?? '';
                  return u.startsWith('about:') || u.startsWith('data:')
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL;
                },
              ),
              if (!_loaded)
                Positioned.fill(
                  child: ColoredBox(
                    color: v.tonal,
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: v.primary))),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
