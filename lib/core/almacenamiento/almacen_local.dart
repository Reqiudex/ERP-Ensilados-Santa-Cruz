import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/experimental/persist.dart';
import 'package:riverpod_sqflite/riverpod_sqflite.dart';
import 'package:sqflite/sqflite.dart';

/// La aplicación Android trabaja sin conexión (SQLite en el teléfono); el portal web siempre está en línea.
bool get esAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Almacenamiento de la persistencia de Riverpod 3: SQLite en Android, memoria en web y pruebas.
final almacenPersistenteProvider = FutureProvider<Storage<String, String>>((ref) async {
  if (!esAndroid) return AlmacenEnMemoria();
  final ruta = p.join(await getDatabasesPath(), 'erp_ensilados.db');
  return JsonSqFliteStorage.open(ruta);
});

/// Almacenamiento seguro para el PIN (resumen con sal), el perfil en caché y la hora de la última sincronización.
class AlmacenSeguro {
  AlmacenSeguro([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage(), _soloMemoria = false;

  /// Almacén en memoria (portal web y pruebas que simulan el dispositivo).
  AlmacenSeguro.enMemoria() : _s = const FlutterSecureStorage(), _soloMemoria = true;

  final FlutterSecureStorage _s;
  final bool _soloMemoria;
  final Map<String, String> _memoria = {};

  Future<String?> leer(String clave) async {
    if (!esAndroid || _soloMemoria) return _memoria[clave];
    try {
      return await _s.read(key: clave);
    } catch (_) {
      return null;
    }
  }

  Future<void> escribir(String clave, String? valor) async {
    if (!esAndroid || _soloMemoria) {
      valor == null ? _memoria.remove(clave) : _memoria[clave] = valor;
      return;
    }
    if (valor == null) {
      await _s.delete(key: clave);
    } else {
      await _s.write(key: clave, value: valor);
    }
  }
}

final almacenSeguroProvider = Provider<AlmacenSeguro>((ref) => AlmacenSeguro());

/// Almacenamiento en memoria para el portal web (siempre en línea) y las pruebas.
final class AlmacenEnMemoria extends Storage<String, String> {
  final Map<String, PersistedData<String>> _datos = {};

  @override
  FutureOr<PersistedData<String>?> read(String key) => _datos[key];

  @override
  FutureOr<void> write(String key, String value, StorageOptions options) {
    final d = options.cacheTime.duration;
    _datos[key] = PersistedData(value, expireAt: d == null ? null : DateTime.now().toUtc().add(d), destroyKey: options.destroyKey);
  }

  @override
  FutureOr<void> delete(String key) => _datos.remove(key);

  @override
  void deleteOutOfDate() {}
}
