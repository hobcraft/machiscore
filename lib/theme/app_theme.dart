import 'package:flutter/material.dart';

/// アプリの配色を1か所にまとめたパレット。
///
/// 色の「役割」で持つのが要点。ウィジェット側は具体的な色ではなく
/// 役割（textPrimary、scoreRamp…）を参照するので、明暗の切り替えは
/// このクラスのインスタンスを差し替えるだけで済む。
///
/// ThemeExtension にしてあるので `context.palette` で取り出せ、
/// 端末のダークモード設定に自動で追従する。
/// 他のアプリに持っていく場合は [light]/[dark] の値だけ差し替えればよい。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  // サーフェス
  final Color pageBackground;
  final Color cardBackground;
  final Color border;

  /// スコアバーの下地
  final Color track;

  // インク
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// ブランド色。スコアランプと同じ色相から採り、画面に出る色相を1つに絞る。
  final Color brand;

  /// 増減。増加だけ色を立て、減少は中立色で沈める。
  /// 緑と赤茶の2色にすると色覚特性で区別できない（CVD ΔE 2.1）ため、
  /// 彩度の有無で差をつけている。矢印と符号も併記するので色だけに頼らない。
  final Color increase;
  final Color decrease;

  /// スコアの高さを濃さ（暗所では明るさ）で表す単色ランプ。低→高の3段。
  ///
  /// 3段なのは検証の結果。淡すぎる段は下地とのコントラストが取れず
  /// バーの端が見えなくなり、逆に濃い側へ寄せて5段にすると段どうしの
  /// 明度差が詰まって判別できなくなる。両立するのがこの3段で、
  /// いずれも下地に対し3:1以上、隣接する段の明度差は0.06以上ある。
  /// 点数の細かい違いはバーの長さが表すので、色は3段で足りる。
  final List<Color> scoreRamp;

  const AppPalette({
    required this.pageBackground,
    required this.cardBackground,
    required this.border,
    required this.track,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brand,
    required this.increase,
    required this.decrease,
    required this.scoreRamp,
  });

  /// 点数に対応するバーの色。
  Color scoreColor(int score) {
    if (score >= 67) return scoreRamp[2];
    if (score >= 34) return scoreRamp[1];
    return scoreRamp[0];
  }

  static const light = AppPalette(
    pageBackground: Color(0xFFFAFAF8),
    cardBackground: Color(0xFFFFFFFF),
    border: Color(0xFFE2E0DA),
    track: Color(0xFFEDEBE5),
    textPrimary: Color(0xFF1C1B19),
    textSecondary: Color(0xFF6B6A66),
    textMuted: Color(0xFF706F6B),
    brand: Color(0xFF1C5CAB),
    increase: Color(0xFF1F6F43),
    decrease: Color(0xFF6B6A66),
    scoreRamp: [Color(0xFF3987E5), Color(0xFF256ABF), Color(0xFF104281)],
  );

  /// 暗所では明暗が反転する。ランプも「高いほど明るい」向きに取り直す。
  /// 明るい色をそのまま暗所に流用すると眩しく、暗い色は沈んで見えないため、
  /// 単純な反転ではなく同じ色相の別の段を選び直している。
  static const dark = AppPalette(
    pageBackground: Color(0xFF131312),
    cardBackground: Color(0xFF1C1C1A),
    border: Color(0xFF34332F),
    track: Color(0xFF2E2D2A),
    textPrimary: Color(0xFFF5F4F1),
    textSecondary: Color(0xFFB5B3AC),
    textMuted: Color(0xFF95938C),
    brand: Color(0xFF5598E7),
    increase: Color(0xFF4FA97A),
    decrease: Color(0xFFB5B3AC),
    scoreRamp: [Color(0xFF2A78D6), Color(0xFF5598E7), Color(0xFF86B6EF)],
  );

  @override
  AppPalette copyWith({
    Color? pageBackground,
    Color? cardBackground,
    Color? border,
    Color? track,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? brand,
    Color? increase,
    Color? decrease,
    List<Color>? scoreRamp,
  }) {
    return AppPalette(
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      border: border ?? this.border,
      track: track ?? this.track,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      brand: brand ?? this.brand,
      increase: increase ?? this.increase,
      decrease: decrease ?? this.decrease,
      scoreRamp: scoreRamp ?? this.scoreRamp,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      border: Color.lerp(border, other.border, t)!,
      track: Color.lerp(track, other.track, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      increase: Color.lerp(increase, other.increase, t)!,
      decrease: Color.lerp(decrease, other.decrease, t)!,
      scoreRamp: [
        for (var i = 0; i < scoreRamp.length; i++)
          Color.lerp(scoreRamp[i], other.scoreRamp[i], t)!,
      ],
    );
  }
}

/// `context.palette` で配色を取り出す。
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final palette = isDark ? AppPalette.dark : AppPalette.light;

  // container 系まで明示する。既定のままだとブランド色がベタで解決され、
  // Chip や選択行が濃い単色で塗りつぶされてしまう。
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.brand,
    onPrimary: isDark ? const Color(0xFF0B1B2E) : Colors.white,
    primaryContainer: isDark ? const Color(0xFF1B2A3D) : const Color(0xFFE8EFF8),
    onPrimaryContainer: isDark ? const Color(0xFFCDE2FB) : const Color(0xFF104281),
    secondary: palette.brand,
    onSecondary: isDark ? const Color(0xFF0B1B2E) : Colors.white,
    secondaryContainer: isDark ? const Color(0xFF272622) : const Color(0xFFF3F1EC),
    onSecondaryContainer: palette.textPrimary,
    error: isDark ? const Color(0xFFE68585) : const Color(0xFFA32D2D),
    onError: isDark ? const Color(0xFF2A0F0F) : Colors.white,
    surface: palette.cardBackground,
    onSurface: palette.textPrimary,
    surfaceContainerHighest: isDark ? const Color(0xFF272622) : const Color(0xFFF3F1EC),
    outline: palette.border,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.pageBackground,
    extensions: [palette],
    // Material3 のサーフェス着色を切る。これを残すとカードが色かぶりする。
    appBarTheme: AppBarTheme(
      backgroundColor: palette.pageBackground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: palette.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border, width: 0.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: palette.border, thickness: 0.5),
    listTileTheme: ListTileThemeData(
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: palette.textPrimary,
    ),
  );
}
