import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/contracts.dart';
import '../strings.dart';

/// 设置：通知开关、主题、诊断日志、版本。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = watchController(context);
    final settings = controller.settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settings)),
      body: ListView(
        children: <Widget>[
          const _SectionHeader(title: AppStrings.notifications),
          SwitchListTile(
            title: const Text(AppStrings.notifications),
            value: settings.notificationsEnabled,
            onChanged: (value) => controller.updateSettings(settings.copyWith(notificationsEnabled: value)),
          ),
          SwitchListTile(
            title: const Text(AppStrings.notifyComplete),
            value: settings.notifyOnComplete,
            onChanged: settings.notificationsEnabled
                ? (value) => controller.updateSettings(settings.copyWith(notifyOnComplete: value))
                : null,
          ),
          SwitchListTile(
            title: const Text(AppStrings.notifyWaiting),
            value: settings.notifyOnWaiting,
            onChanged: settings.notificationsEnabled
                ? (value) => controller.updateSettings(settings.copyWith(notifyOnWaiting: value))
                : null,
          ),
          const Divider(),
          const _SectionHeader(title: AppStrings.theme),
          for (final mode in AppThemeMode.values)
            RadioListTile<AppThemeMode>(
              title: Text(switch (mode) {
                AppThemeMode.system => AppStrings.themeSystem,
                AppThemeMode.light => AppStrings.themeLight,
                AppThemeMode.dark => AppStrings.themeDark,
              }),
              value: mode,
              // ignore: deprecated_member_use
              groupValue: settings.themeMode,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  controller.updateSettings(settings.copyWith(themeMode: value));
                }
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text(AppStrings.diagnostics),
            subtitle: const Text('查看最近的连接与协议日志（不含令牌）'),
            onTap: () async {
              final text = await controller.exportDiagnostics();
              if (!context.mounted) {
                return;
              }
              await showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text(AppStrings.diagnostics),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text.isEmpty ? '暂无日志' : text,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('关闭')),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text('DSH 伴侣 0.1.0'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
