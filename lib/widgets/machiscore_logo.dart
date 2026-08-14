import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// アプリアイコンと同じシルエットのピンマーク。
/// SVGライブラリを足さずに済むよう、アイコンと同じ座標系で直接描く。
///
/// アイコンは「青い角丸背景 + 明るいピン + 濃いバー」だが、ヘッダーでは
/// 背景の板が無いので図と地が反転する。ピンをブランド色のベタにし、
/// バーは地の色で"抜く"ことで、小さいサイズでもシルエットが同じに読める。
/// バーをスコアランプの青で塗ると青地に青が乗って消えるため、この構造にしている。
class MachiscoreMark extends StatelessWidget {
  final double height;

  const MachiscoreMark({super.key, this.height = 24});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // 隣の「マチスコア」の文字が名前を読み上げるので、マークは装飾扱いにする
    return ExcludeSemantics(
      child: SizedBox(
      height: height,
      width: height * _MarkPainter.aspectRatio,
      child: CustomPaint(
        painter: _MarkPainter(
          pin: palette.brand,
          knockout: palette.pageBackground,
        ),
      ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  /// アイコンSVGの描画範囲 540x730 に対応する縦横比。
  static const aspectRatio = 540 / 730;

  /// CustomPainter は BuildContext を持たないので、色は受け取る。
  final Color pin;

  /// バーを"抜く"色。地の色と同じにする。
  final Color knockout;

  const _MarkPainter({required this.pin, required this.knockout});

  @override
  void paint(Canvas canvas, Size size) {
    // アイコンSVGの座標(x:242〜782, y:160〜890)をこのサイズに写す
    final scale = size.height / 730;
    double x(double v) => (v - 242) * scale;
    double y(double v) => (v - 160) * scale;

    final body = Paint()..color = pin;
    canvas.drawCircle(Offset(x(512), y(430)), 270 * scale, body);
    canvas.drawPath(
      Path()
        ..moveTo(x(280), y(565))
        ..lineTo(x(512), y(890))
        ..lineTo(x(744), y(565))
        ..close(),
      body,
    );

    const bars = [
      (364.0, 500.0, 115.0),
      (478.0, 432.0, 183.0),
      (592.0, 364.0, 251.0),
    ];
    final barPaint = Paint()..color = knockout;
    for (final (left, top, barHeight) in bars) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x(left), y(top), 68 * scale, barHeight * scale),
          Radius.circular(16 * scale),
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.pin != pin || oldDelegate.knockout != knockout;
}

/// ヘッダーに置くロゴタイプ。マークと文字を組み合わせる。
/// 「スコア」だけをブランド色にして、このアプリが何を出すのかを字面で示す。
class MachiscoreLogotype extends StatelessWidget {
  const MachiscoreLogotype({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MachiscoreMark(height: 22),
        const SizedBox(width: 7),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'マチ'),
              TextSpan(text: 'スコア', style: TextStyle(color: palette.brand)),
            ],
            // カタカナは字間を少し開けるとロゴらしく締まる
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: context.palette.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
