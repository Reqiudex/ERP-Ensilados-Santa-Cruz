// Operación sin conexión del operador de centro (Android) contra el proyecto de Supabase en línea.
//
// Corre el código real de la app en modo Android: la cola va al almacén seguro (en el teléfono, Android Keystore) y la
// copia de datos a SQLite (aquí sqflite_common_ffi). Simula una jornada sin señal, el reinicio del teléfono, la vuelta
// de la señal, respuestas perdidas, cortes a mitad del envío, rechazos del servidor y el ingreso con PIN o contraseña
// sin conexión. Cada prueba deja sus registros en la base de demostración: después se restablece la demo.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:erp_ensilados_santa_cruz/core/almacenamiento/almacen_local.dart';
import 'package:erp_ensilados_santa_cruz/core/conexion/conexion.dart';
import 'package:erp_ensilados_santa_cruz/core/errores/errores.dart';
import 'package:erp_ensilados_santa_cruz/core/supabase/api.dart';
import 'package:erp_ensilados_santa_cruz/core/supabase/supabase_config.dart';
import 'package:erp_ensilados_santa_cruz/features/operaciones_ensilado/data/cola_sincronizacion.dart';
import 'package:erp_ensilados_santa_cruz/features/operaciones_ensilado/data/repositorio_operaciones_supabase.dart';
import 'package:erp_ensilados_santa_cruz/features/operaciones_ensilado/domain/registro_pendiente.dart';
import 'package:erp_ensilados_santa_cruz/features/operaciones_ensilado/domain/repositorio_operaciones.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/data/pin_local.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/data/repositorio_seguridad_supabase.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/perfil.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/reglas_seguridad.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/presentation/sesion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/experimental/persist.dart';
import 'package:riverpod_sqflite/riverpod_sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import '../apoyo/cliente_prueba.dart';

const _uuid = Uuid();

/// Cuenta del operador de San Ramón con su cliente de Supabase y su perfil.
late SupabaseClient _cliente;
late Perfil _perfil;
late Sesion _verificador; // lecturas directas por la API para comprobar lo que quedó en el servidor

Future<SupabaseClient> _ingresar(String correo) async {
  final c = SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  await c.auth.signInWithPassword(email: correo, password: claveDemo);
  return c;
}

/// Un «teléfono» nuevo (o el mismo tras reiniciarse): el almacén seguro y el SQLite son los del dispositivo.
ProviderContainer _telefono({
  required bool sinSenal,
  SupabaseClient? cliente,
  Perfil? perfil,
  RepositorioOperaciones? repo,
  bool conPerfil = true,
}) {
  final c = ProviderContainer(overrides: [
    supabaseProvider.overrideWithValue(cliente ?? _cliente),
    redProvider.overrideWith((ref) => Stream.value(true)),
    if (conPerfil) perfilProvider.overrideWithValue(perfil ?? _perfil),
    if (repo != null) repositorioOperacionesProvider.overrideWithValue(repo),
  ]);
  c.read(modoSinRedProvider.notifier).cambiar(sinSenal);
  return c;
}

/// Apaga el «teléfono» cuando terminó de leer su copia local (evita cerrar el contenedor a mitad de la lectura).
Future<void> _apagar(ProviderContainer tel) async {
  tel.read(datosOperadorProvider);
  await tel.read(almacenPersistenteProvider.future);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  tel.dispose();
}

