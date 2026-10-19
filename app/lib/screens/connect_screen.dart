import 'package:flutter/material.dart';

import '../api/api.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import 'home_screen.dart';

/// First run: point the app at the Verlium server and enter the single-user token.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _url = TextEditingController(text: Api.I.baseUrl.isEmpty ? 'http://localhost:8000' : Api.I.baseUrl);
  final _token = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.save(_url.text, _token.text);
      await Api.I.health();
      await Api.I.get('/notebooks'); // verifies the token
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: VerliumLogo(size: 40, showText: true)),
                const SizedBox(height: 32),
                Text('Connect to your Verlium server', style: vText(22, 28, color: v.textTitle)),
                const SizedBox(height: 8),
                Text('Your notebooks and model keys live on your server, so every device sees the same thing.',
                    style: vText(14, 20, color: v.textMuted)),
                const SizedBox(height: 24),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'Server URL'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _token,
                  decoration: const InputDecoration(labelText: 'Access token (VERLIUM_API_TOKEN)'),
                  obscureText: true,
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: v.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
