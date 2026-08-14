import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geocoding/geocoding.dart';
import 'package:machiscore/data/current_location_finder.dart';
import 'package:machiscore/data/home_town_store.dart';
import 'package:machiscore/data/machiscore_repository.dart';
import 'package:machiscore/main.dart';
import 'package:machiscore/models/municipality.dart';
import 'package:machiscore/screens/about_score_screen.dart';
import 'package:machiscore/screens/compare_screen.dart';
import 'package:machiscore/screens/ranking_screen.dart';
import 'package:machiscore/screens/result_screen.dart';
import 'package:machiscore/widgets/score_radar_chart.dart';
import 'package:machiscore/widgets/town_map_preview.dart';
import 'package:machiscore/widgets/share_card.dart';
import 'package:machiscore/theme/app_theme.dart';
import 'package:machiscore/utils/map_link.dart';
import 'package:machiscore/utils/town_profile_text.dart';
import 'package:machiscore/utils/town_summary.dart';

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
Future<void> pumpLoadedApp(WidgetTester tester, {HomeTownStore? homeTownStore}) async {
  final repository = newTestRepository();
  await tester.runAsync(repository.load);
  await tester.pumpWidget(
    MachiscoreApp(
      repository: repository,
      // 既定でもメモリ実装にする。本物は SharedPreferences のプラグインを叩き、
      // flutter_test では解決せずロード中のまま止まってしまう。
      homeTownStore: homeTownStore ?? InMemoryHomeTownStore(),
    ),
  );
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
    // 分母は昼間人口。3桁区切りで表示する。
    expect(find.text('551,344人'), findsOneWidget);
    // カテゴリのカードはレーダーチャートの下にあり初期表示の外なので送る
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('全国'), findsWidgets);
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

    // 増減バッジはカテゴリカード内にあり、初期表示の外なので送る
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
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

  testWidgets('最長の町名でも文字3倍の結果画面が下まで崩れない', (tester) async {
    // 「さいたま市大宮区を地図で見る」が最長のボタン文言になる。
    // 既存の拡大テストは渋谷区かつ初期表示分だけなので、
    // 名前が長い町で、画面外の要素まで送って確かめる。
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    final longest = repository.municipalities.reduce(
      (a, b) => a.name.length >= b.name.length ? a : b,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ResultScreen(
            municipality: longest,
            categories: repository.categories,
          ),
        ),
      ),
    );
    await tester.pump();

    // 地図の節まで送って、そこでも崩れないことを見る
    await tester.scrollUntilVisible(find.text('この町の位置'), 300);
    expect(find.text('地図アプリで開く'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ListViewは画面外を組み立てないので、最後まで送りながら例外を拾う
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${longest.name} の$i回送った先で崩れた');
    }
  });

  testWidgets('文字を3倍にしてもスコアの説明画面が崩れない', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repository = newTestRepository();
    await tester.runAsync(repository.load);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: AboutScoreScreen(repository: repository),
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'スコアの説明画面の$i回送った先で崩れた');
    }
  });

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

  test('かな・カタカナ・ローマ字のどれでも検索できる', () async {
    final repository = await loadRepository();
    // 表記が違っても同じ町に当たること
    for (final query in ['渋谷区', 'しぶや', 'シブヤ', 'shibuya', 'ｼﾌﾞﾔ']) {
      final hits = repository.search(query);
      expect(
        hits.any((m) => m.code == '13113'),
        isTrue,
        reason: '「$query」で渋谷区に当たらない',
      );
    }
    // 促音・拗音を含む読みも通ること
    expect(
      repository.search('sapporoshichuuou').any((m) => m.code == '01101'),
      isTrue,
      reason: 'ローマ字で札幌市中央区に当たらない',
    );
    expect(
      repository.search('はままつしてんりゅう').any((m) => m.code == '22137'),
      isTrue,
      reason: 'かなで浜松市天竜区に当たらない',
    );
  });

  test('全市区町村に読み仮名がある', () async {
    final repository = await loadRepository();
    for (final municipality in repository.municipalities) {
      expect(municipality.kana, isNotEmpty, reason: '${municipality.name} に読みが無い');
      expect(municipality.romaji, isNotEmpty, reason: '${municipality.name} にローマ字が無い');
    }
  });

  testWidgets('結果画面から比較に追加できる', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), 'しぶや');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    // 結果画面に「くらべる」の導線がある。
    // 文字ボタンだとタイトルを圧迫するのでアイコンにしてある。
    expect(find.byTooltip('くらべる対象に追加'), findsOneWidget);
    await tester.tap(find.byTooltip('くらべる対象に追加'));
    await tester.pumpAndSettle();

    // 検索画面に戻り、選択済みになっている
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  test('県内順位が全国順位と矛盾しない', () async {
    final repository = await loadRepository();
    for (final municipality in repository.municipalities) {
      if (!municipality.ranked) continue;
      expect(municipality.prefectureRank, isNotNull);
      // 県内順位は全国順位を超えない（母集団が部分集合なので）
      for (final entry in municipality.categories.values) {
        if (!entry.hasRank || entry.prefectureRank == null) continue;
        expect(
          entry.prefectureRank!,
          lessThanOrEqualTo(entry.rank!),
          reason: '${municipality.name}: 県内順位が全国順位より下',
        );
        expect(entry.prefectureRank!, lessThanOrEqualTo(entry.prefectureTotal!));
      }
    }
  });

  test('似ている町は自分を含まず、対象外の町も入らない', () async {
    final repository = await loadRepository();
    final sapporo = repository.municipalities.firstWhere((m) => m.code == '01101');
    final similar = repository.similarTo(sapporo);

    expect(similar, hasLength(5));
    expect(similar.any((m) => m.code == sapporo.code), isFalse);
    expect(similar.every((m) => m.ranked), isTrue);
    // 政令市の中心区には似た性格の町が並ぶはず（総合点が極端に離れない）
    for (final m in similar) {
      expect((m.totalScore! - sapporo.totalScore!).abs(), lessThan(30));
    }
  });

  testWidgets('似ている町から次の町へ進める', (tester) async {
    await pumpLoadedApp(tester);

    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    // 似ている町の節は画面下部にあり ListView の遅延描画で未生成なので、
    // 先にスクロールしてから確かめる
    await tester.scrollUntilVisible(find.text('スコアの傾向が似ている町'), 300);
    expect(find.text('スコアの傾向が似ている町'), findsOneWidget);

    // 1件目をタップすると、その町の結果画面に進む
    final firstSimilar = find.descendant(
      of: find.byType(Card),
      matching: find.byType(ListTile),
    );
    final targetName = tester.widget<Text>(
      find.descendant(of: firstSimilar.first, matching: find.byType(Text)).first,
    ).data;
    await tester.tap(firstSimilar.first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, targetName!), findsOneWidget);
  });

  testWidgets('マイタウンを登録すると検索前の画面に出る', (tester) async {
    final store = InMemoryHomeTownStore();
    await pumpLoadedApp(tester, homeTownStore: store);

    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    // 星ボタンで登録
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();
    expect(await store.load(), '13113');

    // 検索画面に戻って検索語を消すと、マイタウンが出ている
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('マイタウン'), findsOneWidget);
    expect(find.text('渋谷区'), findsOneWidget);
  });

  testWidgets('結果画面にレーダーチャートが出る', (tester) async {
    await pumpLoadedApp(tester);
    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    expect(find.byType(ScoreRadarChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全国ランキングを開いてカテゴリを切り替えられる', (tester) async {
    await pumpLoadedApp(tester);

    await tester.tap(find.byIcon(Icons.leaderboard_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(RankingScreen), findsOneWidget);

    // 1行目の町名を拾う。leading の順位番号ではなく title を見る。
    String topTownName() {
      final tile = tester.widget<ListTile>(find.byType(ListTile).first);
      return (tile.title! as Text).data!;
    }

    final firstBefore = topTownName();

    // カテゴリを切り替えると並びが変わる
    await tester.tap(find.widgetWithText(ChoiceChip, '喫茶店'));
    await tester.pumpAndSettle();
    expect(topTownName(), isNot(firstBefore));
    expect(tester.takeException(), isNull);
  });

  test('ランキングは対象外の町を含まない', () async {
    final repository = await loadRepository();
    final ranked = repository.municipalities.where((m) => m.ranked).toList();
    // 対象外の33件は入らない
    expect(ranked.length, lessThan(repository.municipalities.length));
    expect(ranked.every((m) => m.totalScore != null), isTrue);
  });

  test('全市区町村で特徴文が作れる', () async {
    final repository = await loadRepository();
    final variety = <String>{};
    for (final municipality in repository.municipalities) {
      if (!municipality.ranked) continue;
      final summary = describeTown(municipality, repository.categories);
      expect(summary, isNotNull, reason: '${municipality.name} の特徴文が作れない');
      variety.add(summary!);
    }
    // 全部が同じ文言になっていないこと（判定が機能している証拠）
    expect(variety.length, greaterThan(10));
  });

  test('規模帯の順位が母数の中に収まっている', () async {
    final repository = await loadRepository();
    for (final municipality in repository.municipalities) {
      if (!municipality.ranked) continue;
      expect(municipality.sizeBand, isNotNull);
      expect(municipality.sizeBandRank, isNotNull);
      expect(municipality.sizeBandRank!, lessThanOrEqualTo(municipality.sizeBandTotal!));
      // 規模帯は全国より母数が小さいので、順位も全国以下になる
      expect(municipality.sizeBandTotal!, lessThan(repository.municipalities.length));
    }
  });

  testWidgets('結果画面に町の特徴と規模帯順位が出る', (tester) async {
    await pumpLoadedApp(tester);
    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('が多く、'), findsOneWidget);
    expect(find.textContaining('の中では'), findsOneWidget);
  });

  group('現在地から市区町村を割り出す', () {
    Placemark placemark({
      String admin = '',
      String locality = '',
      String subLocality = '',
      String subAdmin = '',
    }) =>
        Placemark(
          administrativeArea: admin,
          locality: locality,
          subLocality: subLocality,
          subAdministrativeArea: subAdmin,
        );

    test('政令市では市名ではなく区に当てる', () async {
      final repository = await loadRepository();
      // iOSは「札幌市」と「中央区」を別フィールドで返すことがある
      final match = CurrentLocationFinder.matchMunicipality(
        placemark(admin: '北海道', locality: '札幌市', subLocality: '中央区'),
        repository.municipalities,
      );
      expect(match?.code, '01101');
    });

    test('市区町村名がそのまま返る場合', () async {
      final repository = await loadRepository();
      final match = CurrentLocationFinder.matchMunicipality(
        placemark(admin: '東京都', locality: '渋谷区'),
        repository.municipalities,
      );
      expect(match?.code, '13113');
    });

    test('同名の町は都道府県で正しく絞り込む', () async {
      final repository = await loadRepository();
      // 池田町は4県にある。administrativeArea で区別できること。
      final gifu = CurrentLocationFinder.matchMunicipality(
        placemark(admin: '岐阜県', locality: '池田町'),
        repository.municipalities,
      );
      final hokkaido = CurrentLocationFinder.matchMunicipality(
        placemark(admin: '北海道', locality: '池田町'),
        repository.municipalities,
      );
      expect(gifu?.code, '21404');
      expect(hokkaido?.code, '01644');
    });

    test('該当しない住所では null を返す', () async {
      final repository = await loadRepository();
      final match = CurrentLocationFinder.matchMunicipality(
        placemark(admin: 'California', locality: 'San Francisco'),
        repository.municipalities,
      );
      expect(match, isNull);
    });
  });

  test('町の背景データがほぼ全件そろっている', () async {
    final repository = await loadRepository();
    final total = repository.municipalities.length;
    final withProfile = repository.municipalities
        .where((m) => m.populationChangeRate != null && m.elderlyRate != null)
        .length;
    // 浜松市の旧区など数件は欠けるが、99%以上は埋まっているはず
    expect(withProfile / total, greaterThan(0.99));
  });

  testWidgets('結果画面に人口増減と高齢化率が出る', (tester) async {
    await pumpLoadedApp(tester);
    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    expect(find.text('5年間の人口増減'), findsOneWidget);
    expect(find.text('65歳以上の割合'), findsOneWidget);
    expect(find.text('面積'), findsOneWidget);
  });

  testWidgets('共有カードが例外なく描画できる', (tester) async {
    // 共有画像は画面に出ないため、壊れていても気づけない。
    // 端末のテーマや文字サイズに依存しない版であることも含めて確かめる。
    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    final shibuya = repository.municipalities.firstWhere((m) => m.code == '13113');

    await tester.pumpWidget(
      MediaQuery(
        // 大きな文字設定でも版が崩れないこと
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          home: Center(
            child: ShareCard(municipality: shibuya, categories: repository.categories),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ScoreRadarChart), findsOneWidget);
    expect(find.text('渋谷区'), findsOneWidget);
  });

  test('出典表記がデータ側から供給される', () async {
    // アプリに固定文言を持たせると、データを足したとき表示だけ古くなる。
    final repository = await loadRepository();
    expect(repository.sourceNote, isNotEmpty);
    // 実際に使っている統計がすべて出典に含まれること
    for (final source in ['経済センサス', '国勢調査']) {
      expect(repository.sourceNote, contains(source));
    }
  });

  group('町の紹介文', () {
    test('ほぼ全件で生成でき、内容にばらつきがある', () async {
      final repository = await loadRepository();
      var empty = 0;
      final variety = <String>{};
      for (final municipality in repository.municipalities) {
        final paragraphs = TownProfileText.describe(municipality);
        if (paragraphs.isEmpty) empty++;
        variety.addAll(paragraphs);
      }
      // 背景データが欠ける数件を除き生成できること
      expect(empty, lessThan(20));
      // 全部同じ文言になっていないこと（判定が働いている証拠）
      expect(variety.length, greaterThan(50));
    });

    test('小さな町で昼夜間人口比率を過剰に語らない', () async {
      // 青ヶ島村は昼間205人・夜間169人。36人差で比率121%になるが、
      // これを「働く場としての性格が強い」と書くのは言い過ぎ。
      final repository = await loadRepository();
      final aogashima =
          repository.municipalities.firstWhere((m) => m.code == '13402');
      final text = TownProfileText.describe(aogashima).join();

      expect(text, isNot(contains('働く場としての性格')));
      expect(text, isNot(contains('通勤・通学で人が流入')));
    });

    test('大きな町では昼夜間人口比率をきちんと述べる', () async {
      final repository = await loadRepository();
      final chiyoda = repository.municipalities.firstWhere((m) => m.code == '13101');
      final text = TownProfileText.describe(chiyoda).join();

      expect(text, contains('働く場としての性格'));
    });

    test('人口が増えている町と減っている町を書き分ける', () async {
      final repository = await loadRepository();
      final growing = repository.municipalities.firstWhere((m) => m.code == '01101');
      final shrinking = repository.municipalities.firstWhere((m) => m.code == '29441');

      expect(TownProfileText.describe(growing).join(), contains('増えました'));
      expect(TownProfileText.describe(shrinking).join(), contains('減りました'));
    });
  });

  testWidgets('結果画面に町の紹介が出る', (tester) async {
    await pumpLoadedApp(tester);
    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '渋谷区').first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('この町について'), 300);
    expect(find.text('この町について'), findsOneWidget);
    expect(find.textContaining('昼間は夜間の'), findsOneWidget);
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
    // 夜間人口で割ると専門料理店の密度が全国1位になってしまうため昼間人口を分母にしている。
    final repository = await loadRepository();
    final chiyoda = repository.municipalities.firstWhere((m) => m.code == '13101');
    expect(chiyoda.dayNightRatio, greaterThan(1000));
    // 「スコアの見かた」画面で「400番台まで下がり」と具体的に書いている。
    // データを作り直して順位が動いたら、画面の文言も直す必要があるのでここで留める。
    expect(
      chiyoda.categories['762']!.rank,
      inInclusiveRange(400, 499),
      reason: 'about_score_screen.dart の「400番台」という記述と食い違っている',
    );
  });

  testWidgets('スコアバーが読み上げを二重にしない 検索一覧とランキング', (tester) async {
    await pumpLoadedApp(tester);
    await tester.enterText(find.byType(TextField), '渋谷区');
    await tester.pump();
    _expectBarsHidden(tester, '検索一覧', atLeast: 1);

    await tester.tap(find.byTooltip('全国ランキング'));
    await tester.pumpAndSettle();
    _expectBarsHidden(tester, '全国ランキング', atLeast: 1);
  });

  testWidgets('スコアバーが読み上げを二重にしない 結果画面とくらべる画面', (tester) async {
    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    final towns = [
      repository.municipalities.firstWhere((m) => m.code == '13113'),
      repository.municipalities.firstWhere((m) => m.code == '13101'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ResultScreen(
          municipality: towns.first,
          categories: repository.categories,
        ),
      ),
    );
    await tester.pump();
    _expectBarsHidden(tester, '結果画面', atLeast: 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: CompareScreen(
          municipalities: towns,
          categories: repository.categories,
        ),
      ),
    );
    await tester.pump();
    _expectBarsHidden(tester, 'くらべる画面', atLeast: 1);
  });

  test('全市区町村に地図の代表点がある', () async {
    final repository = await loadRepository();
    for (final municipality in repository.municipalities) {
      final lat = municipality.lat;
      final lon = municipality.lon;
      expect(lat, isNotNull, reason: '${municipality.fullName} に緯度がない');
      expect(lon, isNotNull, reason: '${municipality.fullName} に経度がない');
      // 日本の国土の範囲。取り違えた座標が混ざれば地図が別の国を指す
      expect(lat, inInclusiveRange(20.0, 46.0), reason: municipality.fullName);
      expect(lon, inInclusiveRange(122.0, 154.0), reason: municipality.fullName);
    }
  });

  test('代表点が県内の他の町と一致しない', () async {
    // 集計を取り違えて全部同じ点になっても、範囲チェックだけでは気づけない。
    final repository = await loadRepository();
    final seen = <String>{};
    for (final municipality in repository.municipalities) {
      final key = '${municipality.lat},${municipality.lon}';
      expect(seen.add(key), isTrue, reason: '${municipality.fullName} の座標が他と重複している');
    }
  });

  test('代表点が実際の位置に近い', () async {
    // 大字の中央値なので役場とは数km離れうるが、町を取り違えていれば桁が違う。
    const known = {
      '13113': ('渋谷区', 35.664, 139.698),
      '01101': ('札幌市中央区', 43.056, 141.341),
      '47201': ('那覇市', 26.212, 127.679),
      '13402': ('青ヶ島村', 32.457, 139.766),
      '13421': ('小笠原村', 27.094, 142.192),
    };
    final repository = await loadRepository();
    for (final entry in known.entries) {
      final (name, lat, lon) = entry.value;
      final m = repository.municipalities.firstWhere((x) => x.code == entry.key);
      // 緯度1度=約111km、経度1度=約91km（日本付近）で概算する
      final km = math.sqrt(
        math.pow((m.lat! - lat) * 111, 2) + math.pow((m.lon! - lon) * 91, 2),
      );
      expect(km, lessThan(60), reason: '$name の代表点が${km.toStringAsFixed(0)}kmずれている');
    }
  });

  test('地図の縮尺が町の広さに追随する', () async {
    final repository = await loadRepository();
    final shibuya = repository.municipalities.firstWhere((m) => m.code == '13113');
    final takayama = repository.municipalities.firstWhere((m) => m.name == '高山市');

    final zoomSmall = TownMapPreview.zoomForArea(shibuya.areaKm2);
    final zoomLarge = TownMapPreview.zoomForArea(takayama.areaKm2);
    // 広い町ほど引いて見せる（ズーム値が小さい）
    expect(zoomLarge, lessThan(zoomSmall));
    // 面積が無い町でも破綻せず既定値に落ちる
    expect(TownMapPreview.zoomForArea(null), inInclusiveRange(6.0, 13.0));
    expect(TownMapPreview.zoomForArea(0), inInclusiveRange(6.0, 13.0));
    for (final m in repository.municipalities) {
      expect(TownMapPreview.zoomForArea(m.areaKm2), inInclusiveRange(6.0, 13.0),
          reason: '${m.fullName} の縮尺が範囲外');
    }
  });

  testWidgets('結果画面に地図のプレビューが出る', (tester) async {
    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    final shibuya = repository.municipalities.firstWhere((m) => m.code == '13113');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ResultScreen(
          municipality: shibuya,
          categories: repository.categories,
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(find.text('この町の位置'), 200);
    expect(find.byType(TownMapPreview), findsOneWidget);
    expect(find.text('地図アプリで開く'), findsOneWidget);
  });

  testWidgets('レーダーチャートが読み上げ用の説明を持つ', (tester) async {
    // CustomPaintは画面読み上げから中身が見えない。ここが欠けると、
    // スコアの内訳という主要な情報が丸ごと届かなくなる。
    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    final shibuya =
        repository.municipalities.firstWhere((m) => m.code == '13113');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ScoreRadarChart(
            municipality: shibuya,
            categories: repository.categories,
          ),
        ),
      ),
    );
    await tester.pump();

    final semantics = tester.getSemantics(find.byType(ScoreRadarChart));
    expect(semantics.label, contains('レーダーチャート'));
    for (final category in repository.categories) {
      expect(
        semantics.label,
        contains(category.name),
        reason: '${category.name}が読み上げ文に含まれていない',
      );
    }
    expect(semantics.label, contains('点'));
  });

  testWidgets('スコアの説明画面に算出方法と出典が並ぶ', (tester) async {
    final repository = newTestRepository();
    await tester.runAsync(repository.load);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: AboutScoreScreen(repository: repository),
      ),
    );
    await tester.pump();

    expect(find.text('スコアの見かた'), findsOneWidget);
    for (final category in repository.categories) {
      expect(find.text(category.name), findsOneWidget);
    }
    // 対象外の基準は審査でも説明を求められうるので必ず載せる。
    // ListViewは画面外を組み立てないので、確かめる前にスクロールして出す
    await tester.scrollUntilVisible(find.textContaining('1,000人'), 200);
    // 出典はデータ側から来るので、文言をベタ書きせず実データで確かめる
    await tester.scrollUntilVisible(
      find.textContaining(repository.sourceNote),
      200,
    );
  });

  testWidgets('結果画面から地図アプリに町の名前を渡せる', (tester) async {
    final repository = newTestRepository();
    await tester.runAsync(repository.load);
    final fuchu = repository.municipalities.firstWhere((m) => m.code == '13206');
    final mapLink = _RecordingMapLink();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ResultScreen(
          municipality: fuchu,
          categories: repository.categories,
          mapLink: mapLink,
        ),
      ),
    );
    await tester.pump();

    final button = find.text('地図アプリで開く');
    // scrollUntilVisible はキャッシュ領域に組み立て済みなら「見つけた」と
    // 判定するため、画面外のまま止まることがある。ensureVisible で押せる位置まで出す。
    await tester.scrollUntilVisible(button, 200);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();

    // 府中市は東京都と広島県にある。都道府県込みで渡さないと取り違える
    expect(mapLink.opened?.fullName, '東京都府中市');
  });
}

