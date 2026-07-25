import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../providers/data_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _companyNameCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  final _companyAddressCtrl = TextEditingController();
  final _repNameCtrl = TextEditingController();
  final _printerCtrl = TextEditingController();
  final _fontSizeCtrl = TextEditingController();
  final _columnsCtrl = TextEditingController();
  String? _logoPath;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  void _loadSettings() {
    final provider = Provider.of<DataProvider>(context, listen: false);
    final s = provider.settings;
    _companyNameCtrl.text = s.companyName;
    _companyPhoneCtrl.text = s.companyPhone;
    _companyAddressCtrl.text = s.companyAddress ?? '';
    _repNameCtrl.text = s.representativeName;
    _printerCtrl.text = s.printerAddress ?? '';
    _fontSizeCtrl.text = s.tableFontSize.toString();
    _columnsCtrl.text = s.tableColumns.toString();
    _logoPath = s.logoPath;
    _darkMode = s.darkMode;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle('بيانات الشركة'),
            _buildTextField(_companyNameCtrl, 'اسم الشركة', Icons.business),
            const SizedBox(height: 12),
            _buildTextField(_companyPhoneCtrl, 'هاتف الشركة', Icons.phone),
            const SizedBox(height: 12),
            _buildTextField(_companyAddressCtrl, 'عنوان الشركة', Icons.location_on),
            const SizedBox(height: 16),
            _buildSectionTitle('الشعار'),
            _buildLogoPicker(),
            const SizedBox(height: 16),
            _buildSectionTitle('بيانات المندوب'),
            _buildTextField(_repNameCtrl, 'اسم المندوب', Icons.person),
            const SizedBox(height: 16),
            _buildSectionTitle('إعدادات الطباعة'),
            _buildTextField(_printerCtrl, 'عنوان الطابعة البلوتوث', Icons.bluetooth),
            const SizedBox(height: 12),
            _buildTextField(_fontSizeCtrl, 'حجم خط الجدول', Icons.format_size, keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _buildTextField(_columnsCtrl, 'عدد أعمدة الجدول', Icons.view_column, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _buildSectionTitle('المظهر'),
            SwitchListTile(title: const Text('الوضع الليلي'), value: _darkMode, onChanged: (v) => setState(() => _darkMode = v)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 56,
              child: FilledButton.icon(
                onPressed: _saveSettings, icon: const Icon(Icons.save), label: const Text('حفظ الإعدادات', style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType}) {
    return TextField(controller: controller, keyboardType: keyboardType, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true));
  }

  Widget _buildLogoPicker() {
    return Card(
      child: InkWell(
        onTap: _pickLogo,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 120,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: _logoPath != null && File(_logoPath!).existsSync()
              ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(File(_logoPath!), fit: BoxFit.contain))
              : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate, size: 40), Text('اضغط لاختيار الشعار')]),
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _logoPath = picked.path);
  }

  Future<void> _saveSettings() async {
    final settings = AppSettings(
      companyName: _companyNameCtrl.text, companyPhone: _companyPhoneCtrl.text,
      companyAddress: _companyAddressCtrl.text.isEmpty ? null : _companyAddressCtrl.text,
      logoPath: _logoPath, representativeName: _repNameCtrl.text, currency: 'ريال يمني',
      printerAddress: _printerCtrl.text.isEmpty ? null : _printerCtrl.text,
      tableFontSize: double.tryParse(_fontSizeCtrl.text) ?? 12.0,
      tableColumns: int.tryParse(_columnsCtrl.text) ?? 5, darkMode: _darkMode,
    );
    await Provider.of<DataProvider>(context, listen: false).saveSettings(settings);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose(); _companyPhoneCtrl.dispose(); _companyAddressCtrl.dispose();
    _repNameCtrl.dispose(); _printerCtrl.dispose(); _fontSizeCtrl.dispose(); _columnsCtrl.dispose();
    super.dispose();
  }
}
