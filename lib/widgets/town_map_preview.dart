import 'dart:math' as math;

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../models/municipality.dart';

/// 町の位置を示す小さな地図。
///
/// 統計だけ見せられても位置が分からない町は多い。以前は地図アプリに飛ばして
/// いたが、アプリから出てしまうため、その場で見えるプレビューにした。
/// タップすると地図アプリで開いて、経路や周辺の店まで辿れる。
///
/// MapKit を使うのでAPIキーも課金も要らない。ただしタイルは通信で取るため、
/// 圏外では地図だけ出ない。統計は同梱なので他の表示には影響しない。
class TownMapPreview extends StatelessWidget {
  final Municipality municipality;

  /// 地図をタップしたときの動作。地図アプリで開くのに使う。
  final VoidCallback? onTap;

  final double height;

  const TownMapPreview({
    super.key,
    required this.municipality,
    this.onTap,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final lat = municipality.lat;
    final lon = municipality.lon;
    // 座標を持たない町は無いはずだが（バッチ側で止めている）、
    // 万一欠けてもこの節だけ消えるようにして画面全体は守る。
    if (lat == null || lon == null) return const SizedBox.shrink();

    final center = LatLng(lat, lon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              // 地図そのものは読み上げても意味をなさない。
              // 位置は下のラベルとボタンの文言で伝える。
              child: ExcludeSemantics(
                child: AppleMap(
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: zoomForArea(municipality.areaKm2),
                  ),
                  annotations: {
                    Annotation(
                      annotationId: AnnotationId(municipality.code),
                      position: center,
                    ),
                  },
                  // プレビューなので操作させない。触りたい人はタップで
                  // 地図アプリに移ってもらう。地図の中で指が止まると、
                  // 縦スクロールが効かなくなって画面が動かせなくなる。
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  pitchGesturesEnabled: false,
                  compassEnabled: false,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                ),
              ),
            ),
            // 地図の上に透明な層を重ねてタップを受ける。
            // AppleMap 自身の onTap は座標を返すだけで、押した感じも出ない。
            if (onTap != null)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    child: Semantics(
                      button: true,
                      label: '${municipality.fullName}の位置。'
                          'ひらくと地図アプリで表示します',
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 町の広さに合わせた地図の縮尺。
  ///
  /// 固定の縮尺だと、渋谷区（15km²）はスカスカに、
  /// 高山市（2178km²）は町全体が入りきらない。面積から逆算して、
  /// だいたい町が収まる高さに合わせる。
  @visibleForTesting
  static double zoomForArea(double? areaKm2) {
    const fallback = 10.0;
    if (areaKm2 == null || areaKm2 <= 0) return fallback;

    // 正方形とみなした一辺(km)。この幅が画面に収まる縮尺を求める。
    final sideKm = math.sqrt(areaKm2);
    // ズーム9でおよそ横400km相当。倍率が2倍になるごとに1段上がる。
    final zoom = 9 + math.log(400 / (sideKm * 1.6)) / math.ln2;
    return zoom.clamp(6.0, 13.0);
  }
}
