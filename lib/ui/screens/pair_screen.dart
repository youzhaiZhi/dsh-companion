import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../strings.dart';

/// 配对页：粘贴配对链接，或手动填网关地址 + 配对码。
class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _originController = TextEditingController(text: 'https://192.168.1.2:3443');
  final TextEditingController _codeController = TextEditingController();
  bool _manual = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _linkController.dispose();
    _originController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = readController(context);
      if (_manual) {
        final origin = Uri.tryParse(_originController.text.trim());
        if (origin == null || !origin.hasScheme || origin.host.isEmpty) {
          throw Exception('请输入形如 https://192.168.1.2:3443 的地址');
        }
        await controller.pairWithCode(origin: origin, code: _codeController.text.trim());
      } else {
        await controller.pairWithLink(_linkController.text.trim());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStrings.pairSuccess)));
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.pairTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!_manual) ...<Widget>[
            TextField(
              controller: _linkController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: AppStrings.pairLinkLabel,
                hintText: AppStrings.pairLinkHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _linkController.text = data!.text!;
                  }
                },
                icon: const Icon(Icons.content_paste),
                label: const Text(AppStrings.pairPaste),
              ),
            ),
          ] else ...<Widget>[
            TextField(
              controller: _originController,
              decoration: const InputDecoration(labelText: AppStrings.pairOriginLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: AppStrings.pairCodeLabel),
            ),
          ],
          const SizedBox(height: 8),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? AppStrings.pairWorking : AppStrings.pairSubmit),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _manual = !_manual),
            child: Text(_manual ? '改用配对链接' : AppStrings.pairManual),
          ),
          const SizedBox(height: 24),
          Text(
            '配对链接在电脑上生成：DSH → 设置 → 移动访问 → 局域网 → 创建配对密钥。链接几分钟内有效。',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
