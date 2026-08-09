import 'package:flutter/material.dart';

import '../models/municipality.dart';
import '../theme/app_theme.dart';
import '../utils/number_format.dart';

/// 点数の高さを色の濃さで示すバー。数値の大小を色でも伝える。
class _ScoreBar extends StatelessWidget {
  final int score;
  final double height;

  const _ScoreBar({required this.score, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: score / 100,
        minHeight: height,
        backgroundColor: context.palette.track,
        valueColor: AlwaysStoppedAnimation(context.palette.scoreColor(score)),
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  final Municipality municipality;
  final List<CategoryInfo> categories;

  const ResultScreen({super.key, required this.municipality, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(municipality.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ScoreHeader(municipality: municipality),
          const SizedBox(height: 20),
          for (final category in categories)
            _CategoryCard(
              category: category,
              rank: municipality.categories[category.code],
            ),
          const SizedBox(height: 8),
          if (municipality.ranked)
            Text(
              'スコアは昼間人口1万人あたりの事業所数の全国順位を、100点満点に換算したものです',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
            ),
        ],
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  final Municipality municipality;

  const _ScoreHeader({required this.municipality});

  @override
  Widget build(BuildContext context) {
    final score = municipality.totalScore;
    final ratio = municipality.dayNightRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          municipality.prefecture,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (score != null) ...[
          // 大きな文字設定では横一列に収まらないため折り返す
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                'マチスコア',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
              // 数字はインクで置く。色は下のバーに担わせ、
              // 可読性を色の濃さに左右させない。
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$score',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: context.palette.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: ' 点',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ScoreBar(score: score, height: 8),
        ] else ...[
          Text(
            'マチスコア対象外',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: context.palette.textMuted),
          ),
          const SizedBox(height: 4),
          // 対象外の理由は画面下部ではなくここに置く。
          // なぜスコアが無いのかは、スコアの位置で答えるのが親切。
          Text(
            '昼間人口が少なく数字が振れやすいため、スコアと全国順位は出していません',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ],
        const SizedBox(height: 12),
        _StatRow(
          label: '昼間人口',
          value: '${withThousandsSeparator(municipality.dayPopulation)}人',
        ),
        if (municipality.nightPopulation != null)
          _StatRow(
            label: '夜間人口',
            value: '${withThousandsSeparator(municipality.nightPopulation!)}人',
          ),
        if (ratio != null)
          _StatRow(
            label: '昼夜間人口比率',
            value: '$ratio%',
            note: ratio >= 100 ? '昼に人が集まる町' : '夜に人が戻る町',
          ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final String? note;

  const _StatRow({required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary);
    // ラベル幅は文字サイズ設定に追従させる。固定幅のままだと
    // 大きな文字設定で値がはみ出す。
    final labelWidth = MediaQuery.textScalerOf(context).scale(110);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: labelWidth, child: Text(label, style: labelStyle)),
          // 値と補足は残り幅で折り返す
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value, style: Theme.of(context).textTheme.bodyMedium),
                  if (note != null) TextSpan(text: '  ${note!}', style: labelStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2016年からの5年間の増減を示すバッジ。
/// 増減は「良し悪し」ではなく町の変化なので、赤字/黒字のような
/// 価値判断の強い配色は避け、増加を緑、減少を控えめな灰色系にとどめる。
class _ChangeChip extends StatelessWidget {
  final double changeRate;
  final int count2016;

  const _ChangeChip({required this.changeRate, required this.count2016});

  @override
  Widget build(BuildContext context) {
    final increased = changeRate > 0;
    final flat = changeRate.abs() < 0.05;
    // 全国的には減少が多数派なので、増加だけを緑で立て、減少は中立色で沈める。
    // 緑と赤茶の2色にすると色覚特性で区別できない（CVD ΔE 2.1）ため彩度で差をつける。
    final color = increased && !flat ? context.palette.increase : context.palette.decrease;
    final sign = increased ? '+' : '';

    // Row のままだと大きな文字設定で横にはみ出すため、
    // 折り返せる Wrap にして「(2016年 …)」を次行に送れるようにする。
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              flat
                  ? Icons.trending_flat
                  : increased
                      ? Icons.trending_up
                      : Icons.trending_down,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              flat ? '5年前と横ばい' : '5年前より $sign${changeRate.toStringAsFixed(1)}%',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Text(
          '(2016年 ${withThousandsSeparator(count2016)})',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryInfo category;
  final CategoryRank? rank;

  const _CategoryCard({required this.category, required this.rank});

  @override
  Widget build(BuildContext context) {
    final entry = rank;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: entry == null
            ? Row(
                children: [
                  Expanded(
                    child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('データなし', style: TextStyle(color: context.palette.textMuted)),
                ],
              )
            : _CategoryBody(category: category, entry: entry),
      ),
    );
  }
}

class _CategoryBody extends StatelessWidget {
  final CategoryInfo category;
  final CategoryRank entry;

  const _CategoryBody({required this.category, required this.entry});

  @override
  Widget build(BuildContext context) {
    final score = entry.score;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (score != null)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$score',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: context.palette.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: '点',
                      style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              Text(
                'ランキング対象外',
                style: TextStyle(color: context.palette.textMuted, fontSize: 13),
              ),
          ],
        ),
        if (score != null) ...[
          const SizedBox(height: 8),
          _ScoreBar(score: score),
        ],
        const SizedBox(height: 8),
        Text(
          [
            '事業所数 ${withThousandsSeparator(entry.count)}',
            '昼間人口1万人あたり ${entry.densityPer10000}件',
            if (entry.hasRank) '全国${entry.rank}位 / ${withThousandsSeparator(entry.totalRanked!)}件中',
          ].join(' ・ '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
        ),
        if (entry.changeRate != null) ...[
          const SizedBox(height: 6),
          _ChangeChip(changeRate: entry.changeRate!, count2016: entry.count2016!),
        ],
      ],
    );
  }
}
