import 'package:flutter/material.dart';
import 'invoice_screen.dart';
import 'payment_screen.dart';
import 'customers_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'records_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeContent(),
    const CustomersScreen(),
    const ProductsScreen(),
    const ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'العملاء'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: 'المنتجات'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'التقارير'),
        ],
      ),
    );
  }
}

class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.receipt_long_rounded),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordsScreen())),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                  ],
                ),
                const Text('كادي للمنظفات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildBigCard(context, title: 'عميل نقدي', icon: Icons.person_outline,
                    gradient: const [Color(0xFF0EA5E9), Color(0xFF0284C7)],
                    onTap: () => _openInvoice(context, isCash: true)),
                  _buildBigCard(context, title: 'فاتورة مرتجع', icon: Icons.assignment_return_outlined,
                    gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                    onTap: () => _openInvoice(context, isReturn: true)),
                  _buildBigCard(context, title: 'فاتورة بيع', icon: Icons.receipt_long_outlined,
                    gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                    onTap: () => _openInvoice(context)),
                  _buildBigCard(context, title: 'سند قبض', icon: Icons.payments_outlined,
                    gradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen()))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigCard(BuildContext context, {required String title, required IconData icon, required List<Color> gradient, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: gradient[0].withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _openInvoice(BuildContext context, {bool isCash = false, bool isReturn = false}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(isCash: isCash, isReturn: isReturn)));
  }
}
