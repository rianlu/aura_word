import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'bubbly_button.dart';

/// 逻辑处理
/// 逻辑处理
class AppDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final String? subtitle;
  final Widget? content;
  final String? primaryButtonText;
  final String? secondaryButtonText;
  final VoidCallback? onPrimaryPressed;
  final VoidCallback? onSecondaryPressed;
  final Color primaryButtonColor;
  final Color primaryButtonTextColor;
  final Color titleColor;
  final Color subtitleColor;
  final bool isDestructive;

  const AppDialog({
    super.key,
    required this.icon,
    this.iconColor = AppColors.primary,
    this.iconBackgroundColor = const Color(0xFFEFF6FF),
    required this.title,
    this.subtitle,
    this.content,
    this.primaryButtonText,
    this.secondaryButtonText,
    this.onPrimaryPressed,
    this.onSecondaryPressed,
    this.primaryButtonColor = AppColors.primary,
    this.primaryButtonTextColor = Colors.white,
    this.titleColor = AppColors.textHighEmphasis,
    this.subtitleColor = AppColors.textMediumEmphasis,
    this.isDestructive = false,
  });

  /// 逻辑处理
  factory AppDialog.success({
    Key? key,
    required String title,
    String? subtitle,
    Widget? content,
    String primaryButtonText = '确定',
    VoidCallback? onPrimaryPressed,
  }) {
    return AppDialog(
      key: key,
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF22C55E),
      iconBackgroundColor: const Color(0xFFF0FDF4),
      title: title,
      subtitle: subtitle,
      content: content,
      primaryButtonText: primaryButtonText,
      onPrimaryPressed: onPrimaryPressed,
      primaryButtonColor: const Color(0xFF22C55E),
    );
  }

  /// 逻辑处理
  factory AppDialog.warning({
    Key? key,
    required String title,
    String? subtitle,
    Widget? content,
    String primaryButtonText = '确定',
    String? secondaryButtonText = '取消',
    VoidCallback? onPrimaryPressed,
    VoidCallback? onSecondaryPressed,
  }) {
    return AppDialog(
      key: key,
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.red,
      iconBackgroundColor: const Color(0xFFFEF2F2),
      title: title,
      subtitle: subtitle,
      content: content,
      primaryButtonText: primaryButtonText,
      secondaryButtonText: secondaryButtonText,
      onPrimaryPressed: onPrimaryPressed,
      onSecondaryPressed: onSecondaryPressed,
      primaryButtonColor: Colors.red,
      isDestructive: true,
    );
  }

  /// 逻辑处理
  factory AppDialog.confirm({
    Key? key,
    required String title,
    String? subtitle,
    Widget? content,
    String primaryButtonText = '确认',
    String secondaryButtonText = '取消',
    VoidCallback? onPrimaryPressed,
    VoidCallback? onSecondaryPressed,
  }) {
    return AppDialog(
      key: key,
      icon: Icons.help_outline_rounded,
      iconColor: AppColors.primary,
      iconBackgroundColor: const Color(0xFFEFF6FF),
      title: title,
      subtitle: subtitle,
      content: content,
      primaryButtonText: primaryButtonText,
      secondaryButtonText: secondaryButtonText,
      onPrimaryPressed: onPrimaryPressed,
      onSecondaryPressed: onSecondaryPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                offset: const Offset(0, 8),
                blurRadius: 32,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 逻辑处理
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 36),
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
              const SizedBox(height: 20),
              
              // 逻辑处理
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
              
              // 逻辑处理
              if (subtitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.5,
                    color: subtitleColor,
                  ),
                ).animate().fadeIn(delay: 300.ms),
              ],
              
              // 逻辑处理
              if (content != null) ...[
                const SizedBox(height: 16),
                content!.animate().fadeIn(delay: 400.ms),
              ],
              
              const SizedBox(height: 24),
              
              // 逻辑处理
              _buildButtons(context).animate().fadeIn(delay: 450.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
            ],
          ),
        ).animate().scale(begin: const Offset(0.9, 0.9), duration: 400.ms, curve: Curves.easeOutBack).fadeIn(),
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    final hasSecondary = secondaryButtonText != null;
    
    if (!hasSecondary && primaryButtonText != null) {
      // 逻辑处理
      return SizedBox(
        width: double.infinity,
        child: BubblyButton(
          onPressed: onPrimaryPressed ?? () => Navigator.pop(context),
          color: primaryButtonColor,
          shadowColor: primaryButtonColor.withValues(alpha: 0.4),
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              primaryButtonText!,
              style: GoogleFonts.plusJakartaSans(
                color: primaryButtonTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    
    if (hasSecondary && primaryButtonText != null) {
      // 逻辑处理
      return Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: onSecondaryPressed ?? () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: AppColors.background,
              ),
              child: Text(
                secondaryButtonText!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: AppColors.textMediumEmphasis,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BubblyButton(
              onPressed: onPrimaryPressed ?? () => Navigator.pop(context),
              color: primaryButtonColor,
              shadowColor: primaryButtonColor.withValues(alpha: 0.4),
              borderRadius: 14,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  primaryButtonText!,
                  style: GoogleFonts.plusJakartaSans(
                    color: primaryButtonTextColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    return const SizedBox.shrink();
  }
}

/// 逻辑处理
class AppBottomSheet extends StatelessWidget {
  final String title;
  final List<AppBottomSheetItem> items;
  final double? height;

  const AppBottomSheet({
    super.key,
    required this.title,
    required this.items,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 逻辑处理
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 逻辑处理
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHighEmphasis,
                  ),
                ),
              ],
            ),
          ),
          // 逻辑处理
          Divider(height: 1, color: Colors.grey.shade100),
          // 逻辑处理
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                return items[index]
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                    .slideX(begin: 0.1, end: 0, curve: Curves.easeOutBack);
              },
            ),
          ),
          // 逻辑处理
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

/// 逻辑处理
class AppBottomSheetItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? leading;

  const AppBottomSheetItem({
    super.key,
    required this.title,
    this.subtitle,
    this.isSelected = false,
    this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 14),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: isSelected ? AppColors.primary : Colors.grey.shade400,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? AppColors.primary : AppColors.textHighEmphasis,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textMediumEmphasis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

/// 逻辑处理
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required AppDialog dialog,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => dialog,
  );
}

/// 逻辑处理
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required String title,
  required List<AppBottomSheetItem> items,
  double? height,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => AppBottomSheet(title: title, items: items, height: height),
  );
}
