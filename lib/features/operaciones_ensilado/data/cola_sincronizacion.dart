import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/experimental/persist.dart';
import 'package:uuid/uuid.dart';

import '../../../core/almacenamiento/almacen_local.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/errores/errores.dart';
import '../../../core/supabase/api.dart';
import '../../comercial_abastecimiento/data/repositorio_comercial_supabase.dart';
import '../../inventario_multisede/data/repositorio_inventario_supabase.dart';
import '../../seguridad_accesos/data/pin_local.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../domain/calculos_operaciones.dart';
import '../domain/registro_pendiente.dart';
import 'repositorio_operaciones_supabase.dart';

/// Catálogos base predeterminados de Ensilados Santa Cruz para poder trabajar desde el primer arranque aunque no haya señal.
/// Mismos valores que la tabla «granos» de la base (se reemplazan por los del servidor en la primera sincronización).
const List<Map<String, dynamic>> granosPredeterminados = [
  {'id': 1, 'nombre': 'Maíz', 'humedad_estandar': 14.0, 'dias_fermentacion': 21, 'rollos_ton_min': 1.1, 'rollos_ton_max': 1.3},
  {'id': 2, 'nombre': 'Sorgo', 'humedad_estandar': 14.0, 'dias_fermentacion': 21, 'rollos_ton_min': 1.12, 'rollos_ton_max': 1.35},
  {'id': 3, 'nombre': 'Soya', 'humedad_estandar': 14.0, 'dias_fermentacion': 21, 'rollos_ton_min': 1.05, 'rollos_ton_max': 1.25},
];

const List<Map<String, dynamic>> sedesPredeterminadas = [
  {'id': '11111111-1111-1111-1111-111111111111', 'nombre': 'Oficina Central Santa Cruz', 'tipo': 'oficina', 'activa': true},
  {'id': '22222222-2222-2222-2222-222222222222', 'nombre': 'Centro de Acopio San Ramón', 'tipo': 'centro_acopio', 'activa': true},
  {'id': '33333333-3333-3333-3333-333333333333', 'nombre': 'Centro de Acopio San Julián', 'tipo': 'centro_acopio', 'activa': true},
  {'id': '44444444-4444-4444-4444-444444444444', 'nombre': 'Centro de Acopio San Rafael de Velasco', 'tipo': 'centro_acopio', 'activa': true},
];

const Map<String, String> nombresInsumosOffline = {
  'dddddddd-dddd-dddd-dddd-dddddddddddd': 'Film estirable',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee': 'Malla tubular',
  'ffffffff-ffff-ffff-ffff-ffffffffffff': 'Inoculante',
};

const Map<String, String> skusInsumosOffline = {
  'dddddddd-dddd-dddd-dddd-dddddddddddd': 'INS-FLM-001',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee': 'INS-MLL-001',
  'ffffffff-ffff-ffff-ffff-ffffffffffff': 'INS-INC-001',
};

/// Cola local de solo inserción del teléfono.
///
/// Cada registro lleva un UUID generado en el dispositivo, la hora del dispositivo y la cuenta que lo hizo. Se guarda
/// cifrado en el almacén seguro de Android (Keystore) en cada cambio, así sobrevive a cierres y reinicios del teléfono.
/// Al reconectar se envía en orden de dependencia; el servidor aplica cada operación una sola vez aunque llegue
/// repetida. Solo se rechaza lo que el servidor rechaza por los datos; la falta de señal, una sesión vencida o un
/// servidor ocupado dejan el registro pendiente para el siguiente intento.
class ColaSincronizacion extends Notifier<List<RegistroPendiente>> {
  static const _clave = 'cola_pendientes_v2';
  static const _claveAnterior = 'cola_sincronizacion_v1';
  static const _intentosMaximos = 8;
  static const _uuid = Uuid();

  bool _enviando = false;
  Future<void> _carga = Future.value();
  Future<void> _escritura = Future.value();

  @override
  List<RegistroPendiente> build() {
    _carga = _cargar();
    return const [];
  }

