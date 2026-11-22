import 'package:flutter/material.dart';

/// The desktop system's colours (DTSIMS2 Modules/Theme.vb), so the phone looks like the same system.
class Brand {
  static const maroon = Color(0xFF800000); // Theme.Maroon (128, 0, 0)
  static const maroonDark = Color(0xFF600000); // Theme.MaroonDark (96, 0, 0)
  static const maroonLight = Color(0xFF9E1A1A); // Theme.MaroonLight (158, 26, 26)
  static const maroonTint = Color(0xFFFCF2F2); // Theme.MaroonTint (252, 242, 242)
  static const ink = Color(0xFF181C20); // Theme.TextDark
  static const muted = Color(0xFF586068); // Theme.TextMuted
  static const border = Color(0xFFDADADA); // Theme.BorderColor
  static const alert = Color(0xFFC81E1E); // Theme.AlertRed
  static const alertBack = Color(0xFFFFF0F0); // Theme.AlertBack
  static const green = Color(0xFF16823C); // the "Allowed" / profit green
  static const onMaroonSoft = Color(0xFFEBCDCD); // the subtitle colour on the maroon login panel
  static const background = Color(0xFFF7F7F8);

  static const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// "Monday, November 23, 2026", like the desktop's home screen.
  static String longDate(DateTime d) => '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';

  /// "Superadmin", "Admin", "Cashier".
  static String roleText(String? role) {
    final r = (role ?? '').trim();
    if (r.isEmpty) return '';
    return r[0].toUpperCase() + r.substring(1).toLowerCase();
  }
}

/// The soft white circles of the desktop's maroon login panel.
class BrandCircles extends CustomPainter {
  const BrandCircles();

  @override
  void paint(Canvas canvas, Size size) {
    final big = Paint()..color = Colors.white.withAlpha(28);
    final small = Paint()..color = Colors.white.withAlpha(20);
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 1.02), size.height * 0.62, big);
    canvas.drawCircle(Offset(size.width * 0.92, -size.height * 0.05), size.height * 0.42, small);
  }

  @override
  bool shouldRepaint(covariant BrandCircles oldDelegate) => false;
}
