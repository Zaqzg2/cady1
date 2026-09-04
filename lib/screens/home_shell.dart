import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'goals_screen.dart';
import 'inventory_analysis_screen.dart';
import 'more_menu_screen.dart';
import 'purchases_screen.dart';

/// إطار التنقّل الرئيسي (القسم 30): الرئيسية / المخزون / الأهداف / المشتريات
/// / المزيد. على الهاتف: Bottom Navigation (القسم 31). على الشاشات العريضة
/// (تابلت/ويب): Navigation Rail بدلاً منه — بلا تغيير في الشاشات نفسها.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    InventoryAnalysisScreen(),
    GoalsScreen(),
    PurchasesScreen(),
    MoreMenuScreen(),
  ];

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'الرئيسية'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'المخزون'),
    (Icons.flag_outlined, Icons.flag, 'الأهداف'),
    (Icons.shopping_cart_outlined, Icons.shopping_cart, 'المشتريات'),
    (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'المزيد'),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;

    final body = IndexedStack(index: _index, children: _screens);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.$1),
                        selectedIcon: Icon(d.$2),
                        label: Text(d.$3),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations
            .map((d) => NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3))
            .toList(),
      ),
    );
  }
}
