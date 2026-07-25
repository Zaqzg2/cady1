import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../providers/data_provider.dart';
import '../utils/pdf_helper.dart';
import '../utils/print_helper.dart';

class InvoiceScreen extends StatefulWidget {
  final bool isCash;
  final bool isReturn;
  final Invoice? existingInvoice;

  const InvoiceScreen({super.key, this.isCash = false, this.isReturn = false, this.existingInvoice});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  late TextEditingController _invoiceNumberCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _discountPercentCtrl;
  late TextEditingController _discountAmountCtrl;
  late TextEditingController _notesCtrl;

  DateTime _selectedDate = DateTime.now();
  Customer? _selectedCustomer;
  List<InvoiceItem> _items = [];
  double _subtotal = 0;
  double _discountPercent = 0;
  double _discountAmount = 0;
  double _total = 0;
  double _previousBalance = 0;
  double _newBalance = 0;

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _initControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  void _initControllers() {
    if (widget.existingInvoice != null) {
      final inv = widget.existingInvoice!;
      _invoiceNumberCtrl = TextEditingController(text: inv.invoiceNumber);
      _selectedDate = inv.date;
      _items = List.from(inv.items);
      _discountPercent = inv.discountPercent ?? 0;
      _discountAmount = inv.discountAmount ?? 0;
      _notesCtrl = TextEditingController(text: inv.notes);
      _calculateTotals();
    } else {
      _invoiceNumberCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
    }
    _dateCtrl = TextEditingController(text: DateFormat('yyyy/MM/dd').format(_selectedDate));
    _discountPercentCtrl = TextEditingController(text: _discountPercent > 0 ? _discountPercent.toString() : '');
    _discountAmountCtrl = TextEditingController(text: _discountAmount > 0 ? _discountAmount.toString() : '');
  }

  Future<void> _loadInitialData() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await provider.loadCustomers();
    await provider.loadProducts();