/// スコアバーが読み上げから隠されているか確かめる。
///
/// LinearProgressIndicator は value を渡すと「76%」という読み上げ値を自分で作る。
/// 隣には「76点」が並んでいるので、隠さないと同じ数字が二度読まれる。
/// 画面ごとに手で確認すると漏れるため、バーを見つけて祖先を辿る形で機械的に見る。
void _expectBarsHidden(WidgetTester tester, String where, {required int atLeast}) {
  final bars = find.byType(LinearProgressIndicator);
  final found = tester.widgetList(bars).length;
  // 0件のまま素通りすると、バーが消えた日に気づけない
  expect(found, greaterThanOrEqualTo(atLeast), reason: '$where にスコアバーが見当たらない');

  for (var i = 0; i < found; i++) {
    expect(
      find.ancestor(of: bars.at(i), matching: find.byType(ExcludeSemantics)),
      findsAtLeastNWidgets(1),
      reason: '$where の$i番目のスコアバーが読み上げに露出している。'
          'ExcludeSemantics で隠すこと',
    );
  }
}

/// 地図アプリを起動せず、渡された町だけ覚えるテスト用の差し替え。
class _RecordingMapLink implements MapLink {
  Municipality? opened;

  @override
  Future<bool> open(Municipality municipality) async {
    opened = municipality;
    return true;
  }
}
