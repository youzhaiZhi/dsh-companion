import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/contracts.dart';
import '../strings.dart';
import 'session_detail_screen.dart';
import 'settings_screen.dart';

/// 会话列表。
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = watchController(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.activeDevice?.label ?? AppStrings.sessionsTitle),
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
      body: Column(
        children: <Widget>[
          if (controller.connectionError != null)
            MaterialBanner(
              content: Text(controller.connectionError!),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    final device = controller.activeDevice;
                    if (device != null) {
                      await controller.connect(device);
                    }
                  },
                  child: const Text(AppStrings.retry),
                ),
              ],
            ),
          if (controller.sessions.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  AppStrings.sessionsEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refreshSessions,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: controller.sessions.length,
                  itemBuilder: (context, index) {
                    final session = controller.sessions[index];
                    return Card(
                      child: ListTile(
                        onTap: () async {
                          await controller.openSession(session.id);
                          if (context.mounted) {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SessionDetailScreen(sessionId: session.id),
                              ),
                            );
                            await controller.closeSession();
                          }
                        },
                        title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          <String>[
                            statusLabel(session.status),
                            if (session.workspace != null) session.workspace!,
                            _relative(session.updatedAt),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor(context, session.status),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    }
    return '${diff.inDays} 天前';
  }
}
