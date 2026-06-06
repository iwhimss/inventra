import 'package:inventra_app/core/services/notification_service.dart';
import 'dart:io';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:path_provider/path_provider.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  String? _selectedFilePath;
  List<String> _headers = [];
  bool _isLoading = false;

  final List<String> _inventraFields = [
    'Barkod (Zorunlu)',
    'Ürün Adı (Zorunlu)',
    'Stok',
    'Alış Fiyatı (₺)',
    'Satış Fiyatı (₺) (Zorunlu)',
    'Satış Fiyatı 2 (₺)',
    'Satış Fiyatı 3 (₺)',
    'KDV Oranı',
    'Birim',
    'Hızlı Ürün (0/1)',
    'Anahtar Kelimeler',
    'Ürün Grubu',
  ];

  final Map<String, int?> _fieldMapping = {};

  @override
  void initState() {
    super.initState();
    for (var f in _inventraFields) {
      _fieldMapping[f] = null;
    }
  }

  Future<void> _selectExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        // .xls formatı desteklenmiyor, kullanıcıya açıkla
        if (path.toLowerCase().endsWith('.xls') && !path.toLowerCase().endsWith('.xlsx')) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.panelBackground,
                title: const Text('⚠️ Eski Format (.xls)'),
                content: const Text(
                  'Seçtiğiniz dosya eski Excel formatında (.xls).\n\n'
                  'Bu format desteklenmiyor. Lütfen dosyanızı Excel programında açın ve:\n\n'
                  'Dosya > Farklı Kaydet > Excel Çalışma Kitabı (.xlsx)\n\n'
                  'olarak kaydedip tekrar seçin.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
              ),
            );
          }
          return;
        }

        setState(() {
          _isLoading = true;
          _selectedFilePath = path;
          _headers = [];
        });

        final bytes = await File(_selectedFilePath!).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final table = excel.tables[excel.tables.keys.first];

        if (table != null && table.rows.isNotEmpty) {
          final firstRow = table.rows[0];
          _headers = firstRow
              .map((c) => c?.value?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();

          // Eğer tüm hücreler boşsa ikinci satıra bak (bazı dosyalar bos satır la başlar)
          if (_headers.isEmpty && table.rows.length > 1) {
            _headers = table.rows[1]
                .map((c) => c?.value?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }

        if (_headers.isEmpty) {
          setState(() { _isLoading = false; _selectedFilePath = null; });
          if (mounted) NotificationService.showError('Excel dosyasında sütun başlıkları okunamadı. İlk satırın sütun başlıklarını içerdiğinden emin olun.');
          return;
        }

        // Otomatik eşleştirme
        for (var f in _inventraFields) {
          _fieldMapping[f] = null;
          for (var i = 0; i < _headers.length; i++) {
            final hLower = _headers[i].toLowerCase();
            final fLower = f.toLowerCase();
            if (hLower.contains('barkod') && fLower.contains('barkod')) _fieldMapping[f] = i;
            if ((hLower.contains('isim') || hLower.contains('ad')) && fLower.contains('adı')) _fieldMapping[f] = i;
            if (hLower.contains('alış') && fLower.contains('alış')) _fieldMapping[f] = i;
            if (hLower.contains('satış') && fLower.contains('satış')) _fieldMapping[f] = i;
            if (hLower == 'stok' && fLower.contains('stok')) _fieldMapping[f] = i;
          }
        }

        setState(() { _isLoading = false; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _selectedFilePath = null; _headers = []; });
      if (mounted) NotificationService.showError('Dosya okunamadı: $e');
    }
  }

  Future<void> _convertAndSave() async {
    if (_selectedFilePath == null) return;
    
    if (_fieldMapping['Ürün Adı (Zorunlu)'] == null || _fieldMapping['Satış Fiyatı (₺) (Zorunlu)'] == null) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Ürün Adı ve Satış Fiyatı eşleştirmesi zorunludur!'), backgroundColor: AppTheme.dangerAccent));
       return;
    }

    setState(() => _isLoading = true);
    
    try {
       final bytes = await File(_selectedFilePath!).readAsBytes();
       final sourceExcel = Excel.decodeBytes(bytes);
       final sourceTable = sourceExcel.tables[sourceExcel.tables.keys.first];

       if (sourceTable == null) throw Exception('Excel sayfası okunamadı.');

       var newExcel = Excel.createExcel();
       Sheet sheet = newExcel['Inventra Sütun Dönüşüm'];
       newExcel.delete('Sheet1');

       sheet.appendRow([
          TextCellValue('Barkod'),
          TextCellValue('Ürün İsmi'),
          TextCellValue('Stok'),
          TextCellValue('Alış Fiyatı'),
          TextCellValue('Satış Fiyatı'),
          TextCellValue('Satış Fiyatı 2'),
          TextCellValue('Satış Fiyatı 3'),
          TextCellValue('KDV Oranı'),
          TextCellValue('Birim'),
          TextCellValue('Hızlı Ürün'),
          TextCellValue('Anahtar Kelimeler'),
          TextCellValue('Ürün Grubu'),
       ]);

       for (var i = 1; i < sourceTable.maxRows; i++) {
         try {
           final row = sourceTable.rows[i];
           if (row.isEmpty) continue;
           
           String getVal(String field) {
             final idx = _fieldMapping[field];
             if (idx == null || idx >= row.length || row[idx] == null) return '';
             return row[idx]!.value.toString();
           }

           final name = getVal('Ürün Adı (Zorunlu)');
           if (name.isEmpty) continue;

           sheet.appendRow([
             TextCellValue(getVal('Barkod (Zorunlu)')),
             TextCellValue(name),
             TextCellValue(getVal('Stok')),
             TextCellValue(getVal('Alış Fiyatı (₺)')),
             TextCellValue(getVal('Satış Fiyatı (₺) (Zorunlu)')),
             TextCellValue(getVal('Satış Fiyatı 2 (₺)')),
             TextCellValue(getVal('Satış Fiyatı 3 (₺)')),
             TextCellValue(getVal('KDV Oranı')),
             TextCellValue(getVal('Birim')),
             TextCellValue(getVal('Hızlı Ürün (0/1)')),
             TextCellValue(getVal('Anahtar Kelimeler')),
             TextCellValue(getVal('Ürün Grubu')),
           ]);
         } catch (_) {}
       }

       String? outputFile;
       if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
         // Windows: kayıtlı yolu kontrol et
         final gDb = await DatabaseHelper.instance.globalDb;
         final dbCheck = await gDb.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
         String? rootPath = (dbCheck.isNotEmpty && dbCheck.first['value'].toString().isNotEmpty) ? dbCheck.first['value'].toString() : null;
         if (rootPath != null) {
           final dir = Directory('$rootPath/donusturucu');
           if (!await dir.exists()) await dir.create(recursive: true);
           outputFile = '${dir.path}/donusturulmus_${DateTime.now().millisecondsSinceEpoch}.xlsx';
         } else {
           outputFile = await FilePicker.platform.saveFile(
             dialogTitle: 'Dönüştürülen Excel\'i Kaydet',
             fileName: 'inventra_donusturulmus_${DateTime.now().millisecondsSinceEpoch}.xlsx',
             type: FileType.custom,
             allowedExtensions: ['xlsx'],
           );
         }
       } else {
         // Mobil: kayıtlı yolu kontrol et
         final gDb = await DatabaseHelper.instance.globalDb;
         final dbCheck = await gDb.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
         String? rootPath = (dbCheck.isNotEmpty && dbCheck.first['value'].toString().isNotEmpty) ? dbCheck.first['value'].toString() : null;
         if (rootPath != null) {
           final dir = Directory('$rootPath/donusturucu');
           if (!await dir.exists()) await dir.create(recursive: true);
           outputFile = '${dir.path}/donusturulmus_${DateTime.now().millisecondsSinceEpoch}.xlsx';
         } else {
           String dir = '/storage/emulated/0/Download';
           if (!Directory(dir).existsSync()) {
             dir = (await getApplicationDocumentsDirectory()).path;
           }
           outputFile = '$dir/inventra_donusturulmus_${DateTime.now().millisecondsSinceEpoch}.xlsx';
         }
       }

       if (outputFile != null) {
         final fileBytes = newExcel.encode();
         if (fileBytes != null) {
           await File(outputFile).writeAsBytes(fileBytes);
           SoundService.playSuccess();
           if (mounted) {
             showDialog(
               context: context,
               builder: (ctx) => AlertDialog(
                 backgroundColor: AppTheme.panelBackground,
                 title: const Text('Başarılı'),
                 content: Text('Dosya başarıyla dönüştürüldü ve kaydedildi:\n\n$outputFile\n\nBu dosyayı Ayarlar > Veri İçe Aktar menüsünden sisteme yükleyebilirsiniz.'),
                 actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
               )
             );
           }
         }
       }
    } catch (e) {
       if (mounted) NotificationService.showError('Hata: $e');
    } finally {
       setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground, // AppTheme.darkBackground tema'ya göre güncellenir
      body: SafeArea(
        child: _isLoading && _selectedFilePath == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Excel Sütun Eşleştirici',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Başka bir yazılımdan aldığınız ürün listesini (.xlsx), Inventra sistemine uygun Excel formatına çevirmek için kullanabilirsiniz.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: isMobile ? 13 : 14),
                  ),
                  const SizedBox(height: 24),

                  if (_selectedFilePath == null) ...[
                    // Dosya seçme alanı
                    InkWell(
                      onTap: _selectExcelFile,
                      child: Container(
                        padding: EdgeInsets.all(isMobile ? 24 : 32),
                        decoration: BoxDecoration(
                          color: AppTheme.panelBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.borderBright, width: 2),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file, size: isMobile ? 48 : 64, color: AppTheme.primaryAccent),
                            const SizedBox(height: 16),
                            Text(
                              'Dışarıdan Alınan Excel Dosyasını Seçin',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 16 : 18),
                            ),
                            const SizedBox(height: 8),
                            Text('Sadece .xlsx uzantılı dosyalar desteklenir.', style: TextStyle(color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Seçilen dosya bilgisi
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.panelBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderBright),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.description, color: AppTheme.primaryAccent, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _selectedFilePath!.split(Platform.pathSeparator).last,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () => setState(() { _selectedFilePath = null; _headers = []; }),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('İptal'),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: _selectExcelFile,
                                icon: const Icon(Icons.file_open, size: 16),
                                label: const Text('Değiştir'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Sütun Eşleştirme
                    Container(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      decoration: BoxDecoration(
                        color: AppTheme.panelBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.compare_arrows, color: AppTheme.primaryAccent, size: 20),
                              const SizedBox(width: 8),
                              const Text('Sütun Eşleştirme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Dış kaynak sütunlarını Inventra alanlarıyla eşleştirin.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          const SizedBox(height: 16),
                          ..._inventraFields.map((field) {
                            final isRequired = field.contains('Zorunlu)');
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: isMobile ? _buildMobileFieldRow(field, isRequired) : _buildDesktopFieldRow(field, isRequired),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Dönüştür butonu
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _convertAndSave,
                        icon: _isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_fix_high),
                        label: Text(_isLoading ? 'DÖNÜŞTÜRÜLÜYOR...' : 'DÖNÜŞTÜR VE KAYDET'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
      ),
    );
  }

  // Desktop: yatay satır (label → dropdown)
  Widget _buildDesktopFieldRow(String field, bool isRequired) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              if (isRequired) Text('* ', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
              Flexible(child: Text(field, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        Icon(Icons.arrow_forward, size: 14, color: Colors.grey.withOpacity(0.5)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: _buildDropdown(field)),
      ],
    );
  }

  // Mobile: dikey düzen (label üstte, dropdown altta)
  Widget _buildMobileFieldRow(String field, bool isRequired) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (isRequired) Text('* ', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
            Flexible(child: Text(field, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
          ],
        ),
        const SizedBox(height: 6),
        _buildDropdown(field),
      ],
    );
  }

  Widget _buildDropdown(String field) {
    return DropdownButtonFormField<int?>(
      initialValue: _fieldMapping[field],
      isExpanded: true,
      dropdownColor: AppTheme.panelBackground,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: AppTheme.darkBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.borderBright)),
      ),
      hint: Text('Sütun Seç...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text('Yok / Boş Bırak', style: TextStyle(fontSize: 12, color: AppTheme.textMain)),
        ),
        for (var i = 0; i < _headers.length; i++)
          DropdownMenuItem<int?>(
            value: i,
            child: Text(
              '${String.fromCharCode(65 + i)}: ${_headers[i]}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppTheme.textMain),
            ),
          ),
      ],
      onChanged: (val) => setState(() { _fieldMapping[field] = val; }),
    );
  }
}
