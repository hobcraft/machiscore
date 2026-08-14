import 'package:flutter/material.dart';

import '../models/municipality.dart';
import '../theme/app_theme.dart';
import '../utils/number_format.dart';
import '../widgets/score_bar.dart';

/// 選んだ市区町村を横に並べて比べる画面。
class CompareScreen extends StatelessWidget {
  final List<Municipality> municipalities;
  final List<CategoryInfo> categories;

  const CompareScreen({super.key, required this.municipalities, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('くらべる')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final municipality in municipalities)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        municipality.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        municipality.prefecture,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 24),
          _CompareRow(
            label: 'マチスコア',
            emphasize: true,
            municipalities: municipalities,
            valueOf: (m) => m.totalScore == null ? '—' : '${m.totalScore}',
            scoreOf: (m) => m.totalScore,
          ),
          const Divider(height: 24),
          for (final category in categories)
            _CompareRow(
              label: category.name,
              municipalities: municipalities,
              valueOf: (m) {
                final score = m.categories[category.code]?.score;
                return score == null ? '—' : '$score';
              },
              scoreOf: (m) => m.categories[category.code]?.score,
            ),
          const Divider(height: 24),
          _CompareRow(
            label: '昼間人口',
            municipalities: municipalities,
            valueOf: (m) => withThousandsSeparator(m.dayPopulation),
            scoreOf: (m) => null,
            compact: true,
          ),
          _CompareRow(
            label: '昼夜間人口比率',
            municipalities: municipalities,
            valueOf: (m) => m.dayNightRatio == null ? '—' : '${m.dayNightRatio}%',
            scoreOf: (m) => null,
            compact: true,
          ),
          const SizedBox(height: 12),
          Text(
            '「—」はデータが無いか、昼間人口が少なくスコアの対象外であることを示します',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final List<Municipality> municipalities;
  final String Function(Municipality) valueOf;
  final int? Function(Municipality) scoreOf;
  final bool emphasize;
  final bool compact;

  const _CompareRow({
    required this.label,
    required this.municipalities,
    required this.valueOf,
    required this.scoreOf,
    this.emphasize = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // 最高得点の町を強調する。同点なら全員強調しない（勝ち負けを作らない）
    final scores = municipalities.map(scoreOf).whereType<int>().toList();
    final best = scores.isEmpty ? null : scores.reduce((a, b) => a > b ? a : b);
    final bestIsUnique = best != null && scores.where((s) => s == best).length == 1;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final municipality in municipalities)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final score = scoreOf(municipality);
                      final isBest = bestIsUnique && score == best;
                      if (compact) {
                        return Text(
                          valueOf(municipality),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        );
                      }
                      return Column(
                        children: [
                          Text(
                            valueOf(municipality),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: emphasize ? 30 : 20,
                              color: isBest ? context.palette.textPrimary : context.palette.textSecondary,
                              fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (score != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: ScoreBar(
                                score: score,
                                height: emphasize ? 6 : 4,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
