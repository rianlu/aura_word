import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/offline_asr_service.dart';
import '../theme/app_colors.dart';

class OfflineAsrDownloadDialog extends StatefulWidget {
  const OfflineAsrDownloadDialog({super.key});

  static Future<bool> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const OfflineAsrDownloadDialog(),
    ).then((value) => value ?? false);
  }

  @override
  State<OfflineAsrDownloadDialog> createState() => _OfflineAsrDownloadDialogState();
}

class _OfflineAsrDownloadDialogState extends State<OfflineAsrDownloadDialog> {
  double _progress = 0;
  String? _error;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _progress = 0;
    });
    try {
      await OfflineAsrService.instance.download(
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value.clamp(0, 1));
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '下载失败，请检查网络后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '下载离线识别',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textHighEmphasis,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '约 30MB，下载后不依赖系统语音引擎',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textMediumEmphasis,
                ),
              ),
              const SizedBox(height: 20),
              if (_running) ...[
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  color: AppColors.primary,
                  backgroundColor: AppColors.primaryLight,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                Text(
                  _progress == 0 ? '正在连接…' : '$percent%',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMediumEmphasis,
                  ),
                ),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _start,
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
