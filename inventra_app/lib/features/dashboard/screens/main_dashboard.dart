import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/theme/theme_provider.dart';
import 'package:inventra_app/core/services/cart_transfer_service.dart';
import 'package:inventra_app/core/network/websocket_service.dart';
import 'package:inventra_app/core/services/version_check_service.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';
import 'package:inventra_app/features/pos/screens/pos_screen.dart';
import 'package:inventra_app/features/product/screens/products_screen.dart';
import 'package:inventra_app/features/analytics/screens/sales_history_screen.dart';
import 'package:inventra_app/features/analytics/screens/reports_screen.dart';
import 'package:inventra_app/features/receipt/screens/label_designer_screen.dart';
import 'package:inventra_app/features/settings/screens/settings_screen.dart';
import 'package:inventra_app/features/backup/screens/converter_screen.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:inventra_app/features/auth/screens/login_screen.dart';
import 'package:inventra_app/core/widgets/custom_title_bar.dart';
import 'package:inventra_app/features/clients/screens/clients_screen.dart';
import 'package:inventra_app/features/logs/screens/activity_logs_screen.dart';
import 'package:inventra_app/features/auth/screens/server_connect_screen.dart';
import 'package:inventra_app/main.dart' show AppGate;

class _NavItem {
  final String permKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget screen;
  const _NavItem(this.permKey, this.icon, this.title, this.subtitle, this.color, this.screen);
}

final _allNavItems = [
  _NavItem('pos', Icons.payments, 'Satış (POS)', 'Hızlı satış ekranı', AppTheme.primaryAccent, const PosScreen()),
  _NavItem('products', Icons.inventory_2, 'Stoklar', 'Stok ve ürün yönetimi', AppTheme.secondaryAccent, const ProductsScreen()),
  _NavItem('clients', Icons.people, 'Müşteri/Tedarikçi', 'Cari hesap yönetimi', Colors.indigoAccent, const ClientsScreen()),
  _NavItem('history', Icons.receipt_long, 'Geçmiş İşlemler', 'Satış geçmişi', AppTheme.warningAccent, const SalesHistoryScreen()),
  _NavItem('reports', Icons.bar_chart, 'Raporlar', 'Ciro ve analiz', Colors.blueAccent, const ReportsScreen()),
  _NavItem('movements', Icons.history, 'Hareketler', 'Aktivite ve stok logları', Colors.cyan, const ActivityLogsScreen()),
  _NavItem('converter', Icons.swap_horiz, 'Dönüştürücü', 'Format dönüştürme', Colors.teal, const ConverterScreen()),
  _NavItem('labels', Icons.qr_code_2, 'Etiket Tasarımı', 'Barkod ve etiket', Colors.purpleAccent, const LabelDesignerScreen()),
  _NavItem('settings', Icons.settings, 'Ayarlar', 'Uygulama ayarları', Colors.grey, const SettingsScreen()),
];

class MainDashboard extends ConsumerStatefulWidget {
  const MainDashboard({super.key});

  @override
  ConsumerState<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends ConsumerState<MainDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _menuAnimCtrl;
  late Animation<double> _menuWidthAnim;
  bool _wasOnline = true;
  List<_NavItem> _visibleItems = _allNavItems; // Memoize: her build'de yeniden hesaplanmaz

  static const double _menuExpandedWidth = 220;
  static const double _menuCollapsedWidth = 68;

