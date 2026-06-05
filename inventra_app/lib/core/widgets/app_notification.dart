import 'dart:async';
import 'package:flutter/material.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/services/notification_service.dart';

class AppNotificationWidget extends StatefulWidget {
  final String message;
  final NotificationType type;
  final VoidCallback onDismissed;

  const AppNotificationWidget({
    super.key,
    required this.message,
    required this.type,
    required this.onDismissed,
  });

  @override
  AppNotificationWidgetState createState() => AppNotificationWidgetState();
}

class AppNotificationWidgetState extends State<AppNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnimation = Tween<double>(begin: -100, end: 16).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    if (mounted) {
      _controller.reverse().then((_) {
        widget.onDismissed();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color accentColor;
    IconData icon;

    switch (widget.type) {
      case NotificationType.success:
        bgColor = AppTheme.successAccent.withOpacity(0.1);
        accentColor = AppTheme.successAccent;
        icon = Icons.check_circle_outline;
        break;
      case NotificationType.error:
        bgColor = AppTheme.dangerAccent.withOpacity(0.1);
        accentColor = AppTheme.dangerAccent;
        icon = Icons.error_outline;
        break;
      case NotificationType.warning:
        bgColor = AppTheme.warningAccent.withOpacity(0.1);
        accentColor = AppTheme.warningAccent;
        icon = Icons.warning_amber_rounded;
        break;
      case NotificationType.info:
        bgColor = AppTheme.infoAccent.withOpacity(0.1);
        accentColor = AppTheme.infoAccent;
        icon = Icons.info_outline;
        break;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: _slideAnimation.value,
          left: 16,
          right: 16,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.panelBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withOpacity(0.5)),
                        boxShadow: [
                            const BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 10),
                            BoxShadow(color: accentColor.withOpacity(0.2), offset: const Offset(0, 0), blurRadius: 20, spreadRadius: -5),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(width: 4, color: accentColor),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                                        child: Icon(icon, color: accentColor, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        widget.message,
                                        style: TextStyle(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close, color: AppTheme.textMuted, size: 20),
                                      onPressed: _dismiss,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
