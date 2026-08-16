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
  ///
  /// 返り値は「利用者に見せるべき失敗があったか」を表す。開けたときも、
  /// 利用者が自分でキャンセルしたときも true を返す。
  ///
  /// Googleマップのような他社アプリのスキームを叩くと、iOSが
  /// 「"マチスコア"が"Google Maps"を開こうとしています」という確認を挟む。
  /// ここでキャンセルされた場合も起動に失敗した場合も launchUrl は同じく
  /// false を返し、区別する手段が無い。エラー扱いにすると、
  /// 自分でキャンセルしただけの人に「開けませんでした」と出てしまう。
  /// 押し間違いなら本人がもう一度押せるので、黙って何もしないほうが良い。
  Future<bool> open(Municipality municipality) async {
    final query = Uri.encodeComponent(municipality.fullName);

    // 端末側の事情で起動に失敗することがある。ここで例外にすると
    // ボタンを押しただけでクラッシュするので、false にして呼び出し元に返す。
    try {
      // Googleマップアプリの独自スキーム。Info.plistに登録が必要
      final googleMaps = Uri.parse('comgooglemaps://?q=$query');
      if (await canLaunchUrl(googleMaps)) {
        // 起動できてもキャンセルされても、ここで打ち切る。
        // 失敗と決めつけて標準マップを開くと、キャンセルを無視することになる。
        await launchUrl(googleMaps);
        return true;
      }

      // iOSには必ず入っている標準マップ。こちらは確認が挟まらないので、
      // false が返れば本当に開けなかったと判断してよい。
      final appleMaps = Uri.parse('https://maps.apple.com/?q=$query');
      return await launchUrl(appleMaps, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
