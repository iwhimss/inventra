import 'package:inventra_app/core/services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/features/product/providers/product_provider.dart';
import 'package:inventra_app/features/receipt/services/pdf_service.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:sqflite/sqflite.dart';

// Label element model
class LabelElement {
  String type; // 'name', 'barcode', 'price'
  bool visible;
  double x, y, fontSize;
  bool bold;
  String alignment; // 'left', 'center', 'right'
  String fontFamily; // 'inter', 'roboto', 'robotoMono', 'serif'

  LabelElement({
    required this.type,
    this.visible = true,
    this.x = 0,
    this.y = 0,
    this.fontSize = 10,
    this.bold = false,
    this.alignment = 'left',
    this.fontFamily = 'inter',
  });

  Map<String, dynamic> toJson() => {
    'type': type, 'visible': visible, 'x': x, 'y': y,
    'fontSize': fontSize, 'bold': bold, 'alignment': alignment, 'fontFamily': fontFamily,
  };

  factory LabelElement.fromJson(Map<String, dynamic> json) => LabelElement(
    type: json['type'], visible: json['visible'] ?? true,
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 10,
    bold: json['bold'] ?? false,
    alignment: json['alignment'] ?? 'left',
    fontFamily: json['fontFamily'] ?? 'inter',
  );
}

class LabelTemplate {
  String id;
  String name;
  double width, height;
  List<LabelElement> elements;
  DateTime createdAt;

  LabelTemplate({
    required this.id,
    required this.name,
    this.width = 50,
    this.height = 30,
    List<LabelElement>? elements,
    DateTime? createdAt,
  }) : elements = elements ?? [
    LabelElement(type: 'name', x: 2, y: 2, fontSize: 9, bold: true, alignment: 'center'),
    LabelElement(type: 'barcode', x: 2, y: 14, fontSize: 8, alignment: 'center'),
    LabelElement(type: 'price', x: 2, y: 22, fontSize: 12, bold: true, alignment: 'center'),
  ], createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'width': width, 'height': height,
    'elements': elements.map((e) => e.toJson()).toList(),
  };

  factory LabelTemplate.fromJson(Map<String, dynamic> json) => LabelTemplate(
    id: json['id'] ?? const Uuid().v4(),
    name: json['name'] ?? 'İsimsiz',
    width: (json['width'] as num?)?.toDouble() ?? 50,
    height: (json['height'] as num?)?.toDouble() ?? 30,
    elements: (json['elements'] as List?)?.map((e) => LabelElement.fromJson(e)).toList(),
    createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
  );
}

class LabelDesignerScreen extends ConsumerStatefulWidget {
  const LabelDesignerScreen({super.key});

  @override
  ConsumerState<LabelDesignerScreen> createState() => _LabelDesignerScreenState();
}

