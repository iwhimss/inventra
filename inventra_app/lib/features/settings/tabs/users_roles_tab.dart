import 'package:inventra_app/core/services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:inventra_app/core/utils/responsive_utils.dart';

/// Uygulama içi (bu dosya) ve web admin panelindeki (`admin_handler.dart` →
/// `_permLabels`) izin anahtarlarıyla birebir eşleşir.
const Map<String, String> _kPermLabels = {
  'pos': 'Satış Ekranı (POS)',
  'products': 'Ürün Yönetimi',
  'history': 'Geçmiş İşlemler',
  'reports': 'Raporlar ve Analiz',
  'labels': 'Etiket Tasarımı',
  'settings': 'Ayarlar',
  'converter': 'Dönüştürücü',
  'movements': 'Hareketler',
  'clients': 'Müşteri/Tedarikçi',
  'modules': 'Modüller',
};

Map<String, bool> _staffDefaultPerms() => {
      for (final k in _kPermLabels.keys) k: false,
    }..['pos'] = true;

List<Widget> _buildPermCheckboxes(Map<String, bool> perms, void Function(VoidCallback) setStateFn) {
  return _kPermLabels.entries.map((e) => CheckboxListTile(
    dense: true, title: Text(e.value, style: const TextStyle(fontSize: 13)), value: perms[e.key] ?? false,
    onChanged: (v) => setStateFn(() => perms[e.key] = v ?? false),
  )).toList();
}

class UsersRolesTab extends ConsumerStatefulWidget {
  const UsersRolesTab({super.key});

  @override
  ConsumerState<UsersRolesTab> createState() => _UsersRolesTabState();
}

