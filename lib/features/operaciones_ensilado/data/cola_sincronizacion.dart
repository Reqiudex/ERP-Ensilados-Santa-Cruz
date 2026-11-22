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
import '../../seguridad_accesos/presentation/sesion.dart';
import '../domain/calculos_operaciones.dart';
import '../domain/registro_pendiente.dart';
import 'repositorio_operaciones_supabase.dart';

/// Catálogos base predeterminados de Ensilados Santa Cruz para poder trabajar desde el primer arranque aunque no haya señal.
const List<Map<String, dynamic>> granosPredeterminados = [
  {'id': 1, 'nombre': 'Maíz', 'humedad_estandar': 14.0, 'dias_fermentacion': 21, 'rollos_ton_min': 1.0, 'rollos_ton_max': 1.4},
  {'id': 2, 'nombre': 'Sorgo', 'humedad_estandar': 14.0, 'dias_fermentacion': 21, 'rollos_ton_min': 1.0, 'rollos_ton_max': 1.4},
  {'id': 3, 'nombre': 'Soya', 'humedad_estandar': 13.0, 'dias_fermentacion': 25, 'rollos_ton_min': 0.95, 'rollos_ton_max': 1.35},
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

/// Cola local de solo inserción (persistencia de Riverpod 3 + SQLite en Android).
/// Cada registro lleva un UUID generado en el dispositivo y la hora del dispositivo; al reconectar se envía en orden
/// y sin duplicarse. Si el servidor lo rechaza, queda «rechazado» con el motivo para el operador.
class ColaSincronizacion extends Notifier<List<RegistroPendiente>> {
  bool _enviando = false;

  @override
  List<RegistroPendiente> build() {
    // ignore: experimental_member_use
    persist(
      ref.watch(almacenPersistenteProvider.future),
      key: 'cola_sincronizacion_v1',
      encode: (s) => jsonEncode(s.map((r) => r.aJson()).toList()),
      decode: (t) => (jsonDecode(t) as List).map((e) => RegistroPendiente.desdeJson(e as Map<String, dynamic>)).toList(),
      options: const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever),
    );
    return const [];
  }

  static const _uuid = Uuid();

  /// Guarda el registro en el teléfono y lo envía de inmediato si hay conexión.
  /// Devuelve el identificador generado en el dispositivo.
  Future<String> registrar(String tabla, Map<String, dynamic> datos) async {
    if (!tablasSinConexion.contains(tabla)) throw ArgumentError('$tabla exige conexión');
    final id = (datos['id'] as String?) ?? _uuid.v4();
    final r = RegistroPendiente(id: id, tabla: tabla, datos: {...datos, 'id': id}, creado: DateTime.now());
    state = [...state, r];
    ref.read(datosOperadorProvider.notifier).aplicarMovimientoLocal(tabla, r.datos);
    if (ref.read(enLineaProvider)) await sincronizar();
    return id;
  }

  int get pendientes => state.where((r) => !r.rechazado).length;

  /// Envía la cola en orden cronológico y de dependencia. Se detiene si se pierde la conexión.
  Future<void> sincronizar() async {
    if (_enviando || !ref.read(enLineaProvider)) return;
    _enviando = true;
    var envioAlguno = false;
    try {
      final repo = ref.read(repositorioOperacionesProvider);
      for (final r in ordenDeEnvio(state)) {
        try {
          await repo.sincronizar(r.tabla, r.datos);
          state = state.where((x) => x.id != r.id).toList();
          envioAlguno = true;
        } on ErrorNegocio catch (e) {
          if (e.codigo == 'red') break;
          state = [for (final x in state) x.id == r.id ? x.rechazar(e.mensaje) : x];
        } catch (e) {
          final err = traducirError(e);
          if (err.codigo == 'red') break;
          state = [for (final x in state) x.id == r.id ? x.rechazar(err.mensaje) : x];
        }
      }
      if (envioAlguno || state.where((r) => !r.rechazado).isEmpty) {
        if (esAndroid) await ref.read(pinLocalProvider).marcarSincronizado();
        await ref.read(datosOperadorProvider.notifier).refrescar();
      }
    } finally {
      _enviando = false;
    }
  }

  /// El operador descarta un registro rechazado después de leer el motivo (no se edita: se vuelve a registrar).
  void descartar(String id) => state = state.where((r) => r.id != id).toList();
}

final colaProvider = NotifierProvider<ColaSincronizacion, List<RegistroPendiente>>(ColaSincronizacion.new);

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

  Future<void> refrescar() async {
    if (!ref.read(enLineaProvider)) return;
    final repoOp = ref.read(repositorioOperacionesProvider);
    final repoInv = ref.read(repositorioInventarioProvider);
    final repoCom = ref.read(repositorioComercialProvider);
    final api = ref.read(apiProvider);
    final perfil = ref.read(perfilProvider);
    final nuevo = {...state};

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
    if (perfil != null) {
      await intentar('despachos_pendientes', () => repoCom.despachosPendientes());
      await intentar('despachos', () => repoCom.despachos());
    }

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