Future<void> _esperar(bool Function() condicion, {Duration max = const Duration(seconds: 10)}) async {
  final fin = DateTime.now().add(max);
  while (!condicion()) {
    if (DateTime.now().isAfter(fin)) throw TimeoutException('La condición no se cumplió a tiempo');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

class TimeoutException implements Exception {
  TimeoutException(this.m);
  final String m;
  @override
  String toString() => m;
}

/// Pesaje de báscula tal como lo arma la pantalla (bascula_pagina.dart).
Map<String, dynamic> _pesaje(String? orden, {String origen = 'propio', String? productor, int bruto = 21000, int tara = 12000}) => {
      'sede_id': sedeSanRamon,
      'origen': origen,
      'proveedor_id': productor,
      'grano_id': 1,
      'placa': 'PRB-${sello().substring(3)}',
      'peso_bruto': bruto,
      'tara': tara,
      'humedad': 14,
      'impurezas': 1,
      'orden_id': orden,
      'estado': 'confirmado',
      'fecha_dispositivo': DateTime.now().toUtc().toIso8601String(),
      'registrado_por': _perfil.id,
    };

Future<int> _filas(String ruta) async => ((await _verificador.get(ruta)).cuerpo as List).length;

/// Repositorio real con fallas inyectadas: corta la señal después de N envíos o pierde la respuesta de uno.
class _RepoConFallas extends RepositorioOperacionesSupabase {
  _RepoConFallas(super.api);
  int enviados = 0;
  int? cortarDespuesDe;
  int? perderRespuestaDe;

  @override
  Future<void> sincronizar(String tabla, Registro datos, String id) async {
    if (cortarDespuesDe != null && enviados >= cortarDespuesDe!) {
      throw const SocketException('Network is unreachable');
    }
    await super.sincronizar(tabla, datos, id);
    enviados++;
    if (perderRespuestaDe == enviados) {
      // El servidor guardó el registro, pero la respuesta no llegó al teléfono.
      throw const SocketException('Connection reset by peer');
    }
  }
}

void main() {
  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ruta = '${await getDatabasesPath()}/erp_ensilados.db';
    if (File(ruta).existsSync()) File(ruta).deleteSync();
    FlutterSecureStorage.setMockInitialValues({});
    _cliente = await _ingresar(cuentas['op_sr']!);
    _perfil = (await RepositorioSeguridadSupabase(Api(_cliente)).perfilActual())!;
    _verificador = await Sesion.de('op_sr');
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  test('Jornada completa sin señal: báscula, orden, insumos, cierre, fermentación y merma; reinicio y sincronización', () async {
    // Al iniciar el turno con señal, el teléfono guarda la copia local (granos, productores, órdenes, insumos).
    var tel = _telefono(sinSenal: false);
    await tel.read(datosOperadorProvider.notifier).refrescar();
    final productores = tel.read(datosOperadorProvider.notifier).lista('productores');
    expect(productores, isNotEmpty, reason: 'la copia local debe traer los productores activos');

    // Se pierde la señal (sin Wi-Fi ni datos): toda petición al servidor se corta antes de salir.
    tel.read(modoSinRedProvider.notifier).cambiar(true);
    expect(tel.read(enLineaProvider), isFalse);
    await expectLater(tel.read(apiProvider).rpc('mi_perfil'),
        throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'red')));

    final cola = tel.read(colaProvider.notifier);
    final marca = 'prueba sin conexión ${sello()}';
    final orden = await cola.registrar('ordenes_ensilado', {
      'sede_id': sedeSanRamon,
      'grano_id': 1,
      'fecha_apertura': DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String(),
      'estado': 'abierta',
      'registrado_por': _perfil.id,
    });
    final p1 = await cola.registrar('pesajes', _pesaje(orden));
    final p2 = await cola.registrar('pesajes', _pesaje(orden, origen: 'productor', productor: '${productores.first['id']}'));
    final c1 = await cola.registrar('consumos_insumo', {'orden_id': orden, 'producto_id': 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'cantidad': 2});
    final c2 = await cola.registrar('consumos_insumo', {'orden_id': orden, 'producto_id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'cantidad': 1});
    // 18 t ajustadas y 22 rollos = 1,22 rollos/t (rango normal del maíz: 1,10 a 1,30).
    final lote = await cola.registrar('cerrar_orden', {
      'orden_id': orden,
      'rollos': 22,
      'fecha_dispositivo': DateTime.now().toUtc().toIso8601String(),
      'codigo_temporal': 'L-MAI-PEND',
    });
    final rev = await cola.registrar('revisiones_fermentacion',
        {'lote_id': lote, 'estado_film': 'integro', 'observacion': 'Film sin daños (prueba sin conexión)', 'registrado_por': _perfil.id});
    final merma = await cola.registrar('solicitar_merma',
        {'lote_id': lote, 'cantidad': 1, 'causa': 'manipuleo', 'descripcion': 'Rollo roto al apilar ($marca)'});

    // Lo que ve el operador: 8 pendientes y las pantallas con lo registrado (copia local).
    expect(tel.read(pendientesSincronizarProvider), 8);
    final local = tel.read(datosOperadorProvider.notifier);
    expect(local.lista('ordenes_lista').firstWhere((o) => o['id'] == orden)['estado'], 'cerrada');
    expect(local.lista('lotes_fermentacion').any((l) => l['id'] == lote), isTrue);
    expect(local.lista('pesajes').where((p) => p['id'] == p1 || p['id'] == p2).length, 2);
    // Nada salió del teléfono.
    expect(await _filas('ordenes_ensilado?id=eq.$orden&select=id'), 0);

    // La cola está en el almacén seguro (cifrado en Android), no en el SQLite de la copia local.
    final crudo = await tel.read(almacenSeguroProvider).leer('cola_pendientes_v2');
    expect(crudo, contains(p1));
    final copiaVieja = await (await tel.read(almacenPersistenteProvider.future)).read('cola_sincronizacion_v1');
    expect(copiaVieja, isNull);

    // Se apaga el teléfono sin señal y vuelve a encenderse: la cola y la copia local siguen ahí.
    await _apagar(tel);
    tel = _telefono(sinSenal: true);
    tel.read(datosOperadorProvider);
    await _esperar(() => tel.read(colaProvider).length == 8);
    await _esperar(() => tel.read(datosOperadorProvider.notifier).lista('lotes_fermentacion').any((l) => l['id'] == lote));
    expect(tel.read(pendientesSincronizarProvider), 8);

    // Vuelve la señal: la cola se envía sola en orden de dependencia.
    tel.read(modoSinRedProvider.notifier).cambiar(false);
    await tel.read(colaProvider.notifier).sincronizar();
    expect(tel.read(colaProvider), isEmpty, reason: tel.read(colaProvider).map((r) => '${r.tabla}: ${r.motivo ?? r.ultimoError}').join('; '));
    expect(tel.read(avisoSincronizacionProvider), isNull);

    // En el servidor quedó todo, una sola vez, con los ids del teléfono.
    final o = (await _verificador.get('ordenes_ensilado?id=eq.$orden&select=estado,rollos_obtenidos')).cuerpo as List;
    expect(o.single['estado'], 'cerrada');
    expect(o.single['rollos_obtenidos'], 22);
    expect(await _filas('pesajes?id=in.($p1,$p2)&select=id'), 2);
    expect(await _filas('consumos_insumo?id=in.($c1,$c2)&select=id'), 2);
    final l = (await _verificador.get('lotes?orden_id=eq.$orden&select=id,codigo,estado,rollos_producidos')).cuerpo as List;
    expect(l.single['id'], lote, reason: 'el lote conserva el id generado en el teléfono');
    expect(l.single['codigo'], startsWith('L-MAI-'));
    expect(l.single['rollos_producidos'], 22);
    expect(await _filas('revisiones_fermentacion?id=eq.$rev&select=id'), 1);
    final sol = (await _verificador.rpc('mis_solicitudes')).cuerpo as List;
    expect(sol.where((s) => s['tipo'] == 'merma' && '${s['motivo']}'.contains(marca)).length, 1);

    // Reenvío de TODO (como si ninguna respuesta hubiera llegado): el servidor no duplica nada.
    final repo = tel.read(repositorioOperacionesProvider);
    final registros = (await _verificador.get('pesajes?id=in.($p1,$p2)&select=*')).cuerpo as List;
    for (final p in registros) {
      final datos = Map<String, dynamic>.from(p as Map)..removeWhere((k, _) => const {'peso_neto', 'peso_ajustado', 'fecha_registro'}.contains(k));
      await repo.sincronizar('pesajes', datos, '${p['id']}');
    }
    await repo.sincronizar('cerrar_orden', {'orden_id': orden, 'rollos': 22, 'lote_id': lote}, lote);
    await repo.sincronizar('solicitar_merma',
        {'lote_id': lote, 'cantidad': 1, 'causa': 'manipuleo', 'descripcion': 'Rollo roto al apilar ($marca)'}, merma);
    expect(await _filas('pesajes?orden_id=eq.$orden&select=id'), 2);
    expect(await _filas('lotes?orden_id=eq.$orden&select=id'), 1);
    final sol2 = (await _verificador.rpc('mis_solicitudes')).cuerpo as List;
    expect(sol2.where((s) => s['tipo'] == 'merma' && '${s['motivo']}'.contains(marca)).length, 1);
    final ex = (await _verificador.get('existencias?lote_id=eq.$lote&select=disponible')).cuerpo as List;
    expect(ex.single['disponible'], 22, reason: 'el reenvío del cierre no suma stock otra vez');
    // ignore: avoid_print
    print('SIN_CONEXION|1|8 registros sin señal; tras reinicio siguen 8; al volver la señal: 0 pendientes; '
        'orden cerrada con 22 rollos, lote ${l.single['codigo']} con el id del teléfono, 2 pesajes, 2 consumos, '
        '1 revisión, 1 merma; reenvío completo sin duplicados (stock del lote 22).');
    await _apagar(tel);
  });

  test('Corte de señal a mitad del envío y respuesta perdida: nada se pierde ni se duplica', () async {
    final repo = _RepoConFallas(Api(_cliente));
    var tel = _telefono(sinSenal: true, repo: repo);
    final cola = tel.read(colaProvider.notifier);
    final ids = [for (var i = 0; i < 4; i++) await cola.registrar('pesajes', _pesaje(null, bruto: 20000 + i))];
    expect(tel.read(pendientesSincronizarProvider), 4);

    // Vuelve la señal, pero se corta después de enviar 2; además la respuesta del 2.º se pierde.
    repo
      ..cortarDespuesDe = 2
      ..perderRespuestaDe = 2;
    tel.read(modoSinRedProvider.notifier).cambiar(false);
    await cola.sincronizar();
    final quedan = tel.read(colaProvider);
    expect(quedan.length, 3, reason: 'se envió 1 con respuesta; el 2.º llegó pero el teléfono no lo sabe');
    expect(quedan.first.id, ids[1]);
    expect(quedan.first.intentos, 1);
    expect(quedan.first.rechazado, isFalse, reason: 'la falta de señal no rechaza el registro');
    expect(await _filas('pesajes?id=in.(${ids.join(',')})&select=id'), 2);

    // Reinicio y señal estable: se reenvía el 2.º (el servidor lo ignora) y salen los otros dos.
    await _apagar(tel);
    final repo2 = _RepoConFallas(Api(_cliente));
    tel = _telefono(sinSenal: false, repo: repo2);
    await tel.read(colaProvider.notifier).sincronizar();
    expect(tel.read(colaProvider), isEmpty);
    expect(await _filas('pesajes?id=in.(${ids.join(',')})&select=id'), 4);
    // ignore: avoid_print
    print('SIN_CONEXION|2|4 pesajes; corte tras 2 envíos con la 2.ª respuesta perdida: quedan 3 pendientes (intentos=1), '
        '2 en el servidor; tras reinicio y señal: 0 pendientes y 4 en el servidor, sin duplicados.');
    await _apagar(tel);
  });

  test('Conflictos: el servidor rechaza lo que no corresponde y el operador ve el motivo', () async {
    final tel = _telefono(sinSenal: false);
    // Orden abierta por otro centro (San Julián) y orden propia cerrada en línea desde otro equipo.
    final otra = await Sesion.de('op_sj');
    final ajena = _uuid.v4();
    final r = await otra.post('ordenes_ensilado', {
      'id': ajena, 'sede_id': sedeSanJulian, 'grano_id': 1, 'estado': 'abierta', 'registrado_por': otra.usuarioId,
      'fecha_apertura': DateTime.now().toUtc().toIso8601String(),
    });
    expect(r.estado, 201, reason: '$r');
    final propia = _uuid.v4();
    final cola = tel.read(colaProvider.notifier);
    tel.read(modoSinRedProvider.notifier).cambiar(true);
    await cola.registrar('ordenes_ensilado', {
      'id': propia, 'sede_id': sedeSanRamon, 'grano_id': 1, 'estado': 'abierta', 'registrado_por': _perfil.id,
      'fecha_apertura': DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String(),
    });
    final pesajePropio = await cola.registrar('pesajes', _pesaje(propia));
    final pesajeAjeno = await cola.registrar('pesajes', _pesaje(ajena));
    final cierre = await cola.registrar('cerrar_orden', {'orden_id': propia, 'rollos': 11, 'fecha_dispositivo': DateTime.now().toUtc().toIso8601String()});

    // Se envían la orden y su pesaje, y mientras tanto alguien cierra la orden en línea.
    tel.read(modoSinRedProvider.notifier).cambiar(false);
    final repo = tel.read(repositorioOperacionesProvider);
    final cola0 = tel.read(colaProvider);
    for (final x in cola0.where((x) => x.id == propia || x.id == pesajePropio)) {
      await repo.sincronizar(x.tabla, x.datos, x.id);
    }
    expect((await _verificador.rpc('cerrar_orden', {'p_orden': propia, 'p_rollos': 11})).estado, 200);

    await cola.sincronizar();
    final rechazados = {for (final x in tel.read(colaProvider)) x.id: x};
    expect(rechazados.keys.toSet(), {pesajeAjeno, cierre});
    expect(rechazados[pesajeAjeno]!.rechazado, isTrue);
    expect(rechazados[pesajeAjeno]!.motivo, contains('no existe en su centro'));
    expect(rechazados[cierre]!.motivo, contains('ya está cerrada'));
    expect(tel.read(pendientesSincronizarProvider), 0, reason: 'los rechazados no cuentan como pendientes');
    expect(await _filas('lotes?orden_id=eq.$propia&select=id'), 1, reason: 'el cierre repetido no creó un segundo lote');

    // Reintentar no cambia el resultado; descartar lo quita de la lista del operador.
    tel.read(modoSinRedProvider.notifier).cambiar(true);
    await cola.reintentar(cierre);
    expect(tel.read(pendientesSincronizarProvider), 1);
    tel.read(modoSinRedProvider.notifier).cambiar(false);
    await cola.sincronizar();
    expect(tel.read(colaProvider).firstWhere((x) => x.id == cierre).rechazado, isTrue);
    await cola.descartar(cierre);
    await cola.descartar(pesajeAjeno);
    expect(tel.read(colaProvider), isEmpty);
    // ignore: avoid_print
    print('SIN_CONEXION|3|Pesaje sobre una orden de otro centro: rechazado («${rechazados[pesajeAjeno]!.motivo}»). '
        'Cierre de una orden ya cerrada en línea: rechazado («${rechazados[cierre]!.motivo}»), sin segundo lote.');
    await _apagar(tel);
  });

  test('Sesión del servidor vencida o cerrada: los registros esperan y se envían al volver a ingresar', () async {
    final cliente = await _ingresar(cuentas['op_sr']!);
    final tel = _telefono(sinSenal: true, cliente: cliente);
    final cola = tel.read(colaProvider.notifier);
    final id = await cola.registrar('pesajes', _pesaje(null));
    // Registro hecho por OTRA cuenta en este mismo teléfono: solo lo envía esa cuenta.
    final ajeno = RegistroPendiente(id: _uuid.v4(), tabla: 'pesajes', datos: _pesaje(null), creado: DateTime.now(), usuario: 'otra-cuenta');
    tel.read(colaProvider.notifier).state = [...tel.read(colaProvider), ajeno];

    await cliente.auth.signOut(scope: SignOutScope.local); // ingresó sin señal: no hay sesión del servidor
    tel.read(modoSinRedProvider.notifier).cambiar(false);
    await cola.sincronizar();
    expect(tel.read(pendientesSincronizarProvider), 2);
    expect(tel.read(avisoSincronizacionProvider), contains('Vuelva a ingresar con su contraseña'));

    await cliente.auth.signInWithPassword(email: cuentas['op_sr']!, password: claveDemo);
    await cola.sincronizar();
    expect(tel.read(colaProvider).map((r) => r.id), [ajeno.id]);
    expect(await _filas('pesajes?id=eq.$id&select=id'), 1);
    expect(tel.read(avisoSincronizacionProvider), isNull);
    await cola.descartar(ajeno.id);
    // ignore: avoid_print
    print('SIN_CONEXION|4|Sin sesión del servidor: 2 pendientes y aviso «Vuelva a ingresar…»; tras ingresar: se envía el '
        'propio y el de otra cuenta queda esperando a esa cuenta.');
    await _apagar(tel);
  });

  test('Báscula pública de un despacho registrado sin señal: viaja con el despacho', () async {
    final tel = _telefono(sinSenal: true);
    final cola = tel.read(colaProvider.notifier);
    final desp = await cola.registrar('registrar_despacho', {
      'nota_id': _uuid.v4(), 'lote_id': _uuid.v4(), 'pesos': [850, 860], 'placa': 'ABC-123', 'receptor': 'Chofer de prueba',
    });
    final id = await cola.registrar('registrar_peso_bascula', {'despacho_id': desp, 'peso': 1712});
    expect(id, desp);
    expect(tel.read(colaProvider).length, 1);
    expect(tel.read(colaProvider).single.datos['peso_bascula'], 1712);
    expect(tel.read(datosOperadorProvider.notifier).lista('despachos').first['peso_bascula_publica'], 1712);
    await cola.descartar(desp);
    await _apagar(tel);
  });

  test('Copia local por cuenta: si en el teléfono ingresa otro operador, no ve los datos del centro anterior', () async {
    var tel = _telefono(sinSenal: false);
    await tel.read(datosOperadorProvider.notifier).refrescar();
    final pesajesSr = tel.read(datosOperadorProvider.notifier).lista('pesajes').map((p) => p['id']).toSet();
    expect(tel.read(datosOperadorProvider)['usuario'], _perfil.id);
    await _apagar(tel);
    final clienteSj = await _ingresar(cuentas['op_sj']!);
    final perfilSj = (await RepositorioSeguridadSupabase(Api(clienteSj)).perfilActual())!;
    tel = _telefono(sinSenal: false, cliente: clienteSj, perfil: perfilSj);
    tel.read(datosOperadorProvider);
    await _esperar(() => tel.read(datosOperadorProvider)['usuario'] == _perfil.id); // copia guardada del anterior
    await tel.read(datosOperadorProvider.notifier).refrescar();
    expect(tel.read(datosOperadorProvider)['usuario'], perfilSj.id);
    final pesajesSj = tel.read(datosOperadorProvider.notifier).lista('pesajes');
    expect(pesajesSj.where((p) => pesajesSr.contains(p['id'])), isEmpty);
    expect(pesajesSj.every((p) => p['sede_id'] == sedeSanJulian), isTrue);
    await _apagar(tel);
    await clienteSj.auth.signOut();
  });

  test('Actualización del APK: la cola de la versión anterior (SQLite) pasa al almacén cifrado sin perder registros', () async {
    final sqlite = await JsonSqFliteStorage.open('${await getDatabasesPath()}/erp_ensilados.db');
    final viejo = RegistroPendiente(id: _uuid.v4(), tabla: 'pesajes', datos: _pesaje(null), creado: DateTime.now());
    await sqlite.write('cola_sincronizacion_v1', jsonEncode([viejo.aJson()]),
        const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever));
    final tel = _telefono(sinSenal: true);
    tel.read(colaProvider);
    await _esperar(() => tel.read(colaProvider).any((r) => r.id == viejo.id));
    await Future<void>.delayed(const Duration(milliseconds: 300)); // copia al almacén cifrado y borrado de la vieja
    expect(await tel.read(almacenSeguroProvider).leer('cola_pendientes_v2'), contains(viejo.id));
    expect(await sqlite.read('cola_sincronizacion_v1'), isNull);
    await tel.read(colaProvider.notifier).descartar(viejo.id);
    await _apagar(tel);
  });

  test('Un error del servidor que menciona «sin conexión» no se confunde con falta de señal', () {
    final e = traducirError(const PostgrestException(message: 'Operación sin conexión desconocida: x.', code: 'P0001'),
        codigo: 'P0001', mensaje: 'Operación sin conexión desconocida: x.');
    expect(e.codigo, 'P0001');
    expect(esErrorPasajero(e), isFalse, reason: 'si fuera «red» bloquearía la cola para siempre');
    expect(traducirError(const SocketException('Network is unreachable')).codigo, 'red');
  });

  test('Ingreso sin conexión: PIN tras reiniciar el teléfono, contraseña guardada y bloqueo al 3.er PIN erróneo', () async {
    final cliente = await _ingresar(cuentas['op_sj']!);
    final api = Api(cliente);
    final perfilSj = (await RepositorioSeguridadSupabase(api).perfilActual())!;
    FlutterSecureStorage.setMockInitialValues({});

    // Ingreso en línea (como en la pantalla de ingreso): guarda el perfil y la contraseña (bcrypt) en el teléfono.
    var tel = _telefono(sinSenal: false, cliente: SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey), conPerfil: false);
    await tel.read(sesionProvider.future);
    await tel.read(sesionProvider.notifier).iniciarSesion(perfilSj.ci, claveDemo);
    expect(tel.read(perfilProvider)?.id, perfilSj.id);
    final guardada = await tel.read(almacenSeguroProvider).leer('clave_resumen');
    expect(guardada, isNot(contains(claveDemo)));
    expect(guardada, startsWith(r'$2'), reason: 'resumen bcrypt, nunca la contraseña');
    await tel.read(pinLocalProvider).configurar(perfilSj, '4826');
    await _apagar(tel);

    // Reinicio sin señal: pide el PIN (no entra solo) y lo acepta.
    tel = _telefono(sinSenal: true, cliente: SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey), conPerfil: false);
    var s = await tel.read(sesionProvider.future);
    expect(s.bloqueadaPorPin, isTrue);
    expect(s.sinConexion, isTrue);
    expect(await tel.read(sesionProvider.notifier).desbloquearConPin('1111'), ResultadoPin.incorrecto);
    expect(await tel.read(sesionProvider.notifier).desbloquearConPin('4826'), ResultadoPin.desbloqueado);
    expect(tel.read(perfilProvider)?.id, perfilSj.id);
    expect(tel.read(sesionProvider).value?.sinConexion, isTrue);

    // Tres PIN erróneos seguidos: exige iniciar sesión en línea (CP-26).
    tel.read(sesionProvider.notifier).bloquear();
    for (var i = 0; i < 2; i++) {
      expect(await tel.read(sesionProvider.notifier).desbloquearConPin('0000'), ResultadoPin.incorrecto);
    }
    expect(await tel.read(sesionProvider.notifier).desbloquearConPin('0000'), ResultadoPin.exigeInicioEnLinea);
    expect(tel.read(perfilProvider), isNull);
    await _apagar(tel);

    // Sin PIN y sin señal: entra con su CI o correo y la contraseña verificada contra el resumen guardado.
    tel = _telefono(sinSenal: true, cliente: SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey), conPerfil: false);
    s = await tel.read(sesionProvider.future);
    expect(s.perfil, isNull);
    expect(s.mensaje, contains('Sin señal'));
    await expectLater(tel.read(sesionProvider.notifier).iniciarSesion(perfilSj.ci, 'ClaveErronea9!'), throwsA(isA<ErrorNegocio>()));
    await tel.read(sesionProvider.notifier).iniciarSesion(perfilSj.correo.toUpperCase(), claveDemo);
    expect(tel.read(perfilProvider)?.id, perfilSj.id);
    expect(tel.read(sesionProvider).value?.sinConexion, isTrue);
    // ignore: avoid_print
    print('SIN_CONEXION|5|Reinicio sin señal: pide PIN; PIN correcto entra; 3 PIN erróneos exigen ingreso en línea; '
        'sin PIN entra con CI/correo y contraseña verificada con bcrypt local; clave errónea rechazada.');
    await _apagar(tel);
    await cliente.auth.signOut();
  });
}
