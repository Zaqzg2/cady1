import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../providers/data_provider.dart';
import '../utils/pdf_helper.dart';
import '../utils/print_helper.dart';

class PaymentScreen extends StatefulWidget {
  final Payment? existingPayment;
  const PaymentScreen({super.key, this.existingPayment});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late TextEditingController _receiptNumberCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _notesCtrl;

  DateTime _selectedDate = DateTime.now();
  Customer? _selectedCustomer;
  String _paymentType = 'cash';
  double _previousBalance = 0;
  double _newBalance = 0;

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _initControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _initControllers() {
    if (widget.existingPayment != null) {
      final p = widget.existingPayment!;
      _receiptNumberCtrl = TextEditingController(text: p.receiptNumber);
      _selectedDate = p.date;
      _amountCtrl = TextEditingController(text: p.amount.toStringAsFixed(2));
      _notesCtrl = TextEditingController(text: p.notes);
      _paymentType = p.paymentType;
    } else {
      _receiptNumberCtrl = TextEditingController();
      _amountCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
    }
    _dateCtrl = TextEditingController(text: DateFormat('yyyy/MM/dd').format(_selectedDate));
  }

  Future<void> _loadData() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await provider.loadCustomers();
    if (widget.existingPayment == null) {
      final nextNum = await provider.getNextReceiptNumber();
      setState(() => _receiptNumberCtrl.text = 'RCP\${nextNum.toString().padLeft(5, '0')}');
    } else {
      final customer = provider.getCustomerById(widget.existingPayment!.customerId);
      if (customer != null) {
        setState(() { _selectedCustomer = customer; _previousBalance = customer.balance; _calculateBalance(); });
      }
    }
  }

  void _calculateBalance() {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (_selectedCustomer != null) _newBalance = _previousBalance - amount;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سند قبض'),
        actions: [
          if (widget.existingPayment != null)
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
                _buildPaymentTypeSelector(),
                const SizedBox(height: 16),
                _buildCustomerSelector(provider),
                const SizedBox(height: 16),
                _buildAmountField(),
                const SizedBox(height: 16),
                _buildBalanceCard(),
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
        Expanded(child: _buildTextField(controller: _receiptNumberCtrl, label: 'رقم السند', icon: Icons.numbers)),
        const SizedBox(width: 12),
        Expanded(child: _buildTextField(controller: _dateCtrl, label: 'التاريخ', icon: Icons.calendar_today, readOnly: true, onTap: () => _pickDate(context))),
      ],
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool readOnly = false, int maxLines = 1, TextInputType? keyboardType, Function(String)? onChanged, VoidCallback? onTap}) {
    return TextField(controller: controller, readOnly: readOnly, maxLines: maxLines, keyboardType: keyboardType, onChanged: onChanged, onTap: onTap,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true));
  }

  Widget _buildPaymentTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: ChoiceChip(label: const Text('نقداً'), selected: _paymentType == 'cash', onSelected: (v) { if (v) setState(() => _paymentType = 'cash'); })),
          const SizedBox(width: 8),
          Expanded(child: ChoiceChip(label: const Text('تحويل'), selected: _paymentType == 'transfer', onSelected: (v) { if (v) setState(() => _paymentType = 'transfer'); })),
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
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { _selectedCustomer = null; _previousBalance = 0; _calculateBalance(); }); }),
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
                  onTap: () { setState(() { _selectedCustomer = customer; _previousBalance = customer.balance; _calculateBalance(); }); },
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

  Widget _buildAmountField() {
    return _buildTextField(controller: _amountCtrl, label: 'المبلغ', icon: Icons.money, keyboardType: TextInputType.number, onChanged: (v) => _calculateBalance());
  }

  Widget _buildBalanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTotalRow('الرصيد السابق:', _previousBalance),
            _buildTotalRow('المبلغ المحصل:', double.tryParse(_amountCtrl.text) ?? 0, color: Colors.green),
            const Divider(),
            _buildTotalRow('الرصيد الجديد:', _newBalance, isBold: true, color: _newBalance > 0 ? Colors.red : Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('\${value.toStringAsFixed(2)} ر.ي', style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('توقيع المندوب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            onPressed: _savePayment, icon: const Icon(Icons.save), label: const Text('حفظ', style: TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(onPressed: _amountCtrl.text.isEmpty ? null : _printReceipt, icon: const Icon(Icons.print), label: const Text('طباعة'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: _amountCtrl.text.isEmpty ? null : _downloadPDF, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: _amountCtrl.text.isEmpty ? null : _shareReceipt, icon: const Icon(Icons.share), label: const Text('مشاركة'),
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

  Future<void> _savePayment() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح'))); return; }
    if (_selectedCustomer == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار عميل'))); return; }

    final signature = await _signatureController.toPngBytes();
    final signatureBase64 = signature != null ? base64Encode(signature) : null;

    final payment = Payment(
      id: widget.existingPayment?.id,
      receiptNumber: _receiptNumberCtrl.text,
      customerId: _selectedCustomer!.id!,
      customerName: _selectedCustomer!.name,
      amount: amount,
      paymentType: _paymentType,
      date: _selectedDate,
      notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      signature: signatureBase64,
      previousBalance: _previousBalance,
      newBalance: _newBalance,
    );

    final provider = Provider.of<DataProvider>(context, listen: false);
    if (widget.existingPayment != null) await provider.updatePayment(payment);
    else await provider.addPayment(payment);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح')));
      Navigator.pop(context);
    }
  }

  Future<void> _printReceipt() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await PrintHelper.printPayment(context, _buildPaymentData(), provider.settings);
  }

  Future<void> _downloadPDF() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await PdfHelper.generatePaymentPdf(context, _buildPaymentData(), provider.settings);
  }

  Future<void> _shareReceipt() async {
    final provider = Provider.of<DataProvider>(context, listen: false);
    await PdfHelper.sharePaymentPdf(context, _buildPaymentData(), provider.settings);
  }

  Payment _buildPaymentData() {
    return Payment(
      receiptNumber: _receiptNumberCtrl.text, customerId: _selectedCustomer?.id ?? 0,
      customerName: _selectedCustomer?.name ?? '', amount: double.tryParse(_amountCtrl.text) ?? 0,
      paymentType: _paymentType, date: _selectedDate, notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      previousBalance: _previousBalance, newBalance: _newBalance,
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'), content: const Text('هل أنت متأكد من حذف هذا السند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              await Provider.of<DataProvider>(context, listen: false).deletePayment(widget.existingPayment!.id!);
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
    _receiptNumberCtrl.dispose(); _dateCtrl.dispose(); _amountCtrl.dispose(); _notesCtrl.dispose(); _signatureController.dispose();
    super.dispose();
  }
}
