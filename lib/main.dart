import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'data/current_location_finder.dart';
import 'data/home_town_store.dart';
import 'data/machiscore_repository.dart';
import 'screens/search_screen.dart';
import 'theme/app_theme.dart';

void main() {
  // 広告の読み込みより前に済ませておく。initialize は待たなくても
  // 後続の読み込みは内部で待ち合わせるが、起動直後に呼んでおくと
  // 最初のバナーが表示されるまでが短くなる。
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const MachiscoreApp());
}

class MachiscoreApp extends StatelessWidget {
  /// テストから差し替えるための注入口。未指定なら既定のリポジトリを使う。
  final MachiscoreRepository? repository;

  /// マイタウンの保存先。テストではメモリ実装に差し替える。
  final HomeTownStore? homeTownStore;

  /// 現在地の解決。テストでは差し替える。
  final CurrentLocationFinder? locationFinder;

  const MachiscoreApp({
    super.key,
    this.repository,
    this.homeTownStore,
    this.locationFinder,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'マチスコア',
      // シミュレータはリリースビルドを動かせないので、審査用の
      // スクリーンショットもデバッグビルドから撮ることになる。
      // 右上の赤い帯が写り込むため消しておく。
      debugShowCheckedModeBanner: false,
      // 端末のダークモード設定に追従する
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: SearchScreen(
        repository: repository,
        homeTownStore: homeTownStore,
        locationFinder: locationFinder,
      ),
    );
  }
}
