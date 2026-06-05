import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/theme/theme_provider.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'dart:io';

class CustomTitleBar extends ConsumerWidget {
  final String title;

  const CustomTitleBar({super.key, this.title = "INVENTRA"});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch theme to rebuild on toggle
    ref.watch(themeProvider);

    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return const SizedBox.shrink();
    }
    
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.panelBackground.withOpacity(0.95),
            border: Border(bottom: BorderSide(color: AppTheme.borderBright, width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onPanStart: (details) => windowManager.startDragging(),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.only(left: 16),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Image.asset('assets/icons/app_icon.png', width: 14, height: 14),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _NavButton(
                icon: Icons.minimize,
                onTap: () => windowManager.minimize(),
                hoverColor: AppTheme.textMuted.withOpacity(0.15),
              ),
              _NavButton(
                icon: Icons.crop_square,
                onTap: () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
                hoverColor: AppTheme.textMuted.withOpacity(0.15),
              ),
              _NavButton(
                icon: Icons.close,
                onTap: () => windowManager.close(),
                hoverColor: AppTheme.dangerAccent.withOpacity(0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color hoverColor;

  const _NavButton({required this.icon, required this.onTap, required this.hoverColor});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Container(
          width: 46,
          height: 38,
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: AppTheme.textMuted),
        ),
      ),
    );
  }
}
