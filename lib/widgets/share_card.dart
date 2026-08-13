import 'package:flutter/material.dart';

import '../models/municipality.dart';
import '../theme/app_theme.dart';
import '../utils/town_summary.dart';
import 'score_radar_chart.dart';

/// SNSに貼る画像として書き出すカード。
///
/// 画面のスクリーンショットではなく専用の版を作っているのは、
/// 共有先では正方形に近い比率で表示され、端末のダークモード設定にも
/// 引きずられない見た目が要るため。ここは常に明るい配色で固定する。
class ShareCard extends StatelessWidget {
  final Municipality municipality;
  final List<CategoryInfo> categories;

  /// 書き出す一辺の長さ（論理ピクセル）。実際の画像はこの3倍で出力する。
  static const side = 360.0;

  const ShareCard({super.key, required this.municipality, required this.categories});

  @override
  Widget build(BuildContext context) {
    // 共有画像は端末のテーマに関係なく一定にしたいので、明るい配色を直に使う
    const palette = AppPalette.light;
    final score = municipality.totalScore;

    // 固定サイズの版なので、端末の文字サイズ設定に左右されてはいけない。
    // 呼び出し側に任せず、この版自身で等倍に固定する。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: _buildCard(palette, score),
    );
  }

  Widget _buildCard(AppPalette palette, int? score) {
    return Container(
      width: side,
      height: side,
      color: palette.cardBackground,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            municipality.prefecture,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  municipality.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (score != null) ...[
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                    height: 1,
                  ),
                ),
                Text(
                  '点',
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ],
            ],
          ),
          if (municipality.prefectureRank != null)
            Text(
              '${municipality.prefecture}で${municipality.prefectureRank}位 '
              '/ ${municipality.prefectureTotal}市区町村中',
              style: TextStyle(
                fontSize: 12,
                color: palette.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (describeTown(municipality, categories) case final summary?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: ScoreRadarChart(
                municipality: municipality,
                categories: categories,
                size: 150,
              ),
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: palette.border),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'マチスコア',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: palette.brand,
                ),
              ),
              const Spacer(),
              Text(
                '出典: 総務省統計局',
                style: TextStyle(fontSize: 10, color: palette.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
