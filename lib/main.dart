import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/contracts.dart';
import 'core/state/companion_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider<CompanionController>(
      create: (_) => CompanionControllerImpl()..initialize(),
      child: const DshCompanionApp(),
    ),
  );
}
