import 'package:flutter/material.dart';

extension ResponsiveContext on BuildContext {
  double get screenW => MediaQuery.of(this).size.width;
  double get screenH => MediaQuery.of(this).size.height;

  /// Ekran genişliğinin oransal değeri (ör: sw(0.9) → ekranın %90'ı)
  double sw(double factor) => screenW * factor;

  /// Ekran yüksekliğinin oransal değeri
  double sh(double factor) => screenH * factor;

  /// Küçük ekran: genişlik < 360px
  bool get isSmallScreen => screenW < 360;

  /// Geniş ekran (tablet/masaüstü): genişlik >= 600px
  bool get isWideScreen => screenW >= 600;

  /// Dialog için güvenli maksimum genişlik:
  /// Verilen sabit değer ile ekranın %90'ı arasındaki küçük olanı döner.
  double dialogWidth(double maxWidth) {
    final limit = screenW * 0.90;
    return maxWidth < limit ? maxWidth : limit;
  }
}
