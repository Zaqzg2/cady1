import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/payment.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kady_sales.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT,
        balance REAL DEFAULT 0,
        notes TEXT,
        createdAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        imagePath TEXT,
        category TEXT,
        isActive INTEGER DEFAULT 1,
        createdAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceNumber TEXT NOT NULL UNIQUE,
        customerId INTEGER NOT NULL,
        customerName TEXT NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        subtotal REAL DEFAULT 0,
        discountPercent REAL,
        discountAmount REAL,
        total REAL DEFAULT 0,
        notes TEXT,
        signature TEXT,
        previousBalance REAL,
        newBalance REAL,
        createdAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoiceId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        total REAL NOT NULL,
        FOREIGN KEY (invoiceId) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receiptNumber TEXT NOT NULL UNIQUE,
        customerId INTEGER NOT NULL,
        customerName TEXT NOT NULL,
        amount REAL NOT NULL,
        paymentType TEXT NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        signature TEXT,
        previousBalance REAL,
        newBalance REAL,
        createdAt TEXT
      )
    ''');
  }

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert('customers', customer.toMap());
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final maps = await db.query('customers', orderBy: 'name');
    return maps.map((e) => Customer.fromMap(e)).toList();
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await database;
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Customer.fromMap(maps.first);
    return null;
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    return await db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateCustomerBalance(int id, double newBalance) async {
    final db = await database;
    return await db.update('customers', {'balance': newBalance}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return await db.insert('products', product.toMap());
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('products', where: 'isActive = 1', orderBy: 'name');
    return maps.map((e) => Product.fromMap(e)).toList();
  }

  Future<Product?> getProduct(int id) async {
    final db = await database;
    final maps = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Product.fromMap(maps.first);
    return null;
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertInvoice(Invoice invoice) async {
    final db = await database;
    final invoiceId = await db.insert('invoices', invoice.toMap());
    for (var item in invoice.items) {
      item.invoiceId = invoiceId;
      await db.insert('invoice_items', item.toMap());
    }
    return invoiceId;
  }

  Future<List<Invoice>> getAllInvoices() async {
    final db = await database;
    final maps = await db.query('invoices', orderBy: 'date DESC');
    List<Invoice> invoices = [];
    for (var map in maps) {
      var inv = Invoice.fromMap(map);
      inv.items = await getInvoiceItems(inv.id!);
      invoices.add(inv);
    }
    return invoices;
  }

  Future<List<Invoice>> getInvoicesByCustomer(int customerId) async {
    final db = await database;
    final maps = await db.query('invoices', where: 'customerId = ?', whereArgs: [customerId], orderBy: 'date DESC');
    List<Invoice> invoices = [];
    for (var map in maps) {
      var inv = Invoice.fromMap(map);
      inv.items = await getInvoiceItems(inv.id!);
      invoices.add(inv);
    }
    return invoices;
  }

  Future<Invoice?> getInvoice(int id) async {
    final db = await database;
    final maps = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      var inv = Invoice.fromMap(maps.first);
      inv.items = await getInvoiceItems(inv.id!);
      return inv;
    }
    return null;
  }

  Future<int> updateInvoice(Invoice invoice) async {
    final db = await database;
    await db.delete('invoice_items', where: 'invoiceId = ?', whereArgs: [invoice.id]);
    for (var item in invoice.items) {
      item.invoiceId = invoice.id;
      await db.insert('invoice_items', item.toMap());
    }
    return await db.update('invoices', invoice.toMap(), where: 'id = ?', whereArgs: [invoice.id]);
  }

  Future<int> deleteInvoice(int id) async {
    final db = await database;
    await db.delete('invoice_items', where: 'invoiceId = ?', whereArgs: [id]);
    return await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<InvoiceItem>> getInvoiceItems(int invoiceId) async {
    final db = await database;
    final maps = await db.query('invoice_items', where: 'invoiceId = ?', whereArgs: [invoiceId]);
    return maps.map((e) => InvoiceItem.fromMap(e)).toList();
  }

  Future<int> getNextInvoiceNumber() async {
    final db = await database;
    final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(invoiceNumber, 4) AS INTEGER)) as maxNum FROM invoices WHERE invoiceNumber LIKE 'INV%'");
    int maxNum = (result.first['maxNum'] as int?) ?? 0;
    return maxNum + 1;
  }

  Future<int> insertPayment(Payment payment) async {
    final db = await database;
    return await db.insert('payments', payment.toMap());
  }

  Future<List<Payment>> getAllPayments() async {
    final db = await database;
    final maps = await db.query('payments', orderBy: 'date DESC');
    return maps.map((e) => Payment.fromMap(e)).toList();
  }

  Future<List<Payment>> getPaymentsByCustomer(int customerId) async {
    final db = await database;
    final maps = await db.query('payments', where: 'customerId = ?', whereArgs: [customerId], orderBy: 'date DESC');
    return maps.map((e) => Payment.fromMap(e)).toList();
  }

  Future<Payment?> getPayment(int id) async {
    final db = await database;
    final maps = await db.query('payments', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Payment.fromMap(maps.first);
    return null;
  }

  Future<int> updatePayment(Payment payment) async {
    final db = await database;
    return await db.update('payments', payment.toMap(), where: 'id = ?', whereArgs: [payment.id]);
  }

  Future<int> deletePayment(int id) async {
    final db = await database;
    return await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getNextReceiptNumber() async {
    final db = await database;
    final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(receiptNumber, 4) AS INTEGER)) as maxNum FROM payments WHERE receiptNumber LIKE 'RCP%'");
    int maxNum = (result.first['maxNum'] as int?) ?? 0;
    return maxNum + 1;
  }

  Future<List<Map<String, dynamic>>> getCustomerStatement(int customerId) async {
    final db = await database;
    final invoices = await db.rawQuery('''
      SELECT date, 'فاتورة بيع' as description, invoiceNumber as docNumber, 
             total as debit, 0 as credit, newBalance as balance, 'invoice' as type, id
      FROM invoices WHERE customerId = ?
    ''', [customerId]);
    final payments = await db.rawQuery('''
      SELECT date, 'سند قبض' as description, receiptNumber as docNumber, 
             0 as debit, amount as credit, newBalance as balance, 'payment' as type, id
      FROM payments WHERE customerId = ?
    ''', [customerId]);
    final allRecords = [...invoices, ...payments];
    allRecords.sort((a, b) => DateTime.parse(a['date'] as String).compareTo(DateTime.parse(b['date'] as String)));
    return allRecords;
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
