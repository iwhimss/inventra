import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

class VersionCheckService {
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final resp = await ApiClient.instance.get('/api/version');
      if (resp.success && resp.data != null) {
        final serverVersionStr = resp.data!['data']['version']?.toString();
        final releaseNotes = resp.data!['data']['release_notes']?.toString();
        final isMandatory = resp.data!['data']['mandatory'] == 1 || resp.data!['data']['mandatory'] == true;

        if (serverVersionStr != null && serverVersionStr.isNotEmpty) {
          final packageInfo = await PackageInfo.fromPlatform();
          final currentVersionStr = packageInfo.version;

          if (_isUpdateAvailable(currentVersionStr, serverVersionStr)) {
            if (context.mounted) {
              _showUpdateDialog(context, serverVersionStr, releaseNotes ?? 'Yeni güncellemeler mevcut.', isMandatory);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Version check error: $e');
    }
  }

  static bool _isUpdateAvailable(String current, String server) {
    // Simple semver comparison (e.g., 1.0.0 vs 1.1.0)
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final serverParts = server.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final s = i < serverParts.length ? serverParts[i] : 0;
      if (s > c) return true;
      if (s < c) return false;
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String releaseNotes, bool isMandatory) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => PopScope(
        canPop: !isMandatory,
        child: AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.system_update_alt, color: AppTheme.primaryAccent, size: 28),
              const SizedBox(width: 12),
              const Text('Yeni Sürüm Mevcut'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Versiyon $newVersion kullanıma sunuldu.', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.darkBackground, borderRadius: BorderRadius.circular(8)),
                child: Text(releaseNotes, style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ),
              if (isMandatory) ...[
                const SizedBox(height: 12),
                Text('Bu güncellemeyi yüklemek zorunludur.', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            if (!isMandatory)
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Daha Sonra', style: TextStyle(color: AppTheme.textMuted))),
            ElevatedButton(
              onPressed: () {
                // In a real app, this would open URL or app store.
                // For now, we just close the dialog if not mandatory.
                if (!isMandatory) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('ŞİMDİ GÜNCELLE'),
            ),
          ],
        ),
      ),
    );
  }
}
