/// Tam sayı değerleri "1" gibi, ondalıklı değerleri "0.5" gibi gösterir.
String formatQty(num value) {
  final d = value.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toString();
}