class _LabelDesignerScreenState extends ConsumerState<LabelDesignerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<LabelTemplate> _templates = [];
  LabelTemplate? _activeTemplate;
  LabelElement? _selectedElement;
  final Map<String, int> _selectedProducts = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _widthCtrl = TextEditingController(text: '50');
  final TextEditingController _heightCtrl = TextEditingController(text: '30');
  final TextEditingController _templateNameCtrl = TextEditingController();
  double _zoom = 1.0;

  static const _fontOptions = {
    'inter': 'Inter',
    'roboto': 'Roboto',
    'robotoMono': 'Roboto Mono',
    'serif': 'Serif',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTemplates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _templateNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    List<Map<String, dynamic>> results = [];
    
    // Tüm platformlar: önce API'den yükle, başarısızsa cache'den
    try {
      final resp = await ApiClient.instance.get('/api/label-templates');
      if (resp.success) {
        results = List<Map<String, dynamic>>.from(resp.dataList);
        // Cache'e kaydet
        try {
          final db = await DatabaseHelper.instance.database;
          await db.transaction((txn) async {
            await txn.delete('label_templates');
            for (var r in results) {
              final map = Map<String, dynamic>.from(r);
              final validCols = {'id', 'name', 'config', 'created_at'};
              map.removeWhere((key, _) => !validCols.contains(key));
              if (map.isNotEmpty) await txn.insert('label_templates', map, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });
        } catch (_) {}
      } else {
        // API başarısız — cache fallback
        final db = await DatabaseHelper.instance.database;
        results = await db.query('label_templates', orderBy: 'created_at DESC');
      }
    } catch (_) {
      // Bağlantı hatası — cache fallback
      try {
        final db = await DatabaseHelper.instance.database;
        results = await db.query('label_templates', orderBy: 'created_at DESC');
      } catch (_) {}
    }
    
    setState(() {
      _templates = results.map((r) {
        final config = jsonDecode(r['config'] as String);
        return LabelTemplate.fromJson({...config, 'id': r['id'], 'createdAt': r['created_at']});
      }).toList();
    });
  }

  Future<void> _saveTemplate() async {
    if (_activeTemplate == null) return;
    _activeTemplate!.name = _templateNameCtrl.text.isNotEmpty ? _templateNameCtrl.text : 'İsimsiz';
    final configJson = jsonEncode(_activeTemplate!.toJson());
    
    // API'ye gönder
    try {
      await ApiClient.instance.post('/api/label-templates', {
        'id': _activeTemplate!.id,
        'name': _activeTemplate!.name,
        'config': configJson,
        'created_at': _activeTemplate!.createdAt.toIso8601String(),
      });
    } catch (_) {}
    
    // Cache'e de kaydet
    try {
      final db = await DatabaseHelper.instance.database;
      await db.rawInsert(
        'INSERT OR REPLACE INTO label_templates (id, name, config, created_at) VALUES (?, ?, ?, ?)',
        [_activeTemplate!.id, _activeTemplate!.name, configJson, _activeTemplate!.createdAt.toIso8601String()],
      );
    } catch (_) {}
    
    await _loadTemplates();
    if (mounted) NotificationService.showSuccess('"${_activeTemplate!.name}" kaydedildi.');
  }

  void _newTemplate() {
    final template = LabelTemplate(id: const Uuid().v4(), name: 'Yeni Şablon ${_templates.length + 1}');
    setState(() {
      _activeTemplate = template;
      _selectedElement = null;
      _templateNameCtrl.text = template.name;
      _widthCtrl.text = template.width.toString();
      _heightCtrl.text = template.height.toString();
    });
  }

  void _selectTemplate(LabelTemplate t) {
    setState(() {
      _activeTemplate = t;
      _selectedElement = null;
      _templateNameCtrl.text = t.name;
      _widthCtrl.text = t.width.toString();
      _heightCtrl.text = t.height.toString();
    });
  }

  Future<void> _deleteTemplate(LabelTemplate t) async {
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Şablonu Sil'),
      content: Text('"${t.name}" silinecek. Emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent), child: const Text('SİL')),
      ],
    ));
    if (confirm != true) return;

    // API'den sil
    try {
      await ApiClient.instance.delete('/api/label-templates/${t.id}');
    } catch (_) {}
    
    // Cache'den de sil
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('label_templates', where: 'id = ?', whereArgs: [t.id]);
    } catch (_) {}
    
    if (_activeTemplate?.id == t.id) { _activeTemplate = null; _templateNameCtrl.clear(); }
    await _loadTemplates();
  }

  Future<void> _exportTemplates() async {
    if (_templates.isEmpty) return;
    final gDb = await DatabaseHelper.instance.globalDb;
    final dbCheck = await gDb.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
    String? rootPath = (dbCheck.isNotEmpty && dbCheck.first['value'].toString().isNotEmpty) ? dbCheck.first['value'].toString() : null;

    String path = '';
    if (rootPath != null) {
      final dir = Directory('$rootPath/Sablonlar');
      if (!await dir.exists()) await dir.create(recursive: true);
      path = dir.path;
    } else {
      String? sp = await FilePicker.platform.getDirectoryPath();
      if (sp == null) return;
      path = sp;
    }
    
    final data = _templates.map((t) => t.toJson()).toList();
    await File('$path/inventra_etiket_sablonlari.json').writeAsString(jsonEncode(data));
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('${_templates.length} şablon $path/inventra_etiket_sablonlari.json konumuna aktarıldı.');
    }
  }

  Future<void> _importTemplates() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.path == null) return;
    final content = File(result.files.single.path!).readAsStringSync();
    final List<dynamic> data = jsonDecode(content);

    // Confirmation dialog
    if (mounted) {
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Şablon İçe Aktarımı'),
        content: Text('${data.length} şablon bulundu. İçe aktarmak istediğinize emin misiniz?\n\nAynı ID ile mevcut şablonlar atlanacaktır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İÇE AKTAR')),
        ],
      ));
      if (confirm != true) return;
    }

    final db = await DatabaseHelper.instance.database;
    int added = 0, skipped = 0;
    for (var item in data) {
      final t = LabelTemplate.fromJson(item);
      final existing = await db.query('label_templates', where: 'id = ?', whereArgs: [t.id]);
      if (existing.isNotEmpty) { skipped++; continue; }
      await db.insert('label_templates', {'id': t.id, 'name': t.name, 'config': jsonEncode(t.toJson()), 'created_at': t.createdAt.toIso8601String()});
      added++;
    }
    await _loadTemplates();
    if (mounted) NotificationService.showSuccess('$added eklendi, $skipped zaten mevcut.');
  }

  void _generateLabels() async {
    if (_selectedProducts.isEmpty || _activeTemplate == null) {
      NotificationService.showError('Lütfen bir şablon ve en az bir ürün seçin.');
      return;
    }
    final products = ref.read(productProvider).value ?? [];
    final showPrice = _activeTemplate!.elements.any((e) => e.type == 'price' && e.visible);

    // Build list of (Product, quantity) entries
    final List<MapEntry<Product, int>> labelsToGenerate = [];
    int totalLabels = 0;
    for (var entry in _selectedProducts.entries) {
      final product = products.firstWhere((p) => p.id == entry.key, orElse: () => products.first);
      labelsToGenerate.add(MapEntry(product, entry.value));
      totalLabels += entry.value;
    }

    await PdfService.printProductLabels(labelsToGenerate, showPrice: showPrice);
    if (mounted) NotificationService.showSuccess('$totalLabels etiket tek PDF olarak oluşturuldu.');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Container(
      color: AppTheme.darkBackground,
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Row(
              children: [
                Expanded(child: Text('Etiket Yönetimi', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 20))),
                IconButton(icon: Icon(Icons.file_download, color: AppTheme.textMuted), tooltip: 'İçe Aktar', onPressed: _importTemplates),
                IconButton(icon: Icon(Icons.file_upload, color: AppTheme.textMuted), tooltip: 'Dışa Aktar', onPressed: _exportTemplates),
              ],
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [Tab(text: 'Tasarım'), Tab(text: 'Ürün Seç & Üret')],
            ),
          ] else ...[
            Row(
              children: [
                Text('Etiket Yönetimi', style: Theme.of(context).textTheme.displayLarge),
                const SizedBox(width: 24),
                SizedBox(width: 300, child: TabBar(controller: _tabController, tabs: const [Tab(text: 'Tasarım'), Tab(text: 'Ürün Seç & Üret')])),
                const Spacer(),
                IconButton(icon: Icon(Icons.file_download, color: AppTheme.textMuted), tooltip: 'Şablonları İçe Aktar', onPressed: _importTemplates),
                IconButton(icon: Icon(Icons.file_upload, color: AppTheme.textMuted), tooltip: 'Şablonları Dışa Aktar', onPressed: _exportTemplates),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(child: TabBarView(controller: _tabController, children: [_buildDesignTab(isMobile), _buildProductSelectTab(isMobile)])),
        ],
      ),
    );
  }

  Widget _buildDesignTab(bool isMobile) {
    final templateList = Column(
      children: [
        ElevatedButton.icon(onPressed: _newTemplate, icon: const Icon(Icons.add, size: 18), label: const Text('Yeni Şablon'), style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44))),
        const SizedBox(height: 12),
        Expanded(
          child: _templates.isEmpty
            ? Center(child: Text('Şablon yok', style: TextStyle(color: AppTheme.textMuted)))
            : ListView.builder(
                itemCount: _templates.length,
                itemBuilder: (ctx, i) {
                        final t = _templates[i];
                        final isActive = _activeTemplate?.id == t.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isActive ? AppTheme.primaryAccent.withOpacity(0.08) : AppTheme.panelBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isActive ? AppTheme.primaryAccent : AppTheme.borderBright),
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(t.name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                            subtitle: Text('${t.width}×${t.height} mm', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            onTap: () => _selectTemplate(t),
                            trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.dangerAccent), onPressed: () => _deleteTemplate(t)),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );

    final editorSection = _activeTemplate == null
      ? Center(child: Text('Bir şablon seçin veya yeni oluşturun.', style: TextStyle(color: AppTheme.textMuted)))
      : Column(
          children: [
            // Template Name + Dimensions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.panelBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderBright)),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: isMobile ? double.infinity : 200, child: TextField(controller: _templateNameCtrl, decoration: InputDecoration(labelText: 'Şablon Adı', isDense: true))),
                  SizedBox(width: 80, child: TextField(controller: _widthCtrl, decoration: InputDecoration(labelText: 'En (mm)', isDense: true), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onChanged: (v) => setState(() => _activeTemplate!.width = (double.tryParse(v) ?? 50).clamp(10, 200)))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('×')),
                  SizedBox(width: 80, child: TextField(controller: _heightCtrl, decoration: InputDecoration(labelText: 'Boy (mm)', isDense: true), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onChanged: (v) => setState(() => _activeTemplate!.height = (double.tryParse(v) ?? 30).clamp(10, 150)))),
                  ElevatedButton.icon(onPressed: _saveTemplate, icon: const Icon(Icons.save, size: 16), label: const Text('Kaydet')),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Preview + Settings
            isMobile
              ? Column(
                    children: [
                      // Preview (fixed height on mobile)
                      SizedBox(
                        height: 220,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppTheme.panelBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderBright)),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('ÖNİZLEME', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.center_focus_strong, size: 18),
                                    tooltip: 'Konumu Sıfırla',
                                    onPressed: () => setState(() {
                                      for (var el in _activeTemplate!.elements) {
                                        el.x = 2;
                                        el.y = el.type == 'name' ? 2 : el.type == 'barcode' ? 12 : 22;
                                      }
                                    }),
                                  ),
                                  IconButton(icon: const Icon(Icons.zoom_out, size: 18), onPressed: _zoom > 0.5 ? () => setState(() => _zoom = (_zoom - 0.25).clamp(0.5, 3.0)) : null),
                                  Text('${(_zoom * 100).toInt()}%', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  IconButton(icon: const Icon(Icons.zoom_in, size: 18), onPressed: _zoom < 3.0 ? () => setState(() => _zoom = (_zoom + 0.25).clamp(0.5, 3.0)) : null),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Center(
                                  child: InteractiveViewer(
                                    constrained: false,
                                    boundaryMargin: const EdgeInsets.all(200),
                                    minScale: 0.5,
                                    maxScale: 5.0,
                                    child: Transform.scale(
                                      scale: _zoom,
                                      child: Container(
                                        width: (_activeTemplate!.width * 3).clamp(60, 300),
                                        height: (_activeTemplate!.height * 3).clamp(40, 200),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black26), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))]),
                                        child: Stack(
                                          children: _activeTemplate!.elements.where((e) => e.visible).map((el) {
                                            final isSelected = _selectedElement == el;
                                            final labelWidth = _activeTemplate!.width * 3;
                                            return Positioned(
                                              left: el.alignment == 'center' ? 0 : el.alignment == 'right' ? null : el.x * 3,
                                              right: el.alignment == 'right' ? el.x * 3 : null,
                                              top: el.y * 3,
                                              width: el.alignment == 'center' ? labelWidth : null,
                                              child: GestureDetector(
                                                onTap: () => setState(() => _selectedElement = el),
                                                onPanUpdate: (d) { setState(() { el.x = (el.x + d.delta.dx / (3 * _zoom)).clamp(0, _activeTemplate!.width - 10); el.y = (el.y + d.delta.dy / (3 * _zoom)).clamp(0, _activeTemplate!.height - 5); }); },
                                                child: Container(
                                                  padding: const EdgeInsets.all(2),
                                                  decoration: isSelected ? BoxDecoration(border: Border.all(color: Colors.blue, width: 1), borderRadius: BorderRadius.circular(2)) : null,
                                                  child: Text(el.type == 'name' ? 'Ürün Adı' : el.type == 'barcode' ? '||| ||||| ||' : '12.50 ₺', textAlign: el.alignment == 'center' ? TextAlign.center : el.alignment == 'right' ? TextAlign.right : TextAlign.left, style: TextStyle(fontSize: el.fontSize * 1.2, fontWeight: el.bold ? FontWeight.bold : FontWeight.normal, fontFamily: el.fontFamily == 'robotoMono' ? 'monospace' : el.fontFamily == 'serif' ? 'serif' : null, color: Colors.black87)),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Settings panel (full width on mobile)
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppTheme.panelBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderBright)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('İÇERİKLER', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                              const SizedBox(height: 8),
                              ..._activeTemplate!.elements.map((el) {
                                final isSelected = _selectedElement == el;
                                final label = el.type == 'name' ? 'Ürün Adı' : el.type == 'barcode' ? 'Barkod' : 'Fiyat';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(color: isSelected ? AppTheme.primaryAccent.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                                  child: ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8), leading: Switch(value: el.visible, onChanged: (v) => setState(() => el.visible = v), activeThumbColor: AppTheme.primaryAccent), title: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)), onTap: () => setState(() => _selectedElement = el)),
                                );
                              }),
                              if (_selectedElement != null) ...[
                                Divider(color: AppTheme.borderBright),
                                Text('AYARLAR', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                                const SizedBox(height: 8),
                                Row(children: [const Text('Boyut: ', style: TextStyle(fontSize: 12)), Expanded(child: Slider(value: _selectedElement!.fontSize, min: 6, max: 24, divisions: 18, activeColor: AppTheme.primaryAccent, label: '${_selectedElement!.fontSize.round()}', onChanged: (v) => setState(() => _selectedElement!.fontSize = v)))]),
                                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Kalın', style: TextStyle(fontSize: 13)), value: _selectedElement!.bold, activeThumbColor: AppTheme.primaryAccent, onChanged: (v) => setState(() => _selectedElement!.bold = v)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(initialValue: _selectedElement!.fontFamily, decoration: const InputDecoration(labelText: 'Yazı Fontu', isDense: true), dropdownColor: AppTheme.panelBackground, style: TextStyle(color: AppTheme.textMain), items: _fontOptions.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value, style: TextStyle(color: AppTheme.textMain)))).toList(), onChanged: (v) => setState(() => _selectedElement!.fontFamily = v ?? 'inter')),
                                const SizedBox(height: 8),
                                Text('Hizalama:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                Row(children: [_alignBtn(Icons.format_align_left, 'left'), const SizedBox(width: 4), _alignBtn(Icons.format_align_center, 'center'), const SizedBox(width: 4), _alignBtn(Icons.format_align_right, 'right')]),
                                const SizedBox(height: 8),
                                Row(children: [const Text('X: ', style: TextStyle(fontSize: 12)), Expanded(child: Slider(value: _selectedElement!.x, min: 0, max: _activeTemplate!.width, activeColor: AppTheme.primaryAccent, onChanged: (v) => setState(() => _selectedElement!.x = v)))]),
                                Row(children: [const Text('Y: ', style: TextStyle(fontSize: 12)), Expanded(child: Slider(value: _selectedElement!.y, min: 0, max: _activeTemplate!.height, activeColor: AppTheme.primaryAccent, onChanged: (v) => setState(() => _selectedElement!.y = v)))]),
                                ],
                              ],
                            ),
                          ),
                      ],
                    )
              : Expanded(
                  child: Row(
                    children: [
                      // Preview
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: AppTheme.panelBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderBright)),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('ÖNİZLEME', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                                  const Spacer(),
                                  IconButton(icon: const Icon(Icons.zoom_out, size: 18), onPressed: _zoom > 0.5 ? () => setState(() => _zoom = (_zoom - 0.25).clamp(0.5, 3.0)) : null),
                                  Text('${(_zoom * 100).toInt()}%', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  IconButton(icon: const Icon(Icons.zoom_in, size: 18), onPressed: _zoom < 3.0 ? () => setState(() => _zoom = (_zoom + 0.25).clamp(0.5, 3.0)) : null),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: InteractiveViewer(
                                  constrained: false,
                                  boundaryMargin: const EdgeInsets.all(500),
                                  minScale: 0.1,
                                  maxScale: 5.0,
                                  child: Transform.scale(
                                    scale: _zoom,
                                    child: Container(
                                      width: (_activeTemplate!.width * 3).clamp(60, 500),
                                      height: (_activeTemplate!.height * 3).clamp(40, 400),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black26), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))]),
                                      child: Stack(
                                        children: _activeTemplate!.elements.where((e) => e.visible).map((el) {
                                          final isSelected = _selectedElement == el;
                                          final labelWidth = _activeTemplate!.width * 3;
                                          return Positioned(
                                            left: el.alignment == 'center' ? 0 : el.alignment == 'right' ? null : el.x * 3,
                                            right: el.alignment == 'right' ? el.x * 3 : null,
                                            top: el.y * 3,
                                            width: el.alignment == 'center' ? labelWidth : null,
                                            child: GestureDetector(
                                              onTap: () => setState(() => _selectedElement = el),
                                              onPanUpdate: (d) {
                                                setState(() {
                                                  el.x = (el.x + d.delta.dx / (3 * _zoom)).clamp(0, _activeTemplate!.width - 10);
                                                  el.y = (el.y + d.delta.dy / (3 * _zoom)).clamp(0, _activeTemplate!.height - 5);
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: isSelected ? BoxDecoration(border: Border.all(color: Colors.blue, width: 1), borderRadius: BorderRadius.circular(2)) : null,
                                                child: Text(
                                                  el.type == 'name' ? 'Ürün Adı' : el.type == 'barcode' ? '||| ||||| ||' : '12.50 ₺',
                                                  textAlign: el.alignment == 'center' ? TextAlign.center : el.alignment == 'right' ? TextAlign.right : TextAlign.left,
                                                  style: TextStyle(fontSize: el.fontSize * 1.2, fontWeight: el.bold ? FontWeight.bold : FontWeight.normal, fontFamily: el.fontFamily == 'robotoMono' ? 'monospace' : el.fontFamily == 'serif' ? 'serif' : null, color: Colors.black87),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Element list + settings
                      SizedBox(
                        width: isMobile ? 160 : 260,
                        child: Container(
                          padding: EdgeInsets.all(isMobile ? 8 : 12),
                          decoration: BoxDecoration(color: AppTheme.panelBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderBright)),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('İÇERİKLER', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                                const SizedBox(height: 8),
                                ..._activeTemplate!.elements.map((el) {
                                  final isSelected = _selectedElement == el;
                                  final label = el.type == 'name' ? 'Ürün Adı' : el.type == 'barcode' ? 'Barkod' : 'Fiyat';
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(color: isSelected ? AppTheme.primaryAccent.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                      leading: Switch(value: el.visible, onChanged: (v) => setState(() => el.visible = v), activeThumbColor: AppTheme.primaryAccent),
                                      title: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                      onTap: () => setState(() => _selectedElement = el),
                                    ),
                                  );
                                }),
                                if (_selectedElement != null) ...[
                                  Divider(color: AppTheme.borderBright),
                                  Text('AYARLAR', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                                  const SizedBox(height: 8),
                                  // Font size slider
                                  Row(children: [
                                    const Text('Boyut: ', style: TextStyle(fontSize: 12)),
                                    Expanded(child: Slider(value: _selectedElement!.fontSize, min: 6, max: 24, divisions: 18, activeColor: AppTheme.primaryAccent, label: '${_selectedElement!.fontSize.round()}', onChanged: (v) => setState(() => _selectedElement!.fontSize = v))),
                                  ]),
                                  // Bold toggle
                                  SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Kalın', style: TextStyle(fontSize: 13)), value: _selectedElement!.bold, activeThumbColor: AppTheme.primaryAccent, onChanged: (v) => setState(() => _selectedElement!.bold = v)),
                                  const SizedBox(height: 4),
                                  // Font family
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedElement!.fontFamily,
                                    decoration: const InputDecoration(labelText: 'Yazı Fontu', isDense: true),
                                    dropdownColor: AppTheme.panelBackground,
                                    style: TextStyle(color: AppTheme.textMain),
                                    items: _fontOptions.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value, style: TextStyle(color: AppTheme.textMain)))).toList(),
                                    onChanged: (v) => setState(() => _selectedElement!.fontFamily = v ?? 'inter'),
                                  ),
                                  const SizedBox(height: 8),
                                  // Alignment
                                  Text('Hizalama:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                  Row(
                                    children: [
                                      _alignBtn(Icons.format_align_left, 'left'),
                                      const SizedBox(width: 4),
                                      _alignBtn(Icons.format_align_center, 'center'),
                                      const SizedBox(width: 4),
                                      _alignBtn(Icons.format_align_right, 'right'),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // X/Y sliders
                                  Row(children: [
                                    const Text('X: ', style: TextStyle(fontSize: 12)),
                                    Expanded(child: Slider(value: _selectedElement!.x, min: 0, max: _activeTemplate!.width, activeColor: AppTheme.primaryAccent, onChanged: (v) => setState(() => _selectedElement!.x = v))),
                                  ]),
                                  Row(children: [
                                    const Text('Y: ', style: TextStyle(fontSize: 12)),
                                    Expanded(child: Slider(value: _selectedElement!.y, min: 0, max: _activeTemplate!.height, activeColor: AppTheme.primaryAccent, onChanged: (v) => setState(() => _selectedElement!.y = v))),
                                  ]),
                                ], // Closes if (_selectedElement != null) ...[
                              ], // Closes Column children
                            ), // Closes Column
                          ), // Closes SingleChildScrollView
                        ), // Closes Container
                      ), // Closes SizedBox
                    ],
                  ),
                ),
          ],
        );
        
    if (isMobile) {
      return SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 200, child: templateList),
            const SizedBox(height: 16),
            editorSection,
          ],
        ),
      );
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 250, child: templateList),
        const SizedBox(width: 16),
        Expanded(child: editorSection),
      ],
    );
  }

  Widget _alignBtn(IconData icon, String value) {
    final isActive = _selectedElement?.alignment == value;
    return InkWell(
      onTap: () => setState(() => _selectedElement!.alignment = value),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryAccent.withOpacity(0.1) : AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppTheme.primaryAccent : AppTheme.borderBright),
        ),
        child: Icon(icon, size: 18, color: isActive ? AppTheme.primaryAccent : AppTheme.textMuted),
      ),
    );
  }

  Widget _buildProductSelectTab(bool isMobile) {
    final productsState = ref.watch(productProvider);
    
    final templateList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ŞABLON SEÇ', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, letterSpacing: 1)),
        const SizedBox(height: 8),
        Expanded(
          child: _templates.isEmpty
            ? Center(child: Text('Önce Tasarım sekmesinde\nbir şablon oluşturun.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)))
            : ListView.builder(
                itemCount: _templates.length,
                itemBuilder: (ctx, i) {
                        final t = _templates[i];
                        final isActive = _activeTemplate?.id == t.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isActive ? AppTheme.primaryAccent.withOpacity(0.08) : AppTheme.panelBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isActive ? AppTheme.primaryAccent : AppTheme.borderBright),
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(t.name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                            subtitle: Text('${t.width}×${t.height} mm', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            onTap: () => _selectTemplate(t),
                            trailing: isActive ? Icon(Icons.check_circle, color: AppTheme.primaryAccent, size: 18) : null,
                          ),
                        );
                },
              ),
        ),
      ],
    );

        // Product list
        final productList = Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: isMobile ? double.infinity : 250,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ürün Ara...',
                        prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_selectedProducts.isNotEmpty) TextButton(onPressed: () => setState(() => _selectedProducts.clear()), child: Text('Temizle', style: TextStyle(color: AppTheme.dangerAccent))),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: productsState.when(
                  loading: () => Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent)),
                  error: (err, _) => Center(child: Text('Hata: $err')),
                  data: (products) {
                    final query = _searchCtrl.text.toLowerCase();
                    final filtered = products.where((p) => p.name.toLowerCase().contains(query) || p.barcode.contains(query)).toList();
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.borderBright),
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final count = _selectedProducts[p.id] ?? 0;
                        return ListTile(
                          dense: true,
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text('${p.barcode} • ${p.salePrice.toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (count > 0) ...[
                                IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: () => setState(() {
                                  if (count <= 1) { _selectedProducts.remove(p.id); } else { _selectedProducts[p.id] = count - 1; }
                                })),
                                Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                              IconButton(icon: Icon(Icons.add_circle_outline, color: AppTheme.primaryAccent, size: 20), onPressed: () => setState(() => _selectedProducts[p.id] = count + 1)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_selectedProducts.isNotEmpty && _activeTemplate != null) ? _generateLabels : null,
                  icon: const Icon(Icons.print),
                  label: Text('ETİKET ÜRET (${_selectedProducts.values.fold(0, (sum, v) => sum + v)} adet)'),
                ),
              ),
            ],
        );

    if (isMobile) {
      return Column(
        children: [
          SizedBox(height: 180, child: templateList),
          const SizedBox(height: 16),
          Expanded(child: productList),
        ],
      );
    }
    
    return Row(
      children: [
        SizedBox(width: 220, child: templateList),
        const SizedBox(width: 16),
        Expanded(child: productList),
      ],
    );
  }
}
