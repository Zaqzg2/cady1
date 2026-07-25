import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/settings.dart';

class PrintHelper {
  static Future<void> printInvoice(BuildContext context, Invoice invoice, AppSettings settings) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(settings.companyName);
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      if (settings.companyPhone.isNotEmpty) bytes += generator.text('هاتف: \${settings.companyPhone}');
      bytes += generator.hr();

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(invoice.type == 'cash' ? 'فاتورة نقدية' : 'فاتورة بيع');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.left));
      bytes += generator.text('رقم: \${invoice.invoiceNumber}');
      bytes += generator.text('التاريخ: \${DateFormat('yyyy/MM/dd').format(invoice.date)}');
      bytes += generator.text('العميل: \${invoice.customerName}');
      bytes += generator.hr();

      bytes += generator.row([
        PosColumn(text: 'الصنف', width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text: 'السعر', width: 2, styles: const PosStyles(bold: true)),
        PosColumn(text: 'الكم', width: 2, styles: const PosStyles(bold: true)),
        PosColumn(text: 'الإجمالي', width: 4, styles: const PosStyles(bold: true)),
      ]);

      for (var item in invoice.items) {
        bytes += generator.row([
          PosColumn(text: item.productName, width: 4),
          PosColumn(text: item.price.toStringAsFixed(0), width: 2),
          PosColumn(text: '\${item.quantity}', width: 2),
          PosColumn(text: item.total.toStringAsFixed(0), width: 4),
        ]);
      }

      bytes += generator.hr();
      bytes += generator.text('الإجمالي: \${invoice.subtotal.toStringAsFixed(2)} \${settings.currency}', styles: const PosStyles(bold: true));
      if (invoice.discountAmount != null && invoice.discountAmount! > 0) {
        bytes += generator.text('الخصم: \${invoice.discountAmount!.toStringAsFixed(2)} \${settings.currency}');
      }
      bytes += generator.text('الصافي: \${invoice.total.toStringAsFixed(2)} \${settings.currency}', styles: const PosStyles(bold: true, height: PosTextSize.size2));

      if (invoice.previousBalance != null) {
        bytes += generator.hr();
        bytes += generator.text('الرصيد السابق: \${invoice.previousBalance!.toStringAsFixed(2)} \${settings.currency}');
        bytes += generator.text('الرصيد الجديد: \${invoice.newBalance!.toStringAsFixed(2)} \${settings.currency}', styles: const PosStyles(bold: true));
      }

      bytes += generator.hr();
      if (invoice.notes != null) bytes += generator.text('ملاحظات: \${invoice.notes}');
      bytes += generator.text('شكراً لتعاملكم معنا', styles: const PosStyles(align: PosAlign.center));
      if (settings.representativeName.isNotEmpty) {
        bytes += generator.text('المندوب: \${settings.representativeName}', styles: const PosStyles(align: PosAlign.center));
      }
      bytes += generator.feed(3);
      bytes += generator.cut();

      await _sendToPrinter(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال للطباعة')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: \$e')));
      }
    }
  }

  static Future<void> printPayment(BuildContext context, Payment payment, AppSettings settings) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(settings.companyName);
      bytes += generator.hr();

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('سند قبض');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.left));
      bytes += generator.text('رقم: \${payment.receiptNumber}');
      bytes += generator.text('التاريخ: \${DateFormat('yyyy/MM/dd').format(payment.date)}');
      bytes += generator.text('العميل: \${payment.customerName}');
      bytes += generator.text('طريقة الدفع: \${payment.paymentType == 'cash' ? 'نقداً' : 'تحويل'}');
      bytes += generator.hr();

      bytes += generator.text('المبلغ: \${payment.amount.toStringAsFixed(2)} \${settings.currency}', styles: const PosStyles(bold: true, height: PosTextSize.size2));

      if (payment.previousBalance != null) {
        bytes += generator.hr();
        bytes += generator.text('الرصيد السابق: \${payment.previousBalance!.toStringAsFixed(2)} \${settings.currency}');
        bytes += generator.text('الرصيد الجديد: \${payment.newBalance!.toStringAsFixed(2)} \${settings.currency}', styles: const PosStyles(bold: true));
      }

      bytes += generator.hr();
      if (payment.notes != null) bytes += generator.text('ملاحظات: \${payment.notes}');
      bytes += generator.text('شكراً لتعاملكم معنا', styles: const PosStyles(align: PosAlign.center));
      if (settings.representativeName.isNotEmpty) {
        bytes += generator.text('المندوب: \${settings.representativeName}', styles: const PosStyles(align: PosAlign.center));
      }
      bytes += generator.feed(3);
      bytes += generator.cut();

      await _sendToPrinter(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال للطباعة')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: \$e')));
      }
    }
  }

  static Future<void> _sendToPrinter(List<int> bytes) async {
    final bluetooth = FlutterBluetoothSerial.instance;
    final bonded = await bluetooth.getBondedDevices();

    if (bonded.isEmpty) {
      throw Exception('لا توجد طابعة متصلة');
    }

    final printer = bonded.firstWhere(
      (d) => d.name?.toLowerCase().contains('printer') ?? false,
      orElse: () => bonded.first,
    );

    final connection = await BluetoothConnection.toAddress(printer.address);
    if (connection.isConnected) {
      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent;
      await connection.close();
    } else {
      throw Exception('تعذر الاتصال بالطابعة');
    }
  }
}
