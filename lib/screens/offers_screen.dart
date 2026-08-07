import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/offer.dart';
import '../services/db_service.dart';
import '../services/manager_service.dart';
import '../utils/formatters.dart';

/// شاشة العروض — تُعرض للمندوب كقائمة للاطلاع فقط (العروض تصله ضمن ملف
/// تحديث من المدير)، وللمدير كشاشة إدارة كاملة (إضافة/تعديل/حذف) عبر
/// [editable].
class OffersScreen extends StatefulWidget {
  final bool editable;
  const OffersScreen({super.key, this.editable = false});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<Offer> _offers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offers = await DbService.instance.getOffers();
    if (!mounted) return;
    setState(() {
      _offers = offers;
      _loading = false;
    });
  }

  Future<void> _editOffer([Offer? existing]) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final discountCtrl = TextEditingController(
        text: (existing != null && existing.discountPercent > 0)
            ? existing.discountPercent.toStringAsFixed(0)
            : '');
    DateTime? start = existing?.startDate;
    DateTime? end = existing?.endDate;
    bool active = existing?.isActive ?? true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'إضافة عرض' : 'تعديل العرض',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'عنوان العرض'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'نسبة الخصم % (اختياري)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: start ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setSheetState(() => start = picked);
                            }
                          },
                          child: Text(start != null
                              ? 'من: ${Formatters.d(start!)}'
                              : 'تاريخ البداية'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: end ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setSheetState(() => end = picked);
                          },
                          child: Text(end != null
                              ? 'إلى: ${Formatters.d(end!)}'
                              : 'تاريخ النهاية'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('نشط'),
                    value: active,
                    onChanged: (v) => setSheetState(() => active = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (titleCtrl.text.trim().isEmpty) return;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('حفظ'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (saved == true) {
      final offer = Offer(
        id: existing?.id ?? const Uuid().v4(),
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        discountPercent: double.tryParse(discountCtrl.text.trim()) ?? 0,
        startDate: start,
        endDate: end,
        isActive: active,
        createdAt: existing?.createdAt,
      );
      await ManagerService.instance.saveOffer(offer);
      await _load();
    }
  }

  Future<void> _deleteOffer(Offer o) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف العرض؟'),
        content: Text('سيُحذف عرض "${o.title}" نهائيًا.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ManagerService.instance.deleteOffer(o.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('العروض')),
      floatingActionButton: widget.editable
          ? FloatingActionButton(
              onPressed: () => _editOffer(),
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _offers.isEmpty
              ? Center(
                  child: Text(
                    widget.editable
                        ? 'لا توجد عروض بعد — اضغط + لإضافة عرض'
                        : 'لا توجد عروض حاليًا',
                    style: const TextStyle(color: Colors.black54),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _offers.length,
                  itemBuilder: (context, index) {
                    final o = _offers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: o.isCurrentlyValid
                              ? primary.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.15),
                          child: Icon(Icons.local_offer_outlined,
                              color: o.isCurrentlyValid ? primary : Colors.grey),
                        ),
                        title: Text(o.title,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(_offerSubtitle(o)),
                        isThreeLine: o.description.isNotEmpty,
                        trailing: widget.editable
                            ? PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') _editOffer(o);
                                  if (v == 'delete') _deleteOffer(o);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('تعديل')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('حذف')),
                                ],
                              )
                            : (o.isCurrentlyValid
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : null),
                        onTap: widget.editable ? () => _editOffer(o) : null,
                      ),
                    );
                  },
                ),
    );
  }

  String _offerSubtitle(Offer o) {
    final parts = <String>[];
    if (o.discountPercent > 0) {
      parts.add('خصم ${o.discountPercent.toStringAsFixed(0)}٪');
    }
    if (o.description.isNotEmpty) parts.add(o.description);
    if (o.startDate != null || o.endDate != null) {
      final from = o.startDate != null ? Formatters.d(o.startDate!) : '...';
      final to = o.endDate != null ? Formatters.d(o.endDate!) : '...';
      parts.add('$from — $to');
    }
    if (!o.isActive) parts.add('(موقوف)');
    return parts.join(' • ');
  }
}
