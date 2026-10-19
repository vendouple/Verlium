import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'widgets/activity_panel.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Api.I.load();
  final prefs = await SharedPreferences.getInstance();
  themeMode.value = ThemeMode.values.byName(prefs.getString('theme') ?? 'dark');
  themeMode.addListener(() => prefs.setString('theme', themeMode.value.name));
  runApp(const VerliumApp());
}

class VerliumApp extends StatelessWidget {
  const VerliumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Verlium',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        // Own Overlay so the shell's tooltips work outside the Navigator.
        builder: (context, child) => Overlay(initialEntries: [
          OverlayEntry(builder: (_) => ActivityShell(child: child ?? const SizedBox())),
        ]),
        home: Api.I.configured ? const HomeScreen() : const ConnectScreen(),
      ),
    );
  }
}
