import 'package:flutter/material.dart';

import '../models/representative.dart';
import '../models/sync_log_entry.dart';
import '../services/manager_service.dart';
import '../utils/formatters.dart';

/// شاشة المزامنة لدى المدير: تبويبات "استيراد" / "تصدير" / "السجل" تجمع
/// شاشتي الاستيراد والتصدير وسجل المزامنة في مكان واحد.
class ManagerSyncScreen extends StatelessWidget {
  const ManagerSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المزامنة'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'استيراد'),
              Tab(text: 'تصدير'),
              Tab(text: 'السجل'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ImportTab(),
            _ExportTab(),
            _LogTab(),
          ],
        ),
      ),
    );
  }
}

// ==================== تبويب الاستيراد ====================
class _ImportTab extends StatefulWidget {
  const _ImportTab();
  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  bool _busy = false;

  void _showMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _pickAndStage() async {
    setState(() => _busy = true);
    try {
      final picked = await ManagerService.instance.pickRepFileContent();
      if (picked == null) return;
      final (content, fileName) = picked;
      final preview = await ManagerService.instance
          .stageImport(content, fileName: fileName);
      if (!mounted) return;
      await _showPreviewDialog(preview);
    } on FormatException catch (e) {
      _showMessage(e.message, error: true);
    } catch (e) {
      _showMessage('تعذر قراءة الملف: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPreviewDialog(RepImportPreview preview) async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(preview.isNewRep
            ? 'ملف من مندوب جديد: ${preview.repName ?? preview.repCode ?? ''}'
            : 'ملف من: ${preview.repName ?? preview.repCode ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('عدد الفواتير', preview.invoicesCount),
              _row('عدد السندات', preview.receiptsCount),
              _row('العملاء الجدد', preview.newCustomersCount),
              _row('التكرارات', preview.duplicatesCount),
              _row('الأخطاء', preview.errorsCount,
                  color: preview.errorsCount > 0 ? Colors.red : null),
              if (preview.errorMessages.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('تفاصيل الأخطاء:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ...preview.errorMessages.take(5).map((m) => Text('• $m',
                    style: const TextStyle(fontSize: 12, color: Colors.red))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'approve'),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );

    if (action == 'approve') {
      try {
        final result =
            await ManagerService.instance.approveImport(preview.logId);
        _showMessage(
            'تم الاعتماد: ${result.invoicesImported} فاتورة، ${result.receiptsImported} سند، ${result.customersImported} عميل');
      } catch (e) {
        _showMessage('تعذر اعتماد الاستيراد: $e', error: true);
      }
    } else if (action == 'cancel') {
      await ManagerService.instance.cancelImport(preview.logId);
    }
  }

  Widget _row(String label, int value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$value',
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            enabled: !_busy,
            leading: const Text('📥', style: TextStyle(fontSize: 24)),
            title: const Text('استيراد ملف مندوب',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                'اختر ملف JSON صادر من شاشة "تصدير بيانات اليوم" لدى أحد المندوبين'),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_left),
            onTap: _busy ? null : _pickAndStage,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'بعد الاختيار ستظهر معاينة (عدد الفواتير/السندات/العملاء الجدد/التكرارات/الأخطاء) قبل أن تختار اعتماد أو إلغاء.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ==================== تبويب التصدير ====================
class _ExportTab extends StatefulWidget {
  const _ExportTab();
  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  final Set<String> _selected = {'products', 'customers'};
  List<Representative> _reps = [];
  String? _targetRepId; // null = كل المندوبين
  bool _busy = false;
  int _nextNumber = 1;
  List<SyncLogEntry> _recentExports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reps = await ManagerService.instance.getRepresentatives();
    final next = await ManagerService.instance.peekNextUpdateNumber();
    final logs = await ManagerService.instance.getLogs(type: 'export');
    if (!mounted) return;
    setState(() {
      _reps = reps;
      _nextNumber = next;
      _recentExports = logs.take(5).toList();
    });
  }

  void _showMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _create() async {
    if (_selected.isEmpty) {
      _showMessage('اختر فئة واحدة على الأقل', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      String? targetCode;
      if (_targetRepId != null) {
        final rep = _reps.firstWhere((r) => r.id == _targetRepId);
        targetCode = rep.repCode;
      }
      await ManagerService.instance.createUpdatePackageAndShare(
        categories: _selected,
        targetRepCode: targetCode,
      );
      await _load();
      _showMessage('تم إنشاء ملف التحديث ومشاركته');
    } catch (e) {
      _showMessage('تعذر إنشاء الملف: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _busy,
      child: Opacity(
        opacity: _busy ? 0.6 : 1,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('اختر البيانات المطلوب تضمينها في التحديث',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _checkTile('products', 'المنتجات'),
            _checkTile('prices', 'الأسعار'),
            _checkTile('customers', 'العملاء'),
            _checkTile('offers', 'العروض'),
            _checkTile('settings', 'الإعدادات'),
            const SizedBox(height: 16),
            const Text('الوجهة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _targetRepId,
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('كل المندوبين')),
                ..._reps.map((r) => DropdownMenuItem<String?>(
                    value: r.id, child: Text('${r.repName} (${r.repCode})'))),
              ],
              onChanged: (v) => setState(() => _targetRepId = v),
            ),
            const SizedBox(height: 20),
            Text('رقم التحديث القادم: $_nextNumber',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _create,
                icon: const Text('📤', style: TextStyle(fontSize: 18)),
                label: const Text('إنشاء تحديث'),
              ),
            ),
            if (_recentExports.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('آخر التحديثات الصادرة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._recentExports.map((l) => Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.upload_file_outlined),
                      title: Text(l.repCode?.isNotEmpty == true
                          ? 'لِـ: ${l.repCode}'
                          : 'لكل المندوبين'),
                      subtitle: Text(Formatters.dt(l.timestamp)),
                      trailing: Text('${l.recordCount} سجل',
                          style: const TextStyle(color: Colors.black54)),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _checkTile(String key, String label) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: _selected.contains(key),
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selected.add(key);
          } else {
            _selected.remove(key);
          }
        });
      },
    );
  }
}

