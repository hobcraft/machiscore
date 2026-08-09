import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/municipality.dart';

/// 同梱JSONのパース結果。
class MachiscoreData {
  final List<CategoryInfo> categories;
  final List<Municipality> municipalities;

  MachiscoreData({required this.categories, required this.municipalities});
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

  return MachiscoreData(categories: categories, municipalities: municipalities);
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

  /// 市区町村名・都道府県名の部分一致で検索する。
  /// 「渋谷」でも「東京都渋谷区」でも引けるよう、都道府県付きの名前も対象にする。
  /// 前方一致を先に、それ以外を後ろに並べる。件数は打ち切らない。
  List<Municipality> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final prefixMatches = <Municipality>[];
    final otherMatches = <Municipality>[];
    for (final municipality in _data?.municipalities ?? const <Municipality>[]) {
      final name = municipality.name;
      final fullName = municipality.fullName;
      if (name.startsWith(trimmed) || fullName.startsWith(trimmed)) {
        prefixMatches.add(municipality);
      } else if (name.contains(trimmed) || fullName.contains(trimmed)) {
        otherMatches.add(municipality);
      }
    }
    return [...prefixMatches, ...otherMatches];
  }
}
