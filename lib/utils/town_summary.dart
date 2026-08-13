import '../models/municipality.dart';

/// 町の特徴を一文にする。
///
/// スコアを5つ並べるだけでは「で、どういう町なの？」に答えられない。
/// 突出して高い／低いジャンルを拾って言葉にすることで、
/// 持ち帰れる一言になり、共有画像にも載せられる。
String? describeTown(Municipality municipality, List<CategoryInfo> categories) {
  if (!municipality.ranked) return null;

  final scored = <({String name, int score})>[];
  for (final category in categories) {
    final score = municipality.categories[category.code]?.score;
    if (score != null) scored.add((name: category.name, score: score));
  }
  if (scored.length < 3) return null;

  final sorted = [...scored]..sort((a, b) => b.score.compareTo(a.score));
  final best = sorted.first;
  final worst = sorted.last;

  // 差が小さい町を無理に「◯◯の町」と決めつけない。
  // 平坦なプロフィールは平坦だと言うほうが正確。
  if (best.score - worst.score < 25) {
    final average = scored.map((e) => e.score).reduce((a, b) => a + b) / scored.length;
    if (average >= 60) return 'どのジャンルもそろっている町';
    if (average <= 35) return 'お店が少なめの町';
    return '大きな偏りのない町';
  }

  if (best.score >= 80 && worst.score <= 30) {
    return '${best.name}が多く、${worst.name}が少ない町';
  }
  if (best.score >= 80) return '${best.name}が目立って多い町';
  if (worst.score <= 20) return '${worst.name}が少なめの町';
  return '${best.name}がやや多い町';
}

/// 5年間の変化のうち、最も動いたジャンルを一文にする。
String? describeChange(Municipality municipality, List<CategoryInfo> categories) {
  ({String name, double rate})? biggest;
  for (final category in categories) {
    final rate = municipality.categories[category.code]?.changeRate;
    if (rate == null) continue;
    if (biggest == null || rate.abs() > biggest.rate.abs()) {
      biggest = (name: category.name, rate: rate);
    }
  }
  if (biggest == null || biggest.rate.abs() < 5) return null;

  final direction = biggest.rate > 0 ? '増えました' : '減りました';
  final amount = biggest.rate.abs().toStringAsFixed(1);
  return 'この5年で${biggest.name}が$amount%$direction';
}
