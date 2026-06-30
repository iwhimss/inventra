import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

const String _kReleasesUrl = 'https://github.com/iwhimss/inventra/releases/latest';

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
              onPressed: () => launchUrl(Uri.parse(_kReleasesUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('GÜNCELLE'),
            ),
          ],
        ),
      ),
    );
  }
}
