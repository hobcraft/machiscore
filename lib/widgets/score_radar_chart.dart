import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/municipality.dart';
import '../theme/app_theme.dart';

/// 5カテゴリのスコアを五角形の形で見せるレーダーチャート。
///
/// 数字を5つ並べるだけだと「どの町も似たようなもの」に見えるが、
/// 形にすると「外食に強く小売が弱い町」といった個性が一目で伝わる。
/// 1つの町の輪郭を見せる用途なので、複数系列を重ねることはしない。
class ScoreRadarChart extends StatelessWidget {
  final Municipality municipality;
  final List<CategoryInfo> categories;
  final double size;

  /// ラベルを描くか。共有画像では描き、小さい場所では省く。
  final bool showLabels;

  const ScoreRadarChart({
    super.key,
    required this.municipality,
    required this.categories,
    this.size = 220,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scores = [
      for (final category in categories) municipality.categories[category.code]?.score ?? 0,
    ];
    // ラベルの分だけ外側に余白を取る
    final canvasSize = showLabels ? size * 1.5 : size;

    // 図形だけでは読み上げられないので、内容を言葉で持たせる。
    // ここを省くと画面読み上げの利用者にはグラフの情報が丸ごと失われる。
    final description = [
      for (final (index, category) in categories.indexed)
        '${category.name}${scores[index]}点',
    ].join('、');

    return Semantics(
      label: '5つのジャンルのスコアを表したレーダーチャート。$description',
      // 中の図形は個別に読み上げても意味をなさないため隠す
      excludeSemantics: true,
      child: SizedBox(
      width: canvasSize,
      height: canvasSize,
      child: CustomPaint(
        painter: _RadarPainter(
          scores: scores,
          labels: [for (final c in categories) c.name],
          radius: size / 2,
          showLabels: showLabels,
          gridColor: palette.border,
          fillColor: palette.brand.withValues(alpha: 0.22),
          strokeColor: palette.brand,
          labelColor: palette.textSecondary,
        ),
      ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<int> scores;
  final List<String> labels;
  final double radius;
  final bool showLabels;
  final Color gridColor;
  final Color fillColor;
  final Color strokeColor;
  final Color labelColor;

  const _RadarPainter({
    required this.scores,
    required this.labels,
    required this.radius,
    required this.showLabels,
    required this.gridColor,
    required this.fillColor,
    required this.strokeColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final axisCount = scores.length;

    // 頂点が真上に来るように -90度から始める
    Offset pointAt(int index, double ratio) {
      final angle = -math.pi / 2 + 2 * math.pi * index / axisCount;
      return center + Offset(math.cos(angle), math.sin(angle)) * radius * ratio;
    }

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = gridColor;

    // 目盛りの輪（25/50/75/100点）
    for (final ratio in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < axisCount; i++) {
        final point = pointAt(i, ratio);
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path..close(), gridPaint);
    }

    // 中心から各頂点への軸
    for (var i = 0; i < axisCount; i++) {
      canvas.drawLine(center, pointAt(i, 1.0), gridPaint);
    }

    // スコアの多角形
    final scorePath = Path();
    for (var i = 0; i < axisCount; i++) {
      final point = pointAt(i, (scores[i] / 100).clamp(0.0, 1.0));
      i == 0 ? scorePath.moveTo(point.dx, point.dy) : scorePath.lineTo(point.dx, point.dy);
    }
    scorePath.close();
    canvas.drawPath(scorePath, Paint()..color = fillColor);
    canvas.drawPath(
      scorePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor,
    );

    // 各頂点の点
    for (var i = 0; i < axisCount; i++) {
      final point = pointAt(i, (scores[i] / 100).clamp(0.0, 1.0));
      canvas.drawCircle(point, 3, Paint()..color = strokeColor);
    }

    if (!showLabels) return;
    for (var i = 0; i < axisCount; i++) {
      final anchor = pointAt(i, 1.18);
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(color: labelColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 1.1);
      // アンカーを中心にして置く
      painter.paint(
        canvas,
        anchor - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.scores != scores ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.gridColor != gridColor;
}
