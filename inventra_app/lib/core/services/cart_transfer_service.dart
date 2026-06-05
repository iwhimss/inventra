import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/features/pos/providers/cart_provider.dart';
import '../network/websocket_service.dart';

/// Global navigation key used to show dialogs from anywhere in the app.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global service that polls for incoming cart transfer requests
/// and shows approval dialogs regardless of current screen.
class CartTransferService {
  static final CartTransferService instance = CartTransferService._();
  CartTransferService._();

  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  Timer? _pollTimer;
  WidgetRef? _ref;
  bool _isShowingDialog = false;
  String? _currentTransferId;

  void start(WidgetRef ref) {
    _ref = ref;
    
    // Önceki subscription varsa iptal et ve yeniden başlat (WS yenilenmiş olabilir)
    _wsSubscription?.cancel();
    _wsSubscription = null;

    final wsService = ref.read(webSocketProvider);
    _wsSubscription = wsService.stream.listen((event) {
      if (event['type'] == 'ws_reconnected') {
        _checkPendingTransfers();
        return;
      }
      if (event['type'] == 'cart_transfer_response') {
        final payload = event['payload'] as Map<String, dynamic>?;
        final transferId = payload?['transfer_id'] as String?;
        final status = payload?['status'] as String?;
        if (transferId != null && transferId == _currentTransferId &&
            (status == 'rejected' || status == 'cancelled')) {
          navigatorKey.currentState?.maybePop(false);
        }
        return;
      }
      if (event['type'] == 'cart_transfer_request') {
        final payload = event['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          final targetDeviceId = payload['target_device_id'] as String?;
          final myDeviceId = ApiClient.instance.deviceId;

          if (targetDeviceId == myDeviceId && !_isShowingDialog) {
            _isShowingDialog = true;
            SoundService.playNotification();
            // Dialog hemen açılır — WS payload'dan sender_name ve transfer_id alınır
            // cart_data yoksa "Kabul Et" anında fetch edilir
            final dialogPayload = <String, dynamic>{
              'id': payload['transfer_id'] ?? payload['id'],
              'sender_name': payload['sender_name'] ?? payload['sender_device_id'] ?? 'Bir cihaz',
              'cart_data': payload['cart_data'],   // WS payload'dan cart_data geçir
            };
            _showApprovalDialog(dialogPayload);
          }
        }
      }
    }, onDone: () {
      // WS bağlantısı kapandı, subscription'ı temizle
      _wsSubscription = null;
    }, onError: (_) {
      _wsSubscription = null;
    });

    // İlk açılışta askıda kalmış (bekleyen) sepet var mı diye bir kere HTTP kontrolü yapalım
    _checkPendingTransfers();

    // Periyodik polling: WS fallback — en geç 60 saniyede bildirim gelir
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_isShowingDialog) _checkPendingTransfers();
    });
  }

  void stop() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _ref = null;
  }

  Future<void> _checkPendingTransfers() async {
    if (_isShowingDialog) return;
    try {
      final resp = await ApiClient.instance.get('/api/cart/transfer/pending');
      if (!resp.success || resp.data?['data'] == null) return;

      final transfers = (resp.data!['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      if (transfers.isNotEmpty) {
        // Polling yolundan gelince ses hemen çal
        SoundService.playNotification();
        await _showApprovalDialog(transfers.first);
      }
    } catch (_) {}
  }

  Future<void> _showApprovalDialog(Map<String, dynamic> transfer) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      _isShowingDialog = false;
      return;
    }

    // _isShowingDialog zaten WS event geldiğinde true yapıldı (veya polling'den geliyorsa burada yap)
    _isShowingDialog = true;

    try {
      final senderName = transfer['sender_name'] ?? 'Bir cihaz';
      final transferId = transfer['id'] as String?;
      if (transferId == null) return;

      _currentTransferId = transferId;

      // Ses WS event'ten anında çalındı; polling'den geliyorsa burada çal
      // (playNotification birden fazla kez çağrılmaktan zarar görmez)

      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.shopping_cart, color: AppTheme.primaryAccent, size: 28),
              const SizedBox(width: 12),
              const Expanded(child: Text('Sepet Transferi')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(color: AppTheme.textMain, fontSize: 14),
                  children: [
                    TextSpan(
                      text: senderName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' cihazından sepet gönderilmek isteniyor.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sepeti kabul etmek istiyor musunuz?',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Reddet', style: TextStyle(color: AppTheme.dangerAccent)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Kabul Et'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (accepted == true) {
        // cart_data yoksa (WS yolundan geldi) önce fetch et
        dynamic cartDataRaw = transfer['cart_data'];
        if (cartDataRaw == null) {
          try {
            final resp = await ApiClient.instance.get('/api/cart/transfer/status/$transferId');
            if (resp.success && resp.data?['data'] != null) {
              cartDataRaw = resp.data!['data']['cart_data'];
            }
          } catch (_) {}
        }

        // Accept: respond to server + import cart
        await ApiClient.instance.post('/api/cart/transfer/respond', {
          'transfer_id': transferId,
          'action': 'accept',
        });

        // Import cart data
        if (_ref != null && cartDataRaw != null) {
          Map<String, dynamic> cartData;
          if (cartDataRaw is String) {
            cartData = jsonDecode(cartDataRaw) as Map<String, dynamic>;
          } else {
            cartData = Map<String, dynamic>.from(cartDataRaw);
          }

          final cartNotifier = _ref!.read(cartProvider.notifier);
          if (cartNotifier.hasEmptyCart()) {
            final tabIndex = cartNotifier.importCartToEmptyTab(cartData);
            if (tabIndex >= 0 && context.mounted) {
              SoundService.playSuccess();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$senderName\'dan sepet geldi → Sepet ${tabIndex + 1}\'e aktarıldı!'),
                  backgroundColor: AppTheme.secondaryAccent,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            if (context.mounted) {
              SoundService.playError();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sepet kabul edildi ama tüm sepetler dolu! Bir sepeti temizleyip tekrar deneyin.'),
                  backgroundColor: AppTheme.warningAccent,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        }
      } else {
        // Reject: respond to server
        await ApiClient.instance.post('/api/cart/transfer/respond', {
          'transfer_id': transferId,
          'action': 'reject',
        });
      }
    } finally {
      _isShowingDialog = false;
      _currentTransferId = null;
    }
  }
}
