import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/theme/theme_provider.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/services/auto_backup_service.dart';
import 'package:inventra_app/core/services/cart_transfer_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:inventra_app/features/auth/screens/login_screen.dart';
import 'package:inventra_app/features/auth/screens/server_connect_screen.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:inventra_app/features/dashboard/screens/main_dashboard.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait on mobile devices
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }
  
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1400, 785),
      minimumSize: Size(1400, 785),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  await DatabaseHelper.instance.globalDb;
  await SoundService.init();
  await AutoBackupService.init();
  
  runApp(
    const ProviderScope(
      child: InventraApp(),
    ),
  );
}

class InventraApp extends ConsumerWidget {
  const InventraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Inventra',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      debugShowCheckedModeBanner: false,
      // Mobil cihazlarda sistem font büyütmesinin layout'u bozmasını önle
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clampedData = (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            ? mq.copyWith(
                textScaler: mq.textScaler.clamp(
                  minScaleFactor: 0.8,
                  maxScaleFactor: 1.0,
                ),
              )
            : mq;
        return MediaQuery(data: clampedData, child: child!);
      },
      home: const AppGate(),
    );
  }
}

class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> {
  // null = kontrol ediliyor, true = başarılı, false = başarısız/yok
  bool? _autoLoginResult;
  bool _autoLoginAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(syncProvider, (_, next) {
        if (next.isInitialized && !_autoLoginAttempted) {
          _autoLoginAttempted = true;
          _attemptAutoLogin();
        }
      }, fireImmediately: true);
    });
  }

  Future<void> _attemptAutoLogin() async {
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final results = await db.query('settings', where: "key = ?", whereArgs: ['remember_me']);
      if (results.isNotEmpty && results.first['value']?.toString() == 'true') {
        final idResult = await db.query('settings', where: "key = ?", whereArgs: ['saved_staff_id']);
        final hashResult = await db.query('settings', where: "key = ?", whereArgs: ['saved_password_hash']);
        final staffId = idResult.isNotEmpty ? idResult.first['value']?.toString() ?? '' : '';
        final passwordHash = hashResult.isNotEmpty ? hashResult.first['value']?.toString() ?? '' : '';
        if (staffId.isNotEmpty && passwordHash.isNotEmpty) {
          // Hash ile direkt offline login — plaintext ağda gönderilmez
          final success = await ref.read(authProvider.notifier).loginWithHash(staffId, passwordHash);
          if (mounted) {
            setState(() { _autoLoginResult = success; });
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _autoLoginResult = false);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    
    // Sunucu başlatılıyor veya auto-login kontrol ediliyor
    if (!syncState.isInitialized || _autoLoginResult == null) {
      return Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    // Sunucu URL yoksa bağlantı ekranına yönlendir
    if (syncState.serverUrl == null || syncState.serverUrl!.isEmpty) {
      return ServerConnectScreen(onConnected: () {});
    }
    
    // Onaylanmış bağlantı varsa
    if (syncState.pairStatus == 'approved') {
      // Auto-login başarılıysa direkt dashboard'a git
      if (_autoLoginResult == true) {
        return const MainDashboard();
      }
      return const LoginScreen();
    }
    
    return ServerConnectScreen(onConnected: () {});
  }
}

