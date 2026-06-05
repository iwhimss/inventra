import 'package:flutter/material.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/widgets/app_notification.dart';
import 'package:inventra_app/core/services/cart_transfer_service.dart'; // import global navigatorKey

class NotificationService {
  static void showSuccess(String message) {
    SoundService.playSuccess();
    _showOverlay(message, NotificationType.success);
  }

  static void showError(String message) {
    SoundService.playError();
    _showOverlay(message, NotificationType.error);
  }

  static void showWarning(String message) {
    SoundService.playNotification();
    _showOverlay(message, NotificationType.warning);
  }

  static void showInfo(String message) {
    SoundService.playNotification();
    _showOverlay(message, NotificationType.info);
  }

  static void _showOverlay(String message, NotificationType type) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final overlayState = Overlay.of(context);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => AppNotificationWidget(
        message: message,
        type: type,
        onDismissed: () => overlayEntry.remove(),
      ),
    );

    overlayState.insert(overlayEntry);
  }
}

enum NotificationType { success, error, warning, info }
