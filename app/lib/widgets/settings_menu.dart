import 'package:flutter/material.dart';

import '../api/api.dart';
import '../main.dart';
import '../screens/connect_screen.dart';
import '../screens/memory_screen.dart';
import '../screens/models_screen.dart';
import '../theme.dart';
import 'common.dart';

/// ⚙ menu (UI-SPEC §3.1, Verlium version).
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Settings',
        icon: Icon(Icons.settings_outlined, color: context.v.iconMuted),
        onSelected: (v) async {
          switch (v) {
            case 'models':
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModelsScreen()));
            case 'memory':
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemoryScreen()));
            case 'light':
              themeMode.value = ThemeMode.light;
            case 'dark':
              themeMode.value = ThemeMode.dark;
            case 'system':
              themeMode.value = ThemeMode.system;
            case 'server':
              await Api.I.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const ConnectScreen()), (_) => false);
              }
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'models', child: MenuRow(Icons.tune_rounded, 'Models & providers')),
          const PopupMenuItem(value: 'memory', child: MenuRow(Icons.person_outline, 'Personalisation')),
          const PopupMenuDivider(),
          PopupMenuItem(
              value: 'light',
              child: MenuRow(themeMode.value == ThemeMode.light ? Icons.check : Icons.light_mode_outlined, 'Light')),
          PopupMenuItem(
              value: 'dark',
              child: MenuRow(themeMode.value == ThemeMode.dark ? Icons.check : Icons.dark_mode_outlined, 'Dark')),
          PopupMenuItem(
              value: 'system',
              child: MenuRow(themeMode.value == ThemeMode.system ? Icons.check : Icons.devices_outlined, 'Device')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'server', child: MenuRow(Icons.dns_outlined, 'Change server')),
        ],
      );
}