  bool get _menuExpanded => _menuAnimCtrl.value > 0.5;
  bool get _menuFullyExpanded => _menuAnimCtrl.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    _menuAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0, // başlangıçta açık
    );
    _menuWidthAnim = Tween<double>(
      begin: _menuCollapsedWidth,
      end: _menuExpandedWidth,
    ).animate(CurvedAnimation(parent: _menuAnimCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webSocketProvider).connect();
      CartTransferService.instance.start(ref);
      VersionCheckService.checkForUpdates(context);
      // İlk yükleme sonrası görünür menü öğelerini hesapla
      if (mounted) setState(() => _visibleItems = _getVisibleItems());
    });
    // Auth değişince (izin güncelleme vb.) menü öğelerini yenile
    ref.listenManual(authProvider, (_, __) {
      if (mounted) setState(() => _visibleItems = _getVisibleItems());
    });
  }

  @override
  void dispose() {
    _menuAnimCtrl.dispose();
    CartTransferService.instance.stop();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuAnimCtrl.isCompleted) {
      _menuAnimCtrl.reverse();
    } else {
      _menuAnimCtrl.forward();
    }
  }

  void _manageOfflineTimer(bool isOnline) {
    _wasOnline = isOnline;
  }

  List<_NavItem> _getVisibleItems() {
    final authState = ref.read(authProvider);
    final user = authState.currentUser;
    if (user == null) return _allNavItems;
    return _allNavItems.where((item) => user.hasPermission(item.permKey)).toList();
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    ref.watch(themeProvider);
    final visibleItems = _visibleItems;

    if (_selectedIndex >= visibleItems.length) _selectedIndex = 0;

    _manageOfflineTimer(syncState.isOnline);
    
    // Eşleşme kaldırıldığında AppGate'e tam yönlendir
    if (syncState.pairStatus == 'none' && syncState.serverUrl == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AppGate()),
            (route) => false,
          );
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isDesktop) {
      return _buildDesktopLayout(visibleItems, syncState);
    } else {
      return _buildMobileHomeScreen(visibleItems, syncState);
    }
  }

  // ─── Desktop Layout ──────────────────────────────────────────
  Widget _buildDesktopLayout(List<_NavItem> visibleItems, SyncState syncState) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                // ─── Animated Sidebar ───────────────────────────
                AnimatedBuilder(
                  animation: _menuWidthAnim,
                  builder: (context, _) {
                    final w = _menuWidthAnim.value;
                    final showLabels = _menuFullyExpanded;
                    return Container(
                      width: w,
                      color: AppTheme.panelBackground,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Başlık / hamburger
                          SizedBox(
                            height: 56,
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: AnimatedIcon(
                                    icon: AnimatedIcons.menu_arrow,
                                    progress: _menuAnimCtrl,
                                    color: AppTheme.primaryAccent,
                                  ),
                                  tooltip: showLabels ? 'Menüyü Kapat' : 'Menüyü Aç',
                                  onPressed: _toggleMenu,
                                ),
                                if (showLabels) ...[
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: AnimatedOpacity(
                                      opacity: showLabels ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 150),
                                      child: Text(
                                        'INVENTRA',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2,
                                          color: AppTheme.primaryAccent,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          // Nav items
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: visibleItems.asMap().entries.map((e) =>
                                  _buildDesktopNavItem(e.key, e.value.icon, e.value.title, showLabels)
                                ).toList(),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          // Çıkış butonu
                          SizedBox(
                            height: 48,
                            child: showLabels
                              ? TextButton.icon(
                                  icon: Icon(Icons.logout, color: AppTheme.dangerAccent, size: 18),
                                  label: Text('Çıkış Yap', style: TextStyle(color: AppTheme.dangerAccent, fontSize: 12)),
                                  style: TextButton.styleFrom(shape: const RoundedRectangleBorder()),
                                  onPressed: () async {
                                    await ref.read(authProvider.notifier).logout();
                                    if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                                  },
                                )
                              : IconButton(
                                  icon: Icon(Icons.logout, color: AppTheme.dangerAccent, size: 20),
                                  tooltip: 'Çıkış Yap',
                                  onPressed: () async {
                                    await ref.read(authProvider.notifier).logout();
                                    if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                                  },
                                ),
                          ),
                          // Sunucu durumu
                          _buildSyncStatusIndicator(syncState, showLabels),
                        ],
                      ),
                    );
                  },
                ),
                // ─── Ana İçerik ───────────────────────────────
                Expanded(
                  child: RepaintBoundary(
                    child: Stack(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: visibleItems[_selectedIndex].screen,
                      ),
                      if (!syncState.isOnline)
                        Positioned(
                          top: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerAccent,
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.cloud_off, color: Colors.white, size: 20),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Çevrimdışı Mod - Sadece önbellekten okuma yapılıyor...',
                                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => ref.read(syncProvider.notifier).checkConnection(),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Tekrar Dene'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  ), // RepaintBoundary
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mobile Home Screen ──────────────────────────────────────
  Widget _buildMobileHomeScreen(List<_NavItem> visibleItems, SyncState syncState) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─ Header
                  Row(
                    children: [
                      Image.asset('assets/icons/app_icon.png', width: 36, height: 36,
                        errorBuilder: (_, _, _) => Icon(Icons.store, size: 36, color: AppTheme.primaryAccent)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('INVENTRA', style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: AppTheme.primaryAccent,
                            )),
                            Text('Hoş geldiniz', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      // Connection indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: syncState.isOnline
                              ? AppTheme.secondaryAccent.withOpacity(0.12)
                              : AppTheme.dangerAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              syncState.isOnline ? Icons.cloud_done : Icons.cloud_off,
                              color: syncState.isOnline ? AppTheme.secondaryAccent : AppTheme.dangerAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              syncState.isOnline ? 'Bağlı' : 'Bağlantı Yok',
                              style: TextStyle(
                                color: syncState.isOnline ? AppTheme.secondaryAccent : AppTheme.dangerAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.logout, color: AppTheme.dangerAccent, size: 22),
                        onPressed: () {
                          ref.read(authProvider.notifier).logout();
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ─ Module Grid
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: visibleItems.length,
                      itemBuilder: (ctx, i) {
                        final item = visibleItems[i];
                        return _buildMobileNavCard(item);
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ─ Connection Lost Overlay
            if (!syncState.isOnline)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerAccent,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Çevrimdışı Mod - Sadece önbellek',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(syncProvider.notifier).checkConnection(),
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('Dene', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(60, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileNavCard(_NavItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _MobileScreenWrapper(
              title: item.title,
              child: item.screen,
            ),
          ));
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.panelBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: item.color.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: item.color.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: item.color, size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Desktop nav item ─────────────────────────────────────────
  Widget _buildDesktopNavItem(int index, IconData icon, String title, bool showLabels) {
    final isSelected = _selectedIndex == index;
    return Tooltip(
      message: showLabels ? '' : title,
      preferBelow: false,
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: isSelected ? AppTheme.primaryAccent : Colors.transparent, width: 3)),
            color: isSelected ? AppTheme.primaryAccent.withOpacity(0.1) : Colors.transparent,
          ),
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: showLabels ? 16 : 0),
          child: Row(
            mainAxisAlignment: showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? AppTheme.primaryAccent : AppTheme.textMuted),
              if (showLabels) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: showLabels ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 100),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? AppTheme.textMain : AppTheme.textMuted,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatusIndicator(SyncState syncState, bool showLabels) {
    final isOnline = syncState.isOnline;
    final url = syncState.serverUrl ?? '';
    final shortUrl = url.replaceAll('http://', '').replaceAll('https://', '');
    final statusText = isOnline ? 'Bağlı — $shortUrl' : 'Bağlantı Yok';
    final statusColor = isOnline ? AppTheme.secondaryAccent : AppTheme.dangerAccent;
    final statusIcon = isOnline ? Icons.cloud_done : Icons.cloud_off;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: showLabels ? 16 : 0, vertical: 12),
      child: Column(
        crossAxisAlignment: showLabels ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabels) ...[
            AnimatedOpacity(
              opacity: showLabels ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Text('Sunucu Durumu', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            mainAxisAlignment: showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Tooltip(
                message: statusText,
                child: Icon(statusIcon, size: showLabels ? 14 : 22, color: statusColor),
              ),
              if (showLabels) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: showLabels ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Wrapper for mobile screens that adds an AppBar with back button
class _MobileScreenWrapper extends StatelessWidget {
  final String title;
  final Widget child;
  const _MobileScreenWrapper({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(title, style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: child,
    );
  }
}
