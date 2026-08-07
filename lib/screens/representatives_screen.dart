import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/representative.dart';
import '../services/manager_service.dart';
import '../utils/formatters.dart';

/// شاشة إدارة المندوبين لدى المدير: إضافة مندوب، تعديل بياناته،
/// تفعيل/إيقاف، وإعادة تعيين آخر مزامنة.
class RepresentativesScreen extends StatefulWidget {
  const RepresentativesScreen({super.key});

  @override
  State<RepresentativesScreen> createState() => _RepresentativesScreenState();
}

class _RepresentativesScreenState extends State<RepresentativesScreen> {
  List<Representative> _reps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reps = await ManagerService.instance.getRepresentatives();
    if (!mounted) return;
    setState(() {
      _reps = reps;
      _loading = false;
    });
  }

  Future<void> _editRep([Representative? existing]) async {
    final codeCtrl = TextEditingController(text: existing?.repCode ?? '');
    final nameCtrl = TextEditingController(text: existing?.repName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String? error;

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
                  Text(
                      existing == null ? 'إضافة مندوب' : 'تعديل بيانات المندوب',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                        labelText: 'رقم المندوب', errorText: error),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم المندوب'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'رقم الهاتف (اختياري)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final code = codeCtrl.text.trim();
                        final name = nameCtrl.text.trim();
                        if (code.isEmpty || name.isEmpty) return;
                        final taken = await ManagerService.instance
                            .isRepCodeTaken(code, excludingId: existing?.id);
                        if (!ctx.mounted) return;
                        if (taken) {
                          setSheetState(
                              () => error = 'رقم المندوب هذا مستخدم مسبقًا');
                          return;
                        }
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
      final rep = Representative(
        id: existing?.id ?? const Uuid().v4(),
        repCode: codeCtrl.text.trim(),
        repName: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
        isActive: existing?.isActive ?? true,
        lastSyncAt: existing?.lastSyncAt,
        createdAt: existing?.createdAt,
      );
      await ManagerService.instance.saveRepresentative(rep);
      await _load();
    }
  }

  Future<void> _toggleActive(Representative r) async {
    await ManagerService.instance.setActive(r, !r.isActive);
    await _load();
  }

  Future<void> _resetLastSync(Representative r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إعادة تعيين آخر مزامنة؟'),
        content: Text(
            'سيُعاد ضبط "آخر مزامنة" لـ ${r.repName} إلى فارغ. لن يحذف هذا أي بيانات مستوردة سابقًا منه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm == true) {
      await ManagerService.instance.resetLastSync(r);
      await _load();
    }
  }

  Future<void> _deleteRep(Representative r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المندوب؟'),
        content: Text(
            'سيُحذف "${r.repName}" من قائمة المندوبين. لن يحذف هذا فواتيره أو سنداته المستوردة سابقًا.'),
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
      await ManagerService.instance.deleteRepresentative(r.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('المندوبون')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editRep(),
        tooltip: 'إضافة مندوب',
        child: const Icon(Icons.person_add_alt),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reps.isEmpty
              ? const Center(
                  child: Text('لا يوجد مندوبون بعد — اضغط + لإضافة مندوب',
                      style: TextStyle(color: Colors.black54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reps.length,
                  itemBuilder: (context, index) {
                    final r = _reps[index];
                    final initial =
                        r.repName.isNotEmpty ? r.repName.substring(0, 1) : '؟';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: r.isActive
                                  ? primary.withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.15),
                              child: Text(initial,
                                  style: TextStyle(
                                      color: r.isActive ? primary : Colors.grey,
                                      fontWeight: FontWeight.bold)),
                            ),
                            title: Text(r.repName,
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              'رقم: ${r.repCode}${r.phone.isNotEmpty ? ' • ${r.phone}' : ''}\n'
                              'آخر مزامنة: ${r.lastSyncAt != null ? Formatters.smartWhen(r.lastSyncAt!) : 'لا يوجد'}',
                            ),
                            isThreeLine: true,
                            trailing: !r.isActive
                                ? const Icon(Icons.pause_circle_outline,
                                    color: Colors.grey)
                                : null,
                            onTap: () => _editRep(r),
                          ),
                          const Divider(height: 1),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _toggleActive(r),
                                  icon: Icon(
                                      r.isActive
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 18),
                                  label: Text(r.isActive ? 'إيقاف' : 'تفعيل'),
                                ),
                              ),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _resetLastSync(r),
                                  icon: const Icon(Icons.restart_alt, size: 18),
                                  label: const Text('إعادة تعيين'),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteRep(r),
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
