/// 検索の表記ゆれを吸収する正規化。
///
/// 検索語と照合先の両方に同じ関数を通すのが要点。片方だけ正規化すると、
/// たとえば「青ヶ島村」の「ヶ」がひらがな「ゖ」に変換されて漢字表記で
/// 引けなくなる、といった取りこぼしが起きる。
String normalizeForSearch(String input) {
  // 半角カナ(ｦ..ﾝ)を全角カタカナに直す表。濁点・半濁点は次の文字として届くので
  // 直前の文字に合成する。
  const halfWidthKana = 'ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ';
  const fullWidthKana = 'ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

  final buffer = StringBuffer();
  for (final rune in input.trim().runes) {
    var code = rune;

    // 濁点・半濁点は直前のかなに合成する（ｼﾌﾞﾔ -> しぶや）
    if (code == 0xFF9E || code == 0xFF9F) {
      final text = buffer.toString();
      if (text.isNotEmpty) {
        final last = text.codeUnitAt(text.length - 1);
        buffer.clear();
        buffer
          ..write(text.substring(0, text.length - 1))
          ..writeCharCode(last + (code == 0xFF9E ? 1 : 2));
      }
      continue;
    }

    final halfIndex = halfWidthKana.indexOf(String.fromCharCode(code));
    if (halfIndex >= 0) code = fullWidthKana.codeUnitAt(halfIndex);

    // カタカナ(ァ..ヶ) -> ひらがな
    if (code >= 0x30A1 && code <= 0x30F6) code -= 0x60;
    // 全角英数字 -> 半角
    if (code >= 0xFF01 && code <= 0xFF5E) code -= 0xFEE0;

    buffer.writeCharCode(code);
  }
  return buffer.toString().toLowerCase();
}
