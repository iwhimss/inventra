import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

const String _kRepo = 'iwhimss/inventra';
const String _kReleasesUrl = 'https://github.com/$_kRepo/releases/latest';

class VersionCheckService {
  /// Sunucudaki `min_app_version` ayarını kontrol eder. Yerel sürüm bu değerin
  /// altındaysa, kapatılamaz bir güncelleme uyarısı gösterir.
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final resp = await ApiClient.instance.get('/api/version');
      if (!resp.success || resp.data == null) return;

      final minVersion = resp.data!['data']?['min_app_version']?.toString();
      if (minVersion == null || minVersion.isEmpty) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_isBelowMinimum(currentVersion, minVersion)) {
        if (context.mounted) {
          _showUpdateRequiredDialog(context, minVersion);
        }
      }
    } catch (e) {
      debugPrint('Version check error: $e');
    }
  }

  static bool _isBelowMinimum(String current, String min) {
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final minParts = min.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final m = i < minParts.length ? minParts[i] : 0;
      if (c < m) return true;
      if (c > m) return false;
    }
    return false;
  }

  static void _showUpdateRequiredDialog(BuildContext context, String minVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.system_update_alt, color: AppTheme.dangerAccent, size: 28),
              const SizedBox(width: 12),
              const Expanded(child: Text('Güncelleme Gerekli')),
            ],
          ),
          content: Text(
            'Bu sunucu en az $minVersion sürümünü gerektiriyor. Devam etmek için uygulamayı güncellemeniz gerekiyor.',
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => _startUpdateFlow(ctx, minVersion),
              icon: const Icon(Icons.system_update, size: 16),
              label: const Text('GÜNCELLE'),
            ),
          ],
        ),
      ),
    );
  }

  /// `min_app_version`a karşılık gelen GitHub Release'i (tag: `v{sürüm}`) çeker,
  /// platforma uygun asset'i indirir. Kurulum otomatik başlatılmaz — kullanıcı
  /// indirilen dosyayı kendisi açar.
  static Future<void> _startUpdateFlow(BuildContext context, String minVersion) async {
    final tag = minVersion.startsWith('v') ? minVersion : 'v$minVersion';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('Sürüm bilgisi kontrol ediliyor...')),
            ],
          ),
        ),
      ),
    );

    Map<String, dynamic>? release;
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$_kRepo/releases/tags/$tag'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        release = json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    if (release == null) {
      if (context.mounted) _showNotFoundDialog(context, tag);
      return;
    }

    final asset = _pickAssetForTag(release, tag);
    if (asset == null) {
      if (context.mounted) _showNotFoundDialog(context, tag, assetMissing: true);
      return;
    }

    if (context.mounted) {
      await _downloadAsset(context, asset['name'] as String, asset['browser_download_url'] as String);
    }
  }

  /// Kullanıcının sabit adlandırma kuralına göre tam eşleşme arar
  /// (`inventra-v{sürüm}.apk`, `v{sürüm}-Windows.rar`); bulunamazsa gevşek
  /// bir sezgisel kurala (uzantı/anahtar kelime) düşer.
  static Map<String, dynamic>? _pickAssetForTag(Map<String, dynamic> release, String tag) {
    final assets = release['assets'] as List?;
    if (assets == null || assets.isEmpty) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;

    Map<String, dynamic>? findByName(bool Function(String nameLower) matches) {
      for (final a in assets) {
        final map = Map<String, dynamic>.from(a as Map);
        final name = (map['name']?.toString() ?? '').toLowerCase();
        if (matches(name)) return map;
      }
      return null;
    }

    if (Platform.isAndroid) {
      final exactName = 'inventra-v$version.apk'.toLowerCase();
      return findByName((n) => n == exactName) ?? findByName((n) => n.endsWith('.apk'));
    }
    if (Platform.isWindows) {
      final exactName = 'v$version-windows.rar'.toLowerCase();
      return findByName((n) => n == exactName) ??
          findByName((n) => n.endsWith('.exe') || n.endsWith('.zip') || n.endsWith('.rar') || n.contains('windows'));
    }
    return null;
  }

  static void _showNotFoundDialog(BuildContext context, String tag, {bool assetMissing = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Güncelleme Bulunamadı'),
        content: Text(
          assetMissing
              ? '$tag sürümü için GitHub Release bulundu ama bu platforma uygun bir kurulum dosyası eklenmemiş.'
              : '$tag sürümü için GitHub Release bulunamadı. Bu sürüm henüz GitHub\'a yüklenmemiş olabilir.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('KAPAT', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(_kReleasesUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('RELEASES SAYFASINI AÇ'),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAsset(BuildContext context, String fileName, String url) async {
    final client = http.Client();
    StreamSubscription<List<int>>? subscription;
    IOSink? sink;
    Timer? stallTimer;
    final progressNotifier = ValueNotifier<double?>(null); // null = toplam boyut bilinmiyor
    final receivedNotifier = ValueNotifier<int>(0);
    bool dialogClosed = false;

    void closeProgressDialog() {
      if (!dialogClosed && context.mounted) {
        dialogClosed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          title: const Text('Güncelleme İndiriliyor'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progressNotifier,
            builder: (ctx, progress, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: receivedNotifier,
                  builder: (ctx, received, __) => Text(
                    progress != null
                        ? '%${(progress * 100).toStringAsFixed(0)} — ${(received / (1024 * 1024)).toStringAsFixed(1)} MB'
                        : '${(received / (1024 * 1024)).toStringAsFixed(1)} MB indirildi...',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                Text(fileName, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );

    Directory? dir;
    try {
      dir = await _resolveDownloadDir();
      final filePath = '${dir.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      sink = file.openWrite();

      final streamedResponse = await client.send(http.Request('GET', Uri.parse(url))).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception('Sunucuya bağlanılamadı (zaman aşımı).'),
          );

      if (streamedResponse.statusCode != 200) {
        throw Exception('Sunucu hatası: HTTP ${streamedResponse.statusCode}');
      }

      final total = streamedResponse.contentLength;
      int received = 0;
      final completer = Completer<void>();

      void resetStallTimer() {
        stallTimer?.cancel();
        stallTimer = Timer(const Duration(seconds: 30), () {
          if (!completer.isCompleted) {
            completer.completeError(Exception('İndirme zaman aşımına uğradı (30 saniye veri gelmedi).'));
          }
        });
      }

      resetStallTimer();
      subscription = streamedResponse.stream.listen(
        (chunk) {
          resetStallTimer();
          sink!.add(chunk);
          received += chunk.length;
          receivedNotifier.value = received;
          if (total != null && total > 0) {
            progressNotifier.value = received / total;
          }
        },
        onDone: () {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;
      await sink.flush();
      await sink.close();
      sink = null;
      client.close();

      closeProgressDialog();

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.panelBackground,
            title: const Text('İndirme Tamamlandı'),
            content: Text(
              'Güncelleme indirildi:\n\n$filePath\n\nKurulumu başlatmak için dosyayı açmanız gerekiyor.',
            ),
            actions: [
              if (Platform.isWindows)
                TextButton(
                  onPressed: () => Process.run('explorer', [dir!.path]),
                  child: const Text('KLASÖRÜ AÇ'),
                ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('TAMAM')),
            ],
          ),
        );
      }
    } catch (e) {
      stallTimer?.cancel();
      await subscription?.cancel();
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      closeProgressDialog();
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.panelBackground,
            title: const Text('İndirme Başarısız'),
            content: Text('Güncelleme indirilemedi:\n\n$e'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse(_kReleasesUrl), mode: LaunchMode.externalApplication);
                },
                child: const Text('RELEASES SAYFASINI AÇ'),
              ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('TAMAM')),
            ],
          ),
        );
      }
    }
  }

  static Future<Directory> _resolveDownloadDir() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloads = await getDownloadsDirectory();
      return downloads ?? await getApplicationDocumentsDirectory();
    }
    final downloadDir = Directory('/storage/emulated/0/Download');
    if (await downloadDir.exists()) return downloadDir;
    return await getApplicationDocumentsDirectory();
  }
}
