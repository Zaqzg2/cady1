import 'package:flutter/material.dart';

import 'branches_screen.dart';
import 'categories_screen.dart';
import 'count_screen.dart';
import 'import_screen.dart';
import 'incoming_screen.dart';
import 'reports_center_screen.dart';
import 'settings_screen.dart';

/// "المزيد" (القسم 30): الجرد، الوارد، البيانات (الاستيراد)، التقارير،
/// الفروع، التصنيفات، الإعدادات.
class MoreMenuScreen extends StatelessWidget {
  const MoreMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, WidgetBuilder)>[
      (Icons.fact_check_outlined, 'الجرد', 'جرد يدوي أو سريع لكل الأصناف', (_) => const CountScreen()),
      (Icons.move_to_inbox_outlined, 'الوارد', 'تسجيل كمية واردة جديدة', (_) => const IncomingScreen()),
      (Icons.upload_file_outlined, 'البيانات', 'استيراد Excel / CSV / PDF / صورة', (_) => const ImportScreen()),
      (Icons.description_outlined, 'التقارير', 'مركز التقارير القابلة للتصدير', (_) => const ReportsCenterScreen()),
      (Icons.store_outlined, 'الفروع', 'إدارة الفروع', (_) => const BranchesScreen()),
      (Icons.category_outlined, 'التصنيفات', 'إدارة تصنيفات الأصناف', (_) => const CategoriesScreen()),
      (Icons.settings_outlined, 'الإعدادات', 'تفضيلات التطبيق والنسخ الاحتياطي', (_) => const SettingsScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final (icon, title, subtitle, builder) = items[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
            ),
          );
        },
      ),
    );
  }
}
