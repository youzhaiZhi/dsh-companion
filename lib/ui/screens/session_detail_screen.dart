import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/contracts.dart';
import '../strings.dart';

/// 会话详情：实时事件流 + 审批卡片 + 输入栏。
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await readController(context).sendPrompt(widget.sessionId, text);
      _input.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = watchController(context);
    final feed = controller.activeFeed;
    final theme = Theme.of(context);
    final events = feed?.events ?? const <SessionEvent>[];
    // 审批来自 `$events` 瀑布（控制器全局维护），按会话过滤后内联展示。
    final approvals = controller.pendingApprovals
        .where((request) => request.sessionId == widget.sessionId)
        .toList(growable: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });

    return Scaffold(
      appBar:
          AppBar(title: Text(feed?.summary?.title ?? AppStrings.sessionsTitle)),
      body: Column(
        children: <Widget>[
          if (feed?.error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Text('${feed!.error}',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text(
                      AppStrings.noMessage,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    itemCount: events.length,
                    itemBuilder: (context, index) =>
                        _EventCard(event: events[index]),
                  ),
          ),
          for (final approval in approvals) _ApprovalCard(request: approval),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration:
                          const InputDecoration(hintText: AppStrings.sendHint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final SessionEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (event.kind) {
      case SessionEventKind.userMessage:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14)),
            child: Text(event.text ?? '',
                style: TextStyle(color: scheme.onPrimaryContainer)),
          ),
        );
      case SessionEventKind.assistantMessage:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14)),
          child: Text(event.text ?? '', style: theme.textTheme.bodyMedium),
        );
      case SessionEventKind.toolCall:
      case SessionEventKind.toolResult:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                event.toolStatus == 'running'
                    ? Icons.build_circle_outlined
                    : Icons.check_circle_outline,
                size: 18,
                color: event.toolStatus == 'running'
                    ? scheme.primary
                    : scheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${event.toolName ?? '工具'} · ${event.toolDetail ?? event.text ?? ''}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      case SessionEventKind.statusChange:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              event.toolStatus == 'running' ? '开始执行…' : '本轮结束',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        );
      case SessionEventKind.error:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12)),
          child: Text(event.text ?? '出错了',
              style: TextStyle(color: scheme.onErrorContainer)),
        );
      case SessionEventKind.approvalRequest:
        return const SizedBox.shrink();
      case SessionEventKind.usage:
      case SessionEventKind.unknown:
        return const SizedBox.shrink();
    }
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.request});

  final ApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final controller = readController(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(request.title, style: theme.textTheme.titleSmall),
              if (request.detail != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(request.detail!, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () async {
                      try {
                        await controller.decideApproval(
                            request, ApprovalDecision.deny);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(describeError(error))));
                        }
                      }
                    },
                    child: const Text(AppStrings.deny),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await controller.decideApproval(
                            request, ApprovalDecision.allow);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(describeError(error))));
                        }
                      }
                    },
                    child: const Text(AppStrings.approve),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
