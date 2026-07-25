import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/payment.dart';
import '../models/settings.dart';
import '../utils/database_helper.dart';

class DataProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Customer> _customers = [];
  List<Product> _products = [];
  List<Invoice> _invoices = [];
  List<Payment> _payments = [];
  AppSettings _settings = AppSettings();

  List<Customer> get customers => _customers;
  List<Product> get products => _products;
  List<Invoice> get invoices => _invoices;
  List<Payment> get payments => _payments;
  AppSettings get settings => _settings;

  DataProvider() {
    loadAllData();
  }

  Future<void> loadAllData() async {
    await loadCustomers();
    await loadProducts();
    await loadInvoices();
    await loadPayments();
    await loadSettings();
  }

  Future<void> loadCustomers() async {
    _customers = await _db.getAllCustomers();
    notifyListeners();
  }

  Future<void> addCustomer(Customer customer) async {
    await _db.insertCustomer(customer);
    await loadCustomers();
  }

  Future<void> updateCustomer(Customer customer) async {
    await _db.updateCustomer(customer);
    await loadCustomers();
  }

  Future<void> deleteCustomer(int id) async {
    await _db.deleteCustomer(id);
    await loadCustomers();
  }

  Customer? getCustomerById(int id) {
    try { return _customers.firstWhere((c) => c.id == id); }
    catch (e) { return null; }
  }

  Future<void> loadProducts() async {
    _products = await _db.getAllProducts();
    notifyListeners();
  }

  Future<void> addProduct(Product product) async {
    await _db.insertProduct(product);
    await loadProducts();
  }

  Future<void> updateProduct(Product product) async {
    await _db.updateProduct(product);
    await loadProducts();
  }

  Future<void> deleteProduct(int id) async {
    await _db.deleteProduct(id);
    await loadProducts();
  }

  Future<void> loadInvoices() async {
    _invoices = await _db.getAllInvoices();
    notifyListeners();
  }

  Future<void> addInvoice(Invoice invoice) async {
    await _db.insertInvoice(invoice);
    await _db.updateCustomerBalance(invoice.customerId, invoice.newBalance ?? 0);
    await loadInvoices();
    await loadCustomers();
  }

  Future<void> updateInvoice(Invoice invoice) async {
    await _db.updateInvoice(invoice);
    await _db.updateCustomerBalance(invoice.customerId, invoice.newBalance ?? 0);
    await loadInvoices();
    await loadCustomers();
  }

  Future<void> deleteInvoice(int id) async {
    final inv = await _db.getInvoice(id);
    if (inv != null) {
      final customer = await _db.getCustomer(inv.customerId);
      if (customer != null) {
        double newBalance = customer.balance - inv.total;
        await _db.updateCustomerBalance(customer.id!, newBalance);
      }
    }
    await _db.deleteInvoice(id);
    await loadInvoices();
    await loadCustomers();
  }

  Future<int> getNextInvoiceNumber() async {
    return await _db.getNextInvoiceNumber();
  }

  Future<void> loadPayments() async {
    _payments = await _db.getAllPayments();
    notifyListeners();
  }

  Future<void> addPayment(Payment payment) async {
    await _db.insertPayment(payment);
    await _db.updateCustomerBalance(payment.customerId, payment.newBalance ?? 0);
    await loadPayments();
    await loadCustomers();
  }

  Future<void> updatePayment(Payment payment) async {
    await _db.updatePayment(payment);
    await _db.updateCustomerBalance(payment.customerId, payment.newBalance ?? 0);
    await loadPayments();
    await loadCustomers();
  }

  Future<void> deletePayment(int id) async {
    final pay = await _db.getPayment(id);
    if (pay != null) {
      final customer = await _db.getCustomer(pay.customerId);
      if (customer != null) {
        double newBalance = customer.balance + pay.amount;
        await _db.updateCustomerBalance(customer.id!, newBalance);
      }
    }
    await _db.deletePayment(id);
    await loadPayments();
    await loadCustomers();
  }

  Future<int> getNextReceiptNumber() async {
    return await _db.getNextReceiptNumber();
  }

  Future<List<Map<String, dynamic>>> getCustomerStatement(int customerId) async {
    return await _db.getCustomerStatement(customerId);
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('app_settings');
    if (settingsJson != null) {
      _settings = AppSettings.fromMap(jsonDecode(settingsJson));
    }
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_settings', jsonEncode(settings.toMap()));
    notifyListeners();
  }
}
