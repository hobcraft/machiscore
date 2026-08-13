import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/municipality.dart';

/// 現在地の特定に失敗した理由。画面側で出し分けるために型で持つ。
enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  notFound,
  failed,
}

sealed class LocationResult {
  const LocationResult();
}

class LocationFound extends LocationResult {
  final Municipality municipality;
  const LocationFound(this.municipality);
}

class LocationError extends LocationResult {
  final LocationFailure failure;
  const LocationError(this.failure);
}

/// 端末の位置から市区町村を割り出す。
///
/// 座標→住所の変換はOSの逆ジオコーディングに任せる（オフラインの地理データを
/// 同梱せずに済み、サーバーも要らない）。返ってくる住所文字列と同梱データの
/// 市区町村名を突き合わせるのが要で、表記が揺れるため段階的に照合する。
class CurrentLocationFinder {
  /// テストから差し替えるための注入口。
  final Future<Position> Function()? getPosition;
  final Future<List<Placemark>> Function(double, double)? getPlacemarks;

  const CurrentLocationFinder({this.getPosition, this.getPlacemarks});

  Future<LocationResult> find(List<Municipality> municipalities) async {
    try {
      if (getPosition == null) {
        if (!await Geolocator.isLocationServiceEnabled()) {
          return const LocationError(LocationFailure.serviceDisabled);
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          return const LocationError(LocationFailure.permissionDeniedForever);
        }
        if (permission == LocationPermission.denied) {
          return const LocationError(LocationFailure.permissionDenied);
        }
      }

      final position = await (getPosition?.call() ??
          Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          ));

      // 住所を日本語で受け取る。geocoding 4系ではロケールを個別に設定する。
      if (getPlacemarks == null) await setLocaleIdentifier('ja_JP');
      final placemarks = await (getPlacemarks?.call(position.latitude, position.longitude) ??
          placemarkFromCoordinates(position.latitude, position.longitude));
      if (placemarks.isEmpty) return const LocationError(LocationFailure.notFound);

      final match = matchMunicipality(placemarks.first, municipalities);
      return match == null
          ? const LocationError(LocationFailure.notFound)
          : LocationFound(match);
    } catch (_) {
      return const LocationError(LocationFailure.failed);
    }
  }

  /// 逆ジオコーディングの結果を同梱データの市区町村に対応づける。
  ///
  /// iOSは `locality`に市区町村、`administrativeArea`に都道府県、
  /// `subAdministrativeArea`に郡や政令市名を返すが、政令市では
  /// locality が「札幌市」で区が subLocality に来るなど揺れがある。
  /// 都道府県で絞ったうえで、候補文字列との一致を長い名前から順に見る。
  static Municipality? matchMunicipality(
    Placemark placemark,
    List<Municipality> municipalities,
  ) {
    final prefecture = placemark.administrativeArea ?? '';
    final locality = placemark.locality ?? '';
    final subLocality = placemark.subLocality ?? '';
    final subAdmin = placemark.subAdministrativeArea ?? '';

    final parts = [subLocality, locality, subAdmin].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    // 「札幌市」と「中央区」が別フィールドで返ることがある。
    // どちらが市でどちらが区かは端末やOSで揺れるので、両方の並びを試す。
    final joined = <String>{
      '$locality$subLocality',
      '$subLocality$locality',
      '$subAdmin$locality',
      '$locality$subAdmin',
      parts.join(),
    }.where((s) => s.isNotEmpty).toList();

    final inPrefecture = prefecture.isEmpty
        ? municipalities
        : municipalities.where((m) => m.prefecture == prefecture).toList();
    final pool = inPrefecture.isEmpty ? municipalities : inPrefecture;

    // 政令市の区（「札幌市中央区」）を市（「札幌市」）より先に当てたいので長い順に見る
    final sorted = [...pool]..sort((a, b) => b.name.length.compareTo(a.name.length));

    for (final municipality in sorted) {
      if (joined.any((s) => s.contains(municipality.name))) return municipality;
    }
    for (final municipality in sorted) {
      if (parts.contains(municipality.name)) return municipality;
    }
    return null;
  }
}
