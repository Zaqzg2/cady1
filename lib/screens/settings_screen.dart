import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل البيانات المحلية؟'),
        content: const Text('سيتم حذف كل الأصناف والمخزون وسجلات الاستيراد نهائيًا من هذا الجهاز. لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائيًا'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await StorageService.instance.wipeAll();
      if (context.mounted) {
        await context.read<InventoryProvider>().load();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف كل البيانات.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    _apiKeyController.text = settings.apiKey ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('محرك الاستخراج الذكي (OCR/AI)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text(
            'يُستخدم فقط عند استيراد صورة أو PDF (يحتاج إنترنت في تلك اللحظة). '
            'استيراد Excel/CSV لا يحتاج هذا المفتاح إطلاقًا ويعمل دائمًا بلا إنترنت.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'مفتاح API',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => context.read<SettingsProvider>().setApiKey(_apiKeyController.text),
                  child: const Text('حفظ المفتاح'),
                ),
              ),
              if (settings.hasApiKey) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _apiKeyController.clear();
                    context.read<SettingsProvider>().clearApiKey();
                  },
                  child: const Text('حذف'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            settings.hasApiKey ? '✓ المفتاح مضبوط ومحفوظ بأمان على الجهاز' : 'لم يُضبط أي مفتاح بعد',
            style: TextStyle(fontSize: 12, color: settings.hasApiKey ? Colors.green : Colors.grey),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text('البيانات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _confirmWipe(context),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('حذف كل البيانات المحلية'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text('عن التطبيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('محلل المخزون والتقارير الذكي — الإصدار 0.1.0',
              style: TextStyle(fontSize: 12.5, color: Colors.grey)),
        ],
      ),
    );
  }
}
