import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;

/// Server-side database helper using pure dart sqlite3 package.
/// Each instance has its own database file.
class ServerDatabaseHelper {
  final String instancePath;
  late Database _db;
  bool _isOpen = false;

  ServerDatabaseHelper(this.instancePath);

  Database get db {
    if (!_isOpen) throw StateError('Database is not open. Call open() first.');
    return _db;
  }

  void open() {
    final dbPath = p.join(instancePath, 'inventra.db');
    _db = sqlite3.open(dbPath);
    _isOpen = true;
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA foreign_keys=ON');
    _createTables();
    _runMigrations();
  }

  void close() {
    if (_isOpen) {
      _db.dispose();
      _isOpen = false;
    }
  }

  bool get isFirstRun {
    final result = _db.select("SELECT COUNT(*) as c FROM users");
    return result.first['c'] as int == 0;
  }

  void _createTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        barcode TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        sale_price REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        critical_stock_level INTEGER NOT NULL DEFAULT 0,
        vat_rate REAL NOT NULL DEFAULT 20,
        unit TEXT NOT NULL DEFAULT 'Adet',
        product_group TEXT,
        is_fast_product INTEGER NOT NULL DEFAULT 0,
        keywords TEXT DEFAULT '',
        image_path TEXT DEFAULT '',
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS product_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT DEFAULT '#2196F3',
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        total_amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT DEFAULT 'Nakit',
        cash_amount REAL DEFAULT 0,
        card_amount REAL DEFAULT 0,
        cashier_id TEXT,
        cashier_name TEXT,
        discount REAL DEFAULT 0,
        note TEXT DEFAULT '',
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT,
        product_name TEXT DEFAULT '',
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        discount REAL DEFAULT 0,
        total_price REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        staff_id TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        name TEXT DEFAULT '',
        role TEXT DEFAULT 'cashier',
        permissions TEXT DEFAULT ''
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS roles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        permissions TEXT DEFAULT ''
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        table_name TEXT,
        record_id TEXT,
        data TEXT,
        device_id TEXT,
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS label_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        config TEXT NOT NULL DEFAULT '{}',
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS paired_devices (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL UNIQUE,
        device_name TEXT DEFAULT '',
        device_type TEXT DEFAULT '',
        status TEXT DEFAULT 'pending',
        api_key TEXT,
        last_sync_at TEXT,
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS cart_transfers (
        id TEXT PRIMARY KEY,
        sender_device_id TEXT NOT NULL,
        sender_name TEXT DEFAULT '',
        target_device_id TEXT NOT NULL,
        cart_data TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT DEFAULT '',
        email TEXT DEFAULT '',
        address TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        tax_office TEXT DEFAULT '',
        tax_number TEXT DEFAULT '',
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT DEFAULT '',
        email TEXT DEFAULT '',
        address TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        tax_office TEXT DEFAULT '',
        tax_number TEXT DEFAULT '',
        created_at TEXT
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS client_transactions (
        id TEXT PRIMARY KEY,
        client_id TEXT NOT NULL,
        client_type TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        transaction_type TEXT NOT NULL,
        payment_method TEXT DEFAULT '',
        description TEXT DEFAULT '',
        sale_id TEXT DEFAULT '',
        created_at TEXT
      )
    ''');

    // ─── Activity Logs ──────────────────────────────────────
    _db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id TEXT PRIMARY KEY,
        module TEXT DEFAULT '',
        user_id TEXT DEFAULT '',
        user_name TEXT DEFAULT '',
        action TEXT NOT NULL,
        target TEXT DEFAULT '',
        description TEXT DEFAULT '',
        created_at TEXT
      )
    ''');

    // ─── Stock History ─────────────────────────────────────
    _db.execute('''
      CREATE TABLE IF NOT EXISTS stock_history (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        product_name TEXT DEFAULT '',
        old_stock INTEGER NOT NULL DEFAULT 0,
        new_stock INTEGER NOT NULL DEFAULT 0,
        change_amount INTEGER NOT NULL DEFAULT 0,
        reason TEXT DEFAULT '',
        user_name TEXT DEFAULT '',
        created_at TEXT
      )
    ''');

    // ─── Cash Shifts (Kasa Vardiyaları) ───────────────────
    _db.execute('''
      CREATE TABLE IF NOT EXISTS cash_shifts (
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'open',
        opened_by TEXT DEFAULT '',
        closed_by TEXT DEFAULT '',
        opening_balance REAL NOT NULL DEFAULT 0,
        closing_balance REAL DEFAULT 0,
        expected_balance REAL DEFAULT 0,
        total_cash_sales REAL DEFAULT 0,
        total_card_sales REAL DEFAULT 0,
        total_sales_count INTEGER DEFAULT 0,
        notes TEXT DEFAULT '',
        opened_at TEXT,
        closed_at TEXT
      )
    ''');
  }

