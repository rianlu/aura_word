import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class BookSelectionResult {
  final String? id;
  final String name;
  final int? grade;
  final int? semester;

  const BookSelectionResult({
    required this.id,
    required this.name,
    this.grade,
    this.semester,
  });
}

class BookSelectionSheet {
  static Future<BookSelectionResult?> show({
    required BuildContext context,
    required List<dynamic> books,
    required String title,
    String? selectedBookId,
    int? selectedGrade,
    int? selectedSemester,
    bool includeAllOption = false,
    String allOptionLabel = '全部教材',
    String? allOptionSubtitle,
  }) {
    return showModalBottomSheet<BookSelectionResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
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
              Divider(height: 1, color: Colors.grey.shade100),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: books.length + (includeAllOption ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final bool isAllRow = includeAllOption && index == 0;
                    final dynamic book = isAllRow
                        ? null
                        : books[index - (includeAllOption ? 1 : 0)];
                    final String? id = isAllRow
                        ? null
                        : (book['id']?.toString());
                    final String name = isAllRow
                        ? allOptionLabel
                        : (book['name']?.toString() ?? '');
                    final int? grade = isAllRow
                        ? null
                        : (book['grade'] as int?);
                    final int? semester = isAllRow
                        ? null
                        : (book['semester'] as int?);

                    bool isSelected = selectedBookId == id;
                    if (!isSelected &&
                        (selectedBookId == null || selectedBookId.isEmpty)) {
                      if (isAllRow) {
                        isSelected = true;
                      } else if (selectedGrade != null &&
                          selectedSemester != null &&
                          grade == selectedGrade &&
                          semester == selectedSemester) {
                        isSelected = true;
                      }
                    }

                    return InkWell(
                      onTap: () {
                        Navigator.pop(
                          context,
                          BookSelectionResult(
                            id: id,
                            name: name,
                            grade: grade,
                            semester: semester,
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : isAllRow
                                    ? Icons.all_inclusive_rounded
                                    : Icons.circle_outlined,
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.grey.shade400,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textHighEmphasis,
                                    ),
                                  ),
                                  if (isAllRow && allOptionSubtitle != null)
                                    Text(
                                      allOptionSubtitle,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: isSelected
                                            ? AppColors.primary.withValues(
                                                alpha: 0.7,
                                              )
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                    .slideX(begin: 0.1, end: 0, curve: Curves.easeOutBack);
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }
}
