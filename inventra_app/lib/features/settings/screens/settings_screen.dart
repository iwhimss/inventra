import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/features/settings/tabs/app_settings_tab.dart';
import 'package:inventra_app/features/settings/tabs/server_settings_tab.dart';
import 'package:inventra_app/features/settings/tabs/users_roles_tab.dart';
import 'package:inventra_app/features/settings/tabs/sync_settings_tab.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const SettingsScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Container(
      color: AppTheme.darkBackground,
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Text('Ayarlar', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Uygulama'),
                Tab(text: 'İşletme & Sunucu'),
                Tab(text: 'Kullanıcılar & Roller'),
                Tab(text: 'Senkronizasyon'),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Text('Ayarlar', style: Theme.of(context).textTheme.displayLarge),
                const SizedBox(width: 24),
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    labelStyle: const TextStyle(fontSize: 13),
                    tabs: const [
                      Tab(text: 'Uygulama'),
                      Tab(text: 'İşletme & Sunucu'),
                      Tab(text: 'Kullanıcılar & Roller'),
                      Tab(text: 'Senkronizasyon'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                AppSettingsTab(),
                ServerSettingsTab(),
                UsersRolesTab(),
                SyncSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
