import 'package:shared_preferences/shared_preferences.dart';

/// 「マイタウン」（自分の町）の保存先。
///
/// 起動するたびに検索し直すのは面倒で、アプリを再び開く理由にもならない。
/// 一度登録すれば検索前の画面に自分の町が出るようにする。
///
/// 保存するのは市区町村コードだけ。名前やスコアは同梱データ側が持っているので、
/// データを更新しても登録が壊れない。
abstract interface class HomeTownStore {
  Future<String?> load();
  Future<void> save(String areaCode);
  Future<void> clear();
}

class SharedPreferencesHomeTownStore implements HomeTownStore {
  static const _key = 'home_town_area_code';

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> save(String areaCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, areaCode);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// テスト用。端末に触らずメモリ上だけで保持する。
class InMemoryHomeTownStore implements HomeTownStore {
  String? _areaCode;

  InMemoryHomeTownStore([this._areaCode]);

  @override
  Future<String?> load() async => _areaCode;

  @override
  Future<void> save(String areaCode) async => _areaCode = areaCode;

  @override
  Future<void> clear() async => _areaCode = null;
}
