import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/settings.dart';

class PdfHelper {
  static Future<void> generateInvoicePdf(BuildContext context, Invoice invoice, AppSettings settings) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(settings.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if (settings.companyPhone.isNotEmpty) pw.Text('هاتف: \${settings.companyPhone}', style: const pw.TextStyle(fontSize: 10)),
            if (settings.companyAddress != null) pw.Text(settings.companyAddress!, style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            pw.Text(invoice.type == 'cash' ? 'فاتورة نقدية' : 'فاتورة بيع', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('رقم: \${invoice.invoiceNumber}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(DateFormat('yyyy/MM/dd').format(invoice.date), style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.Text('العميل: \${invoice.customerName}', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            pw.Table(
              border: pw.TableBorder.all(),
              children: [
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('الصنف', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('السعر', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('الكمية', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('الإجمالي', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                ]),
                ...invoice.items.map((item) => pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(item.productName, style: const pw.TextStyle(fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(item.price.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('\${item.quantity}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(item.total.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                ])).toList(),
              ],
            ),
            pw.Divider(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('الإجمالي:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('\${invoice.subtotal.toStringAsFixed(2)} \${settings.currency}', style: const pw.TextStyle(fontSize: 10)),
            ]),
            if (invoice.discountAmount != null && invoice.discountAmount! > 0)
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('الخصم:', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('\${invoice.discountAmount!.toStringAsFixed(2)} \${settings.currency}', style: const pw.TextStyle(fontSize: 10)),
              ]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('الصافي:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('\${invoice.total.toStringAsFixed(2)} \${settings.currency}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ]),
            if (invoice.previousBalance != null) ...[
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('الرصيد السابق:', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('\${invoice.previousBalance!.toStringAsFixed(2)} \${settings.currency}', style: const pw.TextStyle(fontSize: 10)),
              ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('الرصيد الجديد:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('\${invoice.newBalance!.toStringAsFixed(2)} \${settings.currency}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ]),
            ],
            pw.SizedBox(height: 8),
            if (invoice.notes != null) pw.Text('ملاحظات: \${invoice.notes}', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text('شكراً لتعاملكم معنا', style: const pw.TextStyle(fontSize: 9)),
            if (settings.representativeName.isNotEmpty)
              pw.Text('المندوب: \${settings.representativeName}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('\${output.path}/\${invoice.invoiceNumber}.pdf');
    await file.writeAsBytes(await pdf.save());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ PDF: \${file.path}')),
      );
    }
  }

  static Future<void> shareInvoicePdf(BuildContext context, Invoice invoice, AppSettings settings) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(settings.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(invoice.type == 'cash' ? 'فاتورة نقدية' : 'فاتورة بيع', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text('رقم: \${invoice.invoiceNumber} | \${DateFormat('yyyy/MM/dd').format(invoice.date)}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('العميل: \${invoice.customerName}', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            ...invoice.items.map((item) => pw.Text('\${item.productName} x\${item.quantity} = \${item.total.toStringAsFixed(0)} \${settings.currency}', style: const pw.TextStyle(fontSize: 10))).toList(),
            pw.Divider(),
            pw.Text('الإجمالي: \${invoice.total.toStringAsFixed(2)} \${settings.currency}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('\${output.path}/\${invoice.invoiceNumber}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'فاتورة \${invoice.invoiceNumber}');
  }

  static Future<void> generatePaymentPdf(BuildContext context, Payment payment, AppSettings settings) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(settings.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Text('سند قبض', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('رقم: \${payment.receiptNumber}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(DateFormat('yyyy/MM/dd').format(payment.date), style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.Text('العميل: \${payment.customerName}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('طريقة الدفع: \${payment.paymentType == 'cash' ? 'نقداً' : 'تحويل'}', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('المبلغ:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('\${payment.amount.toStringAsFixed(2)} \${settings.currency}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ]),
            if (payment.previousBalance != null) ...[
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('الرصيد السابق:', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('\${payment.previousBalance!.toStringAsFixed(2)} \${settings.currency}', style: const pw.TextStyle(fontSize: 10)),
              ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('الرصيد الجديد:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('\${payment.newBalance!.toStringAsFixed(2)} \${settings.currency}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ]),
            ],
            pw.SizedBox(height: 8),
            if (payment.notes != null) pw.Text('ملاحظات: \${payment.notes}', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text('شكراً لتعاملكم معنا', style: const pw.TextStyle(fontSize: 9)),
            if (settings.representativeName.isNotEmpty)
              pw.Text('المندوب: \${settings.representativeName}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('\${output.path}/\${payment.receiptNumber}.pdf');
    await file.writeAsBytes(await pdf.save());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ PDF: \${file.path}')),
      );
    }
  }

  static Future<void> sharePaymentPdf(BuildContext context, Payment payment, AppSettings settings) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(settings.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('سند قبض', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text('رقم: \${payment.receiptNumber} | \${DateFormat('yyyy/MM/dd').format(payment.date)}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('العميل: \${payment.customerName}', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            pw.Text('المبلغ: \${payment.amount.toStringAsFixed(2)} \${settings.currency}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('\${output.path}/\${payment.receiptNumber}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'سند قبض \${payment.receiptNumber}');
  }
}
