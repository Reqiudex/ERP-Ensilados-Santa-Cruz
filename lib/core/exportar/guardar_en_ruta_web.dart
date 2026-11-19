import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import 'guardar_en_ruta.dart';

Future<(ResultadoGuardado, String?)> guardarEnRuta(String nombre, Uint8List bytes, {String extension = 'json'}) async {
  final ventana = globalContext;
  if (!ventana.has('showSaveFilePicker')) {
    // Firefox y Safari no permiten elegir la carpeta desde la página: se descarga a la carpeta del navegador.
    await FileSaver.instance.saveFile(name: nombre, bytes: bytes, fileExtension: extension, mimeType: MimeType.json);
    return (ResultadoGuardado.descargado, null);
  }
  try {
    final opciones = {
      'suggestedName': '$nombre.$extension',
      'types': [
        {
          'description': 'Respaldo del ERP',
          'accept': {
            'application/json': ['.$extension'],
          },
        },
      ],
    }.jsify();
    final archivo = await ventana.callMethod<JSPromise<JSObject>>('showSaveFilePicker'.toJS, opciones).toDart;
    final escritura = await archivo.callMethod<JSPromise<JSObject>>('createWritable'.toJS).toDart;
    await escritura.callMethod<JSPromise<JSAny?>>('write'.toJS, bytes.toJS).toDart;
    await escritura.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    // Por seguridad el navegador no revela la ruta completa, solo el nombre del archivo.
    return (ResultadoGuardado.guardado, archivo.getProperty<JSString>('name'.toJS).toDart);
  } catch (e) {
    if ('$e'.contains('AbortError')) return (ResultadoGuardado.cancelado, null);
    rethrow;
  }
}