// ==================== تبويب السجل ====================
class _LogTab extends StatefulWidget {
  const _LogTab();
  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  List<SyncLogEntry> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await ManagerService.instance.getLogs(type: 'import');
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  void _showMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _reImport(SyncLogEntry log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إعادة الاستيراد؟'),
        content: Text(
            'سيُعاد تطبيق بيانات الملف "${log.fileName}" مجددًا. العمليات المستوردة سابقًا لن تتكرر (تُحدَّث فقط بأحدث بياناتها).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إعادة الاستيراد')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final result = await ManagerService.instance.reImport(log.id);
      await _load();
      _showMessage(
          'تم: ${result.invoicesImported} فاتورة، ${result.receiptsImported} سند، ${result.customersImported} عميل');
    } catch (e) {
      _showMessage('تعذر إعادة الاستيراد: $e', error: true);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.orange.shade800;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'مُعتمد';
      case 'cancelled':
        return 'مُلغى';
      default:
        return 'بانتظار الاعتماد';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_logs.isEmpty) {
      return const Center(
          child: Text('لا يوجد سجل مزامنة بعد',
              style: TextStyle(color: Colors.black54)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final l = _logs[index];
          final details = l.details;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: _statusColor(l.status).withOpacity(0.15),
                    child: Icon(Icons.download_outlined,
                        color: _statusColor(l.status)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.repName?.isNotEmpty == true
                              ? l.repName!
                              : (l.repCode ?? 'غير معروف'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(l.fileName,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 4),
                        Text(
                          '${Formatters.dt(l.timestamp)} • ${l.recordCount} سجل',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'فواتير: ${details['invoicesCount'] ?? 0} • سندات: ${details['receiptsCount'] ?? 0} • عملاء جدد: ${details['newCustomersCount'] ?? 0}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_statusLabel(l.status),
                          style: TextStyle(
                              color: _statusColor(l.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      if (l.status != 'cancelled')
                        TextButton(
                          onPressed: () => _reImport(l),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 30)),
                          child: const Text('إعادة الاستيراد',
                              style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
