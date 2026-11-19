import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Exportación de reportes y listados a PDF, Excel y CSV (web y Android).
class Exportador {
  Exportador._();

  static String _nombre(String titulo) =>
      '${titulo.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñ]+'), '_')}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

  static Future<Uint8List> pdfBytes(String titulo, List<String> columnas, List<List<String>> filas,
      {String? subtitulo, List<String> resumen = const []}) async {
    final doc = pw.Document(title: titulo, author: 'ERP Ensilados Santa Cruz');
    final verde = PdfColor.fromHex('#1B4D3E');
    doc.addPage(pw.MultiPage(
      pageFormat: columnas.length > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Ensilados Santa Cruz · ERP Agroindustrial', style: pw.TextStyle(fontSize: 9, color: verde)),
        pw.SizedBox(height: 4),
        pw.Text(titulo, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (subtitulo != null) pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
      ]),
      footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Generado el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8)),
        pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
      ]),
      build: (c) => [
        if (resumen.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Wrap(spacing: 16, children: resumen.map((r) => pw.Text(r, style: const pw.TextStyle(fontSize: 9))).toList()),
          ),
        pw.TableHelper.fromTextArray(
          headers: columnas,
          data: filas,
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: verde),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        ),
      ],
    ));
    return doc.save();
  }

  static Future<void> pdf(String titulo, List<String> columnas, List<List<String>> filas,
      {String? subtitulo, List<String> resumen = const []}) async {
    final bytes = await pdfBytes(titulo, columnas, filas, subtitulo: subtitulo, resumen: resumen);
    await FileSaver.instance.saveFile(name: _nombre(titulo), bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
  }

  static Uint8List excelBytes(String titulo, List<String> columnas, List<List<String>> filas) {
    final libro = xl.Excel.createExcel();
    final hoja = libro[libro.getDefaultSheet()!];
    hoja.appendRow([xl.TextCellValue(titulo)]);
    hoja.appendRow(columnas.map((c) => xl.TextCellValue(c)).toList());
    for (final f in filas) {
      hoja.appendRow(f.map<xl.CellValue>((v) {
        final n = num.tryParse(v.replaceAll('.', '').replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), ''));
        final esNumero = RegExp(r'^-?[\d.]+(,\d+)?( kg| t)?$').hasMatch(v.replaceAll('Bs ', '')) && n != null;
        return esNumero ? xl.DoubleCellValue(n.toDouble()) : xl.TextCellValue(v);
      }).toList());
    }
    return Uint8List.fromList(libro.encode()!);
  }

  static Future<void> excel(String titulo, List<String> columnas, List<List<String>> filas) async {
    await FileSaver.instance.saveFile(
        name: _nombre(titulo), bytes: excelBytes(titulo, columnas, filas), fileExtension: 'xlsx', mimeType: MimeType.microsoftExcel);
  }

  static Future<void> csv(String titulo, List<String> columnas, List<List<String>> filas) async {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final texto = [columnas.map(esc).join(','), ...filas.map((f) => f.map(esc).join(','))].join('\r\n');
    await FileSaver.instance.saveFile(
        name: _nombre(titulo), bytes: Uint8List.fromList(utf8.encode('﻿$texto')), fileExtension: 'csv', mimeType: MimeType.csv);
  }
}
