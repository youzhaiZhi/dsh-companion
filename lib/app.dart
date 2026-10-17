import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/contracts.dart';
import 'ui/screens/devices_screen.dart';
import 'ui/theme.dart';

/// 根组件：注入 CompanionController，统一主题与路由。
class DshCompanionApp extends StatelessWidget {
  const DshCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CompanionController>(
      builder: (context, controller, _) {
        final mode = switch (controller.settings.themeMode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        };
        return MaterialApp(
          title: 'DSH 伴侣',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: mode,
          home: const DevicesScreen(),
        );
      },
    );
  }
}

/// 所有页面共用的 controller 取用方式。
CompanionController watchController(BuildContext context) =>
    context.watch<CompanionController>();

CompanionController readController(BuildContext context) =>
    context.read<CompanionController>();

/// 便捷：把异常转成用户可读文案。
String describeError(Object error) =>
    error is CompanionException ? error.message : '$error';
