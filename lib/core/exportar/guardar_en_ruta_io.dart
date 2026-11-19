import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import 'guardar_en_ruta.dart';

Future<(ResultadoGuardado, String?)> guardarEnRuta(String nombre, Uint8List bytes, {String extension = 'json'}) async {
  final ruta = await FileSaver.instance.saveAs(
    name: nombre,
    bytes: bytes,
    fileExtension: extension,
    mimeType: MimeType.json,
    dialogTitle: 'Elija dónde guardar el respaldo',
  );
  return ruta == null ? (ResultadoGuardado.cancelado, null) : (ResultadoGuardado.guardado, ruta);
}
