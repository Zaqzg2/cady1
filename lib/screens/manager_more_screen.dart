import 'package:flutter/material.dart';

import 'customers_screen.dart';
import 'products_screen.dart';
import 'offers_screen.dart';
import 'settings_screen.dart';

/// قائمة إضافية لدى المدير تصل إلى شاشات إدارة الكتالوج الرئيسي (العملاء/
/// المنتجات/العروض) والإعدادات، دون إثقال شريط التنقل السفلي.
class ManagerMoreScreen extends StatelessWidget {
  const ManagerMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _menuTile(
            context,
            icon: Icons.people_outline,
            title: 'العملاء',
            subtitle: 'قائمة العملاء الرئيسية (الكتالوج المُصدَّر للمندوبين)',
            color: primary,
            builder: (_) => const CustomersScreen(),
          ),
          _menuTile(
            context,
            icon: Icons.inventory_2_outlined,
            title: 'المنتجات',
            subtitle: 'كتالوج المنتجات والأسعار',
            color: primary,
            builder: (_) => const ProductsScreen(),
          ),
          _menuTile(
            context,
            icon: Icons.local_offer_outlined,
            title: 'العروض',
            subtitle: 'إدارة العروض الترويجية المُرسَلة للمندوبين',
            color: primary,
            builder: (_) => const OffersScreen(editable: true),
          ),
          _menuTile(
            context,
            icon: Icons.settings_outlined,
            title: 'الإعدادات',
            subtitle: 'بيانات الشركة، نوع المستخدم، وإعدادات أخرى',
            color: primary,
            builder: (_) => const SettingsScreen(),
          ),
        ],
      ),
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required WidgetBuilder builder,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: builder)),
      ),
    );
  }
}
