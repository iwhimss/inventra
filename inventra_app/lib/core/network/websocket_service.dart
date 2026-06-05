import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';

final webSocketProvider = Provider<WebSocketService>((ref) {
  return WebSocketService(ref);
});

class WebSocketService {
  final Ref ref;
  WebSocketService(this.ref);

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  bool _isDisconnectedIntentionally = false;
  bool _hasConnectedBefore = false;
  
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  /// Projeye özel event stream: Diğer servisler (CartTransfer gibi) burayı dinleyecek
  Stream<Map<String, dynamic>> get stream => _eventController.stream;

  bool get isConnected => _channel != null;

  void connect() {
    _isDisconnectedIntentionally = false;
    if (_isConnecting || isConnected) return;

    final baseUrl = ApiClient.instance.baseUrl;
    if (baseUrl.isEmpty) return; // Server is not configured yet

    // Determine WS URL from HTTP URL
    String wsUrl;
    if (baseUrl.startsWith('https://')) {
      wsUrl = baseUrl.replaceFirst('https://', 'wss://');
    } else if (baseUrl.startsWith('http://')) {
      wsUrl = baseUrl.replaceFirst('http://', 'ws://');
    } else {
      wsUrl = 'ws://$baseUrl';
    }

    final endpoint = '$wsUrl/api/ws';
    final apiKey = ApiClient.instance.apiKey;
    final finalUrl = (apiKey != null && apiKey.isNotEmpty) ? '$endpoint?api_key=$apiKey' : endpoint;

    _isConnecting = true;
    debugPrint('WebSocket bağlanıyor: $finalUrl');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(finalUrl));
      _isConnecting = false;

      // Start pinging to keep connection alive
      _startPingTimer();

      // Yeniden bağlanma ise kaçırılan transferleri kontrol ettir
      if (_hasConnectedBefore) {
        _eventController.add({'type': 'ws_reconnected'});
      }
      _hasConnectedBefore = true;

      _channel!.stream.listen(
        (message) {
          try {
            if (message is String) {
              final data = jsonDecode(message);
              if (data['type'] == 'pong') return; // Ignore pongs
              
              if (data['type'] == 'DEVICE_REJECTED' && data['payload'] != null) {
                if (data['payload']['device_id'] == ApiClient.instance.deviceId) {
                  debugPrint('Device rejected by admin. Disconnecting and logging out.');
                  disconnect();
                  // We need to import authProvider, but to avoid circular dependencies we can just call it via ref if we import it at the top
                  try {
                     ref.read(authProvider.notifier).logout();
                     ref.read(syncProvider.notifier).disconnectFromServer();
                  } catch (e) {
                     debugPrint('Logout error: $e');
                  }
                  return;
                }
              }

              _eventController.add(data);
            }
          } catch (e) {
            debugPrint('WS Mesaj Decode Hatası: \$e');
          }
        },
        onDone: () {
          debugPrint('WebSocket bağlantısı kapandı.');
          _handleDisconnect();
        },
        onError: (error) {
          debugPrint('WebSocket hatası: \$error');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket bağlanılamadı: \$e');
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (isConnected) {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _handleDisconnect() {
    _channel = null;
    _pingTimer?.cancel();
    
    if (_isDisconnectedIntentionally) return;

    // Auto reconnect after 5 seconds
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('WebSocket yeniden bağlanmayı deniyor...');
      connect();
    });
  }

  void disconnect() {
    _isDisconnectedIntentionally = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnecting = false;
  }
}