class _UsersRolesTabState extends ConsumerState<UsersRolesTab> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];
  bool _isLoading = true;
  bool _showRolesPanel = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final usersResp = await ApiClient.instance.get('/api/users');
      if (usersResp.success) _users = List<Map<String, dynamic>>.from(usersResp.dataList);
      
      final rolesResp = await ApiClient.instance.get('/api/roles');
      if (rolesResp.success) _roles = List<Map<String, dynamic>>.from(rolesResp.dataList);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  String _getUserName(Map<String, dynamic> user) {
    if (user['name'] != null && user['name'].toString().isNotEmpty) return user['name'].toString();
    return '';
  }

  Future<String?> _askSavePath(String defaultName) async {
    final db = await DatabaseHelper.instance.globalDb;
    final r = await db.query('settings', where: "key='save_root_path'");
    String root = r.isNotEmpty ? (r.first['value']?.toString() ?? '') : '';
    if (root.isNotEmpty) {
      final dir = Directory('$root/Kullanicilar');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return '${dir.path}/$defaultName';
    }
    return await FilePicker.platform.saveFile(dialogTitle: 'Kaydet', fileName: defaultName, allowedExtensions: ['json'], type: FileType.custom);
  }

  // --- USERS ---
  Future<void> _exportUsers() async {
    if (_users.isEmpty) return;
    String? savePath = await _askSavePath('kullanicilar_${DateTime.now().millisecondsSinceEpoch}.json');
    if (savePath == null) return;
    final data = _users.map((u) => {
      'staff_id': u['staff_id'],
      'name': u['name'],
      'password_hash': u['password_hash'],
      'role': u['role'],
      'permissions': u['permissions'],
    }).toList();
    await File(savePath).writeAsString(json.encode(data));
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('${_users.length} kullanıcı dışa aktarıldı.');
    }
  }

  Future<void> _importUsers() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.path == null) return;
    final content = File(result.files.single.path!).readAsStringSync();
    final List<dynamic> data = json.decode(content);

    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Kullanıcı İçe Aktarımı'),
      content: Text('${data.length} kullanıcı bulundu. İçe aktarmak istediğinize emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İÇE AKTAR')),
      ],
    ));
    if (confirm != true) return;

    int added = 0;
    for (var item in data) {
      try {
        await ApiClient.instance.post('/api/users', {
          'staff_id': item['staff_id'],
          'name': item['name'] ?? '',
          'password_hash': item['password_hash'] ?? '1234',
          'role': item['role'] ?? 'staff',
          'permissions': item['permissions'] ?? '{}',
        });
        added++;
      } catch (_) {}
    }
    await _loadAll();
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('$added kullanıcı eklendi.');
    }
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddUserDialog(existingRoles: _roles, onSaved: _loadAll),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (_) => _EditUserDialog(user: user, existingRoles: _roles, onSaved: _loadAll),
    );
  }

  // --- ROLES ---
  Future<void> _exportRoles() async {
    if (_roles.isEmpty) return;
    String? savePath = await _askSavePath('roller_${DateTime.now().millisecondsSinceEpoch}.json');
    if (savePath == null) return;
    final data = _roles.map((r) => {'name': r['name'], 'permissions': r['permissions']}).toList();
    await File(savePath).writeAsString(json.encode(data));
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('${_roles.length} rol dışa aktarıldı.');
    }
  }

  Future<void> _importRoles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.path == null) return;
    final content = File(result.files.single.path!).readAsStringSync();
    final List<dynamic> data = json.decode(content);
    
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Rol İçe Aktarımı'),
      content: Text('${data.length} rol bulundu. İçe aktarmak istediğinize emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İÇE AKTAR')),
      ],
    ));
    if (confirm != true) return;
    
    int added = 0;
    for (var item in data) {
      try {
        final resp = await ApiClient.instance.post('/api/roles', {
          'name': item['name'] ?? 'Rol',
          'permissions': item['permissions'] ?? '{}',
        });
        if (resp.success) added++;
      } catch (_) {}
    }
    await _loadAll();
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('$added rol içe aktarıldı.');
    }
  }

  void _showAddRoleDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddRoleDialog(onSaved: _loadAll),
    );
  }

  void _showEditRoleDialog(Map<String, dynamic> role) {
    showDialog(
      context: context,
      builder: (_) => _EditRoleDialog(role: role, onSaved: _loadAll),
    );
  }

  Widget _buildRolesSection() {
    final authState = ref.read(authProvider);
    final isOwner = authState.currentUser?.role == 'owner';
    if (!isOwner) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('Rol yönetimi yalnızca Sahip rolündeki kullanıcılar tarafından yapılabilir.', style: TextStyle(color: AppTheme.textMuted)),
      ));
    }
    return Column(
      children: [
        const SizedBox(height: 4),
        Expanded(
          child: _roles.isEmpty
            ? Center(child: Text('Özel rol tanımlanmamış. Varsayılan roller: Sahip, Yönetici, Personel', style: TextStyle(color: AppTheme.textMuted)))
            : ListView.separated(
                itemCount: _roles.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.borderBright),
                itemBuilder: (context, i) {
                  final r = _roles[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.warningAccent.withOpacity(0.1),
                      child: Icon(Icons.shield, color: AppTheme.warningAccent, size: 20),
                    ),
                    title: Text(r['name']?.toString() ?? 'Rol', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Oluşturulma: ${r['created_at']?.toString().substring(0, 10) ?? '-'}', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    trailing: IconButton(
                      icon: Icon(Icons.edit, color: AppTheme.primaryAccent, size: 20),
                      onPressed: () => _showEditRoleDialog(r),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${_users.length} Kullanıcı', style: TextStyle(color: AppTheme.textMuted)),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showRolesPanel = !_showRolesPanel),
              icon: Icon(_showRolesPanel ? Icons.people : Icons.shield, size: 16),
              label: Text(_showRolesPanel ? 'Kullanıcılar' : 'Roller (${_roles.length})'),
            ),
            OutlinedButton.icon(onPressed: _showRolesPanel ? _exportRoles : _exportUsers, icon: const Icon(Icons.file_upload, size: 16), label: const Text('Dışa Aktar')),
            OutlinedButton.icon(onPressed: _showRolesPanel ? _importRoles : _importUsers, icon: const Icon(Icons.file_download, size: 16), label: const Text('İçe Aktar')),
            ElevatedButton.icon(
              onPressed: _showRolesPanel ? _showAddRoleDialog : _showAddUserDialog,
              icon: Icon(_showRolesPanel ? Icons.add : Icons.person_add, size: 18),
              label: Text(_showRolesPanel ? 'Yeni Rol' : 'Yeni Kullanıcı'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _showRolesPanel
            ? _buildRolesSection()
            : _users.isEmpty
              ? Center(child: Text('Henüz kullanıcı yok. Default giriş: ID 1000, Şifre 1234', style: TextStyle(color: AppTheme.textMuted)))
              : ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.borderBright),
                  itemBuilder: (context, i) {
                    final u = _users[i];
                    final role = u['role']?.toString() ?? 'staff';
                    final name = _getUserName(u);
                    
                    String roleLabel;
                    if (role == 'owner') {
                      roleLabel = 'Sahip';
                    } else if (role == 'manager') {
                      roleLabel = 'Yönetici';
                    } else if (role.startsWith('custom_')) {
                      final roleId = role.replaceFirst('custom_', '');
                      final matched = _roles.firstWhere((r) => r['id']?.toString() == roleId, orElse: () => <String, dynamic>{});
                      roleLabel = matched.isNotEmpty ? matched['name']?.toString() ?? 'Özel Rol' : 'Özel Rol';
                    } else {
                      roleLabel = 'Personel';
                    }
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: role == 'owner' || role == 'manager' ? AppTheme.primaryAccent.withOpacity(0.1) : role.startsWith('custom_') ? AppTheme.warningAccent.withOpacity(0.1) : AppTheme.secondaryAccent.withOpacity(0.1),
                        child: Icon(
                          role == 'owner' ? Icons.admin_panel_settings : role == 'manager' ? Icons.manage_accounts : role.startsWith('custom_') ? Icons.shield : Icons.person,
                          color: role == 'owner' || role == 'manager' ? AppTheme.primaryAccent : role.startsWith('custom_') ? AppTheme.warningAccent : AppTheme.secondaryAccent,
                          size: 20,
                        ),
                      ),
                      title: Text(name.isNotEmpty ? name : 'ID: ${u['staff_id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Personel ID: ${u['staff_id']} • $roleLabel', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      trailing: IconButton(
                        icon: Icon(Icons.edit, color: AppTheme.primaryAccent, size: 20),
                        onPressed: () => _showEditUserDialog(u),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Kullanıcı/Rol Ekle-Düzenle Dialogları ────────────────────────────────
// v0.2.2: Bu 4 dialog daha önce showDialog+StatefulBuilder içinde, dış
// metodun yerel değişkenlerini (`role`, `perms`) yakalayan mutable closure'lar
// olarak yazılıyordu. Bu desen kırılgan olduğu ve teşhisi zor bir
// StackOverflowError'a yol açtığı için (bkz. .plan/v0.2.2.md), state'i kendi
// State sınıflarının instance alanlarında tutan gerçek StatefulWidget'lara
// dönüştürüldü.

String _roleForUser(Map<String, dynamic> user, List<Map<String, dynamic>> existingRoles) {
  final rawRole = user['role']?.toString() ?? 'staff';
  if (['owner', 'manager', 'staff'].contains(rawRole)) return rawRole;
  if (rawRole.startsWith('custom_')) {
    final roleId = rawRole.replaceFirst('custom_', '');
    final exists = existingRoles.any((r) => r['id']?.toString() == roleId);
    return exists ? rawRole : 'staff';
  }
  return 'staff';
}

Map<String, bool> _permsForRoleChange(String role, List<Map<String, dynamic>> existingRoles, Map<String, bool> current) {
  if (role == 'owner' || role == 'manager') {
    return current.map((k, _) => MapEntry(k, true));
  } else if (role.startsWith('custom_')) {
    final roleId = role.replaceFirst('custom_', '');
    final matchedRole = existingRoles.firstWhere((r) => r['id']?.toString() == roleId, orElse: () => <String, dynamic>{});
    if (matchedRole.isEmpty) return current;
    try {
      final rolePerms = json.decode(matchedRole['permissions']?.toString() ?? '{}') as Map<String, dynamic>;
      return current.map((k, _) => MapEntry(k, rolePerms[k] == true));
    } catch (_) {
      return current;
    }
  }
  return _staffDefaultPerms();
}

Widget _roleDropdown({
  required String value,
  required List<Map<String, dynamic>> existingRoles,
  required ValueChanged<String> onChanged,
}) {
  return DropdownButtonFormField<String>(
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Rol'),
    dropdownColor: AppTheme.panelBackground,
    style: TextStyle(color: AppTheme.textMain),
    items: [
      DropdownMenuItem(value: 'owner', child: Text('Sahip', style: TextStyle(color: AppTheme.textMain))),
      DropdownMenuItem(value: 'manager', child: Text('Yönetici', style: TextStyle(color: AppTheme.textMain))),
      DropdownMenuItem(value: 'staff', child: Text('Personel', style: TextStyle(color: AppTheme.textMain))),
      ...existingRoles.map((r) => DropdownMenuItem(value: 'custom_${r['id']}', child: Text(r['name']?.toString() ?? '', style: TextStyle(color: AppTheme.textMain)))),
    ],
    onChanged: (v) => onChanged(v ?? 'staff'),
  );
}

class _AddUserDialog extends StatefulWidget {
  final List<Map<String, dynamic>> existingRoles;
  final Future<void> Function() onSaved;
  const _AddUserDialog({required this.existingRoles, required this.onSaved});

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _staffIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'staff';
  late Map<String, bool> _perms = _staffDefaultPerms();

  @override
  void dispose() {
    _staffIdCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_staffIdCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) return;
    try {
      final resp = await ApiClient.instance.post('/api/users', {
        'staff_id': _staffIdCtrl.text,
        'name': _nameCtrl.text,
        'password_hash': _passwordCtrl.text,
        'role': _role,
        'permissions': json.encode(_perms),
      });
      if (!resp.success) throw Exception(resp.error ?? 'API Hatası');
      if (mounted) Navigator.pop(context);
      await widget.onSaved();
    } catch (e) {
      if (mounted) NotificationService.showError('Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.panelBackground,
      title: const Text('Yeni Kullanıcı'),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Ad Soyad')),
            const SizedBox(height: 12),
            TextField(controller: _staffIdCtrl, decoration: const InputDecoration(labelText: 'Personel ID'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 12),
            TextField(controller: _passwordCtrl, decoration: const InputDecoration(labelText: 'Şifre'), obscureText: true),
            const SizedBox(height: 12),
            _roleDropdown(
              value: _role,
              existingRoles: widget.existingRoles,
              onChanged: (v) => setState(() {
                _role = v;
                _perms = _permsForRoleChange(_role, widget.existingRoles, _perms);
              }),
            ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('Yetkiler:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ..._buildPermCheckboxes(_perms, setState),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
        ElevatedButton(onPressed: _save, child: const Text('EKLE')),
      ],
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> existingRoles;
  final Future<void> Function() onSaved;
  const _EditUserDialog({required this.user, required this.existingRoles, required this.onSaved});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _passwordCtrl = TextEditingController();
  late final _nameCtrl = TextEditingController(text: widget.user['name']?.toString() ?? '');
  late final _staffIdCtrl = TextEditingController(text: widget.user['staff_id']?.toString() ?? '');
  late String _role = _roleForUser(widget.user, widget.existingRoles);
  late Map<String, bool> _perms = _parseInitialPerms();

  Map<String, bool> _parseInitialPerms() {
    final basePerms = {for (final k in _kPermLabels.keys) k: false};
    try {
      final rawPerms = widget.user['permissions'];
      if (rawPerms is Map) {
        final parsed = Map<String, dynamic>.from(rawPerms).map((k, v) => MapEntry(k, v == true));
        return {...basePerms, ...parsed};
      } else if ((rawPerms?.toString() ?? '').startsWith('{')) {
        final parsed = (json.decode(rawPerms.toString()) as Map<String, dynamic>).map((k, v) => MapEntry(k, v == true));
        return {...basePerms, ...parsed};
      } else {
        final isPriv = _role == 'owner' || _role == 'manager';
        return {...basePerms, for (final k in basePerms.keys) k: k == 'pos' ? true : isPriv};
      }
    } catch (_) {
      return basePerms;
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _staffIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Sil?'),
      content: Text('${widget.user['staff_id']} silinecek. Emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hayır')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent), child: const Text('SİL')),
      ],
    ));
    if (confirm != true) return;
    final resp = await ApiClient.instance.delete('/api/users/${widget.user['id']}');
    if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
    if (mounted) Navigator.pop(context);
    await widget.onSaved();
  }

  Future<void> _save() async {
    final Map<String, dynamic> data = {
      'name': _nameCtrl.text,
      'role': _role,
      'permissions': json.encode(_perms),
    };
    if (_passwordCtrl.text.isNotEmpty) data['password_hash'] = _passwordCtrl.text;

    final resp = await ApiClient.instance.put('/api/users/${widget.user['id']}', data);
    if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
    if (mounted) Navigator.pop(context);
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.panelBackground,
      title: Text('Kullanıcı Düzenle: ${widget.user['staff_id']}'),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Ad Soyad')),
            const SizedBox(height: 12),
            TextField(controller: _staffIdCtrl, decoration: const InputDecoration(labelText: 'Personel ID'), readOnly: true),
            const SizedBox(height: 12),
            TextField(controller: _passwordCtrl, decoration: const InputDecoration(labelText: 'Yeni Şifre (boş = değişmez)'), obscureText: true),
            const SizedBox(height: 12),
            _roleDropdown(
              value: _role,
              existingRoles: widget.existingRoles,
              onChanged: (v) => setState(() {
                _role = v;
                _perms = _permsForRoleChange(_role, widget.existingRoles, _perms);
              }),
            ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('Yetkiler:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ..._buildPermCheckboxes(_perms, setState),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: _delete, child: Text('SİL', style: TextStyle(color: AppTheme.dangerAccent))),
        const Spacer(),
        TextButton(onPressed: () => Navigator.pop(context), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
        ElevatedButton(onPressed: _save, child: const Text('GÜNCELLE')),
      ],
    );
  }
}

class _AddRoleDialog extends StatefulWidget {
  final Future<void> Function() onSaved;
  const _AddRoleDialog({required this.onSaved});

  @override
  State<_AddRoleDialog> createState() => _AddRoleDialogState();
}

class _AddRoleDialogState extends State<_AddRoleDialog> {
  final _nameCtrl = TextEditingController();
  late Map<String, bool> _perms = _staffDefaultPerms();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty) return;
    try {
      final resp = await ApiClient.instance.post('/api/roles', {
        'name': _nameCtrl.text,
        'permissions': json.encode(_perms),
      });
      if (!resp.success) throw Exception(resp.error ?? 'API Hatası');
      if (mounted) Navigator.pop(context);
      await widget.onSaved();
      SoundService.playNotification();
      NotificationService.showSuccess('Rol "${_nameCtrl.text}" oluşturuldu.');
    } catch (e) {
      if (mounted) NotificationService.showError('Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.panelBackground,
      title: const Text('Yeni Rol'),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Rol Adı')),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('Yetkiler:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ..._buildPermCheckboxes(_perms, setState),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
        ElevatedButton(onPressed: _save, child: const Text('EKLE')),
      ],
    );
  }
}

class _EditRoleDialog extends StatefulWidget {
  final Map<String, dynamic> role;
  final Future<void> Function() onSaved;
  const _EditRoleDialog({required this.role, required this.onSaved});

  @override
  State<_EditRoleDialog> createState() => _EditRoleDialogState();
}

class _EditRoleDialogState extends State<_EditRoleDialog> {
  late final _nameCtrl = TextEditingController(text: widget.role['name']?.toString() ?? '');
  late Map<String, bool> _perms = _parseInitialPerms();

  Map<String, bool> _parseInitialPerms() {
    final basePerms = {for (final k in _kPermLabels.keys) k: false}..['pos'] = true;
    try {
      final raw = widget.role['permissions'];
      final Map<String, dynamic> decoded;
      if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      } else {
        final str = raw?.toString() ?? '{}';
        decoded = str.isEmpty ? {} : (json.decode(str) as Map<String, dynamic>);
      }
      return {...basePerms, ...decoded.map((k, v) => MapEntry(k, v == true))};
    } catch (_) {
      return basePerms;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Rolü Sil?'),
      content: Text('"${widget.role['name']}" silinecek. Emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hayır')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent), child: const Text('SİL')),
      ],
    ));
    if (confirm != true) return;
    final resp = await ApiClient.instance.delete('/api/roles/${widget.role['id']}');
    if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
    if (mounted) Navigator.pop(context);
    await widget.onSaved();
  }

  Future<void> _save() async {
    final resp = await ApiClient.instance.put('/api/roles/${widget.role['id']}', {'name': _nameCtrl.text, 'permissions': json.encode(_perms)});
    if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
    if (mounted) Navigator.pop(context);
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.panelBackground,
      title: Text('Rol Düzenle: ${widget.role['name']}'),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Rol Adı')),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('Yetkiler:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ..._buildPermCheckboxes(_perms, setState),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: _delete, child: Text('SİL', style: TextStyle(color: AppTheme.dangerAccent))),
        const Spacer(),
        TextButton(onPressed: () => Navigator.pop(context), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
        ElevatedButton(onPressed: _save, child: const Text('GÜNCELLE')),
      ],
    );
  }
}
