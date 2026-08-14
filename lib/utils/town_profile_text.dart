import '../models/municipality.dart';

/// 統計から町の紹介文を組み立てる。
///
/// 外部の百科事典から本文を持ってくる案もあったが、記事の質が町ごとに大きく
/// 違ううえ（3割は読み仮名程度しかない）、ライセンス対応も要る。
/// このアプリの拠りどころは公的統計の正確さなので、紹介文も手元の数字から
/// 組み立てる。書けるのは事実だけになるが、全1,896件で破綻せず、
/// 画面の数字と絶対に矛盾しない。
///
/// 全国分布（1,888件の実測）を基準に「全国と比べてどうか」を述べる。
/// 例えば人口は9割の自治体で減っているので、減少しているだけでは特徴にならない。
class TownProfileText {
  /// 全国の中央値。この値を軸に「多い / 少ない」を判断する。
  static const _elderlyMedian = 34.0;
  static const _elderlyHigh = 44.8; // 上位10%
  static const _elderlyLow = 24.4; // 下位10%

  static const _changeMedian = -6.3;
  static const _changeGrowing = 0.7; // 上位10%
  static const _changeShrinking = -12.9; // 下位10%

  static const _densityUrban = 5068.7; // 上位10%
  static const _densityRural = 51.5; // 下位25%

  /// 紹介文を段落として返す。書けるものが無ければ空。
  static List<String> describe(Municipality municipality) {
    return [
      ?_character(municipality),
      ?_population(municipality),
      ?_aging(municipality),
    ];
  }

  /// 都市の性格。人口密度と昼夜間人口比率から。
  static String? _character(Municipality municipality) {
    final density = municipality.populationDensity;
    final ratio = municipality.dayNightRatio;
    if (density == null) return null;

    final scale = switch (density) {
      >= _densityUrban => '人口が密集した市街地',
      >= 1000 => '住宅と商業が混ざる市街地',
      >= 200 => '郊外や地方都市らしい広がりのある地域',
      >= _densityRural => 'ゆとりのある土地に人が住む地域',
      _ => '広い土地に人口が点在する地域',
    };

    if (ratio == null) return '$scaleです。';

    // 規模が小さい町では、数十人の差でも比率が大きく動く。
    // 青ヶ島村は昼間205人・夜間169人（36人差）で比率121%になるが、
    // これを「働く場としての性格が強い」と述べるのは言い過ぎになる。
    if (municipality.dayPopulation < 3000) return '$scaleです。';

    if (ratio >= 120) {
      return '$scaleで、昼間は夜間の${(ratio / 100).toStringAsFixed(1)}倍の人が集まります。'
          '通勤・通学で人が流入する、働く場としての性格が強い町です。';
    }
    if (ratio <= 90) {
      return '$scaleで、昼間人口は夜間の${ratio.toStringAsFixed(0)}%にとどまります。'
          '日中は多くの人が外へ通勤・通学する、住宅地としての性格が強い町です。';
    }
    return '$scaleで、昼と夜で人口があまり変わらず、'
        '住む場と働く場が近い町です。';
  }

  /// 人口の動き。全国の9割が減少しているので、その中での位置づけを述べる。
  static String? _population(Municipality municipality) {
    final rate = municipality.populationChangeRate;
    if (rate == null) return null;
    final amount = rate.abs().toStringAsFixed(1);

    if (rate >= _changeGrowing) {
      return 'この5年で人口が$amount%増えました。'
          '全国では9割の市区町村が人口を減らしており、その中では珍しく人が増えている町です。';
    }
    if (rate >= 0) {
      return 'この5年で人口はほぼ横ばい（$amount%増）です。'
          '多くの市区町村が減少するなか、人口を保っています。';
    }
    if (rate <= _changeShrinking) {
      return 'この5年で人口が$amount%減りました。'
          '全国的にも減少幅の大きい部類に入ります。';
    }
    if (rate <= _changeMedian) {
      return 'この5年で人口が$amount%減りました。全国の中央値（6.3%減）と同じくらいの減り方です。';
    }
    return 'この5年で人口が$amount%減りましたが、全国平均（6.3%減）よりは緩やかです。';
  }

  /// 高齢化。全国中央値34%を基準に。
  static String? _aging(Municipality municipality) {
    final rate = municipality.elderlyRate;
    if (rate == null) return null;
    final amount = rate.toStringAsFixed(0);

    if (rate >= _elderlyHigh) {
      return '65歳以上が$amount%を占め、全国でも高齢化が進んだ地域です。';
    }
    if (rate <= _elderlyLow) {
      return '65歳以上は$amount%で、全国的に見ると若い世代が多い町です。';
    }
    if (rate <= _elderlyMedian) {
      return '65歳以上は$amount%と、全国の中央値（34%）よりやや低めです。';
    }
    return '65歳以上が$amount%を占めています。';
  }
}
