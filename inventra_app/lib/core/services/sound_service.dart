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

  // Kategori başına sabit asset — tek doğruluk kaynağı. Kaynak yalnızca bir
  // kez yüklenir (setSourceAsset), tetikleme yalnızca resume() ile yapılır.
  // Her tetiklemede play(AssetSource(...)) çağırmak (önceki tasarım), her
  // seferinde kaynağı yeniden yükletir — audioplayers paketinin kendi
  // dokümantasyonu bunun yanlış kullanım deseni olduğunu belirtiyor. Bu
  // yanlış kullanım, PlayerMode.lowLatency (Android'de SoundPool) ile
  // birleşince SoundPool'un sınırlı slot sayısını hızla tüketip birkaç
  // çağrı sonra TÜM sesleri kalıcı olarak sessizleştiriyordu (yalnızca
  // uygulamanın tamamen yeniden başlatılmasıyla düzeliyordu).
  static const _assetPaths = {
    SoundCategory.success: 'sounds/success.wav',
    SoundCategory.error: 'sounds/error.wav',
    SoundCategory.warning: 'sounds/notification.wav',
    SoundCategory.notification: 'sounds/notification.wav',
    SoundCategory.info: 'sounds/success.wav',
    SoundCategory.login: 'sounds/login.wav',
    SoundCategory.cartAdd: 'sounds/cart_add.wav',
  };
  static final Set<SoundCategory> _loaded = {};

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

  // Kategori bazlı debounce: bir kategorideki ses, başka bir kategorideki
  // sesin çalınmasını asla bastırmamalı (önceden tek bir paylaşılan
  // değişken vardı — ör. bir hata sesi, hemen ardından tetiklenen sepete
  // ekleme sesini sessizce yutuyordu).
  static final Map<SoundCategory, DateTime> _lastPlayTimes = {};

  /// Oyuncuyu döndürür; yoksa oluşturup moda ayarlar, kaynağı yüklenmemişse
  /// bir kez yükler. Hem açılış ısıtmasında hem her gerçek çalma isteğinde
  /// çağrılır — böylece bir önceki oyuncu bozulup atıldıysa (bkz. _play),
  /// bir sonraki çağrı sıfırdan ve doğru şekilde kurulur.
  static Future<AudioPlayer> _getPlayer(SoundCategory category) async {
    var player = _players[category];
    if (player == null) {
      player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      // Kısa UI bildirim sesleri için: Android'de SoundPool kullanır (önceden
      // belleğe yüklenir, tetiklemede neredeyse gecikmesizdir, üst üste binen
      // çağrıları doğal destekler).
      await player.setPlayerMode(PlayerMode.lowLatency);
      _players[category] = player;
      _loaded.remove(category); // yeni oyuncu — kaynak henüz yüklenmedi
    }
    if (!_loaded.contains(category)) {
      try {
        await player.setSourceAsset(_assetPaths[category]!);
        _loaded.add(category);
      } catch (_) {}
    }
    return player;
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
    await _warmUpPlayers();
  }

  /// Her kategori için oyuncuyu oluşturup kaynağını önceden yükler
  /// (gerçek ilk kullanıcı etkileşiminde ses anında ve güvenilir çalar).
  static Future<void> _warmUpPlayers() async {
    for (final category in _assetPaths.keys) {
      try {
        await _getPlayer(category);
      } catch (_) {}
    }
  }

  static Future<void> _play(SoundCategory category, bool enabled, double volume) async {
    if (!enabled) return;

    final now = DateTime.now();
    final lastForCategory = _lastPlayTimes[category];
    if (lastForCategory != null && now.difference(lastForCategory) < const Duration(milliseconds: 100)) return;
    _lastPlayTimes[category] = now;

    try {
      final player = await _getPlayer(category);
      // Android SoundPool (lowLatency mod) için kritik: native streamId, bir
      // önceki çalma tamamlandıktan sonra da dolu kalır. stop() bu streamId'yi
      // sıfırlar; aksi halde resume() "duraklatılmış akışı devam ettir"
      // dalına düşer — akış zaten bittiği için bu hiçbir şey yapmaz ve ilk
      // çalmadan sonraki TÜM sesler sessizce iptal olur.
      await player.stop();
      await player.setVolume(masterVolume * volume);
      await player.resume();
    } catch (_) {
      // Kendi kendini onarma: native oyuncu bozulmuş olabilir — at, bir
      // sonraki çağrıda sıfırdan kurulup kaynağı yeniden yüklensin. Artık
      // tam uygulama yeniden başlatmaya gerek kalmıyor.
      final broken = _players.remove(category);
      _loaded.remove(category);
      await broken?.dispose();
    }
  }

  static Future<void> playSuccess() async {
    await _play(SoundCategory.success, successEnabled, successVolume);
  }

  static Future<void> playError() async {
    await _play(SoundCategory.error, errorEnabled, errorVolume);
  }

  static Future<void> playWarning() async {
    // Uses notification sound as warning — can be replaced with warning.wav later
    await _play(SoundCategory.warning, warningEnabled, warningVolume);
  }

  static Future<void> playNotification() async {
    await _play(SoundCategory.notification, notificationEnabled, notificationVolume);
  }

  static Future<void> playInfo() async {
    // Uses success sound as info — can be replaced with info.wav later
    await _play(SoundCategory.info, infoEnabled, infoVolume);
  }

  static Future<void> playLogin() async {
    await _play(SoundCategory.login, successEnabled, successVolume);
  }

  static Future<void> playCartAdd() async {
    await _play(SoundCategory.cartAdd, cartAddEnabled, cartAddVolume);
  }

  /// Dispose all players
  static void dispose() {
    for (var player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _loaded.clear();
  }
}
