import 'package:audioplayers/audioplayers.dart';
import 'package:inventra_app/core/database/database_helper.dart';

/// Sound categories for the application.
enum SoundCategory {
  success,
  error,
  warning,
  notification,
  info,
  login,
  cartAdd,
}

class SoundService {
  // Separate players per category to avoid sound overlap
  static final Map<SoundCategory, AudioPlayer> _players = {};
  
  // Per-sound enable flags (loaded from DB)
  static bool successEnabled = true;
  static bool errorEnabled = true;
  static bool warningEnabled = true;
  static bool notificationEnabled = true;
  static bool infoEnabled = true;
  static bool cartAddEnabled = true;
  
  // Volume (0.0 to 1.0)
  static double masterVolume = 1.0;
  static double successVolume = 1.0;
  static double errorVolume = 1.0;
  static double warningVolume = 1.0;
  static double notificationVolume = 1.0;
  static double infoVolume = 1.0;
  static double cartAddVolume = 1.0;

  static DateTime? _lastPlayTime;

  static AudioPlayer _getPlayer(SoundCategory category) {
    return _players.putIfAbsent(category, () {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      return player;
    });
  }
  
  /// Load sound preferences from settings DB
  static Future<void> init() async {
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final results = await db.query('settings');
      for (var s in results) {
        final k = s['key']?.toString() ?? '';
        final v = s['value']?.toString() ?? '';
        switch (k) {
          case 'sound_success': successEnabled = v != 'false'; break;
          case 'sound_error': errorEnabled = v != 'false'; break;
          case 'sound_warning': warningEnabled = v != 'false'; break;
          case 'sound_notification': notificationEnabled = v != 'false'; break;
          case 'sound_info': infoEnabled = v != 'false'; break;
          case 'sound_volume': masterVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_success_volume': successVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_error_volume': errorVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_warning_volume': warningVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_notification_volume': notificationVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_info_volume': infoVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_cart_add': cartAddEnabled = v != 'false'; break;
          case 'sound_cart_add_volume': cartAddVolume = double.tryParse(v) ?? 1.0; break;
        }
      }
    } catch (_) {}
  }

  static Future<void> _play(SoundCategory category, String asset, bool enabled, double volume) async {
    if (!enabled) return;
    
    final now = DateTime.now();
    if (_lastPlayTime != null && now.difference(_lastPlayTime!) < const Duration(milliseconds: 100)) return;
    _lastPlayTime = now;

    try {
      final player = _getPlayer(category);
      await player.stop(); // Stop any currently playing overlapping sound in same category
      await player.setVolume(masterVolume * volume);
      await player.play(AssetSource(asset));
    } catch (_) {}
  }

  static Future<void> playSuccess() async {
    await _play(SoundCategory.success, 'sounds/success.wav', successEnabled, successVolume);
  }

  static Future<void> playError() async {
    await _play(SoundCategory.error, 'sounds/error.wav', errorEnabled, errorVolume);
  }

  static Future<void> playWarning() async {
    // Uses notification sound as warning — can be replaced with warning.wav later
    await _play(SoundCategory.warning, 'sounds/notification.wav', warningEnabled, warningVolume);
  }

  static Future<void> playNotification() async {
    await _play(SoundCategory.notification, 'sounds/notification.wav', notificationEnabled, notificationVolume);
  }

  static Future<void> playInfo() async {
    // Uses success sound as info — can be replaced with info.wav later
    await _play(SoundCategory.info, 'sounds/success.wav', infoEnabled, infoVolume);
  }

  static Future<void> playLogin() async {
    await _play(SoundCategory.login, 'sounds/login.wav', successEnabled, successVolume);
  }

  static Future<void> playCartAdd() async {
    await _play(SoundCategory.cartAdd, 'sounds/cart_add.wav', cartAddEnabled, cartAddVolume);
  }

  /// Dispose all players
  static void dispose() {
    for (var player in _players.values) {
      player.dispose();
    }
    _players.clear();
  }
}
