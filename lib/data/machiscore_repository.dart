import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/municipality.dart';
import '../utils/search_text.dart';

/// 同梱JSONのパース結果。
class MachiscoreData {
  final List<CategoryInfo> categories;
  final List<Municipality> municipalities;

  /// 出典表記。バッチ側が実際に使った統計を書き出すので、
  /// アプリに固定文言を持たせず必ずこちらを表示する
  /// （二重管理にするとデータを足したときに表示だけ古くなる）。
  final String sourceNote;

  MachiscoreData({
    required this.categories,
    required this.municipalities,
    required this.sourceNote,
  });
}

/// 1.5MB のJSONをデコードしてモデルに変換する。
/// UIスレッドを止めないよう [compute] 経由で別isolateから呼ばれる。
MachiscoreData _parseMachiscoreJson(String jsonString) {
  final data = json.decode(jsonString) as Map<String, dynamic>;

  final categories = (data['categories'] as List)
      .map((e) => CategoryInfo.fromJson(e as Map<String, dynamic>))
      .toList();

  final municipalities = (data['municipalities'] as Map<String, dynamic>)
      .entries
      .map((entry) => Municipality.fromJson(entry.key, entry.value as Map<String, dynamic>))
      .toList();

  return MachiscoreData(
    categories: categories,
    municipalities: municipalities,
    sourceNote: data['source_note'] as String? ?? '',
  );
}

typedef JsonParser = Future<MachiscoreData> Function(String jsonString);

class MachiscoreRepository {
  /// 本番では別isolate、テストでは同一isolateでパースする。
  /// flutter_test では compute() が立てるisolateが完了しないため、
  /// パース方法を差し替えられるようにしている。
  MachiscoreRepository({JsonParser? parse}) : _parse = parse ?? parseInIsolate;

  final JsonParser _parse;
  MachiscoreData? _data;

  static Future<MachiscoreData> parseInIsolate(String jsonString) =>
      compute(_parseMachiscoreJson, jsonString);

  /// テスト用。isolateを立てずにその場でパースする。
  static Future<MachiscoreData> parseInline(String jsonString) async =>
      _parseMachiscoreJson(jsonString);

  bool get isLoaded => _data != null;

  Future<void> load() async {
    if (_data != null) return;
    final jsonString = await rootBundle.loadString('assets/data/machiscore.json');
    _data = await _parse(jsonString);
  }

  List<CategoryInfo> get categories => _data?.categories ?? const [];

  List<Municipality> get municipalities => _data?.municipalities ?? const [];

  String get sourceNote => _data?.sourceNote ?? '';

  /// スコアの並びが近い市区町村を返す。
  ///
  /// 5カテゴリのスコアを5次元の点とみなし、ユークリッド距離が小さい順に選ぶ。
  /// 総合点ではなく「どのジャンルが強い町か」という形で似た町が出るので、
  /// 政令市の中心区には他の政令市の中心区が、といった納得感のある結果になる。
  ///
  /// 事前計算せず都度求めているのは、1863件×5次元なら十分速く、
  /// 同梱JSONを膨らませずに済むため。
  List<Municipality> similarTo(Municipality target, {int limit = 5}) {
    if (!target.ranked) return const [];
    final categoryCodes = categories.map((c) => c.code).toList();
    final targetScores = _scoreVector(target, categoryCodes);
    if (targetScores == null) return const [];

    final scored = <(double, Municipality)>[];
    for (final municipality in municipalities) {
      if (municipality.code == target.code || !municipality.ranked) continue;
      final scores = _scoreVector(municipality, categoryCodes);
      if (scores == null) continue;
      var sum = 0.0;
      for (var i = 0; i < scores.length; i++) {
        final diff = scores[i] - targetScores[i];
        sum += diff * diff;
      }
      scored.add((sum, municipality));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final entry in scored.take(limit)) entry.$2];
  }

  static List<int>? _scoreVector(Municipality municipality, List<String> categoryCodes) {
    final scores = <int>[];
    for (final code in categoryCodes) {
      final score = municipality.categories[code]?.score;
      if (score == null) return null;
      scores.add(score);
    }
    return scores;
  }

  /// 市区町村を検索する。
  ///
  /// 漢字だけでなく、ひらがな・カタカナ・ローマ字でも引ける
  /// （「渋谷」「しぶや」「シブヤ」「shibuya」がいずれも渋谷区に当たる）。
  /// 「東京都渋谷区」のように都道府県を付けた形にも対応する。
  /// 前方一致を先に、それ以外を後ろに並べる。件数は打ち切らない。
  List<Municipality> search(String query) {
    final normalized = normalizeForSearch(query);
    if (normalized.isEmpty) return const [];

    final prefixMatches = <Municipality>[];
    final otherMatches = <Municipality>[];
    for (final municipality in _data?.municipalities ?? const <Municipality>[]) {
      var matchedPrefix = false;
      var matched = false;
      for (final key in municipality.searchKeys) {
        if (key.startsWith(normalized)) {
          matchedPrefix = true;
          break;
        }
        if (!matched && key.contains(normalized)) matched = true;
      }
      if (matchedPrefix) {
        prefixMatches.add(municipality);
      } else if (matched) {
        otherMatches.add(municipality);
      }
    }
    return [...prefixMatches, ...otherMatches];
  }

}
