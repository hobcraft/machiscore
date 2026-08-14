import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 点数の高さを色の濃さで示すバー。数値の大小を色でも伝える。
///
/// 同じものを4画面に手で複製していたところ、画面読み上げ対応が2画面だけ
/// 抜けていた。LinearProgressIndicator は value を渡すと「76%」という
/// 読み上げ値を自分で作るため、隣の「76点」と二重に読まれてしまう。
/// 隠す判断をここ1箇所に置いて、画面ごとの付け忘れを起こさないようにする。
class ScoreBar extends StatelessWidget {
  final int score;
  final double height;

  const ScoreBar({super.key, required this.score, this.height = 6});

  @override
  Widget build(BuildContext context) {
    // 点数は隣のテキストが読み上げるので、バーは装飾として隠す
    return ExcludeSemantics(
      child: ClipRRect(
        // 高さの半分にして両端を丸める
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(
          value: score / 100,
          minHeight: height,
          backgroundColor: context.palette.track,
          valueColor: AlwaysStoppedAnimation(context.palette.scoreColor(score)),
        ),
      ),
    );
  }
}
