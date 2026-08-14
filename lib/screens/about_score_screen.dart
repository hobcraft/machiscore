import 'package:flutter/material.dart';

import '../data/machiscore_repository.dart';
import '../theme/app_theme.dart';

/// スコアの算出方法と出典を説明する画面。
///
/// 「100点満点」「昼間人口あたり」といった前提を結果画面の1行注記だけで
/// 済ませていたが、公的統計を根拠にするアプリで算出方法が追えないのは
/// 説得力を欠く。数字の作り方と、あえて対象外にしている範囲を明示する。
class AboutScoreScreen extends StatelessWidget {
  final MachiscoreRepository repository;

  const AboutScoreScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    final categories = repository.categories;

    return Scaffold(
      appBar: AppBar(title: const Text('スコアの見かた')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Section(
            title: 'マチスコアとは',
            body: '暮らしに関わる5つのジャンルについて、その町にお店がどれくらい多いかを'
                '100点満点で表した数値です。点数が高いほど、その町に人が集まる時間帯に'
                'お店が多いことを意味します。',
          ),
          _Section(
            title: '5つのジャンル',
            body: '総務省の産業分類にもとづく区分です。'
                '「ラーメン店」のような細かい単位は統計に区分が無いため、'
                '取得できるもっとも近い分類を使っています。',
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, category) in categories.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(category.name),
                      trailing: Text(
                        '分類 ${category.code}',
                        style: TextStyle(color: context.palette.textMuted, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const _Section(
            title: '点数の付け方',
            body: '① 事業所数を昼間人口1万人あたりに直します\n'
                '② その密度で全国の市区町村を並べ、順位を出します\n'
                '③ 順位を100点満点に置き換えます（1位が100点、最下位が0点）\n\n'
                '密度そのものではなく順位を点数にしているのは、'
                'ごく一部の町が極端に高い値を持つため、'
                'そのままでは大半の町が低い点に潰れてしまうからです。',
          ),
          const _Section(
            title: 'なぜ「昼間人口」で割るのか',
            body: 'お店が相手にするのは、その町に昼間いる人だからです。\n\n'
                '住んでいる人の数（夜間人口）で割ると、'
                '住民が少なく通勤者が多い町、たとえば東京都千代田区が'
                '専門料理店の密度で全国1位になってしまいます。'
                '昼間人口を使うと400番台まで下がり、実感に近づきます。',
          ),
          const _Section(
            title: '順位を出していない町があります',
            body: '昼間人口が1,000人に満たない市区町村は、スコアと順位の対象外にしています。\n\n'
                'お店が数軒しかなく、1軒増えるだけで密度が大きく変わるためです。'
                '対象外の町でも、事業所数と密度はそのまま表示します。',
          ),
          const _Section(
            title: 'ランキングの読み方',
            body: '上位には、お店の数自体は少ない小さな町も入ります。'
                '数字は正確ですが、母数が小さいぶん値が動きやすいため、'
                '一覧では事業所数もあわせて表示しています。',
          ),
          _Section(
            title: 'データの出典',
            body: '${repository.sourceNote}\n\n'
                'いずれも政府統計の総合窓口（e-Stat）で公開されている'
                '総務省統計局の統計です。'
                '経済センサス活動調査は経済産業省との共同実施です。\n\n'
                '${repository.coordinateNote}\n'
                '地図の中心に使う代表点だけは政府統計に含まれないため、'
                '別のデータを利用しています。',
          ),
          const _Section(
            title: '通信について',
            body: '統計データはアプリに内蔵しているので、'
                'スコアや順位の表示に通信は使いません。\n\n'
                '通信するのは地図を表示するときだけです。'
                '圏外では地図が出ませんが、ほかの表示には影響しません。',
          ),
          const _Section(
            title: 'ご注意',
            body: 'スコアはお店の多さを表すものであり、'
                '町の優劣や住みやすさを示すものではありません。'
                '公共交通、自然環境、子育て支援、家賃など、'
                '町を選ぶうえで大切な要素の多くはこの数値に含まれていません。',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  final Widget? child;

  const _Section({required this.title, required this.body, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
              height: 1.7,
            ),
          ),
          if (child != null) ...[const SizedBox(height: 10), child!],
        ],
      ),
    );
  }
}