    if (widget.existingInvoice == null) {
      final nextNum = await provider.getNextInvoiceNumber();
      setState(() => _invoiceNumberCtrl.text = 'INV\${nextNum.toString().padLeft(5, '0')}');
    } else {
      final customer = provider.getCustomerById(widget.existingInvoice!.customerId);
      if (customer != null) {
        setState(() {
          _selectedCustomer = customer;
          _previousBalance = customer.balance;
        });
      }
    }
  }

  void _calculateTotals() {
    _subtotal = _items.fold(0, (sum, item) => sum + item.total);
    if (_discountPercent > 0) _discountAmount = _subtotal * (_discountPercent / 100);
    _total = _subtotal - _discountAmount;
    if (_total < 0) _total = 0;
    if (_selectedCustomer != null) {
      if (widget.isReturn) _newBalance = _previousBalance - _total;
      else _newBalance = _previousBalance + _total;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isReturn ? 'فاتورة مرتجع' : widget.isCash ? 'فاتورة نقدية' : 'فاتورة بيع';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.existingInvoice != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _confirmDelete),
        ],
      ),
      body: Consumer<DataProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderRow(),
                const SizedBox(height: 16),
                _buildTypeSelector(),
                const SizedBox(height: 16),
                _buildCustomerSelector(provider),
                const SizedBox(height: 16),
                _buildProductSelector(provider),
                const SizedBox(height: 16),
                if (_items.isNotEmpty) _buildItemsList(),
                const SizedBox(height: 16),
                _buildTotalsCard(),
                const SizedBox(height: 16),
                _buildDiscountSection(),
                const SizedBox(height: 16),
                _buildTextField(controller: _notesCtrl, label: 'ملاحظات', icon: Icons.notes, maxLines: 3),
                const SizedBox(height: 16),
                _buildSignatureSection(),
                const SizedBox(height: 24),
                _buildActionButtons(),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        Expanded(child: _buildTextField(controller: _invoiceNumberCtrl, label: 'رقم الفاتورة', icon: Icons.numbers)),
        const SizedBox(width: 12),
        Expanded(child: _buildTextField(controller: _dateCtrl, label: 'التاريخ', icon: Icons.calendar_today, readOnly: true, onTap: () => _pickDate(context))),
      ],
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool readOnly = false, int maxLines = 1, TextInputType? keyboardType, Function(String)? onChanged, VoidCallback? onTap}) {
    return TextField(controller: controller, readOnly: readOnly, maxLines: maxLines, keyboardType: keyboardType, onChanged: onChanged, onTap: onTap,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true));
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: ChoiceChip(label: const Text('نقدي'), selected: widget.isCash, onSelected: (v) {})),
          const SizedBox(width: 8),
          Expanded(child: ChoiceChip(label: const Text('آجل'), selected: !widget.isCash && _selectedCustomer != null, onSelected: (v) {})),
        ],
      ),
    );
  }

  Widget _buildCustomerSelector(DataProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('اختيار العميل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_selectedCustomer != null)
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, child: Text(_selectedCustomer!.name[0], style: const TextStyle(color: Colors.white))),
              title: Text(_selectedCustomer!.name),
              subtitle: Text('الرصيد: \${_selectedCustomer!.balance.toStringAsFixed(2)} ر.ي'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { _selectedCustomer = null; _previousBalance = 0; _calculateTotals(); }); }),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: provider.customers.length,
              itemBuilder: (context, index) {
                final customer = provider.customers[index];
                return GestureDetector(
                  onTap: () { setState(() { _selectedCustomer = customer; _previousBalance = customer.balance; _calculateTotals(); }); },
                  child: Container(
                    width: 140, margin: const EdgeInsets.only(left: 10), padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3))),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, child: Text(customer.name[0], style: const TextStyle(color: Colors.white))),
                        const SizedBox(height: 8),
                        Text(customer.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('\${customer.balance.toStringAsFixed(0)} ر.ي', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildProductSelector(DataProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('المنتجات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.4, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: provider.products.length,
          itemBuilder: (context, index) {
            final product = provider.products[index];
            return GestureDetector(
              onTap: () => _addProduct(product),
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2))),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 32),
                    const SizedBox(height: 6),
                    Text(product.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('\${product.price.toStringAsFixed(0)} ر.ي', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _addProduct(Product product) {
    final existingIndex = _items.indexWhere((i) => i.productId == product.id);
    if (existingIndex >= 0) {
      setState(() { _items[existingIndex].quantity++; _items[existingIndex].total = _items[existingIndex].quantity * _items[existingIndex].price; });
    } else {
      setState(() { _items.add(InvoiceItem(productId: product.id!, productName: product.name, price: product.price, quantity: 1, total: product.price)); });
    }
    _calculateTotals();
  }

  Widget _buildItemsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('الأصناف المضافة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildQtyButton(icon: Icons.remove, onTap: () => _updateQuantity(index, -1)),
                        Container(margin: const EdgeInsets.symmetric(horizontal: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                          child: Text('\${item.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        _buildQtyButton(icon: Icons.add, onTap: () => _updateQuantity(index, 1)),
                      ],
                    ),
                  ),
                  Expanded(child: Text('\${item.total.toStringAsFixed(0)}', textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), onPressed: () { setState(() => _items.removeAt(index)); _calculateTotals(); }),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildQtyButton({required IconData icon, required VoidCallback onTap}) {
    return Material(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.all(6), child: Icon(icon, color: Colors.white, size: 18))),
    );
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      _items[index].quantity += delta;
      if (_items[index].quantity <= 0) _items.removeAt(index);
      else _items[index].total = _items[index].quantity * _items[index].price;
    });
    _calculateTotals();
  }

  Widget _buildTotalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTotalRow('الإجمالي الفرعي:', _subtotal),
            if (_discountAmount > 0) _buildTotalRow('الخصم:', _discountAmount, isDiscount: true),
            const Divider(),
            _buildTotalRow('الإجمالي:', _total, isBold: true),
            if (_selectedCustomer != null) ...[
              const Divider(),
              _buildTotalRow('الرصيد السابق:', _previousBalance),
              _buildTotalRow('الرصيد الجديد:', _newBalance, isBold: true, color: _newBalance > 0 ? Colors.red : Colors.green),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool isBold = false, bool isDiscount = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('\${value.toStringAsFixed(2)} ر.ي', style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? (isDiscount ? Colors.red : null))),
        ],
      ),
    );
  }

  Widget _buildDiscountSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الخصم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildTextField(controller: _discountPercentCtrl, label: 'نسبة %', icon: Icons.percent, keyboardType: TextInputType.number,
                  onChanged: (v) { _discountPercent = double.tryParse(v) ?? 0; _discountAmountCtrl.clear(); _calculateTotals(); })),
                const SizedBox(width: 12),
                Expanded(child: _buildTextField(controller: _discountAmountCtrl, label: 'مبلغ', icon: Icons.money_off, keyboardType: TextInputType.number,
                  onChanged: (v) { _discountAmount = double.tryParse(v) ?? 0; _discountPercentCtrl.clear(); _discountPercent = 0; _calculateTotals(); })),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('توقيع العميل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Signature(controller: _signatureController, height: 150, backgroundColor: Colors.white)),
        ),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: () => _signatureController.clear(), icon: const Icon(Icons.clear), label: const Text('مسح التوقيع')),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(width: double.infinity, height: 56,
          child: FilledButton.icon(
            onPressed: _saveInvoice, icon: const Icon(Icons.save), label: const Text('حفظ', style: TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(onPressed: _items.isEmpty ? null : _printInvoice, icon: const Icon(Icons.print), label: const Text('طباعة'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: _items.isEmpty ? null : _downloadPDF, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: _items.isEmpty ? null : _shareInvoice, icon: const Icon(Icons.share), label: const Text('مشاركة'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (picked != null) setState(() { _selectedDate = picked; _dateCtrl.text = DateFormat('yyyy/MM/dd').format(picked); });
  }

  Future<void> _saveInvoice() async {
    if (_items.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إضافة منتجات'))); return; }
    if (_selectedCustomer == null && !widget.isCash) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار عميل'))); return; }

    final signature = await _signatureController.toPngBytes();
    final signatureBase64 = signature != null ? base64Encode(signature) : null;

    final invoice = Invoice(
      id: widget.existingInvoice?.id,
      invoiceNumber: _invoiceNumberCtrl.text,
      customerId: _selectedCustomer?.id ?? 0,
      customerName: _selectedCustomer?.name ?? 'عميل نقدي',
      type: widget.isCash ? 'cash' : 'credit',
      date: _selectedDate,
      items: _items,
      subtotal: _subtotal,
      discountPercent: _discountPercent > 0 ? _discountPercent : null,
      discountAmount: _discountAmount > 0 ? _discountAmount : null,
      total: _total,
      notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      signature: signatureBase64,
      previousBalance: _previousBalance,
      newBalance: _newBalance,
    );

    final provider = Provider.of<DataProvider>(context, listen: false);
    if (widget.existingInvoice != null) await provider.updateInvoice(invoice);
    else await provider.addInvoice(invoice);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح')));
      Navigator.pop(context);
    }
  }

  Future<void> _printInvoice() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await PrintHelper.printInvoice(context, _buildInvoiceData(), provider.settings);
  }

  Future<void> _downloadPDF() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await PdfHelper.generateInvoicePdf(context, _buildInvoiceData(), provider.settings);
  }

  Future<void> _shareInvoice() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await PdfHelper.shareInvoicePdf(context, _buildInvoiceData(), provider.settings);
  }

  Invoice _buildInvoiceData() {
    return Invoice(
      invoiceNumber: _invoiceNumberCtrl.text, customerId: _selectedCustomer?.id ?? 0,
      customerName: _selectedCustomer?.name ?? 'عميل نقدي', type: widget.isCash ? 'cash' : 'credit',
      date: _selectedDate, items: _items, subtotal: _subtotal,
      discountPercent: _discountPercent > 0 ? _discountPercent : null,
      discountAmount: _discountAmount > 0 ? _discountAmount : null,
      total: _total, notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      previousBalance: _previousBalance, newBalance: _newBalance,
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'), content: const Text('هل أنت متأكد من حذف هذه الفاتورة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              await Provider.of<DataProvider>(context, listen: false).deleteInvoice(widget.existingInvoice!.id!);
              if (mounted) { Navigator.pop(ctx); Navigator.pop(context); }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _invoiceNumberCtrl.dispose(); _dateCtrl.dispose(); _discountPercentCtrl.dispose();
    _discountAmountCtrl.dispose(); _notesCtrl.dispose(); _signatureController.dispose();
    super.dispose();
  }
}
