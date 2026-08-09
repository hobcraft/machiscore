/// 3桁ごとにカンマを入れる（244067 -> 244,067）。
/// 桁区切りのためだけに intl を入れるのは重いので、必要になるまでは自前で持つ。
String withThousandsSeparator(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
