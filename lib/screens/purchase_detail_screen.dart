import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/catalog_models.dart';
import '../models/purchase_models.dart';
import '../providers/inventory_provider.dart';
import '../services/attachment_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_styles.dart';

final _dateFormat = DateFormat('yyyy/MM/dd');
final _attachmentService = AttachmentService();

/// إنشاء/إدارة طلب شراء واحد (القسم 13-16): الإنشاء نموذج بسيط بخطوة واحدة؛
/// الإدارة (بعد الإنشاء) تعرض الحالة مباشرة من المزوّد وتحفظ كل تعديل فورًا
/// — بلا نسخة محلية منفصلة قد تتعارض مع حالة محفوظة فعليًا.
class PurchaseDetailScreen extends StatefulWidget {
  final String? requestId;
  const PurchaseDetailScreen({super.key, this.requestId});

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  String _newBranchId = '';
  final _newSupplier = TextEditingController();
  final _newNotes = TextEditingController();
  DateTime _newDate = DateTime.now();
  final List<PurchaseRequestItem> _newItems = [];

  bool get _isNew => widget.requestId == null;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      final provider = context.read<InventoryProvider>();
      _newBranchId = provider.branches.isNotEmpty ? provider.branches.first.id : '';
    }
  }

  @override
  void dispose() {
    _newSupplier.dispose();
    _newNotes.dispose();
    super.dispose();
  }

  // ---------------- إنشاء طلب جديد ----------------

  Future<(String, double)?> _showItemPickerDialog(BuildContext context, List<Product> products) async {
    String productId = products.first.id;
    final qtyController = TextEditingController(text: '1');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          title: const Text('إضافة صنف للطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الصنف'),
                items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                onChanged: (v) => setSheetState(() => productId = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الكمية المطلوبة'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (result != true) return null;
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    if (qty <= 0) return null;
    return (productId, qty);
  }

  Future<void> _addNewItemRow(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final result = await _showItemPickerDialog(context, provider.products);
    if (result == null) return;
    setState(() => _newItems.add(PurchaseRequestItem(productId: result.$1, requestedQty: result.$2)));
  }

  Future<void> _createRequest(BuildContext context) async {
    if (_newBranchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر فرعًا أولًا.')));
      return;
    }
    if (_newItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل.')));
      return;
    }
    final provider = context.read<InventoryProvider>();
    final request = PurchaseRequest(
      requestNumber: provider.suggestPurchaseRequestNumber(),
      date: _newDate,
      branchId: _newBranchId,
      supplierName: _newSupplier.text.trim().isEmpty ? null : _newSupplier.text.trim(),
      notes: _newNotes.text.trim().isEmpty ? null : _newNotes.text.trim(),
      status: PurchaseRequestStatus.requested,
      items: _newItems,
    );
    await provider.savePurchaseRequest(request);
    if (context.mounted) Navigator.of(context).pop();
  }

  Widget _buildCreateForm(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    if (provider.branches.isEmpty || provider.products.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('طلب شراء جديد')),
        body: EmptyState(
          icon: Icons.info_outline,
          title: 'أضف فرعًا وصنفًا واحدًا على الأقل أولًا',
          subtitle: 'طلب الشراء يحتاج فرعًا مستلِمًا وصنفًا واحدًا على الأقل من التصنيفات.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('طلب شراء جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _newBranchId.isEmpty ? null : _newBranchId,
            decoration: const InputDecoration(labelText: 'الفرع'),
            items: provider.branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
            onChanged: (v) => setState(() => _newBranchId = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(controller: _newSupplier, decoration: const InputDecoration(labelText: 'المورد (اختياري)')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('التاريخ'),
            subtitle: Text(_dateFormat.format(_newDate)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _newDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _newDate = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newNotes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('الأصناف', style: TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: () => _addNewItemRow(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
            ],
          ),
          if (_newItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('لم تُضف أي أصناف بعد.', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._newItems.asMap().entries.map((entry) {
              final product = provider.productById(entry.value.productId);
              return Card(
                child: ListTile(
                  title: Text(product?.name ?? '—'),
                  subtitle: Text('المطلوب: ${entry.value.requestedQty.toStringAsFixed(0)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _newItems.removeAt(entry.key)),
                  ),
                ),
              );
            }),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: () => _createRequest(context), child: const Text('إنشاء الطلب')),
        ),
      ),
    );
  }

  // ---------------- إدارة طلب موجود ----------------

  Future<void> _addItemToExisting(BuildContext context, PurchaseRequest request) async {
    final provider = context.read<InventoryProvider>();
    if (provider.products.isEmpty) return;
    final result = await _showItemPickerDialog(context, provider.products);
    if (result == null) return;
    request.items.add(PurchaseRequestItem(productId: result.$1, requestedQty: result.$2));
    await provider.savePurchaseRequest(request);
  }

  Future<void> _receiveItem(
      BuildContext context, PurchaseRequest request, PurchaseRequestItem item) async {
    final controller = TextEditingController(
        text: item.remainingQty > 0 ? item.remainingQty.toStringAsFixed(0) : '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل استلام'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الكمية المستلَمة الآن'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final qty = double.tryParse(controller.text.trim()) ?? 0;
    if (qty <= 0) return;
    await context
        .read<InventoryProvider>()
        .receiveAgainstPurchaseRequest(requestId: request.id, itemId: item.id, quantity: qty);
  }

  Future<void> _editHeaderField(BuildContext context, PurchaseRequest request) async {
    final numberController = TextEditingController(text: request.requestNumber);
    final supplierController = TextEditingController(text: request.supplierName ?? '');
    final notesController = TextEditingController(text: request.notes ?? '');
    var date = request.date;
    var status = request.status;
    final provider = context.read<InventoryProvider>();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تعديل بيانات الطلب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                TextField(controller: numberController, decoration: const InputDecoration(labelText: 'رقم الطلب')),
                const SizedBox(height: 12),
                TextField(controller: supplierController, decoration: const InputDecoration(labelText: 'المورد')),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('التاريخ'),
                  subtitle: Text(_dateFormat.format(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setSheetState(() => date = picked);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PurchaseRequestStatus>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: PurchaseRequestStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.labelAr)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => status = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    request.requestNumber = numberController.text.trim();
    request.supplierName =
        supplierController.text.trim().isEmpty ? null : supplierController.text.trim();
    request.notes = notesController.text.trim().isEmpty ? null : notesController.text.trim();
    request.date = date;
    request.status = status;
    await provider.savePurchaseRequest(request);
  }

  Future<void> _addAttachment(BuildContext context, PurchaseRequest request) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('صورة من المعرض'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('ملف (PDF / Excel)'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    Uint8List? bytes;
    String? name;
    if (choice == 'image') {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      bytes = await picked.readAsBytes();
      name = picked.name;
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      bytes = result.files.first.bytes;
      name = result.files.first.name;
    }
    if (bytes == null || name == null || !context.mounted) return;

    final error = await context
        .read<InventoryProvider>()
        .addAttachmentToPurchaseRequest(request.id, fileName: name, bytes: bytes);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _openAttachment(BuildContext context, PurchaseAttachment attachment) async {
    final bytes = _attachmentService.decode(attachment.dataBase64);
    if (attachment.type == PurchaseAttachmentType.image) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))),
      );
    } else if (attachment.type == PurchaseAttachmentType.pdf) {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } else {
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: attachment.fileName)]));
    }
  }

  Future<void> _deleteAttachment(
      BuildContext context, PurchaseRequest request, PurchaseAttachment a) async {
    final confirmed =
        await showConfirmDialog(context, title: 'حذف المرفق', message: 'هل تريد حذف "${a.fileName}"؟');
    if (!confirmed) return;
    await context.read<InventoryProvider>().removeAttachmentFromPurchaseRequest(request.id, a.id);
  }

  Future<void> _deleteRequest(BuildContext context, PurchaseRequest request) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف الطلب',
      message: 'سيُحذف الطلب نهائيًا. أي حركات وارد سُجِّلت مسبقًا بناءً عليه تبقى محفوظة في سجل الحركات.',
    );
    if (!confirmed) return;
    await context.read<InventoryProvider>().deletePurchaseRequest(request.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  Widget _buildDetail(BuildContext context, PurchaseRequest request) {
    final provider = context.watch<InventoryProvider>();
    final branch = provider.branchById(request.branchId);
    final canReceive =
        request.status != PurchaseRequestStatus.draft && request.status != PurchaseRequestStatus.cancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text(request.requestNumber.isEmpty ? '#${request.id.substring(0, 6)}' : request.requestNumber),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editHeaderField(context, request)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRequest(context, request)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(label: request.status.labelAr, color: colorForPurchaseStatus(request.status)),
              Text('${_dateFormat.format(request.date)} · ${branch?.name ?? '—'}'),
            ],
          ),
          if (request.supplierName != null) ...[
            const SizedBox(height: 6),
            Text('المورد: ${request.supplierName}'),
          ],
          if (request.notes != null && request.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(request.notes!, style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _StatBlock(label: 'المطلوب', value: request.totalRequested),
                  _StatBlock(label: 'الوارد', value: request.totalReceived),
                  _StatBlock(label: 'المتبقي', value: request.totalRemaining),
                  Expanded(
                    child: Column(
                      children: [
                        Text('${request.fulfillmentPct.toStringAsFixed(0)}٪',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Text('التوريد', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('الأصناف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              TextButton.icon(
                onPressed: () => _addItemToExisting(context, request),
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
            ],
          ),
          ...request.items.map((item) {
            final product = provider.productById(item.productId);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'مطلوب ${item.requestedQty.toStringAsFixed(0)} · وارد ${item.receivedQty.toStringAsFixed(0)} · متبقٍ ${item.remainingQty.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: canReceive ? () => _receiveItem(context, request, item) : null,
                          child: const Text('استلام'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: (item.fulfillmentPct / 100).clamp(0, 1),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('المرفقات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              TextButton.icon(
                onPressed: () => _addAttachment(context, request),
                icon: const Icon(Icons.add),
                label: const Text('إضافة مرفق'),
              ),
            ],
          ),
          if (request.attachments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('لا توجد مرفقات بعد.', style: TextStyle(color: Colors.grey)),
            )
          else
            ...request.attachments.map((a) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(a.type == PurchaseAttachmentType.image
                        ? Icons.image_outlined
                        : a.type == PurchaseAttachmentType.pdf
                            ? Icons.picture_as_pdf_outlined
                            : Icons.insert_drive_file_outlined),
                    title: Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_attachmentService.formatSize(a.sizeBytes)),
                    onTap: () => _openAttachment(context, a),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteAttachment(context, request, a),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isNew) return _buildCreateForm(context);

    final provider = context.watch<InventoryProvider>();
    final matches = provider.purchaseRequests.where((r) => r.id == widget.requestId).toList();
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: 'هذا الطلب لم يعد موجودًا'),
      );
    }
    return _buildDetail(context, matches.first);
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final double value;
  const _StatBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
