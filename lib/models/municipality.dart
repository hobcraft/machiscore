import '../utils/search_text.dart';

class CategoryInfo {
  final String code;
  final String name;

  CategoryInfo({required this.code, required this.name});

  factory CategoryInfo.fromJson(Map<String, dynamic> json) {
    return CategoryInfo(code: json['code'] as String, name: json['name'] as String);
  }
}

class CategoryRank {
  final int count;
  final double densityPer10000;

  /// 昼間人口が少なくランキング対象外の自治体では null。
  final int? rank;
  final int? totalRanked;

  /// 順位を0〜100点に換算したもの（1位=100点）。カテゴリ間で母集団サイズが
  /// 違っても同じ尺度で比べられる。
  final int? score;

  /// 5年前(2016年)の事業所数と、そこからの増減率(%)。
  /// 2016年当時データが無い（避難区域など）／0件だった場合は null。
  final int? count2016;
  final double? changeRate;

  /// 県内での順位。「全国1235位」より実感しやすい。
  final int? prefectureRank;
  final int? prefectureTotal;

  CategoryRank({
    required this.count,
    required this.densityPer10000,
    required this.rank,
    required this.totalRanked,
    required this.score,
    required this.count2016,
    required this.changeRate,
    required this.prefectureRank,
    required this.prefectureTotal,
  });

  bool get hasRank => rank != null && totalRanked != null;

  factory CategoryRank.fromJson(Map<String, dynamic> json) {
    return CategoryRank(
      count: json['count'] as int,
      densityPer10000: (json['density_per_10000'] as num).toDouble(),
      rank: json['rank'] as int?,
      totalRanked: json['total_ranked'] as int?,
      score: json['score'] as int?,
      count2016: json['count_2016'] as int?,
      changeRate: (json['change_rate'] as num?)?.toDouble(),
      prefectureRank: json['prefecture_rank'] as int?,
      prefectureTotal: json['prefecture_total'] as int?,
    );
  }
}

class Municipality {
  final String code;
  final String name;
  final String prefecture;

  /// ひらがな読み（「しぶやく」）。かな検索に使う。
  final String kana;

  /// ヘボン式ローマ字（「shibuyaku」）。ローマ字検索に使う。
  final String romaji;

  /// 密度の分母。その町に昼間いる人の数（通勤・通学者を含む）。
  final int dayPopulation;

  /// 常住人口。国勢調査で秘匿されている場合は null。
  final int? nightPopulation;

  /// 昼夜間人口比率（%）。100を超えると昼に人が流入する町。
  final double? dayNightRatio;

  /// 全国ランキングの母集団に含まれるか。
  /// 昼間人口が少ない自治体は事業所1件の増減で密度が乱高下するため対象外にしている。
  final bool ranked;

  /// 地図プレビューの中心。大字の点をまとめた代表点なので役場とは数km離れうる。
  final double? lat;
  final double? lon;

  /// カテゴリ別スコアの平均。ランキング対象外なら null。
  final int? totalScore;

  /// 総合スコアの県内順位。
  final int? prefectureRank;
  final int? prefectureTotal;

  /// 昼間人口が近い町の中での順位。規模の違う町を同列に並べないための指標。
  final String? sizeBand;
  final int? sizeBandRank;
  final int? sizeBandTotal;

  /// 事業所の密度だけでは分からない町の背景。取得できない町では null。
  final double? populationChangeRate;
  final double? areaKm2;
  final double? populationDensity;
  final double? elderlyRate;

  final Map<String, CategoryRank> categories;

  Municipality({
    required this.code,
    required this.name,
    required this.prefecture,
    required this.kana,
    required this.romaji,
    required this.dayPopulation,
    required this.nightPopulation,
    required this.dayNightRatio,
    required this.ranked,
    required this.lat,
    required this.lon,
    required this.totalScore,
    required this.prefectureRank,
    required this.prefectureTotal,
    required this.sizeBand,
    required this.sizeBandRank,
    required this.sizeBandTotal,
    required this.populationChangeRate,
    required this.areaKm2,
    required this.populationDensity,
    required this.elderlyRate,
    required this.categories,
  });

  /// 「池田町」のように同名の市区町村が複数あるため、一覧では都道府県を添えて区別する。
  /// 「札幌市中央区」のように市名を含む区名は都道府県だけを前置する。
  late final String fullName = '$prefecture$name';

  /// 検索の突き合わせ先。漢字・都道府県付き・ひらがな・ローマ字を1つにまとめる。
  /// 検索語と同じ正規化を通しておく（片側だけだと「青ヶ島村」の「ヶ」のような
  /// 文字で取りこぼす）。打鍵のたびに組み立てると1896件×複数回の文字列生成に
  /// なるため、一度だけ作って使い回す。
  late final List<String> searchKeys = [
    normalizeForSearch(name),
    normalizeForSearch(fullName),
    kana,
    romaji,
  ];

  factory Municipality.fromJson(String code, Map<String, dynamic> json) {
    final categoriesJson = json['categories'] as Map<String, dynamic>;
    return Municipality(
      code: code,
      name: json['name'] as String,
      prefecture: json['prefecture'] as String,
      kana: json['kana'] as String? ?? '',
      romaji: json['romaji'] as String? ?? '',
      dayPopulation: json['day_population'] as int,
      nightPopulation: json['night_population'] as int?,
      dayNightRatio: (json['day_night_ratio'] as num?)?.toDouble(),
      ranked: json['ranked'] as bool,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      totalScore: json['total_score'] as int?,
      prefectureRank: json['prefecture_rank'] as int?,
      prefectureTotal: json['prefecture_total'] as int?,
      sizeBand: json['size_band'] as String?,
      sizeBandRank: json['size_band_rank'] as int?,
      sizeBandTotal: json['size_band_total'] as int?,
      populationChangeRate: (json['population_change_rate'] as num?)?.toDouble(),
      areaKm2: (json['area_km2'] as num?)?.toDouble(),
      populationDensity: (json['population_density'] as num?)?.toDouble(),
      elderlyRate: (json['elderly_rate'] as num?)?.toDouble(),
      categories: categoriesJson.map(
        (key, value) => MapEntry(key, CategoryRank.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}