  // ─── Migrations for existing databases ─────────────────────
  void _runMigrations() {
    // Migration 1: Add keywords column to products
    try {
      final cols = _db.select("PRAGMA table_info(products)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('keywords')) {
        _db.execute("ALTER TABLE products ADD COLUMN keywords TEXT DEFAULT ''");
      }
    } catch (_) {}

    // Migration 2: Ensure label_templates has config column
    try {
      final cols = _db.select("PRAGMA table_info(label_templates)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('config')) {
        _db.execute("ALTER TABLE label_templates ADD COLUMN config TEXT NOT NULL DEFAULT '{}'");
      }
    } catch (_) {}

    // Migration 3: Add sale_price_2 and sale_price_3 to products
    try {
      final cols = _db.select("PRAGMA table_info(products)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('sale_price_2')) {
        _db.execute("ALTER TABLE products ADD COLUMN sale_price_2 REAL");
      }
      if (!colNames.contains('sale_price_3')) {
        _db.execute("ALTER TABLE products ADD COLUMN sale_price_3 REAL");
      }
    } catch (_) {}

    // Migration 4: Add image_path to products
    try {
      final cols = _db.select("PRAGMA table_info(products)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('image_path')) {
         _db.execute("ALTER TABLE products ADD COLUMN image_path TEXT DEFAULT ''");
      }
    } catch (_) {}

    // Migration 5: Create customers, suppliers, and client_transactions tables
    try {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS customers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          phone TEXT DEFAULT '',
          email TEXT DEFAULT '',
          address TEXT DEFAULT '',
          notes TEXT DEFAULT '',
          tax_office TEXT DEFAULT '',
          tax_number TEXT DEFAULT '',
          created_at TEXT
        )
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS suppliers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          phone TEXT DEFAULT '',
          email TEXT DEFAULT '',
          address TEXT DEFAULT '',
          notes TEXT DEFAULT '',
          tax_office TEXT DEFAULT '',
          tax_number TEXT DEFAULT '',
          created_at TEXT
        )
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS client_transactions (
          id TEXT PRIMARY KEY,
          client_id TEXT NOT NULL,
          client_type TEXT NOT NULL,
          amount REAL NOT NULL DEFAULT 0,
          transaction_type TEXT NOT NULL,
          payment_method TEXT DEFAULT '',
          description TEXT DEFAULT '',
          sale_id TEXT DEFAULT '',
          created_at TEXT
        )
      ''');
    } catch (_) {}

    // Migration 6: Create activity_logs, stock_history, cash_shifts
    try {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS activity_logs (
          id TEXT PRIMARY KEY,
          module TEXT DEFAULT '',
          user_id TEXT DEFAULT '',
          user_name TEXT DEFAULT '',
          action TEXT NOT NULL,
          target TEXT DEFAULT '',
          description TEXT DEFAULT '',
          created_at TEXT
        )
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS stock_history (
          id TEXT PRIMARY KEY,
          product_id TEXT NOT NULL,
          product_name TEXT DEFAULT '',
          old_stock INTEGER NOT NULL DEFAULT 0,
          new_stock INTEGER NOT NULL DEFAULT 0,
          change_amount INTEGER NOT NULL DEFAULT 0,
          reason TEXT DEFAULT '',
          user_name TEXT DEFAULT '',
          created_at TEXT
        )
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS cash_shifts (
          id TEXT PRIMARY KEY,
          status TEXT NOT NULL DEFAULT 'open',
          opened_by TEXT DEFAULT '',
          closed_by TEXT DEFAULT '',
          opening_balance REAL NOT NULL DEFAULT 0,
          closing_balance REAL DEFAULT 0,
          expected_balance REAL DEFAULT 0,
          total_cash_sales REAL DEFAULT 0,
          total_card_sales REAL DEFAULT 0,
          total_sales_count INTEGER DEFAULT 0,
          notes TEXT DEFAULT '',
          opened_at TEXT,
          closed_at TEXT
        )
      ''');
    } catch (_) {}

    // Migration 7: Ensure activity_logs has module and user_id columns
    try {
      final cols = _db.select("PRAGMA table_info(activity_logs)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('module')) {
        _db.execute("ALTER TABLE activity_logs ADD COLUMN module TEXT DEFAULT ''");
      }
      if (!colNames.contains('user_id')) {
        _db.execute("ALTER TABLE activity_logs ADD COLUMN user_id TEXT DEFAULT ''");
      }
    } catch (_) {}

    // Migration 8: Ensure sales has paid_amount and change_amount
    try {
      final cols = _db.select("PRAGMA table_info(sales)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('paid_amount')) {
        _db.execute("ALTER TABLE sales ADD COLUMN paid_amount REAL DEFAULT 0");
      }
      if (!colNames.contains('change_amount')) {
        _db.execute("ALTER TABLE sales ADD COLUMN change_amount REAL DEFAULT 0");
      }
    } catch (_) {}

    // Migration 9: Ensure product_groups has created_at
    try {
      final cols = _db.select("PRAGMA table_info(product_groups)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('created_at')) {
        _db.execute("ALTER TABLE product_groups ADD COLUMN created_at TEXT");
      }
    } catch (_) {}

    // Migration 10: Ensure sales has cashier_id and cashier_name
    try {
      final cols = _db.select("PRAGMA table_info(sales)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('cashier_id'))
        _db.execute("ALTER TABLE sales ADD COLUMN cashier_id TEXT DEFAULT ''");
      if (!colNames.contains('cashier_name'))
        _db.execute("ALTER TABLE sales ADD COLUMN cashier_name TEXT DEFAULT ''");
    } catch (_) {}

    // Migration 11: Ensure activity_logs has user_name
    try {
      final cols = _db.select("PRAGMA table_info(activity_logs)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('user_name'))
        _db.execute("ALTER TABLE activity_logs ADD COLUMN user_name TEXT DEFAULT ''");
    } catch (_) {}
  }

  // ─── Convenience Query Methods ──────────────────────────────

  List<Map<String, dynamic>> queryAll(String table, {String? orderBy}) {
    final sql = 'SELECT * FROM $table${orderBy != null ? ' ORDER BY $orderBy' : ''}';
    final result = _db.select(sql);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  List<Map<String, dynamic>> query(String sql, [List<Object?> params = const []]) {
    final result = _db.select(sql, params);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void execute(String sql, [List<Object?> params = const []]) {
    _db.execute(sql, params);
  }

  int insert(String table, Map<String, dynamic> values) {
    final keys = values.keys.toList();
    final placeholders = keys.map((_) => '?').join(', ');
    final sql = 'INSERT OR REPLACE INTO $table (${keys.join(', ')}) VALUES ($placeholders)';
    _db.execute(sql, values.values.toList());
    return _db.lastInsertRowId;
  }

  int update(String table, Map<String, dynamic> values, {required String where, required List<Object?> whereArgs}) {
    final sets = values.keys.map((k) => '$k = ?').join(', ');
    final sql = 'UPDATE $table SET $sets WHERE $where';
    _db.execute(sql, [...values.values, ...whereArgs]);
    return _db.updatedRows;
  }

  int delete(String table, {String? where, List<Object?>? whereArgs}) {
    final sql = 'DELETE FROM $table${where != null ? ' WHERE $where' : ''}';
    _db.execute(sql, whereArgs ?? []);
    return _db.updatedRows;
  }
}
