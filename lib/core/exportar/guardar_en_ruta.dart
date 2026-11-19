/// Guarda un archivo en la carpeta que elija el usuario (por ejemplo C:\Documentos\Respaldos).
/// Web: diálogo «Guardar como» del navegador (Chrome y Edge); si el navegador no lo ofrece, se descarga.
/// Android: selector de archivos del sistema.
library;

export 'guardar_en_ruta_io.dart' if (dart.library.js_interop) 'guardar_en_ruta_web.dart';

enum ResultadoGuardado { guardado, descargado, cancelado }
