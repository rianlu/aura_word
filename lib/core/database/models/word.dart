import 'dart:convert';
import '../../services/pronunciation_settings.dart';

class Word {
  final String id;
  final String text;
  final String meaning;
  final String phonetic;
  final String phoneticTextbook;
  final String phoneticDictionary;
  final String pos;

  /// 音素评分用的参考音标。优先课本，没有再退回现用音标。
  String get referencePhonetic {
    final textbook = phoneticTextbook.trim();
    if (textbook.isNotEmpty) return textbook;
    if (phonetic.trim().isNotEmpty) return phonetic.trim();
    return phoneticDictionary.trim();
  }

  /// 按设置返回课本音标或词典音标。课本没有音标时回退到词典。
  String get displayPhonetic {
    final textbook = phoneticTextbook.trim();
    final dictionary = phoneticDictionary.trim().isNotEmpty
        ? phoneticDictionary.trim()
        : phonetic.trim();
    final chosen = PhoneticSourceSettings.useTextbook
        ? (textbook.isNotEmpty ? textbook : dictionary)
        : (dictionary.isNotEmpty ? dictionary : textbook);
    if (chosen.contains('US:')) {
      final match = RegExp(r'US:\s*(\[[^\]]+\]|[^\]\s]+)').firstMatch(chosen);
      return match?.group(1)?.trim() ?? chosen;
    }
    return chosen.trim();
  }

  final int grade;
  final int semester;
  final String unit;
  final int difficulty;
  final String category;
  final String bookId;
  final int orderIndex; // 教材排序顺序
  final List<String> syllables;
  final List<Map<String, String>> examples; 

  Word({
    required this.id,
    required this.text,
    required this.meaning,
    required this.phonetic,
    this.phoneticTextbook = '',
    this.phoneticDictionary = '',
    this.pos = '',
    required this.grade,
    required this.semester,
    required this.unit,
    required this.difficulty,
    required this.category,
    this.bookId = '',
    this.orderIndex = 0,
    this.syllables = const [],
    this.examples = const [],
  });

  factory Word.fromJson(Map<String, dynamic> json) {
     List<Map<String, String>> examplesList = [];
     if (json['examples'] != null) {
       examplesList = (json['examples'] as List).map((e) => {
         'en': (e['en'] ?? e['text'] ?? '') as String,
         'cn': (e['cn'] ?? e['translation'] ?? '') as String,
       }).toList();
     }

     List<String> syllablesList = [];
     if (json['syllables'] != null) {
       if (json['syllables'] is String) {
         try {
           syllablesList = List<String>.from(jsonDecode(json['syllables']));
         } catch (e) {
           syllablesList = [];
         }
       } else if (json['syllables'] is List) {
         syllablesList = List<String>.from(json['syllables']);
       }
     }
     
     return Word(
         id: json['id'] as String,
         text: json['text'] as String,
         meaning: json['meaning'] as String,
         phonetic: json['phonetic'] as String? ?? '',
         phoneticTextbook: json['phonetic_textbook'] as String? ?? '',
         phoneticDictionary: json['phonetic_dictionary'] as String? ??
             json['phonetic'] as String? ??
             '',
         pos: json['pos'] as String? ?? '',
         grade: json['grade'] as int,
         semester: json['semester'] as int,
         unit: json['unit'] as String,
         difficulty: json['difficulty'] as int,
         category: json['category'] as String,
         bookId: json['book_id'] as String? ?? '',
         orderIndex: json['order_index'] as int? ?? 0,
         syllables: syllablesList,
         examples: examplesList,
       );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'meaning': meaning,
        'phonetic': phonetic,
        'phonetic_textbook': phoneticTextbook,
        'phonetic_dictionary': phoneticDictionary,
        'pos': pos,
        'grade': grade,
        'semester': semester,
        'unit': unit,
        'difficulty': difficulty,
        'category': category,
        'book_id': bookId,
        'order_index': orderIndex,
        'syllables': jsonEncode(syllables), 
      };
}
