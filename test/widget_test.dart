import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:machiscore/data/machiscore_repository.dart';
import 'package:machiscore/main.dart';
import 'package:machiscore/screens/compare_screen.dart';
import 'package:machiscore/screens/result_screen.dart';
import 'package:machiscore/theme/app_theme.dart';

/// テスト用のリポジトリ。
/// 本番は compute() で別isolateに逃がすが、flutter_test ではそのisolateが
/// 完了しないため、同一isolateでパースするものに差し替える。
MachiscoreRepository newTestRepository() =>
    MachiscoreRepository(parse: MachiscoreRepository.parseInline);

/// 同梱JSONを読み終えた状態のアプリを描画する。
///
/// rootBundle の読み込みは testWidgets の疑似非同期環境では解決しないため、
/// runAsync で実I/Oを先に済ませてから注入する。これをやらないと
/// ローディング表示のまま pumpAndSettle がタイムアウトする。
Future<void> pumpLoadedApp(WidgetTester tester) async {
  final repository = newTestRepository();
  await tester.runAsync(repository.load);
  await tester.pumpWidget(MachiscoreApp(repository: repository));
  await tester.pump();
}

Future<MachiscoreRepository> loadRepository() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = newTestRepository();
  await repository.load();
  return repository;
}

void main() {
  testWidgets('起動すると検索画面が表示される', (tester) async {
    await pumpLoadedApp(tester);

    expect(find.text('マチスコア'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('同名の市区町村を都道府県で区別できる', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '池田町');
    await tester.pump();

    // 池田町は北海道・福井・長野・岐阜の4件ある。
    // find.text は検索欄の入力値も拾うため、一覧の行だけを数える。
    expect(find.widgetWithText(ListTile, '池田町'), findsNWidgets(4));
    expect(find.widgetWithText(ListTile, '北海道'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '岐阜県'), findsOneWidget);
  });

  testWidgets('検索結果をタップすると順位が表示される', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.textContaining('全国'), findsWidgets);
    // 分母は昼間人口。3桁区切りで表示する。
    expect(find.text('551,344人'), findsOneWidget);
  });

  testWidgets('検索結果が0件のときはその旨を表示する', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), 'そんな町はない');
    await tester.pump();

    expect(find.text('該当する市区町村が見つかりません'), findsOneWidget);
  });

  test('検索結果を打ち切らない', () async {
    final repository = await loadRepository();
    // 「町」は数百件該当する。以前は50件で無言に打ち切っていた。
    final results = repository.search('町');
    expect(results.length, greaterThan(100));
  });

  test('昼間人口が少ない自治体は順位を持たない', () async {
    // 青ヶ島村は昼間人口205人。1件の増減で密度が乱高下するため、
    // 全国順位は出さずに事業所数と密度だけ見せる。
    final repository = await loadRepository();
    final aogashima = repository.municipalities.firstWhere((m) => m.name == '青ヶ島村');

    expect(aogashima.ranked, isFalse);
    final shops = aogashima.categories['58']!;
    expect(shops.hasRank, isFalse);
    expect(shops.count, greaterThan(0)); // 数字自体は残す
  });

  test('ranked と順位の有無が食い違わない', () async {
    final repository = await loadRepository();
    for (final municipality in repository.municipalities) {
      for (final rank in municipality.categories.values) {
        expect(
          rank.hasRank,
          municipality.ranked,
          reason: '${municipality.name}: ranked=${municipality.ranked} なのに '
              'rank=${rank.rank}',
        );
      }
    }
  });

  testWidgets('ランキング対象外の町ではその旨を表示する', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '青ヶ島村');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '青ヶ島村').first);
    await tester.pumpAndSettle();

    expect(find.text('マチスコア対象外'), findsOneWidget);
    expect(find.text('ランキング対象外'), findsWidgets);
    expect(find.textContaining('スコアと全国順位は出していません'), findsOneWidget);
    // 順位は出さないが事業所数と密度は見せる
    expect(find.textContaining('昼間人口1万人あたり'), findsWidgets);
  });

  test('スコアが0〜100に収まり、順位と整合している', () async {
    final repository = await loadRepository();
    for (final municipality in repository.municipalities) {
      final total = municipality.totalScore;
      if (total != null) expect(total, inInclusiveRange(0, 100));

      for (final rank in municipality.categories.values) {
        // 順位があればスコアもある、無ければ両方無い
        expect(rank.score != null, rank.hasRank);
        if (rank.score == null) continue;
        expect(rank.score, inInclusiveRange(0, 100));
        // 1位なら満点、最下位なら0点
        if (rank.rank == 1) expect(rank.score, 100);
        if (rank.rank == rank.totalRanked) expect(rank.score, 0);
      }
    }
  });

  test('スコアが高い町ほど順位も上（同一カテゴリ内で逆転しない）', () async {
    final repository = await loadRepository();
    for (final category in repository.categories) {
      final pairs = <(int rank, int score)>[];
      for (final municipality in repository.municipalities) {
        final entry = municipality.categories[category.code];
        if (entry?.score == null) continue;
        pairs.add((entry!.rank!, entry.score!));
      }
      pairs.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < pairs.length; i++) {
        expect(
          pairs[i].$2,
          lessThanOrEqualTo(pairs[i - 1].$2),
          reason: '${category.name}: 順位${pairs[i].$1}のスコアが上位より高い',
        );
      }
    }
  });

  testWidgets('結果画面に総合スコアと昼夜間人口比率が出る', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '千代田区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '千代田区').first);
    await tester.pumpAndSettle();

    expect(find.text('マチスコア'), findsOneWidget);
    expect(find.text('昼夜間人口比率'), findsOneWidget);
    // 千代田区は昼に人が集まる典型。
    // 値と補足は1つのテキストにまとめているので部分一致で見る。
    expect(find.textContaining('昼に人が集まる町'), findsOneWidget);
  });

  testWidgets('2件選ぶとくらべる画面に進み、両方のスコアが並ぶ', (tester) async {
    await pumpLoadedApp(tester);

    // 「区」で検索して先頭2件を選ぶ
    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();

    // 1件だけではまだ比較できない
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.enterText(find.byType(TextField), '千代田区');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    // FABは登場アニメーション中 IgnorePointer に包まれてタップを受け付けない。
    // pump() だけだとアニメーションが終わらないので settle させる。
    await tester.pumpAndSettle();

    expect(find.text('2件をくらべる'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(CompareScreen), findsOneWidget);
    // 見出しに両方の町が並ぶ
    expect(find.text('渋谷区'), findsOneWidget);
    expect(find.text('千代田区'), findsOneWidget);
    // 比較の行がそろっている
    expect(find.text('マチスコア'), findsOneWidget);
    for (final category in ['専門料理店', '喫茶店', '美容室']) {
      expect(find.text(category), findsOneWidget, reason: '$category の行がない');
    }

    // 人口の行はカテゴリ5行の下にあり、初期表示では画面外なのでスクロールする
    await tester.scrollUntilVisible(find.text('昼夜間人口比率'), 200);
    expect(find.text('昼夜間人口比率'), findsOneWidget);
    expect(find.text('昼間人口'), findsOneWidget);
  });

  testWidgets('選択を解除できる', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle).first);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  test('5年間の増減率が2016年の件数と整合している', () async {
    final repository = await loadRepository();
    var withTrend = 0;
    var total = 0;
    for (final municipality in repository.municipalities) {
      for (final entry in municipality.categories.values) {
        total++;
        final past = entry.count2016;
        final rate = entry.changeRate;
        if (rate == null) continue;
        withTrend++;
        expect(past, isNotNull, reason: '増減率があるのに2016年の件数が無い');
        expect(past, greaterThan(0), reason: '2016年0件から増減率は出せない');
        // 増減率は (2021-2016)/2016 と一致するはず。
        // バッチはPython(偶数丸め)、テストはDart(0.5切り上げ)で丸めの流儀が違うため、
        // 丸め後の値どうしではなく「表示桁1桁分の誤差に収まるか」で検証する。
        final exact = (entry.count - past!) / past * 100;
        expect(rate, closeTo(exact, 0.1), reason: '${municipality.name} の増減率が計算と合わない');
      }
    }
    // ほとんどの市区町村で5年前と比較できていること
    expect(withTrend / total, greaterThan(0.95));
  });

  testWidgets('結果画面に5年間の増減が出る', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    // 渋谷区は美容室が5年で増えている
    expect(find.textContaining('5年前より'), findsWidgets);
    expect(find.textContaining('2016年'), findsWidgets);
  });

  // 端末の文字サイズ設定を上げるとレイアウトが崩れやすい。
  // iPhone相当の幅で、アクセシビリティ設定の拡大率まで検証する。
  for (final scale in [1.6, 2.2, 3.0]) {
    testWidgets('文字を$scale倍にしても結果画面がはみ出さない', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final repository = newTestRepository();
      await tester.runAsync(repository.load);
      final shibuya = repository.municipalities.firstWhere((m) => m.name == '渋谷区');
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: ResultScreen(
              municipality: shibuya,
              categories: repository.categories,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ダークモードでも配色が切り替わり、崩れない', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: MachiscoreApp(repository: repository),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // ライト用の配色のままになっていないこと
    final context = tester.element(find.byType(Scaffold).first);
    expect(context.palette, AppPalette.dark);
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  test('明暗どちらのパレットもコントラスト基準を満たす', () {
    double luminance(Color c) {
      double channel(double v) =>
          v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    }

    double contrast(Color a, Color b) {
      final la = luminance(a), lb = luminance(b);
      final hi = math.max(la, lb), lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final (name, palette) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
      // 本文テキストは 4.5:1
      for (final (label, color) in [
        ('textPrimary', palette.textPrimary),
        ('textSecondary', palette.textSecondary),
        ('textMuted', palette.textMuted),
      ]) {
        for (final (bgName, bg) in [
          ('card', palette.cardBackground),
          ('page', palette.pageBackground),
        ]) {
          expect(
            contrast(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name: $label が $bgName で4.5:1未満',
          );
        }
      }
      // スコアバーは下地に対して 3:1（非テキスト要素）
      for (final color in palette.scoreRamp) {
        expect(
          contrast(color, palette.track),
          greaterThanOrEqualTo(3.0),
          reason: '$name: スコアバーが下地から識別できない',
        );
      }
      // 増加の色も本文と同じ扱いで読ませる
      expect(
        contrast(palette.increase, palette.cardBackground),
        greaterThanOrEqualTo(4.5),
        reason: '$name: increase が読みにくい',
      );
    }
  });

  test('総合スコアは常に全カテゴリの平均である', () async {
    // 事業所ゼロのカテゴリを平均から外すと「店が無い町ほど高得点」になる。
    // e-Statの「-」はゼロを意味するので0点として必ず平均に含める。
    final repository = await loadRepository();
    final categoryCount = repository.categories.length;
    for (final municipality in repository.municipalities) {
      if (!municipality.ranked) continue;
      expect(
        municipality.categories.length,
        categoryCount,
        reason: '${municipality.name} のカテゴリが $categoryCount 個そろっていない',
      );
      final scores = municipality.categories.values.map((c) => c.score!).toList();
      final expected = (scores.reduce((a, b) => a + b) / scores.length).round();
      expect(
        municipality.totalScore,
        expected,
        reason: '${municipality.name} の総合スコアが全カテゴリ平均と一致しない',
      );
    }
  });

  test('ロゴマークのバーが地の色で抜かれ、ピンから識別できる', () {
    // ピンもバーもスコアランプの青にすると青地に青が乗って消える。
    // 明暗どちらでもバーがピンから十分に分離していることを確認する。
    double luminance(Color c) {
      double ch(double v) =>
          v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    for (final (name, palette) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
      final pin = luminance(palette.brand);
      final bar = luminance(palette.pageBackground);
      final hi = math.max(pin, bar), lo = math.min(pin, bar);
      expect(
        (hi + 0.05) / (lo + 0.05),
        greaterThanOrEqualTo(3.0),
        reason: '$name: ロゴのバーがピンに埋もれる',
      );
    }
  });

  test('同じ密度なら同じ順位になっている', () async {
    // 表示上の密度が同じなのに順位が違うと、ユーザーには不整合に見える。
    // バッチ側の順位付け(competition ranking)が崩れていないことを検証する。
    final repository = await loadRepository();
    for (final category in repository.categories) {
      final rankByDensity = <double, int>{};
      for (final municipality in repository.municipalities) {
        final rank = municipality.categories[category.code];
        if (rank == null || !rank.hasRank) continue;
        final existing = rankByDensity.putIfAbsent(rank.densityPer10000, () => rank.rank!);
        expect(
          rank.rank,
          existing,
          reason: '${municipality.name} の${category.name}: '
              '密度${rank.densityPer10000}に対し順位が${rank.rank}と$existingで割れている',
        );
      }
    }
  });

  test('全市区町村に都道府県と昼間人口が入っている', () async {
    final repository = await loadRepository();
    expect(repository.municipalities.length, greaterThan(1800));
    for (final municipality in repository.municipalities) {
      expect(municipality.prefecture, isNotEmpty, reason: '${municipality.name} に都道府県がない');
      // 昼間人口は密度の分母なので、0やnullがあってはならない
      expect(
        municipality.dayPopulation,
        greaterThan(0),
        reason: '${municipality.name} の昼間人口が不正',
      );
    }
  });

  test('オフィス街が夜間人口ベースの過大評価から補正されている', () async {
    // 千代田区は夜間人口が少なく昼間人口が桁違いに多い。
    // 夜間人口で割ると飲食店密度が全国1位になってしまうため昼間人口を分母にしている。
    final repository = await loadRepository();
    final chiyoda = repository.municipalities.firstWhere((m) => m.code == '13101');
    expect(chiyoda.dayNightRatio, greaterThan(1000));
    expect(chiyoda.categories['762']!.rank, greaterThan(100));
  });
}
