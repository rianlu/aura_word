import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/daos/word_dao.dart';
import '../../../../core/database/daos/user_stats_dao.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/global_stats_notifier.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/dictionary_word_tile.dart';
import '../../../../core/widgets/book_selection_sheet.dart';
import '../../../../core/utils/string_utils.dart';
import 'dictionary_search_screen.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final WordDao _wordDao = WordDao();
  final UserStatsDao _userStatsDao = UserStatsDao();

  // List state
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _words = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 40;

  int _requestVersion = 0;
  // 逻辑处理
  int? _masteryFilter; // 掌握度处理
  String? _currentBookId; // 逻辑处理
  String? _currentUnit;

  // List states
  List<dynamic> _books = [];
  Map<int, int> _counts = {0: 0, 1: 0, 2: 0};
  List<String> _units = [];

  // Navigation lock

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    // Search listener removed
    _scrollController.addListener(_onScroll);
    GlobalStatsNotifier.instance.addListener(_fullReload);
  }

  bool _isNavigatingToSearch = false;

  @override
  void dispose() {
    GlobalStatsNotifier.instance.removeListener(_fullReload);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || !_hasMore) return;
    if (_scrollController.position.extentAfter < 800) {
      _loadMore();
    }
  }

  Future<void> _loadMetadata() async {
    try {
      _books = await DatabaseHelper().loadBooksManifest();

      // 逻辑处理
      final stats = await _userStatsDao.getUserStats();

      // 逻辑处理
      final bool hasCurrentBook = _books.any(
        (b) => b['id'] == stats.currentBookId,
      );
      if (stats.currentBookId.isNotEmpty && hasCurrentBook) {
        _currentBookId = stats.currentBookId;
      } else if (_books.isNotEmpty) {
        _currentBookId = _books[0]['id'];
      } else {
        _currentBookId = null;
      }

      // 逻辑处理
      await _loadUnits();

      _reload();
    } catch (e) {
      debugPrint("Error loading metadata: $e");
    }
  }

  Future<void> _loadUnits() async {
    if (_currentBookId == null || _currentBookId!.isEmpty) {
      _units = [];
      _currentUnit = null;
      setState(() {});
      return;
    }
    _units = await _wordDao.getUnitsForBook(_currentBookId!);
    _units.sort(StringUtils.naturalCompare); // 逻辑处理
    _currentUnit = null;
    setState(() {});
  }

  /// 逻辑处理
  /// 逻辑处理
  Future<void> _fullReload() async {
    try {
      // 逻辑处理
      final stats = await _userStatsDao.getUserStats();
      if (stats.currentBookId.isNotEmpty) {
        _currentBookId = stats.currentBookId;
      }
      await _loadUnits();
    } catch (e) {
      debugPrint("Error in full reload: $e");
    }
    await _reload();
  }

  /// 逻辑处理
  Future<void> _reload() async {
    final int requestId = ++_requestVersion;
    setState(() {
      _words = [];
      _offset = 0;
      _hasMore = true;
      _isLoading = true;
    });
    await _updateCounts(requestId);
    await _loadMore(requestId: requestId, force: true);
  }

  Future<void> _updateCounts(int requestId) async {
    final counts = await _wordDao.getWordCounts(
      bookId: _currentBookId,
      unit: _currentUnit,
      searchQuery: "",
    );
    if (mounted && requestId == _requestVersion) {
      setState(() {
        _counts = counts;
      });
    }
  }

  Future<void> _loadMore({int? requestId, bool force = false}) async {
    final int activeRequestId = requestId ?? _requestVersion;
    if (!force && _isLoading) return;
    if (!_hasMore) {
      return;
    }
    setState(() => _isLoading = true);

    final newWords = await _wordDao.getDictionaryWords(
      limit: _limit,
      offset: _offset,
      masteryFilter: _masteryFilter,
      searchQuery: "",
      bookId: _currentBookId,
      unit: _currentUnit,
    );

    if (mounted && activeRequestId == _requestVersion) {
      setState(() {
        _words.addAll(newWords);
        _offset += newWords.length;
        _hasMore = newWords.length >= _limit;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onFilterChanged(int? filter) {
    if (_masteryFilter == filter) return;
    setState(() {
      _masteryFilter = filter;
      _words = [];
      _offset = 0;
      _hasMore = true;
      _isLoading = true;
    });
    // 只单纯拉取新词单，不再去查 count（count 没变） 
    _loadMore(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader()
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),

            Expanded(
              child:
                  Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildFilters(),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _isLoading && _words.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : ListView.separated(
                                    controller: _scrollController,
                                    cacheExtent: 1400,
                                    padding: const EdgeInsets.all(16),
                                    itemCount:
                                        _words.length +
                                        ((_isLoading && _words.isNotEmpty)
                                            ? 1
                                            : 0),
                                    separatorBuilder: (c, i) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      if (index == _words.length) {
                                        return const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(8),
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      }
                                      
                                      // 添加级联动画逻辑，使用 Key 触发重新播放
                                      final delay = (index % 10) * 40; 
                                      
                                      return DictionaryWordTile(
                                        key: ValueKey('${_words[index]['id']}_${_masteryFilter}'),
                                        item: _words[index],
                                        onTap: () =>
                                            DictionaryWordTile.showDetail(
                                              context,
                                              _words[index],
                                            ),
                                      )
                                      .animate()
                                      .fadeIn(duration: 350.ms, delay: delay.ms)
                                      .slideX(begin: 0.05, end: 0, curve: Curves.easeOutBack);
                                    },
                                  ),
                          ),
                        ],
                      )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 150.ms)
                      .slideY(begin: 0.05, end: 0, curve: Curves.easeOutBack),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "词典",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textHighEmphasis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildBookSelector(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Bar Button (Navigates to Search Screen)
          GestureDetector(
            onTap: () async {
              if (_isNavigatingToSearch) return;
              _isNavigatingToSearch = true;
              await Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const DictionarySearchScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                ),
              );
              _isNavigatingToSearch = false;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadowWhite,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.search_rounded,
                    color: AppColors.textMediumEmphasis,
                  ),
                  SizedBox(width: 12),
                  Text(
                    "搜索单词...",
                    style: TextStyle(
                      color: AppColors.textMediumEmphasis,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookSelector() {
    String currentBookName = "全部教材";
    if (_currentBookId != null && _currentBookId!.isNotEmpty) {
      final idx = _books.indexWhere((b) => b['id'] == _currentBookId);
      if (idx >= 0) {
        final book = _books[idx];
        currentBookName = (book['name'] ?? currentBookName).toString();
      }
    }

    return InkWell(
      onTap: () {
        BookSelectionSheet.show(
          context: context,
          books: _books,
          title: '选择教材',
          selectedBookId: _currentBookId,
          includeAllOption: true,
          allOptionLabel: '全部教材',
          allOptionSubtitle: '查看所有已添加单词',
        ).then((selected) async {
          if (selected == null) return;
          _currentBookId = selected.id;
          await _loadUnits();
          _reload();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                currentBookName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHighEmphasis,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.textMediumEmphasis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    int total = (_counts[0] ?? 0) + (_counts[1] ?? 0) + (_counts[2] ?? 0);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // 逻辑处理
          if (_units.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildDropdownChip(
                _currentUnit == null ? "所有单元" : _currentUnit!,
                () async {
                  final String? selected = await showModalBottomSheet<String>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => _UnitSelectionSheet(
                      units: _units,
                      currentUnit: _currentUnit,
                    ),
                  );
                  if (selected != null) {
                    final newUnit = selected == "__ALL__" ? null : selected;
                    if (newUnit != _currentUnit) {
                      setState(() => _currentUnit = newUnit);
                      _reload();
                    }
                  }
                },
              ),
            ),

          _buildFilterChip("全部 ($total)", null),
          const SizedBox(width: 8),
          _buildFilterChip("未学 (${_counts[0] ?? 0})", 0),
          const SizedBox(width: 8),
          _buildFilterChip("学习中 (${_counts[1] ?? 0})", 1),
          const SizedBox(width: 8),
          _buildFilterChip("已掌握 (${_counts[2] ?? 0})", 2),
        ],
      ),
    );
  }

  Widget _buildDropdownChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int? value) {
    final isSelected = _masteryFilter == value;
    return GestureDetector(
      onTap: () => _onFilterChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        transform: Matrix4.identity()..scale(isSelected ? 1.06 : 1.0),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textMediumEmphasis,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _UnitSelectionSheet extends StatelessWidget {
  final List<String> units;
  final String? currentUnit;

  const _UnitSelectionSheet({
    required this.units,
    required this.currentUnit,
  });

  @override
  Widget build(BuildContext context) {
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
                  '选择单元',
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
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: units.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final isAllUnits = i == 0;
                final unit = isAllUnits ? null : units[i - 1];
                final bool isSelected = currentUnit == unit;
                final String label = isAllUnits ? "所有单元" : unit!;

                return InkWell(
                  onTap: () {
                    Navigator.pop(context, isAllUnits ? "__ALL__" : unit);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                : (isAllUnits ? Icons.all_inclusive_rounded : Icons.circle_outlined),
                            color: isSelected ? AppColors.primary : Colors.grey.shade400,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? AppColors.primary : AppColors.textHighEmphasis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: (i * 40).ms)
                .slideX(begin: 0.1, end: 0, curve: Curves.easeOutBack);
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
