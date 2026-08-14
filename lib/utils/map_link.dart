import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/municipality.dart';

/// 町の位置を地図アプリで開く。
///
/// アプリ内に地図を埋め込むと、通信と地図APIの契約が必要になり、
/// 「データを内蔵していて通信しない」という作りが崩れる。
/// 位置を確かめたいだけなら、端末の地図アプリに渡すのが確実で軽い。
///
/// 座標は持っていないが、「東京都府中市」のように都道府県から
/// 書いた名前で引けば、同名の町（府中市は東京都と広島県にある）も取り違えない。
class MapLink {
  const MapLink();

  /// Googleマップ（入っていれば）を優先し、無ければiOS標準のマップを開く。
  /// 返り値は開けたかどうか。
  Future<bool> open(Municipality municipality) async {
    final query = Uri.encodeComponent(municipality.fullName);

    // 端末側の事情で起動に失敗することがある。ここで例外にすると
    // ボタンを押しただけでクラッシュするので、false にして呼び出し元に返す。
    try {
      // Googleマップアプリの独自スキーム。Info.plistに登録が必要
      final googleMaps = Uri.parse('comgooglemaps://?q=$query');
      if (await canLaunchUrl(googleMaps)) {
        return await launchUrl(googleMaps);
      }

      // iOSには必ず入っている標準マップ
      final appleMaps = Uri.parse('https://maps.apple.com/?q=$query');
      return await launchUrl(appleMaps, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
