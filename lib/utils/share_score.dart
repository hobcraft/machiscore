import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/municipality.dart';
import '../theme/app_theme.dart';
import '../widgets/share_card.dart';

/// 共有カードを画像にして共有シートに渡す。
///
/// 画面をそのまま撮るのではなく [ShareCard] を画面外で描画して切り出す。
/// スクロール位置や端末のテーマに左右されず、常に同じ絵になる。
Future<void> shareMunicipality(
  BuildContext context, {
  required Municipality municipality,
  required List<CategoryInfo> categories,
}) async {
  final bytes = await _renderShareCard(
    municipality: municipality,
    categories: categories,
  );
  if (bytes == null) return;

  // 共有先によってはパスを要求するので実ファイルに書き出す。
  // 共有シートを閉じたあとに消し、一時領域に溜め続けないようにする。
  final directory = await getTemporaryDirectory();
  final path = '${directory.path}/machiscore_${municipality.code}.png';
  final file = XFile.fromData(
    bytes,
    mimeType: 'image/png',
    name: 'machiscore_${municipality.code}.png',
  );
  await file.saveTo(path);

  final score = municipality.totalScore;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'image/png')],
        text: score == null
            ? '${municipality.prefecture}${municipality.name}のマチスコア'
            : '${municipality.prefecture}${municipality.name}のマチスコアは$score点でした',
      ),
    );
  } finally {
    final written = File(path);
    if (written.existsSync()) await written.delete();
  }
}

/// ウィジェットツリーに載せずに [ShareCard] を描画してPNGにする。
Future<Uint8List?> _renderShareCard({
  required Municipality municipality,
  required List<CategoryInfo> categories,
}) async {
  const side = ShareCard.side;
  // SNSで縮小されても粗くならないよう3倍で書き出す
  const pixelRatio = 3.0;

  final boundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;

  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.center, child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: const BoxConstraints.tightFor(width: side, height: side),
      devicePixelRatio: pixelRatio,
    ),
  );

  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  final buildOwner = BuildOwner(focusManager: FocusManager());
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        // 端末の文字サイズ設定に引きずられると版が崩れるので等倍に固定する
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Theme(
          data: buildAppTheme(Brightness.light),
          child: ShareCard(municipality: municipality, categories: categories),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner
    ..buildScope(element)
    ..finalizeTree();
  pipelineOwner
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
