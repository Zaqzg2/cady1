import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../widgets/settings_tile.dart';

/// إعدادات المزامنة ونوع المستخدم: التبديل بين وضع "مندوب" و"مدير" لهذا
/// الجهاز، ورقم المندوب واسم الجهاز المُستخدمَين في التعرّف على ملفات
/// المزامنة، إضافة إلى معلومات تعريفية (رقم آخر تحديث مستورد، إصدار قاعدة
/// البيانات).
class SettingsSyncScreen extends StatefulWidget {
  const SettingsSyncScreen({super.key});

  @override
  State<SettingsSyncScreen> createState() => _SettingsSyncScreenState();
}

class _SettingsSyncScreenState extends State<SettingsSyncScreen> {
  late TextEditingController _repCode;
  late TextEditingController _deviceName;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppProvider>().settings;
    _repCode = TextEditingController(text: s.repCode);
    _deviceName = TextEditingController(text: s.deviceName);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.repCode = _repCode.text.trim();
    s.deviceName = _deviceName.text.trim();
    await app.saveSettings(s);
    if (mounted) _snack('تم حفظ البيانات');
  }

  Future<void> _switchRole(String role) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    if (s.appRole == role) return;
    final label = role == 'manager' ? 'مدير' : 'مندوب';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('التبديل إلى وضع $label؟'),
        content: Text(role == 'manager'
            ? 'سيعرض التطبيق شاشات المدير (لوحة التحكم، المندوبون، الاستيراد والتصدير) بدل شاشات المندوب. تبقى كل البيانات المحفوظة على هذا الجهاز كما هي.'
            : 'سيعرض التطبيق شاشات المندوب (العملاء، الفواتير، السندات، المزامنة) بدل شاشات المدير. تبقى كل البيانات المحفوظة على هذا الجهاز كما هي.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تبديل')),
        ],
      ),
    );
    if (confirm != true) return;
    s.appRole = role;
    await app.saveSettings(s);
    if (!mounted) return;
    // نعود لجذر التطبيق حتى يظهر شريط التنقل الخاص بالوضع الجديد فورًا،
    // بدل ترك المستخدم وسط مكدس شاشات يخص الوضع السابق
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppProvider>().settings;
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المزامنة ونوع المستخدم'),
        actions: [
          TextButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('نوع المستخدم', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('يحدّد الشاشات التي يعرضها التطبيق على هذا الجهاز',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          SettingsSection(
            children: [
              RadioListTile<String>(
                value: 'rep',
                groupValue: s.appRole,
                onChanged: (v) => _switchRole(v!),
                title: const Text('مندوب'),
                subtitle: const Text('العملاء، الفواتير، السندات، والمزامنة'),
              ),
              RadioListTile<String>(
                value: 'manager',
                groupValue: s.appRole,
                onChanged: (v) => _switchRole(v!),
                title: const Text('مدير'),
                subtitle:
                    const Text('لوحة التحكم، المندوبون، الاستيراد والتصدير'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('بيانات المزامنة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _repCode,
            decoration: const InputDecoration(
              labelText: 'رقم المندوب',
              helperText: 'يُستخدم ليتعرف المدير على مصدر ملفات المزامنة',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _deviceName,
            decoration: const InputDecoration(
              labelText: 'اسم الجهاز',
              helperText: 'اختياري — يظهر بسجل المزامنة لدى المدير',
            ),
          ),
          const SizedBox(height: 20),
          SettingsSection(
            children: [
              SettingsTile(
                icon: Icons.badge_outlined,
                iconColor: primary,
                title: 'اسم المندوب',
                subtitle: s.repName.isEmpty
                    ? 'يُعدَّل من: بيانات الشركة والمندوب'
                    : s.repName,
                showChevron: false,
              ),
              SettingsTile(
                icon: Icons.numbers_outlined,
                iconColor: Colors.indigo,
                title: 'رقم آخر تحديث مستورد',
                subtitle: s.lastImportedUpdateNumber > 0
                    ? '#${s.lastImportedUpdateNumber}'
                    : 'لم يُستورد أي تحديث بعد',
                showChevron: false,
              ),
              SettingsTile(
                icon: Icons.storage_outlined,
                iconColor: Colors.blueGrey,
                title: 'إصدار قاعدة البيانات',
                subtitle: '${DbService.schemaVersion}',
                showChevron: false,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
