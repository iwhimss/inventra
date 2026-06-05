import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:inventra_server/core_server.dart';
import 'package:inventra_server/database_helper.dart';
import 'package:inventra_server/setup.dart';
import 'package:inventra_server/server_paths.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('setup', negatable: false, help: 'İlk kurulum sihirbazını çalıştır')
    ..addFlag('reset', negatable: false, help: 'Tüm verileri sil ve sıfırdan kurulum yap')
    ..addOption('port', abbr: 'p', help: 'Port numarasını geçersiz kıl')
    ..addOption('host', help: 'Bağlanılacak IP adresi (varsayılan: config\'den okunur)')
    ..addFlag('local', negatable: false, help: 'Sadece yerel erişim (127.0.0.1)')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Yardım göster');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    print('Hata: $e');
    _printHelp(parser);
    exit(1);
  }

  if (results['help'] as bool) {
    _printHelp(parser);
    return;
  }

  final dataPath = p.join(serverBaseDir, 'data');

  if (results['setup'] as bool) {
    await SetupWizard.run(dataPath: dataPath);
    return;
  }

  if (results['reset'] as bool) {
    await _resetData(dataPath);
    return;
  }

  final configFile = File(p.join(dataPath, 'config.json'));
  if (!configFile.existsSync()) {
    // Docker/CI: ENV değişkenleri ile otomatik kurulum dene
    final autoSetup = await SetupWizard.runFromEnv(dataPath: dataPath);
    if (!autoSetup) {
      print('');
      print('⚠  Kurulum bulunamadı. Sunucuyu ilk kez çalıştırıyorsanız kurulumu başlatın:');
      print('');
      print('   dart run bin/server.dart --setup');
      print('');
      print('   Docker kullanıyorsanız INVENTRA_SETUP=true ile ENV değişkenlerini ayarlayın.');
      print('   Bkz: docs/vds-deployment.md — Docker Kurulumu');
      print('');
      exit(1);
    }
  }

  final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  if (results['local'] as bool) {
    config['host'] = '127.0.0.1';
  } else if (results['host'] != null) {
    config['host'] = results['host'] as String;
  }

  if (results['port'] != null) {
    final portOverride = int.tryParse(results['port'] as String);
    if (portOverride != null) config['port'] = portOverride;
  }

  await _startServer(dataPath, config);
}

void _printHelp(ArgParser parser) {
  print('');
  print('Inventra Server — Bağımsız POS Sunucusu');
  print('');
  print('Kullanım:');
  print('  dart run bin/server.dart [seçenekler]');
  print('');
  print('Seçenekler:');
  print(parser.usage);
  print('');
  print('Örnekler:');
  print('  dart run bin/server.dart --setup     # İlk kurulumu çalıştır');
  print('  dart run bin/server.dart --reset     # TÜM VERİLERİ SİL, sıfırdan kur');
  print('  dart run bin/server.dart             # Sunucuyu başlat');
  print('  dart run bin/server.dart --local     # Sadece bu cihazdan erişilebilir');
  print('  dart run bin/server.dart --port 8080 # Farklı port ile başlat');
  print('');
}

Future<void> _resetData(String dataPath) async {
  print('');
  print('⚠  UYARI: Bu işlem TÜM verilerinizi kalıcı olarak siler!');
  print('   Silinecekler: config.json, inventra.db, tüm resimler ve loglar');
  print('');
  stdout.write('Devam etmek istediğinizden emin misiniz? [e/H]: ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  if (answer != 'e') {
    print('İptal edildi.');
    return;
  }

  print('');
  print('Veriler siliniyor...');

  final configFile = File(p.join(dataPath, 'config.json'));
  final dbFile = File(p.join(dataPath, 'inventra.db'));
  final imagesDir = Directory(p.join(dataPath, 'images'));
  final logsDir = Directory(p.join(dataPath, 'logs'));

  if (configFile.existsSync()) {
    configFile.deleteSync();
    print('  ✓ config.json silindi');
  }
  if (dbFile.existsSync()) {
    dbFile.deleteSync();
    print('  ✓ inventra.db silindi');
  }
  if (imagesDir.existsSync()) {
    imagesDir.deleteSync(recursive: true);
    print('  ✓ images/ silindi');
  }
  if (logsDir.existsSync()) {
    logsDir.deleteSync(recursive: true);
    print('  ✓ logs/ silindi');
  }

  print('');
  print('Tüm veriler silindi. Kurulum başlatılıyor...');
  print('');

  await SetupWizard.run(dataPath: dataPath);
}

Future<void> _startServer(String dataPath, Map<String, dynamic> config) async {
  print('');
  print('  📂 Data dizini : ${p.absolute(dataPath)}');
  print('  🏪 İşletme     : ${config['name'] ?? '-'}');
  print('  🌐 Adres       : ${config['host'] ?? '0.0.0.0'}:${config['port'] ?? 5000}');
  print('');
  final dbHelper = ServerDatabaseHelper(dataPath);
  dbHelper.open();
  final server = CoreServer(dbHelper, config, dataPath);

  try {
    await server.start();
    print('Çıkmak için Ctrl+C basın.');
  } catch (e) {
    print('Sunucu başlatılamadı: $e');
    dbHelper.close();
    exit(1);
  }

  Future<void> shutdown() async {
    print('\nKapatılıyor...');
    await server.stop();
    dbHelper.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
}
