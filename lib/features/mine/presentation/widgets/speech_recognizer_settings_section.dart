import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/offline_asr_service.dart';
import '../../../../core/services/pronunciation_settings.dart';
import '../../../../core/services/speech_recognizer_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/widgets/offline_asr_download_dialog.dart';

class SpeechPracticeSettingsSection extends StatefulWidget {
  const SpeechPracticeSettingsSection({super.key});

  @override
  State<SpeechPracticeSettingsSection> createState() => _SpeechPracticeSettingsSectionState();
}

class _SpeechPracticeSettingsSectionState extends State<SpeechPracticeSettingsSection> {
  SpeechRecognizerMode _mode = SpeechRecognizerMode.auto;
  PronunciationStrictness _strictness = PronunciationStrictness.loose;
  bool _installed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await SpeechRecognizerSettings.instance.getMode();
    final strictness = await PronunciationSettings.instance.getStrictness();
    final installed = await OfflineAsrService.instance.isInstalled();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _strictness = strictness;
      _installed = installed;
      _loading = false;
    });
  }

  String get _modeLabel {
    switch (_mode) {
      case SpeechRecognizerMode.auto:
        return '自动';
      case SpeechRecognizerMode.system:
        return '手机自带';
      case SpeechRecognizerMode.offline:
        return _installed ? '离线识别' : '离线识别 · 未下载';
    }
  }

  String get _strictnessLabel {
    return _strictness == PronunciationStrictness.strict ? '严格' : '宽松';
  }

  Future<void> _pickRecognizer() async {
    final selected = await showModalBottomSheet<SpeechRecognizerMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionSheet(
        title: '跟读识别',
        options: const [
          _Option('自动', '先用手机自带，用不了再提示下载离线识别', SpeechRecognizerMode.auto),
          _Option('手机自带', '只用系统语音识别', SpeechRecognizerMode.system),
          _Option('离线识别', '使用本机英语模型，约 30MB', SpeechRecognizerMode.offline),
        ],
        selected: _mode,
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == SpeechRecognizerMode.offline && !_installed) {
      final ok = await OfflineAsrDownloadDialog.show(context);
      if (!ok || !mounted) return;
      _installed = true;
    }
    await SpeechRecognizerSettings.instance.setMode(selected);
    if (!mounted) return;
    setState(() => _mode = selected);
  }

  Future<void> _pickStrictness() async {
    final selected = await showModalBottomSheet<PronunciationStrictness>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionSheet(
        title: '发音评分',
        options: const [
          _Option('宽松', '少一个很短的音也可以过，适合初中跟读', PronunciationStrictness.loose),
          _Option('严格', '必须读全这个单词，少一截不过', PronunciationStrictness.strict),
        ],
        selected: _strictness,
      ),
    );
    if (selected == null || !mounted) return;
    await PronunciationSettings.instance.setStrictness(selected);
    if (!mounted) return;
    setState(() => _strictness = selected);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      children: [
        _menuItem(
          icon: Icons.mic_rounded,
          iconColor: AppColors.primary,
          title: '跟读识别',
          subtitle: _modeLabel,
          onTap: _pickRecognizer,
        ),
        const SizedBox(height: 16),
        _menuItem(
          icon: Icons.graphic_eq_rounded,
          iconColor: const Color(0xFF7C3AED),
          title: '发音评分',
          subtitle: '按教材音标对齐 · $_strictnessLabel',
          onTap: _pickStrictness,
        ),
      ],
    );
  }

  Widget _menuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return BubblyButton(
      onPressed: onTap,
      color: Colors.white,
      shadowColor: Colors.grey.shade200,
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textHighEmphasis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMediumEmphasis,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
        ],
      ),
    );
  }
}

class _Option {
  final String title;
  final String subtitle;
  final Object value;

  const _Option(this.title, this.subtitle, this.value);
}

class _OptionSheet extends StatelessWidget {
  final String title;
  final List<_Option> options;
  final Object selected;

  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHighEmphasis,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            for (final option in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                title: Text(
                  option.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHighEmphasis,
                  ),
                ),
                subtitle: Text(
                  option.subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textMediumEmphasis,
                  ),
                ),
                trailing: Icon(
                  option.value == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: option.value == selected
                      ? AppColors.primary
                      : AppColors.textMediumEmphasis,
                ),
                onTap: () => Navigator.pop(context, option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
