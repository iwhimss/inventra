import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

const String _kReleasesUrl = 'https://github.com/iwhimss/inventra/releases/latest';
const String _kGithubApiLatest = 'https://api.github.com/repos/iwhimss/inventra/releases/latest';

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
              onPressed: () => _startUpdateFlow(ctx),
              icon: const Icon(Icons.system_update, size: 16),
              label: const Text('GÜNCELLE'),
            ),
          ],
        ),
      ),
    );
  }

  /// GitHub Releases'ten en son sürümü çeker, platforma uygun bir dosya
  /// (apk/exe/zip) varsa indirir. Bulunamazsa tarayıcıda releases sayfasını açar.
  /// Kurulum otomatik başlatılmaz — kullanıcı indirilen dosyayı kendisi açar.
  static Future<void> _startUpdateFlow(BuildContext context) async {
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
        Uri.parse(_kGithubApiLatest),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode == 200) {
        release = json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    final asset = _pickAssetForPlatform(release);
    if (asset == null) {
      await launchUrl(Uri.parse(_kReleasesUrl), mode: LaunchMode.externalApplication);
      return;
    }

    if (context.mounted) {
      await _downloadAsset(context, asset['name'] as String, asset['browser_download_url'] as String);
    }
  }

  static Map<String, dynamic>? _pickAssetForPlatform(Map<String, dynamic>? release) {
    if (release == null) return null;
    final assets = release['assets'] as List?;
    if (assets == null || assets.isEmpty) return null;

    bool matches(String name) {
      final n = name.toLowerCase();
      if (Platform.isAndroid) return n.endsWith('.apk');
      if (Platform.isWindows) return n.endsWith('.exe') || n.endsWith('.zip') || n.contains('windows');
      return false;
    }

    for (final a in assets) {
      final map = a as Map<String, dynamic>;
      final name = map['name']?.toString() ?? '';
      if (matches(name)) return map;
    }
    return null;
  }

  static Future<void> _downloadAsset(BuildContext context, String fileName, String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          title: const Text('Güncelleme İndiriliyor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(fileName, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    try {
      final dir = await _resolveDownloadDir();
      final filePath = '${dir.path}${Platform.pathSeparator}$fileName';
      final resp = await http.get(Uri.parse(url));
      final file = File(filePath);
      await file.writeAsBytes(resp.bodyBytes);

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

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
                  onPressed: () => Process.run('explorer', [dir.path]),
                  child: const Text('KLASÖRÜ AÇ'),
                ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('TAMAM')),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        await launchUrl(Uri.parse(_kReleasesUrl), mode: LaunchMode.externalApplication);
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
