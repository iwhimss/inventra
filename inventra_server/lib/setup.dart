import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'database_helper.dart';

class SetupWizard {
  /// Otomatik kurulum: ortam değişkenlerinden okur, interaktif sormaz.
  /// Docker ve CI ortamları için tasarlanmıştır.
  ///
  /// Gerekli ENV değişkenleri:
  ///   INVENTRA_BUSINESS_NAME  — İşletme adı
  ///   INVENTRA_ADMIN_ID       — Yönetici Staff ID (varsayılan: 1000)
  ///   INVENTRA_ADMIN_PASSWORD — Yönetici şifresi
  ///   INVENTRA_PORT           — Port numarası (varsayılan: 5000)
  ///   INVENTRA_HOST           — 0.0.0.0 veya 127.0.0.1 (varsayılan: 0.0.0.0)
  static Future<bool> runFromEnv({required String dataPath}) async {
    final businessName = Platform.environment['INVENTRA_BUSINESS_NAME'];
    final adminId = Platform.environment['INVENTRA_ADMIN_ID'] ?? '1000';
    final adminPassword = Platform.environment['INVENTRA_ADMIN_PASSWORD'];
    final portStr = Platform.environment['INVENTRA_PORT'] ?? '5000';
    final host = Platform.environment['INVENTRA_HOST'] ?? '0.0.0.0';

    if (businessName == null || businessName.isEmpty) return false;
    if (adminPassword == null || adminPassword.isEmpty) return false;

    final port = int.tryParse(portStr) ?? 5000;
    final configFile = File(p.join(dataPath, 'config.json'));
    if (configFile.existsSync()) return false; // Zaten kurulu

    print('');
    print('🐳 Docker otomatik kurulum başlatılıyor...');
    print('   İşletme: $businessName');
    print('   Admin ID: $adminId');
    print('   Port: $port / Host: $host');
    print('');

    await Directory(dataPath).create(recursive: true);
    final apiKey = 'inv_${const Uuid().v4().replaceAll('-', '')}';

    final config = {
      'name': businessName,
      'port': port,
      'host': host,
      'api_key': apiKey,
      'created_at': DateTime.now().toIso8601String(),
      'api_version': '1.0',
    };

    await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));

    final dbHelper = ServerDatabaseHelper(dataPath);
    dbHelper.open();

    final passwordHash = sha256.convert(utf8.encode(adminPassword)).toString();
    dbHelper.insert('users', {
      'id': const Uuid().v4(),
      'staff_id': adminId,
      'password_hash': passwordHash,
      'name': 'Yönetici',
      'role': 'owner',
      'permissions': 'all',
    });
    dbHelper.insert('settings', {'key': 'api_key', 'value': apiKey});
    dbHelper.insert('settings', {'key': 'business_name', 'value': businessName});
    dbHelper.insert('roles', {'id': const Uuid().v4(), 'name': 'owner', 'permissions': 'all'});
    dbHelper.insert('roles', {'id': const Uuid().v4(), 'name': 'cashier', 'permissions': 'pos,products_read'});
    dbHelper.close();

    print('✓ Otomatik kurulum tamamlandı');
    print('✓ API Key: $apiKey');
    print('');
    return true;
  }

  static Future<void> run({required String dataPath}) async {
    print('');
    print('═══════════════════════════════════════════════');
    print('   Inventra Server — İlk Kurulum');
    print('═══════════════════════════════════════════════');
    print('');

    final configFile = File(p.join(dataPath, 'config.json'));
    if (configFile.existsSync()) {
      stdout.write('⚠  Bu dizinde zaten bir kurulum mevcut. Üzerine yazılsın mı? [e/H]: ');
      final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
      if (answer != 'e') {
        print('Kurulum iptal edildi.');
        return;
      }
    }

    final businessName = _promptRequired('İşletme Adı');
    final staffId = _prompt('Yönetici Staff ID', defaultValue: '1000');
    final password = _promptRequired('Yönetici Şifre');
    final passwordConfirm = _promptRequired('Şifre Tekrar');
    if (password != passwordConfirm) {
      print('⚠  Şifreler eşleşmiyor. Kurulum iptal edildi.');
      exit(1);
    }

    final portInput = _prompt('Port', defaultValue: '5000');
    final port = int.tryParse(portInput) ?? 5000;

    stdout.write('Ağ erişimi [0=Sadece bu cihaz / 1=Tüm ağ (LAN/VDS)] [varsayılan: 1]: ');
    final hostChoice = stdin.readLineSync()?.trim() ?? '';
    final host = hostChoice == '0' ? '127.0.0.1' : '0.0.0.0';

    await Directory(dataPath).create(recursive: true);

    final apiKey = 'inv_${const Uuid().v4().replaceAll('-', '')}';

    final config = {
      'name': businessName,
      'port': port,
      'host': host,
      'api_key': apiKey,
      'created_at': DateTime.now().toIso8601String(),
      'api_version': '1.0',
    };

    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    final dbHelper = ServerDatabaseHelper(dataPath);
    dbHelper.open();

    final passwordHash = sha256.convert(utf8.encode(password)).toString();
    dbHelper.insert('users', {
      'id': const Uuid().v4(),
      'staff_id': staffId,
      'password_hash': passwordHash,
      'name': 'Yönetici',
      'role': 'owner',
      'permissions': 'all',
    });
    dbHelper.insert('settings', {'key': 'api_key', 'value': apiKey});
    dbHelper.insert('settings', {'key': 'business_name', 'value': businessName});
    dbHelper.insert('roles', {
      'id': const Uuid().v4(),
      'name': 'owner',
      'permissions': 'all',
    });
    dbHelper.insert('roles', {
      'id': const Uuid().v4(),
      'name': 'cashier',
      'permissions': 'pos,products_read',
    });
    dbHelper.close();

    print('');
    print('✓ Veritabanı oluşturuldu');
    print('✓ Yönetici hesabı kaydedildi (Staff ID: $staffId)');
    print('✓ API Key: $apiKey');
    print('  → Bu anahtarı uygulamada sunucuya bağlanırken kullanın.');
    print('');
    print('Sunucuyu başlatmak için:');
    print('  dart run bin/server.dart');
    if (Platform.isWindows) print('  veya  start.bat');
    if (Platform.isLinux || Platform.isMacOS) print('  veya  ./start.sh');
    print('');
  }

  static String _prompt(String message, {String? defaultValue}) {
    if (defaultValue != null) {
      stdout.write('$message [$defaultValue]: ');
    } else {
      stdout.write('$message: ');
    }
    final line = stdin.readLineSync()?.trim() ?? '';
    return line.isEmpty && defaultValue != null ? defaultValue : line;
  }

  static String _promptRequired(String message) {
    while (true) {
      stdout.write('$message: ');
      final value = stdin.readLineSync()?.trim() ?? '';
      if (value.isNotEmpty) return value;
      print('  ⚠ Bu alan boş olamaz.');
    }
  }
}
