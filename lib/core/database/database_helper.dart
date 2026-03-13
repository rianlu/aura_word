import 'dart:async';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:aura_word/core/database/models/word.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static const Uuid _uuid = Uuid();

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aura_word.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // 旧版本兼容：极老版本直接清表（仅开发）
      await db.execute('DROP TABLE IF EXISTS words');
      await db.execute('DROP TABLE IF EXISTS sentences');
      await db.execute('DROP TABLE IF EXISTS word_sentence_map');
      await db.execute('DROP TABLE IF EXISTS word_progress');
      await db.execute('DROP TABLE IF EXISTS user_stats');
      await db.execute('DROP TABLE IF EXISTS daily_records');
      await _createDB(db, newVersion);
      return;
    }

    if (oldVersion < 4) {
      // 安全迁移 3 -> 4（新增同步字段）
      debugPrint("Migrating DB to version 4 (Cloud Sync Prep)...");

      // 逻辑处理
      await _safeAddColumn(db, 'word_progress', 'account_id', 'TEXT');
      await _safeAddColumn(db, 'word_progress', 'device_id', 'TEXT');
      await _safeAddColumn(
        db,
        'word_progress',
        'last_updated_at',
        'INTEGER DEFAULT 0',
      );
      await _safeAddColumn(
        db,
        'word_progress',
        'is_deleted',
        'INTEGER DEFAULT 0',
      );

      // 逻辑处理
      await _safeAddColumn(db, 'user_stats', 'account_id', 'TEXT');
      await _safeAddColumn(db, 'user_stats', 'device_id', 'TEXT');
      await _safeAddColumn(
        db,
        'user_stats',
        'last_updated_at',
        'INTEGER DEFAULT 0',
      );

      // 逻辑处理
      await _safeAddColumn(db, 'daily_records', 'account_id', 'TEXT');
      await _safeAddColumn(db, 'daily_records', 'device_id', 'TEXT');
      await _safeAddColumn(
        db,
        'daily_records',
        'last_updated_at',
        'INTEGER DEFAULT 0',
      );
      await _safeAddColumn(
        db,
        'daily_records',
        'is_deleted',
        'INTEGER DEFAULT 0',
      );

      // 逻辑处理
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_state (
          table_name TEXT PRIMARY KEY NOT NULL,
          last_synced_at INTEGER DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 5) {
      // 迁移 4 -> 5（ 表新增 字段）
      debugPrint("Migrating DB to version 5 (Adding pos column)...");
      await _safeAddColumn(db, 'words', 'pos', "TEXT NOT NULL DEFAULT ''");
    }

    if (oldVersion < 6) {
      // 迁移 5 -> 6（ 表新增 _序号 字段）
      debugPrint("Migrating DB to version 6 (Adding order_index column)...");
      await _safeAddColumn(
        db,
        'words',
        'order_index',
        "INTEGER NOT NULL DEFAULT 0",
      );
    }

    if (oldVersion < 7) {
      // 迁移 6 -> 7（用户头像键）
      debugPrint("Migrating DB to version 7 (Adding avatar_key column)...");
      await _safeAddColumn(
        db,
        'user_stats',
        'avatar_key',
        "TEXT NOT NULL DEFAULT 'a01'",
      );
    }
  }

  // 安全添加字段的辅助方法
  Future<void> _safeAddColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    } catch (e) {
      // 字段已存在则忽略
      debugPrint("Column $column already exists in $table");
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // 逻辑处理
    await db.execute('''
      CREATE TABLE words (
        id TEXT PRIMARY KEY NOT NULL,
        text TEXT NOT NULL,
        meaning TEXT NOT NULL,
        phonetic TEXT NOT NULL,
        pos TEXT NOT NULL DEFAULT '',
        grade INTEGER NOT NULL,
        semester INTEGER NOT NULL,
        unit TEXT NOT NULL,
        difficulty INTEGER NOT NULL,
        category TEXT NOT NULL,
        book_id TEXT NOT NULL DEFAULT '',
        order_index INTEGER NOT NULL DEFAULT 0,
        syllables TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_words_book ON words(book_id)');
    await db.execute(
      'CREATE INDEX idx_words_grade_semester ON words(grade, semester)',
    );
    await db.execute('CREATE INDEX idx_words_unit ON words(unit)');
    await db.execute('CREATE INDEX idx_words_category ON words(category)');
    await db.execute('CREATE INDEX idx_words_text ON words(text)');

    // 逻辑处理
    await db.execute('''
      CREATE TABLE sentences (
        id TEXT PRIMARY KEY NOT NULL,
        text TEXT NOT NULL,
        translation TEXT NOT NULL,
        category TEXT NOT NULL,
        difficulty INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sentences_category ON sentences(category)',
    );

    // 逻辑处理
    await db.execute('''
      CREATE TABLE word_sentence_map (
        word_id TEXT NOT NULL,
        sentence_id TEXT NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 1,
        word_position INTEGER NOT NULL,
        PRIMARY KEY (word_id, sentence_id),
        FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE,
        FOREIGN KEY (sentence_id) REFERENCES sentences(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_wsm_word ON word_sentence_map(word_id)');
    await db.execute(
      'CREATE INDEX idx_wsm_sentence ON word_sentence_map(sentence_id)',
    );
    await db.execute(
      'CREATE INDEX idx_wsm_primary ON word_sentence_map(word_id, is_primary)',
    );

    // 逻辑处理
    await db.execute('''
      CREATE TABLE word_progress (
        id TEXT PRIMARY KEY NOT NULL,
        word_id TEXT NOT NULL,
        easiness_factor REAL NOT NULL DEFAULT 2.5,
        interval INTEGER NOT NULL DEFAULT 1,
        repetition INTEGER NOT NULL DEFAULT 0,
        next_review_date INTEGER NOT NULL DEFAULT 0,
        last_review_date INTEGER NOT NULL DEFAULT 0,
        review_count INTEGER NOT NULL DEFAULT 0,
        correct_count INTEGER NOT NULL DEFAULT 0,
        wrong_count INTEGER NOT NULL DEFAULT 0,
        mastery_level INTEGER NOT NULL DEFAULT 0,
        select_mode_count INTEGER NOT NULL DEFAULT 0,
        spell_mode_count INTEGER NOT NULL DEFAULT 0,
        speak_mode_count INTEGER NOT NULL DEFAULT 0,
        account_id TEXT,
        device_id TEXT,
        last_updated_at INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_progress_word ON word_progress(word_id)',
    );
    await db.execute(
      'CREATE INDEX idx_progress_review_date ON word_progress(next_review_date)',
    );
    await db.execute(
      'CREATE INDEX idx_progress_mastery ON word_progress(mastery_level)',
    );

    // 逻辑处理
    await db.execute('''
      CREATE TABLE user_stats (
        id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
        nickname TEXT NOT NULL DEFAULT '学习者',
        avatar_key TEXT NOT NULL DEFAULT 'a01',
        current_grade INTEGER NOT NULL DEFAULT 3,
        current_semester INTEGER NOT NULL DEFAULT 1,
        total_words_learned INTEGER NOT NULL DEFAULT 0,
        total_words_mastered INTEGER NOT NULL DEFAULT 0,
        total_reviews INTEGER NOT NULL DEFAULT 0,
        total_correct INTEGER NOT NULL DEFAULT 0,
        total_wrong INTEGER NOT NULL DEFAULT 0,
        continuous_days INTEGER NOT NULL DEFAULT 0,
        total_study_days INTEGER NOT NULL DEFAULT 0,
        last_study_date TEXT NOT NULL DEFAULT '',
        total_study_minutes INTEGER NOT NULL DEFAULT 0,
        current_book_id TEXT NOT NULL DEFAULT '',
        account_id TEXT,
        device_id TEXT,
        last_updated_at INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');
    // 初始化默认用户统计
    await db.insert('user_stats', {
      'id': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'current_book_id': '',
      'avatar_key': 'a01',
    });

    // 逻辑处理
    await db.execute('''
      CREATE TABLE daily_records (
        date TEXT PRIMARY KEY NOT NULL,
        new_words_count INTEGER NOT NULL DEFAULT 0,
        review_words_count INTEGER NOT NULL DEFAULT 0,
        correct_count INTEGER NOT NULL DEFAULT 0,
        wrong_count INTEGER NOT NULL DEFAULT 0,
        study_minutes INTEGER NOT NULL DEFAULT 0,
        account_id TEXT,
        device_id TEXT,
        last_updated_at INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_daily_records_date ON daily_records(date)',
    );

    // 逻辑处理
    await db.execute('''
      CREATE TABLE sync_state (
        table_name TEXT PRIMARY KEY NOT NULL,
        last_synced_at INTEGER DEFAULT 0
      )
    ''');

    // 建库后立即初始化数据
    await _seedData(db);
  }

  Future<void> _onOpen(Database db) async {
    // 检查数据是否存在，不存在则初始化
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );
    if (count == 0) {
      await _seedData(db);
    }
  }

  Future<void> _seedData(Database db) async {
    debugPrint('Starting data seeding from MANIFEST...');

    final manifest = await loadBooksManifest();

    if (manifest.isEmpty) {
      debugPrint("Warning: Manifest empty or failed.");
      return;
    }

    try {
      final batch = db.batch();

      for (final book in manifest) {
        final bookId = (book['id'] ?? '').toString();
        final filename = (book['file'] ?? '').toString();
        final grade = _asInt(book['grade'], _inferGradeFromBookId(bookId));
        final semester = _asInt(
          book['semester'],
          _inferSemesterFromBookId(bookId),
        );
        if (bookId.isEmpty || filename.isEmpty) continue;

        // 尝试加载 数据文件
        try {
          final jsonContent = await rootBundle.loadString(
            'assets/data/$filename',
          );
          debugPrint("Importing $filename for book $bookId...");
          await _seedFromJson(batch, jsonContent, grade, semester, bookId);
        } catch (e) {
          debugPrint("Error loading $filename: $e");
        }
      }

      await batch.commit(noResult: true);
      debugPrint('Data seeding completed.');

      // 如果有教材则自动选择第一本
      if (manifest.isNotEmpty) {
        final firstBook = manifest.first;
        final bookId = (firstBook['id'] ?? '').toString();
        final grade = _asInt(firstBook['grade'], _inferGradeFromBookId(bookId));
        final semester = _asInt(
          firstBook['semester'],
          _inferSemesterFromBookId(bookId),
        );

        await db.update('user_stats', {
          'current_book_id': bookId,
          'current_grade': grade,
          'current_semester': semester,
        }, where: 'id = 1');
        debugPrint('Auto-selected default book: $bookId');
      }
    } catch (e) {
      debugPrint('Error seeding data: $e');
    }
  }

  Future<List<dynamic>> loadBooksManifest() async {
    try {
      final manifestContent = await rootBundle.loadString(
        'assets/data/books_manifest.json',
      );
      final dynamic decoded = jsonDecode(manifestContent);
      final books = _normalizeManifestBooks(_extractBookList(decoded));
      if (books.isNotEmpty) {
        debugPrint('Loaded manifest with ${books.length} books.');
        return books;
      }
    } catch (e) {
      debugPrint('Manifest load failed: $e. Falling back to asset scan.');
    }

    try {
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files =
          assetManifest
              .listAssets()
              .where(
                (k) =>
                    k.startsWith('assets/data/') &&
                    k.endsWith('.json') &&
                    !k.endsWith('books_manifest.json'),
              )
              .map((k) => k.split('/').last)
              .toList()
            ..sort();

      final List<Map<String, dynamic>> fallback = [];
      for (int i = 0; i < files.length; i++) {
        final filename = files[i];
        final inferred = _inferBookMeta(filename, i + 1);
        fallback.add({
          'id': inferred['id'],
          'name': inferred['name'],
          'file': filename,
          'grade': inferred['grade'],
          'semester': inferred['semester'],
        });
      }
      debugPrint(
        'Generated fallback manifest with ${fallback.length} books from assets.',
      );
      return fallback;
    } catch (e) {
      debugPrint('Fallback manifest generation failed: $e');
      return [];
    }
  }

  Map<String, dynamic> _inferBookMeta(String filename, int serial) {
    int grade = 7;
    int semester = 1;

    if (filename.contains('七年级')) grade = 7;
    if (filename.contains('八年级')) grade = 8;
    if (filename.contains('九年级')) grade = 9;

    if (filename.contains('下册')) {
      semester = 2;
    } else if (filename.contains('上册')) {
      semester = 1;
    }

    final name = basenameWithoutExtension(filename);
    final id = 'book_${grade}_${semester}_$serial';
    return {'id': id, 'name': name, 'grade': grade, 'semester': semester};
  }

  List<dynamic> _extractBookList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      const candidates = ['books', 'data', 'list', 'items'];
      for (final key in candidates) {
        final value = decoded[key];
        if (value is List) return value;
      }
    }
    return const [];
  }

  List<Map<String, dynamic>> _normalizeManifestBooks(List<dynamic> rawBooks) {
    final List<Map<String, dynamic>> normalized = [];
    for (int i = 0; i < rawBooks.length; i++) {
      final item = rawBooks[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final filename = (map['file'] ?? map['filename'] ?? map['path'] ?? '')
          .toString();
      if (filename.isEmpty) continue;
      final inferred = _inferBookMeta(filename, i + 1);
      final id = (map['id'] ?? inferred['id']).toString();
      final name = (map['name'] ?? map['title'] ?? inferred['name']).toString();
      normalized.add({
        'id': id,
        'name': name,
        'file': filename,
        'grade': _asInt(map['grade'], inferred['grade'] as int),
        'semester': _asInt(map['semester'], inferred['semester'] as int),
      });
    }
    return normalized;
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
      if (value.contains('七')) return 7;
      if (value.contains('八')) return 8;
      if (value.contains('九')) return 9;
      if (value.contains('上')) return 1;
      if (value.contains('下')) return 2;
    }
    return fallback;
  }

  int _inferGradeFromBookId(String bookId) {
    final match = RegExp(r'(\d)').firstMatch(bookId);
    final parsed = match == null ? null : int.tryParse(match.group(1)!);
    if (parsed != null && parsed >= 7 && parsed <= 9) return parsed;
    return 7;
  }

  int _inferSemesterFromBookId(String bookId) {
    if (bookId.contains('_2') || bookId.contains('down')) return 2;
    return 1;
  }

  ({List<dynamic> items, String unit}) _extractItemsAndUnit(
    dynamic decoded, {
    String fallbackUnit = 'Module 1',
  }) {
    if (decoded is List) {
      return (items: decoded, unit: fallbackUnit);
    }

    if (decoded is Map<String, dynamic>) {
      final unit = (decoded['unit'] ?? decoded['module'] ?? fallbackUnit)
          .toString();
      const keys = [
        'data',
        'words',
        'word_list',
        'vocab',
        'vocabulary',
        'list',
        'items',
        'modules',
      ];
      for (final key in keys) {
        final value = decoded[key];
        if (value is List) {
          return (items: value, unit: unit);
        }
      }
      if (decoded.containsKey('text') && decoded.containsKey('meaning')) {
        return (items: [decoded], unit: unit);
      }
    }

    return (items: const [], unit: fallbackUnit);
  }

  String _normalizeUnit(String unit) {
    final normalized = unit.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return normalized.isEmpty ? 'unit' : normalized;
  }

  String _normalizeWordText(String text) {
    return text.trim().toLowerCase();
  }

  String _wordIndexKey(String bookId, String unit, int index) {
    return 'idx|$bookId|${_normalizeUnit(unit)}|$index';
  }

  String _wordTextKey(String bookId, String unit, String text) {
    return 'text|$bookId|${_normalizeUnit(unit)}|${_normalizeWordText(text)}';
  }

  String _makeWordId(String bookId, String unit, int index) {
    return _uuid.v4();
  }

  Future<Map<String, String>> _loadExistingWordIdMap(
    Database db,
    String bookId,
  ) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'words',
      columns: ['id', 'unit', 'order_index', 'text'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    final Map<String, String> map = {};
    for (final row in rows) {
      final unit = row['unit'] as String? ?? '';
      final index = row['order_index'] as int? ?? 0;
      final text = row['text'] as String? ?? '';
      final id = row['id'] as String;
      map[_wordIndexKey(bookId, unit, index)] = id;
      if (text.isNotEmpty) {
        map[_wordTextKey(bookId, unit, text)] = id;
      }
    }
    return map;
  }

  Future<void> _seedFromJson(
    Batch batch,
    String jsonString,
    int grade,
    int semester,
    String bookId,
  ) async {
    final dynamic decoded = jsonDecode(jsonString);
    final extracted = _extractItemsAndUnit(decoded);
    final items = extracted.items;
    final defaultUnit = extracted.unit;

    int wordIndex = 0;

    for (var item in items) {
      if (item is Map<String, dynamic>) {
        // 判断是单词还是模块包装
        if (item.containsKey('data') || item.containsKey('words')) {
          final module = _extractItemsAndUnit(item, fallbackUnit: defaultUnit);
          await _seedWordList(
            batch,
            module.items,
            grade,
            semester,
            module.unit,
            bookId,
            null,
          );
        } else {
          wordIndex++;
          _insertWord(
            batch,
            item,
            grade,
            semester,
            defaultUnit,
            wordIndex,
            bookId,
            null,
          );
        }
      }
    }
  }

  Future<void> _seedWordList(
    Batch batch,
    List<dynamic> words,
    int grade,
    int semester,
    String unit,
    String bookId,
    Map<String, String>? existingIdMap,
  ) async {
    int wordIndex = 0;
    for (var w in words) {
      if (w is Map<String, dynamic>) {
        wordIndex++;
        _insertWord(
          batch,
          w,
          grade,
          semester,
          unit,
          wordIndex,
          bookId,
          existingIdMap,
        );
      }
    }
  }

  void _insertWord(
    Batch batch,
    Map<String, dynamic> data,
    int grade,
    int semester,
    String unit,
    int index,
    String bookId,
    Map<String, String>? existingIdMap,
  ) {
    final text = (data['text'] ?? '').toString();
    if (text.isEmpty) return;

    final indexKey = _wordIndexKey(bookId, unit, index);
    final textKey = _wordTextKey(bookId, unit, text);
    final id =
        existingIdMap?[indexKey] ??
        existingIdMap?[textKey] ??
        _makeWordId(bookId, unit, index);

    List<String> syllables = [];
    if (data['syllables'] != null && data['syllables'] is List) {
      syllables = List<String>.from(data['syllables']);
    }

    final word = Word(
      id: id,
      text: text,
      meaning: (data['meaning'] ?? '[释义]').toString(),
      phonetic: (data['phonetic'] ?? '').toString(),
      pos: (data['pos'] ?? '').toString(),
      grade: grade,
      semester: semester,
      unit: unit,
      difficulty: 1,
      category: 'general',
      syllables: syllables,
      bookId: bookId,
      orderIndex: index,
    );

    batch.insert(
      'words',
      word.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 处理例句
    if (data.containsKey('app_sentences') && data['app_sentences'] is List) {
      final sentences = data['app_sentences'] as List;
      int sIndex = 0;
      for (var s in sentences) {
        if (s is Map<String, dynamic>) {
          sIndex++;
          final en = (s['en'] ?? '').toString();
          final cn = (s['cn'] ?? '').toString();
          if (en.isNotEmpty) {
            final sId = _uuid.v4();

            // 插入例句
            batch.insert('sentences', {
              'id': sId,
              'text': en,
              'translation': cn,
              'category': 'example',
              'difficulty': 1,
            }, conflictAlgorithm: ConflictAlgorithm.replace);

            // 插入映射关系
            batch.insert('word_sentence_map', {
              'word_id': id,
              'sentence_id': sId,
              'is_primary': sIndex == 1 ? 1 : 0, // 第一条标记为主例句
              'word_position': -1, // 暂不计算词位
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    }
  }

  /// 安全更新：从 数据文件 更新单词且保留进度
  Future<void> updateLibraryFromAssets() async {
    final db = await database;
    debugPrint('Starting SAFE library update from MANIFEST...');

    final manifest = await loadBooksManifest();

    if (manifest.isEmpty) return;

    try {
      final batch = db.batch();

      for (final book in manifest) {
        final bookId = (book['id'] ?? '').toString();
        final filename = (book['file'] ?? '').toString();
        final grade = _asInt(book['grade'], _inferGradeFromBookId(bookId));
        final semester = _asInt(
          book['semester'],
          _inferSemesterFromBookId(bookId),
        );
        if (bookId.isEmpty || filename.isEmpty) continue;
        final existingIdMap = await _loadExistingWordIdMap(db, bookId);

        try {
          final jsonContent = await rootBundle.loadString(
            'assets/data/$filename',
          );
          debugPrint("Updating $filename for book $bookId...");
          await _safeSeedFromJson(
            batch,
            jsonContent,
            grade,
            semester,
            bookId,
            existingIdMap,
          );
        } catch (e) {
          debugPrint("Error loading $filename: $e");
        }
      }

      await batch.commit(noResult: true);
      debugPrint('Library update completed successfully.');
    } catch (e) {
      debugPrint('Error updating library: $e');
    }
  }

  Future<void> _safeSeedFromJson(
    Batch batch,
    String jsonString,
    int grade,
    int semester,
    String bookId,
    Map<String, String>? existingIdMap,
  ) async {
    final dynamic decoded = jsonDecode(jsonString);
    final extracted = _extractItemsAndUnit(decoded);
    final items = extracted.items;
    final defaultUnit = extracted.unit;

    int wordIndex = 0;
    for (var item in items) {
      if (item is Map<String, dynamic>) {
        if (item.containsKey('data') || item.containsKey('words')) {
          final module = _extractItemsAndUnit(item, fallbackUnit: defaultUnit);
          await _safeSeedWordList(
            batch,
            module.items,
            grade,
            semester,
            module.unit,
            bookId,
            existingIdMap,
          );
        } else {
          wordIndex++;
          _upsertWord(
            batch,
            item,
            grade,
            semester,
            defaultUnit,
            wordIndex,
            bookId,
            existingIdMap,
          );
        }
      }
    }
  }

  Future<void> _safeSeedWordList(
    Batch batch,
    List<dynamic> words,
    int grade,
    int semester,
    String unit,
    String bookId,
    Map<String, String>? existingIdMap,
  ) async {
    int wordIndex = 0;
    for (var w in words) {
      if (w is Map<String, dynamic>) {
        wordIndex++;
        _upsertWord(
          batch,
          w,
          grade,
          semester,
          unit,
          wordIndex,
          bookId,
          existingIdMap,
        );
      }
    }
  }

  void _upsertWord(
    Batch batch,
    Map<String, dynamic> data,
    int grade,
    int semester,
    String unit,
    int index,
    String bookId,
    Map<String, String>? existingIdMap,
  ) {
    final text = (data['text'] ?? '').toString();
    if (text.isEmpty) return;

    final indexKey = _wordIndexKey(bookId, unit, index);
    final textKey = _wordTextKey(bookId, unit, text);
    final id =
        existingIdMap?[indexKey] ??
        existingIdMap?[textKey] ??
        _makeWordId(bookId, unit, index);

    // 重要：使用 插入或更新 保持 编号 与外键
    // 数据库 的 插入或替换 会删除旧行并触发级联删除
    // 必须使用明确的 插入或更新 语法

    final meaning = (data['meaning'] ?? '[释义]').toString();
    final phonetic = (data['phonetic'] ?? '').toString();
    // 音节等字段处理
    String syllablesJson = '[]';
    if (data['syllables'] != null && data['syllables'] is List) {
      syllablesJson = jsonEncode(data['syllables']); // 必要时存成字符串或逗号分隔
      // 表的 是 文本，上面使用 列表 可能不一致
      // 检查 _单词：若模型未处理序列化会被忽略
      // 通常 单词. 会存成 数据文件 字符串
    }

    // 使用 原始插入 构造 插入或更新 语句
    // 冲突时执行更新
    final pos = (data['pos'] ?? '').toString();
    batch.rawInsert(
      '''
       INSERT INTO words (id, text, meaning, phonetic, pos, grade, semester, unit, difficulty, category, book_id, order_index, syllables)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         text = excluded.text,
         meaning = excluded.meaning,
         phonetic = excluded.phonetic,
         pos = excluded.pos,
         order_index = excluded.order_index,
         syllables = excluded.syllables,
         unit = excluded.unit
     ''',
      [
        id,
        text,
        meaning,
        phonetic,
        pos,
        grade,
        semester,
        unit,
        1,
        'general',
        bookId,
        index,
        syllablesJson,
      ],
    );

    // 例句不直接承载进度，保留优先级较低
    // 但 词句映射表 会受影响
    // 若例句 编号 可复现，可直接替换
    // 例句 编号 形如 _{单词编号}_{序号}

    if (data.containsKey('app_sentences') && data['app_sentences'] is List) {
      final sentences = data['app_sentences'] as List;
      int sIndex = 0;
      for (var s in sentences) {
        if (s is Map<String, dynamic>) {
          sIndex++;
          final en = (s['en'] ?? '').toString();
          final cn = (s['cn'] ?? '').toString();
          if (en.isNotEmpty) {
            final sId = 'sentence_${id}_$sIndex';

            // 插入或更新 例句
            batch.rawInsert(
              '''
               INSERT INTO sentences (id, text, translation, category, difficulty)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET
                 text = excluded.text,
                 translation = excluded.translation
             ''',
              [sId, en, cn, 'example', 1],
            );

            // 确保映射存在（只是关联关系）
            batch.insert('word_sentence_map', {
              'word_id': id,
              'sentence_id': sId,
              'is_primary': sIndex == 1 ? 1 : 0,
              'word_position': -1,
            }, conflictAlgorithm: ConflictAlgorithm.ignore); // 已存在则忽略
          }
        }
      }
    }
  }

  // 重置数据库的辅助方法（调试用）
  Future<void> resetDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aura_word.db');
    await deleteDatabase(path);
    _database = null;
  }
}
