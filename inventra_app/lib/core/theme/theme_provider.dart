import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/database/database_helper.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final results = await db.query('settings', where: "key = ?", whereArgs: ['dark_mode']);
      if (results.isNotEmpty && results.first['value'] == 'true') {
        state = ThemeMode.dark;
        AppTheme.setDarkMode(true);
      }
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    final isDark = state == ThemeMode.light;
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    AppTheme.setDarkMode(isDark);
    try {
      final db = await DatabaseHelper.instance.globalDb;
      await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['dark_mode', isDark.toString()]);
    } catch (_) {}
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) => ThemeNotifier());
