import 'package:flutter/material.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/network/api_client.dart';

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  List<Map<String, dynamic>> _activityLogs = [];
  List<Map<String, dynamic>> _stockLogs = [];
  bool _isLoading = true;

  // Filters
  String? _selectedCategory; // null = Tümü
  String? _selectedUser;

  // Merged & sorted unified list
  List<Map<String, dynamic>> _unified = [];
  List<String> _users = [];

  static const _categories = [
    _Category(null, 'Tümü', Icons.list_alt),
    _Category('auth', 'Giriş/Çıkış', Icons.login),
    _Category('sales', 'Satışlar', Icons.shopping_cart),
    _Category('products', 'Ürünler', Icons.inventory_2),
    _Category('stock', 'Stok', Icons.equalizer),
    _Category('customers', 'Müşteriler', Icons.person),
    _Category('suppliers', 'Tedarikçiler', Icons.local_shipping),
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/logs/activity?limit=500'),
        ApiClient.instance.get('/api/logs/stock?limit=500'),
      ]);

      _activityLogs = results[0].success && results[0].data?['data'] != null
          ? List<Map<String, dynamic>>.from(results[0].data!['data'])
          : [];
      _stockLogs = results[1].success && results[1].data?['data'] != null
          ? List<Map<String, dynamic>>.from(results[1].data!['data'])
          : [];
    } catch (_) {
      _activityLogs = [];
      _stockLogs = [];
    }
    _buildUnified();
    if (mounted) setState(() => _isLoading = false);
  }

  void _buildUnified() {
    final list = <Map<String, dynamic>>[];
    for (final a in _activityLogs) {
      list.add({...a, '_type': 'activity'});
    }
    for (final s in _stockLogs) {
      list.add({...s, '_type': 'stock', 'action': 'stock_update'});
    }
    list.sort((a, b) {
      final aDate = a['created_at']?.toString() ?? '';
      final bDate = b['created_at']?.toString() ?? '';
      return bDate.compareTo(aDate);
    });
    _unified = list;

    final userSet = <String>{};
    for (final e in list) {
      final u = e['user_name']?.toString();
      if (u != null && u.isNotEmpty && u != 'Sistem') userSet.add(u);
    }
    _users = userSet.toList()..sort();
  }

  List<Map<String, dynamic>> get _filtered {
    return _unified.where((e) {
      if (_selectedUser != null && e['user_name']?.toString() != _selectedUser) return false;
      if (_selectedCategory == null) return true;
      return _actionMatchesCategory(e['action']?.toString() ?? '', _selectedCategory!);
    }).toList();
  }

  bool _actionMatchesCategory(String action, String cat) {
    switch (cat) {
      case 'auth': return action == 'user_login' || action == 'user_logout';
      case 'sales': return action == 'sale_create' || action == 'sale_delete';
      case 'products': return action.startsWith('product_');
      case 'stock': return action == 'stock_update';
      case 'customers': return action == 'customer_add' || action == 'customer_delete';
      case 'suppliers': return action == 'supplier_add' || action == 'supplier_delete';
      default: return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.panelBackground,
        title: const Text('Hareketler'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loadAll,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: AppTheme.panelBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: Icon(cat.icon, size: 14,
                        color: isSelected ? AppTheme.primaryAccent : AppTheme.textMuted),
                    label: Text(cat.label, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryAccent.withOpacity(0.15),
                    checkmarkColor: AppTheme.primaryAccent,
                    onSelected: (_) => setState(() => _selectedCategory = cat.key),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_users.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Text('Kullanıcı:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedUser,
                    isDense: true,
                    dropdownColor: AppTheme.panelBackground,
                    style: TextStyle(color: AppTheme.textMain, fontSize: 12),
                    icon: Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textMuted),
                    hint: Text('Tümü', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tümü', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      ),
                      ..._users.map((u) => DropdownMenuItem<String?>(
                            value: u,
                            child: Text(u, style: const TextStyle(fontSize: 12)),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedUser = v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: AppTheme.textMuted.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('Hareket kaydı bulunamadı.', style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final e = items[i];
          return e['_type'] == 'stock' ? _buildStockCard(e) : _buildActivityCard(e);
        },
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> e) {
    final action = e['action']?.toString() ?? '';
    final icon = _actionIcon(action);
    final color = _actionColor(action);
    final label = _actionLabel(action);
    final description = e['description']?.toString() ?? '';
    final userName = e['user_name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(label,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color))),
                  Text(_formatDate(e['created_at']?.toString() ?? ''),
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(description, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ],
                if (userName.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.person_outline, size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(userName, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(Map<String, dynamic> e) {
    final change = (e['change_amount'] as num?)?.toInt() ?? 0;
    final isPositive = change >= 0;
    final color = isPositive ? AppTheme.secondaryAccent : AppTheme.dangerAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(e['product_name']?.toString() ?? 'Ürün',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${isPositive ? '+' : ''}$change',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text('${e['old_stock']} → ${e['new_stock']}  •  ${e['reason'] ?? ''}',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 2),
                Row(children: [
                  if ((e['user_name']?.toString() ?? '').isNotEmpty) ...[
                    Icon(Icons.person_outline, size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(e['user_name'].toString(),
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    const SizedBox(width: 8),
                  ],
                  Text(_formatDate(e['created_at']?.toString() ?? ''),
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'user_login': return Icons.login;
      case 'user_logout': return Icons.logout;
      case 'sale_create': return Icons.shopping_cart;
      case 'sale_delete': return Icons.remove_shopping_cart;
      case 'product_add': return Icons.add_box;
      case 'product_update': return Icons.edit;
      case 'product_delete': return Icons.delete;
      case 'customer_add': return Icons.person_add;
      case 'customer_delete': return Icons.person_remove;
      case 'supplier_add': return Icons.add_business;
      case 'supplier_delete': return Icons.remove_circle_outline;
      case 'shift_open': return Icons.lock_open;
      case 'shift_close': return Icons.lock;
      case 'backup_create': return Icons.backup;
      default: return Icons.info_outline;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'user_login':
      case 'user_logout': return AppTheme.primaryAccent;
      case 'sale_create':
      case 'product_add':
      case 'customer_add':
      case 'supplier_add':
      case 'shift_open': return AppTheme.secondaryAccent;
      case 'sale_delete':
      case 'product_delete':
      case 'customer_delete':
      case 'supplier_delete': return AppTheme.dangerAccent;
      case 'product_update':
      case 'shift_close': return AppTheme.warningAccent;
      default: return AppTheme.textMuted;
    }
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'user_login': return 'Giriş Yapıldı';
      case 'user_logout': return 'Çıkış Yapıldı';
      case 'sale_create': return 'Satış Tamamlandı';
      case 'sale_delete': return 'Satış Silindi';
      case 'product_add': return 'Ürün Eklendi';
      case 'product_update': return 'Ürün Güncellendi';
      case 'product_delete': return 'Ürün Silindi';
      case 'customer_add': return 'Müşteri Eklendi';
      case 'customer_delete': return 'Müşteri Silindi';
      case 'supplier_add': return 'Tedarikçi Eklendi';
      case 'supplier_delete': return 'Tedarikçi Silindi';
      case 'shift_open': return 'Kasa Açıldı';
      case 'shift_close': return 'Kasa Kapatıldı';
      case 'backup_create': return 'Yedek Alındı';
      case 'stock_update': return 'Stok Güncellendi';
      default: return action;
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _Category {
  final String? key;
  final String label;
  final IconData icon;
  const _Category(this.key, this.label, this.icon);
}
