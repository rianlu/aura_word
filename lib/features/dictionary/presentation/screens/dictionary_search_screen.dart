import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/database/daos/word_dao.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/dictionary_word_tile.dart';

class DictionarySearchScreen extends StatefulWidget {
  const DictionarySearchScreen({super.key});

  @override
  State<DictionarySearchScreen> createState() => _DictionarySearchScreenState();
}

class _DictionarySearchScreenState extends State<DictionarySearchScreen> {
  final WordDao _wordDao = WordDao();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 40;
  int _requestVersion = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);

    // Auto focus after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || !_hasMore) return;
    if (_scrollController.position.extentAfter < 800) {
      _loadMore();
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _reload();
    });
  }

  Future<void> _reload() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _offset = 0;
        _hasMore = false;
        _isLoading = false;
      });
      return;
    }

    final int requestId = ++_requestVersion;
    setState(() {
      _results = [];
      _offset = 0;
      _hasMore = true;
      _isLoading = true;
    });

    await _loadMore(requestId: requestId, force: true);
  }

  Future<void> _loadMore({int? requestId, bool force = false}) async {
    final int activeRequestId = requestId ?? _requestVersion;
    if (!force && _isLoading) return;
    if (!_hasMore) return;

    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (!force) setState(() => _isLoading = true);

    try {
      final newWords = await _wordDao.getDictionaryWords(
        limit: _limit,
        offset: _offset,
        searchQuery: query,
        // No book/unit/mastery filter in global search for now, unless desired.
        // User's prompt implies general dictionary search.
      );

      if (mounted && activeRequestId == _requestVersion) {
        setState(() {
          _results.addAll(newWords);
          _offset += newWords.length;
          _hasMore = newWords.length >= _limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted && activeRequestId == _requestVersion) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _reload(); // Will clear list
    // Keep focus
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.surfaceVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textHighEmphasis,
                ),
                decoration: InputDecoration(
                  icon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textMediumEmphasis,
                  ),
                  border: InputBorder.none,
                  hintText: "搜索单词...",
                  hintStyle: const TextStyle(
                    color: AppColors.textMediumEmphasis,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: AppColors.textMediumEmphasis,
                          ),
                          onPressed: _clearSearch,
                        )
                      : null,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  // Hide keyboard on submit if desired, but user wants active search
                  // FocusScope.of(context).unfocus();
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            child: const Text("取消"),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 64,
              color: Colors.grey.shade200,
            ),
            const SizedBox(height: 16),
            Text(
              "输入单词进行搜索",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Colors.grey.shade200,
            ),
            const SizedBox(height: 16),
            Text(
              "未找到相关单词",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _results.length + ((_isLoading) ? 1 : 0),
      separatorBuilder: (c, i) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final delay = (index % 10) * 50;
        return DictionaryWordTile(
          item: _results[index],
          onTap: () {
            // Keep focus when tapping? No, user wants unfocus -> detail.
            // But specifically for search screen, let's keep it simple:
            // Tap -> Detail opens. Since Detail is modal, keyboard might hide or stay behind.
            // But DetailSheet is bottom sheet.
            // To prevent keyboard flickering, we might want to unfocus.
            FocusScope.of(context).unfocus();
            DictionaryWordTile.showDetail(context, _results[index]);
          },
        )
        .animate()
        .fadeIn(duration: 400.ms, delay: delay.ms)
        .slideX(begin: 0.05, end: 0, curve: Curves.easeOutBack);
      },
    );
  }
}
