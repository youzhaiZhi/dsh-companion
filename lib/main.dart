import 'package:flutter/material.dart';

/// 临时入口：CI 流水线先跑通，真实入口由 lib/app.dart + CompanionController 注入后替换。
void main() {
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH 伴侣',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4D6BFE), useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('DSH 伴侣')),
      ),
    );
  }
}
