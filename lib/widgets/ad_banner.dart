import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_config.dart';
import '../theme/app_theme.dart';

/// 画面下部に固定するバナー広告。
///
/// 画面ごとに同じ部品を複製しないこと。過去に進捗バーを4画面へコピーした
/// 結果、読み上げ対応が2画面だけ漏れた。広告枠もここ1つに集約する。
///
/// 使う側は `Scaffold` の `bottomNavigationBar` に置く。本文の末尾に
/// 混ぜると、スクロールしてきた指が広告に当たって誤タップになり、
/// AdMobのポリシー違反として扱われるおそれがある。
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;

  /// 端末幅に合わせた広告の寸法。読み込み前に高さを確保するために先に取る。
  AnchoredAdaptiveBannerAdSize? _size;
  bool _loaded = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 幅の取得に MediaQuery が要るので initState では早すぎる。
    // 画面回転などで複数回呼ばれるため、一度だけ走らせる。
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final width = MediaQuery.sizeOf(context).width.truncate();
    // 320x50の固定サイズは使わない。端末幅に合わせた高さで要求すると
    // 視認性が上がる。null が返る端末では広告を出さない。
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;

    // 読み込み完了を待たずに高さを確保する。あとから枠が現れると
    // 本文が押し上げられ、読んでいた位置がずれるため。
    setState(() => _size = size);

    final ad = BannerAd(
      size: size,
      adUnitId: AdConfig.bannerUnitId,
      // 非パーソナライズ広告のみ。追跡しない方針なのでATTも出さない。
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // 圏外などで読み込めなかったときに空の帯を残すと、
          // ただの死んだ余白になる。枠ごと畳む。
          if (mounted) {
            setState(() {
              _ad = null;
              _size = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    if (size == null) return const SizedBox.shrink();

    final ad = _ad;
    return SafeArea(
      // 左右と上には効かせない。下端だけ、ホームインジケータに
      // 潜り込んで見切れるのを防ぐ。
      top: false,
      left: false,
      right: false,
      child: SizedBox(
        width: size.width.toDouble(),
        height: size.height.toDouble(),
        // 広告は装飾ではないが、読み上げても意味をなさない。
        // 中身はSDKが描くので、こちらからは説明を付けられない。
        child: ExcludeSemantics(
          child: _loaded && ad != null
              ? AdWidget(ad: ad)
              : ColoredBox(color: context.palette.pageBackground),
        ),
      ),
    );
  }
}
