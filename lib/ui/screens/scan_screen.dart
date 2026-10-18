import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../strings.dart';

/// 扫码配对：扫描电脑上 DSH「移动访问」生成的配对二维码。
///
/// 二维码内容就是配对链接本身
/// （`https://<电脑IP>:3443/mobile-access/pair#instance=...&token=...`），
/// 因此扫到后直接交给 `pairWithLink`，走与粘贴完全相同的逻辑。
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) {
        continue;
      }
      _handled = true;
      // 把结果交回配对页；由它负责调用 pairWithLink 并展示错误。
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.scanTitle),
        actions: <Widget>[
          IconButton(
            tooltip: '手电筒',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: '切换摄像头',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              final message = _scanErrorMessage(error);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.no_photography_outlined,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('返回手动输入'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // 取景框
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  AppStrings.scanHint,
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 把相机错误翻成用户能看懂的话。
  String _scanErrorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return '没有相机权限。请在系统设置里允许「DSH 伴侣」使用相机，或返回手动输入配对链接。';
      case MobileScannerErrorCode.unsupported:
        return '这台设备的相机不支持扫码，请返回手动输入配对链接。';
      default:
        return '相机启动失败：${error.errorDetails?.message ?? error.errorCode.name}';
    }
  }
}
