import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/contracts.dart';
import '../strings.dart';
import 'pair_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';

/// 设备列表 / 首页。
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = watchController(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appTitle),
        actions: <Widget>[
          IconButton(
            tooltip: AppStrings.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: controller.initializing
          ? const Center(child: CircularProgressIndicator())
          : controller.devices.isEmpty
              ? _EmptyState(onPair: () => _openPair(context))
              : RefreshIndicator(
                  onRefresh: controller.refreshSessions,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: controller.devices.length,
                    itemBuilder: (context, index) {
                      final device = controller.devices[index];
                      return _DeviceCard(device: device);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPair(context),
        icon: const Icon(Icons.add_link),
        label: const Text(AppStrings.addDevice),
      ),
    );
  }

  void _openPair(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PairScreen()));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPair});

  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.devices_other, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(AppStrings.devicesEmptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              AppStrings.devicesEmptyBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPair,
              icon: const Icon(Icons.qr_code_2),
              label: const Text(AppStrings.addDevice),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final DeviceRecord device;

  @override
  Widget build(BuildContext context) {
    final controller = watchController(context);
    final active = controller.activeDevice?.instanceId == device.instanceId &&
        controller.activeDevice?.origin == device.origin;
    final phase = controller.phase;
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          try {
            await controller.connect(device);
            if (context.mounted) {
              _openSessions(context);
            }
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(error))));
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.computer, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(device.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${device.origin.host}:${device.origin.port} · ${gatewayKindLabel(device.kind)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (active)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          connectionLabel(phase),
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'connect':
                      await controller.connect(device);
                      if (context.mounted) {
                        _openSessions(context);
                      }
                    case 'rename':
                      await _rename(context, controller, device);
                    case 'delete':
                      await controller.removeDevice(device.instanceId);
                  }
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'connect', child: Text(AppStrings.connect)),
                  PopupMenuItem<String>(value: 'rename', child: Text(AppStrings.rename)),
                  PopupMenuItem<String>(value: 'delete', child: Text(AppStrings.delete)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, CompanionController controller, DeviceRecord device) async {
    final textController = TextEditingController(text: device.label);
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.rename),
        content: TextField(controller: textController, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(textController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) {
      await controller.renameDevice(device.instanceId, label);
    }
  }

  void _openSessions(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SessionsScreen()));
  }
}
