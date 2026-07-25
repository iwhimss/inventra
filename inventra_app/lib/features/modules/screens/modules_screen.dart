import 'package:flutter/material.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/features/modules/screens/price_update_screen.dart';

class _ModuleDef {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final WidgetBuilder builder;
  const _ModuleDef({required this.icon, required this.title, required this.subtitle, required this.color, required this.builder});
}

/// Ek sistemler/modüller için genişleyebilir ana sayfa. Yeni bir modül
/// eklemek için buraya yeni bir [_ModuleDef] eklemek yeterli.
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  static final List<_ModuleDef> _modules = [
    _ModuleDef(
      icon: Icons.calculate_outlined,
      title: 'Fiyat Güncelleme',
      subtitle: 'İskonto, KDV ve kâr oranına göre yeni satış fiyatı hesapla',
      color: AppTheme.primaryAccent,
      builder: (_) => const PriceUpdateScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      color: AppTheme.darkBackground,
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modüller', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: isMobile ? 20 : null)),
          const SizedBox(height: 8),
          Text('Ek sistemler ve yardımcı araçlar.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              itemCount: _modules.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: 130,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (ctx, i) {
                final m = _modules[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: m.builder)),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.panelBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderBright),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(m.icon, color: m.color, size: 28),
                        const SizedBox(height: 10),
                        Text(m.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textMain)),
                        const SizedBox(height: 4),
                        Text(m.subtitle, style: TextStyle(color: AppTheme.textMuted, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
