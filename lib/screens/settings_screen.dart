import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_repository.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DataRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline, color: AppTheme.primary),
            title: Text('محلل المخزون والتقارير الذكي'),
            subtitle: Text('الإصدار 1.0.0'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('عدد الأصناف'),
            trailing: Text('${repo.products.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('عدد الفروع'),
            trailing: Text('${repo.branches.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('عمليات الاستيراد'),
            trailing: Text('${repo.imports.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Firebase'),
            subtitle: Text('جاهز للربط مستقبلاً — التطبيق يعمل أوفلاين حالياً'),
          ),
          const ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('الأمان والجودة'),
            subtitle: Text('لا تُحذف البيانات الأصلية • سجل التعديلات • مصدر كل قيمة'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
            title: const Text('مسح البيانات التجريبية'),
            subtitle: const Text('لإعادة التعيين (تجريبي)'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تأكيد'),
                  content: const Text('هذه النسخة التجريبية تستخدم بيانات في الذاكرة. أعد تشغيل التطبيق لإعادة التحميل.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}