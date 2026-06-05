import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Database? _globalDb;
  static String? _currentServerUrl;

  DatabaseHelper._init();

  Future<Database> get globalDb async {
    if (_globalDb != null) return _globalDb!;
    
    // Copy inventra_local.db to inventra_global.db on first run to preserve existing settings
    try {
      if (!kIsWeb) {
        final dbPathStr = await getDatabasesPath();
        final globalPath = join(dbPathStr, 'inventra_global.db');
        final localPath = join(dbPathStr, 'inventra_local.db');
        
        if (!File(globalPath).existsSync() && File(localPath).existsSync()) {
          File(localPath).copySync(globalPath);
        }
      }
    } catch (_) {}

    _globalDb = await _initDB('inventra_global.db');
    return _globalDb!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    // If no server is set yet, we use a fallback anonymous cache DB
    String safeName = 'default';
    if (_currentServerUrl != null && _currentServerUrl!.isNotEmpty) {
      safeName = _currentServerUrl!.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    }
    _database = await _initDB('inventra_cache_$safeName.db');
    return _database!;
  }

  Future<void> switchToServer(String serverUrl) async {
    if (_currentServerUrl == serverUrl) return;

    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    _currentServerUrl = serverUrl;
    
    // Initialize the new cache DB immediately
    await database;
    
    // Also save active server to global db
    final gDb = await globalDb;
    await gDb.insert('settings', {'key': 'active_server_url', 'value': serverUrl}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getActiveServerUrl() async {
    if (_currentServerUrl != null) return _currentServerUrl;
    
    final gDb = await globalDb;
    final res = await gDb.query('settings', where: "key = 'active_server_url'");
    if (res.isNotEmpty) {
      _currentServerUrl = res.first['value']?.toString();
    }
    return _currentServerUrl;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      throw Exception("Web is not supported in this version.");
    }
    
    // Initialize FFI for Windows/Desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 16,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS products');
          await db.execute('DROP TABLE IF EXISTS sales');
          await db.execute('DROP TABLE IF EXISTS sale_items');
          await db.execute('DROP TABLE IF EXISTS users');
          await db.execute('DROP TABLE IF EXISTS events');
          await _createDB(db, newVersion);
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN cash_amount REAL DEFAULT 0');
            await db.execute('ALTER TABLE sales ADD COLUMN card_amount REAL DEFAULT 0');
          } catch(_) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE products ADD COLUMN is_fast_product INTEGER DEFAULT 0');
            await db.execute('ALTER TABLE products ADD COLUMN keywords TEXT');
          } catch(_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS label_templates (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              config TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
        if (oldVersion < 5) {
          try {
            await db.execute('ALTER TABLE sale_items ADD COLUMN product_name TEXT');
            await db.execute('ALTER TABLE sale_items ADD COLUMN discount REAL DEFAULT 0');
            await db.execute('ALTER TABLE sales ADD COLUMN discount_amount REAL DEFAULT 0');
          } catch(_) {}
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS roles (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              permissions TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS product_groups (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          try {
            await db.execute('ALTER TABLE products ADD COLUMN product_group TEXT');
          } catch(_) {}
        }
        if (oldVersion < 8) {
          // Retry adding all newly introduced columns in case a previous upgrade failed or didn't run properly on some mobile devices
          try { await db.execute('ALTER TABLE sales ADD COLUMN cash_amount REAL DEFAULT 0'); } catch(_) {}
          try { await db.execute('ALTER TABLE sales ADD COLUMN card_amount REAL DEFAULT 0'); } catch(_) {}
          try { await db.execute('ALTER TABLE sales ADD COLUMN discount_amount REAL DEFAULT 0'); } catch(_) {}
          try { await db.execute('ALTER TABLE products ADD COLUMN is_fast_product INTEGER DEFAULT 0'); } catch(_) {}
          try { await db.execute('ALTER TABLE products ADD COLUMN keywords TEXT'); } catch(_) {}
          try { await db.execute('ALTER TABLE products ADD COLUMN product_group TEXT'); } catch(_) {}
          try { await db.execute('ALTER TABLE sale_items ADD COLUMN product_name TEXT'); } catch(_) {}
          try { await db.execute('ALTER TABLE sale_items ADD COLUMN discount REAL DEFAULT 0'); } catch(_) {}
        }
        if (oldVersion < 9) {
          // Add device_id to events for bidirectional sync
          try { await db.execute('ALTER TABLE events ADD COLUMN device_id TEXT'); } catch(_) {}
          // Create paired_devices table
          await db.execute('''
            CREATE TABLE IF NOT EXISTS paired_devices (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              device_type TEXT NOT NULL,
              paired_at TEXT NOT NULL,
              last_sync_at TEXT,
              is_approved INTEGER DEFAULT 0
            )
          ''');
        }
        if (oldVersion < 10) {
          // Ensure product_groups table exists (may have been missed on some installs)
          await db.execute('''
            CREATE TABLE IF NOT EXISTS product_groups (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          try { await db.execute('ALTER TABLE products ADD COLUMN product_group TEXT'); } catch(_) {}
        }
        if (oldVersion < 11) {
          // Phase 4: Multiple sale prices
          try { await db.execute('ALTER TABLE products ADD COLUMN sale_price_2 REAL'); } catch(_) {}
          try { await db.execute('ALTER TABLE products ADD COLUMN sale_price_3 REAL'); } catch(_) {}
        }
        if (oldVersion < 12) {
          // Phase 5: Product Images
          try { await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT'); } catch(_) {}
        }
        if (oldVersion < 13) {
          // Phase 6: Customers, Suppliers and Transactions
          await db.execute('''
            CREATE TABLE IF NOT EXISTS customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              email TEXT,
              address TEXT,
              notes TEXT,
              tax_office TEXT,
              tax_number TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS suppliers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              email TEXT,
              address TEXT,
              notes TEXT,
              tax_office TEXT,
              tax_number TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS client_transactions (
              id TEXT PRIMARY KEY,
              client_id TEXT NOT NULL,
              client_type TEXT NOT NULL,
              amount REAL NOT NULL,
              transaction_type TEXT NOT NULL,
              payment_method TEXT,
              description TEXT,
              sale_id TEXT,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 14) {
          // Ensure product_groups has created_at column (may be missing in old cache DBs)
          try { await db.execute('ALTER TABLE product_groups ADD COLUMN created_at TEXT'); } catch(_) {}
          // Ensure customers, suppliers, client_transactions tables exist
          await db.execute('''
            CREATE TABLE IF NOT EXISTS customers (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT,
              address TEXT, notes TEXT, tax_office TEXT, tax_number TEXT, created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS suppliers (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT,
              address TEXT, notes TEXT, tax_office TEXT, tax_number TEXT, created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS client_transactions (
              id TEXT PRIMARY KEY, client_id TEXT NOT NULL, client_type TEXT NOT NULL,
              amount REAL NOT NULL, transaction_type TEXT NOT NULL, payment_method TEXT,
              description TEXT, sale_id TEXT, created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 15) {
          // Phase 8: Credit limits and payment due days for customers/suppliers
          try { await db.execute('ALTER TABLE customers ADD COLUMN credit_limit REAL'); } catch(_) {}
          try { await db.execute('ALTER TABLE customers ADD COLUMN payment_due_days INTEGER'); } catch(_) {}
          try { await db.execute('ALTER TABLE suppliers ADD COLUMN credit_limit REAL'); } catch(_) {}
        }
        if (oldVersion < 16) {
          // Phase 9: User display name for offline login & activity log
          try { await db.execute("ALTER TABLE users ADD COLUMN name TEXT DEFAULT ''"); } catch (_) {}
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';
    
    // Products Table
    await db.execute('''
    CREATE TABLE products (
      id $idType,
      barcode $textType UNIQUE,
      name $textType,
      stock $integerType,
      purchase_price $realType,
      sale_price $realType,
      sale_price_2 REAL,
      sale_price_3 REAL,
      vat_rate $realType,
      unit $textNullable,
      is_fast_product INTEGER DEFAULT 0,
      keywords $textNullable,
      product_group $textNullable,
      image_path $textNullable,
      created_at $textType,
      updated_at $textType
    )
    ''');

    // Sales Table
    await db.execute('''
    CREATE TABLE sales (
      id $idType,
      total_amount $realType,
      paid_amount $realType,
      change_amount $realType,
      payment_type $textType,
      cash_amount $realType DEFAULT 0,
      card_amount $realType DEFAULT 0,
      discount_amount $realType DEFAULT 0,
      status $textType,
      device_id $textType,
      created_at $textType
    )
    ''');

    // Sale Items Table
    await db.execute('''
    CREATE TABLE sale_items (
      id $idType,
      sale_id $textType,
      product_id $textType,
      product_name $textNullable,
      quantity $integerType,
      unit_price $realType,
      discount $realType DEFAULT 0,
      total_price $realType,
      FOREIGN KEY (sale_id) REFERENCES sales (id)
    )
    ''');

    // Users / Staff Table
    await db.execute('''
    CREATE TABLE users (
      id $idType,
      staff_id $textType UNIQUE,
      password_hash $textType,
      role $textType,
      permissions $textNullable
    )
    ''');

    // Events Table for Syncing
    await db.execute('''
    CREATE TABLE events (
      id $idType,
      entity_type $textType,
      entity_id $textType,
      action $textType,
      payload $textType,
      is_synced INTEGER DEFAULT 0,
      device_id $textNullable,
      created_at $textType
    )
    ''');

    // Paired Devices Table
    await db.execute('''
    CREATE TABLE paired_devices (
      id $idType,
      name $textType,
      device_type $textType,
      paired_at $textType,
      last_sync_at $textNullable,
      is_approved INTEGER DEFAULT 0
    )
    ''');

    // Label Templates Table
    await db.execute('''
    CREATE TABLE label_templates (
      id $idType,
      name $textType,
      config $textType,
      created_at $textType
    )
    ''');

    // Settings Table
    await db.execute('''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''');

    // Product Groups Table
    await db.execute('''
    CREATE TABLE IF NOT EXISTS product_groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''');

    // Roles Table
    await db.execute('''
    CREATE TABLE roles (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      permissions TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''');

    // Customers Table
    await db.execute('''
    CREATE TABLE IF NOT EXISTS customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      address TEXT,
      notes TEXT,
      tax_office TEXT,
      tax_number TEXT,
      created_at TEXT NOT NULL,
      credit_limit REAL,
      payment_due_days INTEGER
    )
    ''');

    // Suppliers Table
    await db.execute('''
    CREATE TABLE IF NOT EXISTS suppliers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      address TEXT,
      notes TEXT,
      tax_office TEXT,
      tax_number TEXT,
      created_at TEXT NOT NULL,
      credit_limit REAL
    )
    ''');

    // Client Transactions Table
    await db.execute('''
    CREATE TABLE IF NOT EXISTS client_transactions (
      id TEXT PRIMARY KEY,
      client_id TEXT NOT NULL,
      client_type TEXT NOT NULL,
      amount REAL NOT NULL,
      transaction_type TEXT NOT NULL,
      payment_method TEXT,
      description TEXT,
      sale_id TEXT,
      created_at TEXT NOT NULL
    )
    ''');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