  Future<void> _cargar() async {
    var guardados = <RegistroPendiente>[];
    try {
      final texto = await ref.read(almacenSeguroProvider).leer(_clave);
      if (texto != null && texto.isNotEmpty) {
        guardados = (jsonDecode(texto) as List)
            .whereType<Map>()
            .map((e) => RegistroPendiente.desdeJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      // Un almacén ilegible no debe impedir seguir registrando.
    }
    final anteriores = await _colaVersionAnterior();
    final ids = state.map((r) => r.id).toSet();
    final vistos = <String>{};
    state = [
      for (final r in [...guardados, ...anteriores])
        if (!ids.contains(r.id) && vistos.add(r.id)) r,
      ...state,
    ];
    if (anteriores.isNotEmpty) {
      // La cola pasa al almacén cifrado antes de borrar la copia de la versión anterior.
      await _persistir();
      try {
        await (await ref.read(almacenPersistenteProvider.future)).delete(_claveAnterior);
      } catch (_) {}
    }
  }

  /// Registros que la versión anterior de la app dejó pendientes en SQLite (clave «cola_sincronizacion_v1»):
  /// se recuperan al actualizar el APK para no perder lo registrado sin señal antes de la actualización.
  Future<List<RegistroPendiente>> _colaVersionAnterior() async {
    try {
      final almacen = await ref.read(almacenPersistenteProvider.future);
      final d = await almacen.read(_claveAnterior);
      if (d == null || d.data.isEmpty) return const [];
      return (jsonDecode(d.data) as List)
          .whereType<Map>()
          .map((e) => RegistroPendiente.desdeJson(Map<String, dynamic>.from(e)))
          .where((r) => tablasSinConexion.contains(r.tabla))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Guarda la cola completa; las escrituras van en fila para que nunca quede una versión vieja encima de una nueva.
  Future<void> _persistir() {
    final texto = jsonEncode(state.map((r) => r.aJson()).toList());
    final almacen = ref.read(almacenSeguroProvider);
    _escritura = _escritura.then((_) async {
      try {
        await almacen.escribir(_clave, texto);
      } catch (_) {}
    });
    return _escritura;
  }

  void _reemplazar(RegistroPendiente r) => state = [for (final x in state) x.id == r.id ? r : x];

  /// Guarda el registro en el teléfono y lo envía en segundo plano si hay conexión.
  /// Devuelve el identificador generado en el dispositivo.
  Future<String> registrar(String tabla, Map<String, dynamic> datos) async {
    if (!tablasSinConexion.contains(tabla)) throw ArgumentError('$tabla exige conexión');
    await _carga;
    // El peso de báscula pública de un despacho que aún no se envió viaja dentro de ese despacho: en el servidor el
    // despacho recibe otro identificador y una operación aparte sobre el id del teléfono se rechazaría.
    if (tabla == 'registrar_peso_bascula') {
      final despacho = state.where((r) => !r.rechazado && r.tabla == 'registrar_despacho' && r.id == datos['despacho_id']);
      if (despacho.isNotEmpty) {
        final r = despacho.first;
        _reemplazar(r.conDatos({...r.datos, 'peso_bascula': datos['peso']}));
        await _persistir();
        ref.read(datosOperadorProvider.notifier).aplicarMovimientoLocal(tabla, datos);
        if (ref.read(enLineaProvider)) unawaited(sincronizar());
        return r.id;
      }
    }
    final id = (datos['id'] as String?) ?? _uuid.v4();
    final r = RegistroPendiente(
      id: id,
      tabla: tabla,
      datos: {...datos, 'id': id},
      creado: DateTime.now(),
      usuario: ref.read(perfilProvider)?.id,
    );
    state = [...state, r];
    await _persistir();
    ref.read(datosOperadorProvider.notifier).aplicarMovimientoLocal(tabla, r.datos);
    // El envío no bloquea la pantalla: con señal débil la petición puede tardar.
    if (ref.read(enLineaProvider)) unawaited(sincronizar());
    return id;
  }

  int get pendientes => state.where((r) => !r.rechazado).length;

  /// Envía la cola en orden de dependencia. Se detiene si se pierde la conexión o hay que volver a ingresar.
  Future<void> sincronizar() async {
    if (_enviando || !ref.read(enLineaProvider)) return;
    _enviando = true;
    var envioAlguno = false;
    final aviso = ref.read(avisoSincronizacionProvider.notifier);
    try {
      await _carga;
      if (ordenDeEnvio(state).isEmpty) {
        aviso.fijar(null);
        return;
      }
      final auth = ref.read(supabaseProvider).auth;
      final sesion = auth.currentSession;
      if (sesion == null) {
        // Ingresó sin conexión: no hay sesión del servidor con la que enviar.
        aviso.fijar('Hay $pendientes registros guardados en el teléfono. Vuelva a ingresar con su contraseña '
            'para enviarlos al servidor.');
        return;
      }
      if (sesion.isExpired) {
        try {
          await auth.refreshSession();
        } catch (e) {
          if (esErrorRed(e)) return;
          aviso.fijar('Su sesión venció. Vuelva a ingresar con su contraseña para enviar los registros pendientes.');
          return;
        }
      }
      final usuario = auth.currentUser?.id;
      final repo = ref.read(repositorioOperacionesProvider);
      for (final r in ordenDeEnvio(state)) {
        // Lo registrado por otra cuenta en este teléfono espera a que esa cuenta ingrese.
        if (r.usuario != null && usuario != null && r.usuario != usuario) continue;
        try {
          await repo.sincronizar(r.tabla, r.datos, r.id);
          state = state.where((x) => x.id != r.id).toList();
          await _persistir();
          envioAlguno = true;
        } catch (e) {
          var err = e is ErrorNegocio ? e : traducirError(e);
          // Un «sin permiso» con la sesión revocada no es culpa del registro: se reintenta tras ingresar de nuevo.
          if (err.codigo == '42501' && !await _sesionVigente()) {
            err = const ErrorNegocio('Su sesión venció. Vuelva a iniciar sesión.', codigo: 'sesion');
          }
          if (esErrorPasajero(err)) {
            _reemplazar(r.conError(err.mensaje));
            await _persistir();
            if (err.codigo == 'sesion') {
              aviso.fijar('Su sesión venció. Vuelva a ingresar con su contraseña para enviar los registros pendientes.');
            }
            break;
          }
          if (err.codigo == null && r.intentos + 1 < _intentosMaximos) {
            // Error desconocido: se reintenta unas veces antes de pedir revisión al operador.
            _reemplazar(r.conError(err.mensaje));
          } else {
            _reemplazar(r.rechazar(err.mensaje));
          }
          await _persistir();
        }
      }
      if (ordenDeEnvio(state).where((r) => r.usuario == null || r.usuario == usuario).isEmpty) aviso.fijar(null);
      if (envioAlguno || state.where((r) => !r.rechazado).isEmpty) {
        if (esAndroid) await ref.read(pinLocalProvider).marcarSincronizado();
        await ref.read(datosOperadorProvider.notifier).refrescar();
      }
    } finally {
      _enviando = false;
    }
  }

  Future<bool> _sesionVigente() async {
    try {
      return (await ref.read(apiProvider).rpc('sesion_vigente'))['valor'] == true;
    } catch (_) {
      return true;
    }
  }

  /// El operador descarta un registro rechazado después de leer el motivo (no se edita: se vuelve a registrar).
  Future<void> descartar(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _persistir();
  }

  /// El operador vuelve a enviar un registro rechazado (por ejemplo, después de que la oficina corrigió un dato).
  Future<void> reintentar(String id) async {
    state = [for (final r in state) r.id == id ? r.reintentar() : r];
    await _persistir();
    if (ref.read(enLineaProvider)) unawaited(sincronizar());
  }
}

final colaProvider = NotifierProvider<ColaSincronizacion, List<RegistroPendiente>>(ColaSincronizacion.new);

/// Mensaje para el usuario cuando la cola no puede enviarse (sin sesión del servidor o sesión vencida).
class AvisoSincronizacion extends Notifier<String?> {
  @override
  String? build() => null;
  void fijar(String? mensaje) {
    if (state != mensaje) state = mensaje;
  }
}

final avisoSincronizacionProvider = NotifierProvider<AvisoSincronizacion, String?>(AvisoSincronizacion.new);

final pendientesSincronizarProvider = Provider<int>((ref) => ref.watch(colaProvider).where((r) => !r.rechazado).length);

/// Almacén local completo en SQLite para trabajo 24/7 sin conexión.
/// Persiste catálogos, pesajes, órdenes abiertas y cerradas, consumos, insumos, lotes, guías, despachos, solicitudes y reportes.
class DatosOperador extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() {
    // ignore: experimental_member_use
    persist(
      ref.watch(almacenPersistenteProvider.future),
      key: 'datos_operador_v2',
      encode: jsonEncode,
      decode: (t) => Map<String, dynamic>.from(jsonDecode(t) as Map),
      options: const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever),
    );
    return const {
      'granos': granosPredeterminados,
      'sedes': sedesPredeterminadas,
    };
  }

  List<Map<String, dynamic>> lista(String clave) {
    final raw = state[clave];
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    if (clave == 'granos') return granosPredeterminados;
    if (clave == 'sedes') return sedesPredeterminadas;
    return const [];
  }

  Map<String, dynamic>? mapa(String clave) {
    final raw = state[clave];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  void guardarClave(String clave, Object? valor) {
    state = {...state, clave: valor, 'actualizado': DateTime.now().toIso8601String()};
  }

  /// Roles que registran en un centro y necesitan la copia local para trabajar sin señal. Para los demás no se
  /// descarga: sus consultas de centro se rechazarían (403) y llenarían la bitácora de accesos denegados.
  static bool usaCopiaLocal(Rol? rol) => rol == Rol.operadorCentro || rol == Rol.gerenteGeneral || rol == Rol.superadmin;

  Future<void> refrescar() async {
    if (!ref.read(enLineaProvider)) return;
    final perfil = ref.read(perfilProvider);
    if (perfil == null || !usaCopiaLocal(perfil.rol)) return;
    final repoOp = ref.read(repositorioOperacionesProvider);
    final repoInv = ref.read(repositorioInventarioProvider);
    final repoCom = ref.read(repositorioComercialProvider);
    final api = ref.read(apiProvider);
    // La copia es de una sola cuenta: si en el teléfono ingresa otra, se descarta la anterior (no se ven datos de
    // otro centro). La cola de registros pendientes no se toca.
    final propia = state['usuario'] == null || state['usuario'] == perfil.id;
    final nuevo = <String, dynamic>{
      ...(propia ? state : const {'granos': granosPredeterminados, 'sedes': sedesPredeterminadas}),
      'usuario': perfil.id,
    };

    Future<void> intentar(String clave, Future<Object?> Function() f) async {
      try {
        final v = await f();
        if (v != null) nuevo[clave] = v;
      } catch (_) {}
    }

    await intentar('granos', () async {
      final g = await repoOp.granos();
      return g.isEmpty ? granosPredeterminados : g;
    });
    await intentar('sedes', () async {
      final s = await repoInv.sedes();
      return s.isEmpty ? sedesPredeterminadas : s;
    });
    await intentar('productores', () => repoOp.productores());
    await intentar('pesajes', () => repoOp.pesajes());
    await intentar('ordenes_lista', () async {
      final o = await repoOp.ordenes();
      nuevo['ordenes'] = o
          .where((x) => x['estado'] == 'abierta')
          .map((x) => {
                'id': x['id'],
                'grano_id': x['grano_id'],
                'fecha_apertura': x['fecha_apertura'],
                'grano': x['granos']?['nombre'],
              })
          .toList();
      final mapaConsumos = <String, dynamic>{
        ...((nuevo['consumos_por_orden'] as Map?)?.map((k, v) => MapEntry('$k', v)) ?? const {}),
      };
      for (final ord in o.where((x) => x['estado'] == 'abierta')) {
        try {
          mapaConsumos['${ord['id']}'] = await repoOp.consumos('${ord['id']}');
        } catch (_) {}
      }
      nuevo['consumos_por_orden'] = mapaConsumos;
      return o;
    });
    await intentar('insumos', () => repoOp.insumosDisponibles());
    await intentar('lotes_fermentacion', () => repoOp.lotesEnFermentacion());
    await intentar('lotes_stock', () => repoInv.lotes());
    await intentar('existencias', () => repoInv.existencias());
    await intentar('guias', () => repoInv.guias());
    await intentar('mis_solicitudes', () => api.rpcLista('mis_solicitudes'));
    await intentar('despachos_pendientes', () => repoCom.despachosPendientes());
    await intentar('despachos', () => repoCom.despachos());

    nuevo['actualizado'] = DateTime.now().toIso8601String();
    state = nuevo;
  }

  void agregarOrdenLocal(Map<String, dynamic> orden) {
    final l = [...lista('ordenes').where((x) => x['id'] != orden['id']), orden];
    state = {...state, 'ordenes': l};
  }

  /// Actualiza la copia local en SQLite de inmediato cuando se registra una operación con o sin conexión,
  /// para que todas las pantallas reflejen el trabajo 24/7 sin esperar al servidor.
  void aplicarMovimientoLocal(String tabla, Map<String, dynamic> datos) {
    final perfil = ref.read(perfilProvider);
    final granos = lista('granos');
    final productores = lista('productores');
    final nuevo = {...state};

    switch (tabla) {
      case 'ordenes_ensilado':
        final granoObj = granos.where((g) => g['id'] == datos['grano_id']).firstOrNull ??
            {'id': datos['grano_id'], 'nombre': 'Grano', 'rollos_ton_min': 1.0, 'rollos_ton_max': 1.4};
        final filaOrden = {
          'id': datos['id'],
          'sede_id': datos['sede_id'] ?? perfil?.sedeId,
          'grano_id': datos['grano_id'],
          'estado': 'abierta',
          'fecha_apertura': datos['fecha_apertura'] ?? DateTime.now().toUtc().toIso8601String(),
          'fecha_cierre': null,
          'rollos_obtenidos': null,
          'granos': {
            'nombre': granoObj['nombre'],
            'rollos_ton_min': granoObj['rollos_ton_min'] ?? 1.0,
            'rollos_ton_max': granoObj['rollos_ton_max'] ?? 1.4,
          },
          'sedes': {'nombre': perfil?.sede ?? 'Centro de acopio'},
          'pesajes': <Map<String, dynamic>>[],
          'lotes': <Map<String, dynamic>>[],
        };
        nuevo['ordenes_lista'] = [filaOrden, ...lista('ordenes_lista').where((x) => x['id'] != datos['id'])];
        nuevo['ordenes'] = [
          {
            'id': datos['id'],
            'grano_id': datos['grano_id'],
            'fecha_apertura': filaOrden['fecha_apertura'],
            'grano': granoObj['nombre'],
          },
          ...lista('ordenes').where((x) => x['id'] != datos['id']),
        ];

      case 'pesajes':
        final granoObj = granos.where((g) => g['id'] == datos['grano_id']).firstOrNull;
        final prodObj = productores.where((p) => '${p['id']}' == '${datos['proveedor_id']}').firstOrNull;
        final bruto = (datos['peso_bruto'] as num?)?.toDouble() ?? 0;
        final tara = (datos['tara'] as num?)?.toDouble() ?? 0;
        final hum = (datos['humedad'] as num?)?.toDouble() ?? 14;
        final est = (granoObj?['humedad_estandar'] as num?)?.toDouble() ?? 14;
        final neto = bruto > tara && tara > 0 ? bruto - tara : 0.0;
        final ajustado = neto > 0 ? pesoAjustadoPorHumedad(neto, hum, est) : 0.0;
        final filaPesaje = {
          ...datos,
          'peso_neto': neto,
          'peso_ajustado': ajustado,
          'fecha_registro': datos['fecha_dispositivo'],
          'granos': {'nombre': granoObj?['nombre'] ?? 'Grano'},
          'proveedores': prodObj == null ? null : {'razon_social': prodObj['razon_social']},
          'sedes': {'nombre': perfil?.sede ?? 'Centro de acopio'},
        };
        nuevo['pesajes'] = [filaPesaje, ...lista('pesajes').where((x) => x['id'] != datos['id'])];
        if (datos['orden_id'] != null) {
          nuevo['ordenes_lista'] = [
            for (final o in lista('ordenes_lista'))
              if (o['id'] == datos['orden_id'])
                {
                  ...o,
                  'pesajes': [
                    ...((o['pesajes'] as List?) ?? const []),
                    {'id': datos['id'], 'peso_ajustado': ajustado, 'estado': 'confirmado'},
                  ],
                }
              else
                o,
          ];
        }

      case 'consumos_insumo':
        final ordenId = '${datos['orden_id']}';
        final prodId = '${datos['producto_id']}';
        final mapaConsumos = <String, dynamic>{
          ...((nuevo['consumos_por_orden'] as Map?)?.map((k, v) => MapEntry('$k', v)) ?? const {}),
        };
        final actual = ((mapaConsumos[ordenId] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        actual.add({
          'id': datos['id'],
          'orden_id': ordenId,
          'producto_id': prodId,
          'cantidad': datos['cantidad'],
          'productos': {
            'nombre': nombresInsumosOffline[prodId] ?? 'Insumo',
            'sku': skusInsumosOffline[prodId] ?? 'INS',
          },
        });
        mapaConsumos[ordenId] = actual;
        nuevo['consumos_por_orden'] = mapaConsumos;

      case 'cerrar_orden':
        final ordenId = '${datos['orden_id']}';
        final rollos = (datos['rollos'] as num?)?.toInt() ?? 0;
        final fechaCierre = '${datos['fecha_dispositivo'] ?? DateTime.now().toUtc().toIso8601String()}';
        final codigoTemp = '${datos['codigo_temporal'] ?? 'L-SIN-CONEXION'}';
        final loteId = '${datos['lote_id'] ?? datos['id']}';
        Map<String, dynamic>? ordenCerrada;
        nuevo['ordenes_lista'] = [
          for (final o in lista('ordenes_lista'))
            if (o['id'] == ordenId)
              (ordenCerrada = {
                ...o,
                'estado': 'cerrada',
                'fecha_cierre': fechaCierre,
                'rollos_obtenidos': rollos,
                'lotes': {'id': loteId, 'codigo': codigoTemp, 'estado': 'fermentacion'},
              })
            else
              o,
        ];
        nuevo['ordenes'] = lista('ordenes').where((x) => x['id'] != ordenId).toList();
        if (ordenCerrada != null) {
          final cerrada = ordenCerrada;
          final granoNombre = '${cerrada['granos']?['nombre'] ?? 'Maíz'}';
          final granoObj = granos.where((g) => g['nombre'] == granoNombre || g['id'] == cerrada['grano_id']).firstOrNull;
          final nuevoLote = {
            'id': loteId,
            'codigo': codigoTemp,
            'fecha_sellado': fechaCierre.substring(0, 10),
            'estado': 'fermentacion',
            'rollos_producidos': rollos,
            'peso_promedio_rollo': 850,
            'sede_id': cerrada['sede_id'] ?? perfil?.sedeId,
            'sedes': {'nombre': perfil?.sede ?? 'Centro de acopio'},
            'productos': {
              'nombre': 'Rollo de $granoNombre',
              'granos': {'nombre': granoNombre, 'dias_fermentacion': granoObj?['dias_fermentacion'] ?? 21},
            },
            'existencias': [
              {
                'sede_id': cerrada['sede_id'] ?? perfil?.sedeId,
                'disponible': rollos,
                'reservado': 0,
                'en_transito': 0,
              }
            ],
          };
          nuevo['lotes_fermentacion'] = [nuevoLote, ...lista('lotes_fermentacion')];
          nuevo['lotes_stock'] = [nuevoLote, ...lista('lotes_stock')];
        }

      case 'revisiones_fermentacion':
        if (datos['estado_film'] == 'danado') {
          nuevo['lotes_fermentacion'] = [
            for (final l in lista('lotes_fermentacion'))
              if (l['id'] == datos['lote_id']) {...l, 'estado': 'observado'} else l,
          ];
          nuevo['lotes_stock'] = [
            for (final l in lista('lotes_stock'))
              if (l['id'] == datos['lote_id']) {...l, 'estado': 'observado'} else l,
          ];
        }

      case 'solicitar_correccion_pesaje' || 'solicitar_merma' || 'solicitar_ajuste':
        final tipoSol = switch (tabla) {
          'solicitar_correccion_pesaje' => 'correccion_pesaje',
          'solicitar_merma' => 'merma',
          _ => 'ajuste',
        };
        final motivo = '${datos['motivo'] ?? datos['descripcion'] ?? 'Solicitud registrada sin conexión'}';
        nuevo['mis_solicitudes'] = [
          {
            'id': datos['id'],
            'tipo': tipoSol,
            'motivo': motivo,
            'estado': 'pendiente',
            'fecha_registro': DateTime.now().toUtc().toIso8601String(),
            'aprobado_por': null,
            'datos': datos,
          },
          ...lista('mis_solicitudes'),
        ];

      case 'emitir_guia':
        final sedes = lista('sedes');
        final destObj = sedes.where((s) => '${s['id']}' == '${datos['destino']}').firstOrNull;
        final items = ((datos['items'] as List?) ?? const []).whereType<Map>().toList();
        nuevo['guias'] = [
          {
            'id': datos['id'],
            'numero': 'PEND',
            'estado': 'en_transito',
            'fecha_emision': DateTime.now().toUtc().toIso8601String(),
            'sede_origen': perfil?.sedeId,
            'sede_destino': datos['destino'],
            'origen': {'nombre': perfil?.sede ?? 'Centro de origen'},
            'destino': {'nombre': destObj?['nombre'] ?? 'Centro de destino'},
            'emisor': {'nombre_completo': perfil?.nombre ?? 'Operador'},
            'receptor': null,
            'guia_detalle': [
              for (final i in items)
                {
                  'lote_id': i['lote_id'],
                  'cantidad_enviada': i['cantidad'],
                  'cantidad_recibida': null,
                  'lotes': {'codigo': i['codigo'] ?? 'Lote'},
                }
            ],
          },
          ...lista('guias'),
        ];

      case 'recibir_guia':
        nuevo['guias'] = [
          for (final g in lista('guias'))
            if (g['id'] == datos['guia_id'])
              {
                ...g,
                'estado': 'recibida',
                'fecha_recepcion': DateTime.now().toUtc().toIso8601String(),
                'receptor': {'nombre_completo': perfil?.nombre ?? 'Operador'},
              }
            else
              g,
        ];

      case 'registrar_despacho':
        final pesos = ((datos['pesos'] as List?) ?? const []).map((x) => (x as num).toDouble()).toList();
        final totalKg = pesos.fold<double>(0, (a, b) => a + b);
        nuevo['despachos'] = [
          {
            'id': datos['id'],
            'fecha_registro': DateTime.now().toUtc().toIso8601String(),
            'notas_venta': {'numero': datos['numero_nota'] ?? '—'},
            'sedes': {'nombre': perfil?.sede ?? 'Centro'},
            'lotes': {'codigo': datos['codigo_lote'] ?? 'Lote'},
            'cantidad': pesos.length,
            'peso_vendido': datos['peso_vendido'] ?? totalKg,
            'peso_despachado': totalKg,
            'peso_bascula_publica': datos['peso_bascula'],
            'placa': datos['placa'],
            'receptor': datos['receptor'],
          },
          ...lista('despachos'),
        ];
        nuevo['despachos_pendientes'] = [
          for (final dp in lista('despachos_pendientes'))
            if (dp['nota_id'] == datos['nota_id'] && dp['lote_id'] == datos['lote_id'])
              {
                ...dp,
                'despachados': ((dp['despachados'] as num?)?.toInt() ?? 0) + pesos.length,
                'reservado_sede': (((dp['reservado_sede'] as num?)?.toInt() ?? 0) - pesos.length).clamp(0, 999999),
              }
            else
              dp,
        ];

      case 'registrar_peso_bascula':
        nuevo['despachos'] = [
          for (final d in lista('despachos'))
            if (d['id'] == datos['despacho_id']) {...d, 'peso_bascula_publica': datos['peso']} else d,
        ];
    }

    state = nuevo;
  }
}

final datosOperadorProvider = NotifierProvider<DatosOperador, Map<String, dynamic>>(DatosOperador.new);

/// Filas de una copia local (lista JSON guardada en el teléfono).
List<Fila> filasDeCopia(Object? copia) =>
    ((copia as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

/// Consulta de pantalla con copia local para trabajar sin conexión.
///
/// Sin señal observa la copia guardada en el teléfono, así lo registrado sin conexión se ve al instante. Con señal
/// consulta el servidor y actualiza la copia SIN observarla: antes las pantallas observaban la copia y la escribían
/// en la misma consulta, lo que las recargaba sin fin y las dejaba «cargando» para siempre.
Future<T> consultarConCopiaLocal<T>(
  Ref ref,
  String clave, {
  required Future<T> Function() remoto,
  required T Function(Object? copia) local,
}) async {
  if (!ref.watch(enLineaProvider)) {
    return local(ref.watch(datosOperadorProvider.select((m) => m[clave])));
  }
  try {
    final valor = await remoto();
    try {
      ref.read(datosOperadorProvider.notifier).guardarClave(clave, valor);
    } catch (_) {
      // La pantalla se cerró mientras llegaba la respuesta: no hace falta guardar la copia.
    }
    return valor;
  } on ErrorNegocio catch (e) {
    Object? copia;
    try {
      copia = ref.read(datosOperadorProvider)[clave];
    } catch (_) {}
    // Sin permiso y sin copia: se muestra el motivo en lugar de una pantalla vacía.
    if (copia == null && e.prohibido) rethrow;
    return local(copia);
  } catch (_) {
    Object? copia;
    try {
      copia = ref.read(datosOperadorProvider)[clave];
    } catch (_) {}
    return local(copia);
  }
}
