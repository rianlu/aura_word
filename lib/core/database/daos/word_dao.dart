import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../models/word.dart';
import '../models/word_progress.dart';
import '../../services/global_stats_notifier.dart';

class WordDao {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<int> insertWord(Word word) async {
    final db = await _dbHelper.database;
    return await db.insert('words', word.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Word>> getAllWords() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('words');
    return List.generate(maps.length, (i) {
      return Word.fromJson(maps[i]);
    });
  }

  Future<List<Word>> getWordsByUnit(int grade, int semester, String unit) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'words',
      where: 'grade = ? AND semester = ? AND unit = ?',
      whereArgs: [grade, semester, unit],
    );
    return List.generate(maps.length, (i) {
      return Word.fromJson(maps[i]);
    });
  }

  // 为单词列表加载例句
  Future<List<Word>> _attachSentences(List<Word> words) async {
    if (words.isEmpty) return words;

    final db = await _dbHelper.database;
    final wordIds = words.map((w) => w.id).toList();
    final placeholders = List.filled(wordIds.length, '?').join(',');

    final sentenceMaps = await db.rawQuery('''
      SELECT m.word_id, s.text, s.translation
      FROM word_sentence_map m
      JOIN sentences s ON s.id = m.sentence_id
      WHERE m.word_id IN ($placeholders)
      ORDER BY m.word_id, m.is_primary DESC, m.sentence_id ASC
    ''', wordIds);

    final Map<String, List<Map<String, String>>> examplesByWordId = {};
    for (final row in sentenceMaps) {
      final wordId = row['word_id'] as String;
      final example = {
        'en': row['text'] as String? ?? '',
        'cn': row['translation'] as String? ?? '',
      };
      examplesByWordId.putIfAbsent(wordId, () => <Map<String, String>>[]).add(example);
    }

    return words.map((word) {
      return Word(
        id: word.id,
        text: word.text,
        meaning: word.meaning,
        phonetic: word.phonetic,
        phoneticTextbook: word.phoneticTextbook,
        phoneticDictionary: word.phoneticDictionary,
        pos: word.pos,
        grade: word.grade,
        semester: word.semester,
        unit: word.unit,
        difficulty: word.difficulty,
        category: word.category,
        bookId: word.bookId,
        orderIndex: word.orderIndex,
        syllables: word.syllables,
        examples: examplesByWordId[word.id] ?? const [],
      );
    }).toList();
  }

  Future<List<Word>> getNewWords(int limit, {String? bookId, int? grade, int? semester}) async {
    final db = await _dbHelper.database;
    String whereClause = 'id NOT IN (SELECT word_id FROM word_progress)';
    List<dynamic> args = [];

    if (bookId != null && bookId.isNotEmpty) {
      whereClause += ' AND book_id = ?';
      args.add(bookId);
    } else {
      if (grade != null) {
        whereClause += ' AND grade = ?';
        args.add(grade);
      }
      if (semester != null) {
        whereClause += ' AND semester = ?';
        args.add(semester);
      }
    }

    // 数量限制 参数
    args.add(limit);

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT * FROM words 
      WHERE $whereClause
      ORDER BY grade ASC, semester ASC, book_id ASC, order_index ASC, rowid ASC
      LIMIT ?
    ''', args);
    
    final words = List.generate(maps.length, (i) {
      return Word.fromJson(maps[i]);
    });
    
    return await _attachSentences(words);
  }

  Future<List<Word>> getWordsDueForReview(int limit, {String? bookId, int? grade, int? semester}) async {
    final db = await _dbHelper.database;
    
    // 计算今天结束时间以包含当天复习
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59).millisecondsSinceEpoch;
    
    // 关联单词表与进度表
    // 筛选已有进度且到期的单词
    
    String whereClause = 'p.next_review_date <= ?';
    List<dynamic> args = [endOfToday];

    // 优先按教材筛选
    if (bookId != null && bookId.isNotEmpty) {
       whereClause += ' AND w.book_id = ?';
       args.add(bookId);
    } else {
      // 旧逻辑兜底
      if (grade != null) {
        whereClause += ' AND w.grade = ?';
        args.add(grade);
      }
      if (semester != null) {
        whereClause += ' AND w.semester = ?';
        args.add(semester);
      }
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT w.* 
      FROM words w
      INNER JOIN word_progress p ON w.id = p.word_id
      WHERE $whereClause
      ORDER BY p.next_review_date ASC
      LIMIT ?
    ''', [...args, limit]);
    
    final words = List.generate(maps.length, (i) {
      return Word.fromJson(maps[i]);
    });
    
    return await _attachSentences(words);
  }

  Future<void> batchMarkAsLearned(List<Word> words) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var word in words) {
      batch.insert('word_progress', {
        'id': 'progress_${word.id}',
        'word_id': word.id,
        'created_at': now,
        'updated_at': now,
        // 细节处理
        'easiness_factor': 2.5,
        'interval': 1,
        'repetition': 0,
        'next_review_date': now + 86400000,
        'last_review_date': now,
        'review_count': 1, // 复习流程
        'mastery_level': 1, // 掌握度处理
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
    GlobalStatsNotifier.instance.notify();
  }

  Future<List<Word>> getRandomWords(int limit) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'words',
      orderBy: 'RANDOM()',
      limit: limit,
    );
     final words = List.generate(maps.length, (i) {
      return Word.fromJson(maps[i]);
    });
    // 细节处理
    return words;
  }

  Future<void> updateReviewStats(String wordId, int quality) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 细节处理
    final List<Map<String, dynamic>> maps = await db.query(
      'word_progress',
      where: 'word_id = ?',
      whereArgs: [wordId],
    );

    if (maps.isEmpty) return;

    final current = WordProgress.fromJson(maps.first);

    // 细节处理
    double oldEf = current.easinessFactor;
    int oldInterval = current.interval;
    int repetition = current.repetition;

    double newEf = oldEf;
    int newInterval = oldInterval;

    if (quality >= 3) {
      newEf = oldEf + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
      if (newEf < 1.3) newEf = 1.3;

      repetition += 1;

      if (repetition == 1) {
        newInterval = 1;
      } else if (repetition == 2) {
        newInterval = 6;
      } else {
        newInterval = (oldInterval * newEf).round();
      }
    } else {
      repetition = 0;
      newInterval = 1;
    }

    // 细节处理
    int newMastery = (newInterval > 21) ? 2 : 1;

    // 细节处理
    await db.update(
      'word_progress',
      {
        'easiness_factor': newEf,
        'interval': newInterval,
        'repetition': repetition,
        'next_review_date': now + (newInterval * 24 * 60 * 60 * 1000),
        'last_review_date': now,
        'review_count': current.reviewCount + 1,
        'correct_count': current.correctCount + (quality >= 3 ? 1 : 0),
        'wrong_count': current.wrongCount + (quality < 3 ? 1 : 0),
        'mastery_level': newMastery,
        'updated_at': now,
      },
      where: 'word_id = ?',
      whereArgs: [wordId],
    );
    GlobalStatsNotifier.instance.notify();
  }

  Future<Map<int, int>> getWordCounts({String? bookId, String? unit, String? searchQuery}) async {
    final db = await _dbHelper.database;
    String whereClause = '1=1';
    List<dynamic> args = [];

    if (bookId != null && bookId.isNotEmpty) {
      whereClause += ' AND w.book_id = ?';
      args.add(bookId);
    }
    if (unit != null && unit.isNotEmpty) {
      whereClause += ' AND w.unit = ?';
      args.add(unit);
    }
    final analyzed = _analyzeSearchQuery(searchQuery);
    if (analyzed.hasSearch) {
      if (analyzed.hasLatinOrDigit && !analyzed.hasCjk) {
        whereClause += ' AND LOWER(w.text) LIKE ?';
        args.add('%${analyzed.queryLower}%');
      } else if (analyzed.hasCjk && !analyzed.hasLatinOrDigit) {
        whereClause += ' AND w.meaning LIKE ?';
        args.add('%${analyzed.query}%');
      } else {
        whereClause += ' AND (LOWER(w.text) LIKE ? OR w.meaning LIKE ?)';
        args.add('%${analyzed.queryLower}%');
        args.add('%${analyzed.query}%');
      }
    }

    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT IFNULL(s.mastery_level, 0) as status, COUNT(*) as count
      FROM words w
      LEFT JOIN word_progress s ON w.id = s.word_id
      WHERE $whereClause
      GROUP BY IFNULL(s.mastery_level, 0)
    ''', args);
    
    final Map<int, int> counts = {0: 0, 1: 0, 2: 0};
    for (var row in result) {
      int status = row['status'] as int;
      int count = row['count'] as int;
      counts[status] = count;
    }
    return counts;
  }

  /// 细节处理
  Future<List<Map<String, dynamic>>> getDictionaryWords({
    int limit = 50,
    int offset = 0,
    int? masteryFilter, // 掌握度处理
    String? searchQuery,
    String? bookId,
    String? unit,
  }) async {
    final db = await _dbHelper.database;
    
    // 细节处理
    String sql = '''
      SELECT w.*, 
             p.mastery_level,
             p.next_review_date,
             p.interval,
             p.easiness_factor,
             CASE WHEN p.id IS NULL THEN 0 ELSE 1 END as is_learned
      FROM words w
      LEFT JOIN word_progress p ON w.id = p.word_id
    ''';

    List<String> whereConditions = [];
    List<dynamic> args = [];

    // 细节处理
    if (masteryFilter != null) {
      if (masteryFilter == 0) {
        // 细节处理
        whereConditions.add('(p.id IS NULL OR p.mastery_level = 0)');
      } else {
        whereConditions.add('p.mastery_level = ?');
        args.add(masteryFilter);
      }
    }

    // 细节处理
    final analyzed = _analyzeSearchQuery(searchQuery);
    if (analyzed.hasSearch) {
      if (analyzed.hasLatinOrDigit && !analyzed.hasCjk) {
        whereConditions.add('LOWER(w.text) LIKE ?');
        args.add('%${analyzed.queryLower}%');
      } else if (analyzed.hasCjk && !analyzed.hasLatinOrDigit) {
        whereConditions.add('w.meaning LIKE ?');
        args.add('%${analyzed.query}%');
      } else {
        whereConditions.add('(LOWER(w.text) LIKE ? OR w.meaning LIKE ?)');
        args.add('%${analyzed.queryLower}%');
        args.add('%${analyzed.query}%');
      }
    }
    
    if (bookId != null && bookId.isNotEmpty) {
        whereConditions.add('w.book_id = ?');
        args.add(bookId);
    }

    if (unit != null && unit.isNotEmpty) {
        whereConditions.add('w.unit = ?');
        args.add(unit);
    }

    if (whereConditions.isNotEmpty) {
      sql += ' WHERE ${whereConditions.join(' AND ')}';
    }

    if (analyzed.hasSearch) {
      sql += '''
        ORDER BY
          CASE
            WHEN LOWER(w.text) = ? THEN 0
            WHEN LOWER(w.text) LIKE ? THEN 1
            WHEN w.meaning LIKE ? THEN 2
            ELSE 3
          END,
          w.grade ASC, w.semester ASC, w.unit ASC, w.order_index ASC
      ''';
      args.add(analyzed.queryLower);
      args.add('${analyzed.queryLower}%');
      args.add('%${analyzed.query}%');
    } else {
      sql += ' ORDER BY w.grade ASC, w.semester ASC, w.unit ASC, w.order_index ASC';
    }
    sql += ' LIMIT ? OFFSET ?';
    args.add(limit);
    args.add(offset);

    return await db.rawQuery(sql, args);
  }

  Future<List<String>> getUnitsForBook(String bookId) async {
    final db = await _dbHelper.database;
    // 细节处理
    // 细节处理
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT unit FROM words WHERE book_id = ? GROUP BY unit ORDER BY MIN(rowid) ASC', 
      [bookId]
    );
    return maps.map((e) => e['unit'] as String).toList();
  }

  ({bool hasSearch, bool hasLatinOrDigit, bool hasCjk, String query, String queryLower})
      _analyzeSearchQuery(String? searchQuery) {
    final query = (searchQuery ?? '').trim();
    if (query.isEmpty) {
      return (
        hasSearch: false,
        hasLatinOrDigit: false,
        hasCjk: false,
        query: '',
        queryLower: '',
      );
    }
    final hasLatinOrDigit = RegExp(r'[A-Za-z0-9]').hasMatch(query);
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
    return (
      hasSearch: true,
      hasLatinOrDigit: hasLatinOrDigit,
      hasCjk: hasCjk,
      query: query,
      queryLower: query.toLowerCase(),
    );
  }

  /// 细节处理
  Future<Word?> getWordDetails(String wordId) async {
    final db = await _dbHelper.database;
    
    // 细节处理
    final List<Map<String, dynamic>> wordMaps = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [wordId],
    );

    if (wordMaps.isEmpty) return null;
    
    // 细节处理
    final List<Map<String, dynamic>> sentenceMaps = await db.rawQuery('''
      SELECT s.text as en, s.translation as cn
      FROM sentences s
      JOIN word_sentence_map m ON s.id = m.sentence_id
      WHERE m.word_id = ?
      ORDER BY m.is_primary DESC, m.word_position ASC
    ''', [wordId]);
    
    final Map<String, dynamic> wordData = Map<String, dynamic>.from(wordMaps.first);
    
    final List<Map<String, String>> examplesForJson = sentenceMaps.map((s) => {
      'text': s['en'] as String,
      'translation': s['cn'] as String
    }).toList();
    
    wordData['examples'] = examplesForJson;
    
    return Word.fromJson(wordData);
  }
  Future<WordProgress?> getWordProgress(String wordId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'word_progress',
      where: 'word_id = ?',
      whereArgs: [wordId],
    );
    if (maps.isEmpty) return null;
    return WordProgress.fromJson(maps.first);
  }
}
