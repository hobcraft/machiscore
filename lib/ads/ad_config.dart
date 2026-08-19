import 'package:flutter/foundation.dart';

/// AdMob の広告IDをまとめる。
///
/// 本番IDのままシミュレータや実機で広告を出したりタップしたりすると、
/// Googleに無効なトラフィックと判定され、アカウント停止と収益没収の
/// おそれがある。開発中は必ずGoogle提供のテスト用IDを使う。
///
/// アプリIDは区切りが `~`、広告ユニットIDは `/`。取り違えると初期化に失敗する。
class AdConfig {
  const AdConfig._();

  /// 本番の広告を配信してよいか。
  ///
  /// 次の3つがすべて済むまで false のままにすること。
  ///   1. App Store の審査が完了し、マチスコアが公開されている
  ///   2. AdMob のアカウントが承認済み
  ///   3. AdMob 側でストア情報を紐づけ、アプリ審査が完了している
  ///
  /// 済んだら `kReleaseMode` に変えると、リリースビルドだけ本番になる。
  /// あわせて ios/Flutter/Release.xcconfig の ADMOB_APP_ID も本番へ。
  /// 片方だけ切り替えるとアプリIDと広告ユニットIDが食い違い、読み込みに失敗する。
  static const bool useProductionAds = false;

  /// リリースビルドかどうか。本番解禁後の切り替え先として置いてある。
  static bool get isReleaseBuild => kReleaseMode;

  /// バナーの広告ユニットID。
  ///
  /// テスト用は Google 公式（developers.google.com/admob/ios/test-ads）の
  /// iOS向けバナー。Android用の `/2934735716` とは別物なので注意。
  static String get bannerUnitId =>
      useProductionAds ? _productionBannerUnitId : testBannerUnitId;

  static const _productionBannerUnitId = 'ca-app-pub-3660525702986796/3242067931';
  static const testBannerUnitId = 'ca-app-pub-3940256099942544/2435281174';

  /// Info.plist の GADApplicationIdentifier に入る値。
  ///
  /// plist はDartから切り替えられないので、実体は xcconfig の ADMOB_APP_ID。
  /// ここでは対応関係を残すためだけに持つ。
  static const productionAppId = 'ca-app-pub-3660525702986796~8286561381';
  static const testAppId = 'ca-app-pub-3940256099942544~1458002511';
}
