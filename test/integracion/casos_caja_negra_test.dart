// Casos de prueba de caja negra CP-01 a CP-27 (18 casos) contra el proyecto de Supabase en línea.
// Cada caso inicia sesión con la cuenta del rol que indica la tesis.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/data/pin_local.dart';
import 'package:erp_ensilados_santa_cruz/core/almacenamiento/almacen_local.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/perfil.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/reglas_seguridad.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../apoyo/cliente_prueba.dart';

const _uuid = Uuid();

/// Abre una orden con tres pesajes confirmados en el centro del operador y devuelve su id.
Future<String> ordenConPesajes(Sesion op, String sede, {int grano = 1, double netoKg = 34000, double film = 1}) async {
  final orden = _uuid.v4();
  final ahora = DateTime.now().toUtc().toIso8601String();
  final r = await op.post('ordenes_ensilado', {
    'id': orden, 'sede_id': sede, 'grano_id': grano, 'fecha_apertura': ahora, 'estado': 'abierta', 'registrado_por': op.usuarioId,
  });
  expect(r.estado, 201, reason: '$r');
  for (var i = 0; i < 3; i++) {
    final p = await op.post('pesajes', {
      'id': _uuid.v4(), 'sede_id': sede, 'origen': 'propio', 'grano_id': grano, 'placa': 'PRB-${sello().substring(3)}',
      'peso_bruto': 12000 + netoKg, 'tara': 12000, 'humedad': 14, 'impurezas': 1, 'orden_id': orden, 'estado': 'confirmado',
      'fecha_dispositivo': ahora, 'registrado_por': op.usuarioId,
    });
    expect(p.estado, 201, reason: '$p');
  }
  final c = await op.post('consumos_insumo', {'id': _uuid.v4(), 'orden_id': orden, 'producto_id': 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'cantidad': film});
  expect(c.estado, 201, reason: '$c');
  return orden;
}

void main() {
  test('CP-01 RF-01 Crear una cuenta con un CI ya registrado', () async {
    final admin = await Sesion.de('admin');
    final r = await admin.rpc('crear_usuario', {
      'p_nombre': 'Prueba Duplicado', 'p_ci': '6543210', 'p_correo': 'duplicado${sello()}@ensilados.demo',
      'p_rol': 'operador_centro', 'p_sede': sedeSanRamon, 'p_clave': 'Ensilados2026!',
    });
    obtenido('CP-01', '$r');
    expect(r.estado, isNot(200));
    expect(r.mensaje, contains('Ya existe una cuenta registrada con ese CI'));
  });

  test('CP-02 RF-02 Registrar una solicitud propia para luego aprobarla', () async {
    // Desde la migración 20261124120000 nadie inserta solicitudes directamente: solo las funciones que validan
    // los datos las crean, y el gerente (quien aprueba) no tiene ninguna función que registre solicitudes.
    final g = await Sesion.de('gerente');
    final ins = await g.post('solicitudes_aprobacion', {
      'tipo': 'prueba_control', 'entidad': 'pruebas', 'entidad_id': _uuid.v4(), 'datos_propuestos': {'caso': 'CP-02'},
      'motivo': 'Prueba de doble control (CP-02)', 'registrado_por': g.usuarioId, 'estado': 'pendiente',
    });
    obtenido('CP-02', '$ins');
    expect(ins.estado, anyOf(401, 403));
  });

  test('CP-03 RF-03 Guardar una clave débil', () async {
    final op = await Sesion.de('op_sr');
    final r = await op.rpc('cambiar_mi_clave', {'p_actual': claveDemo, 'p_nueva': 'abc123'});
    obtenido('CP-03', '$r');
    expect(r.estado, isNot(200));
    expect(r.mensaje, contains('Al menos 8 caracteres'));
  });

  test('CP-04 RF-04 Dejar la sesión sin uso 15 minutos', () async {
    final op = await Sesion.de('op_sr');
    final perfil = await op.rpc('mi_perfil');
    final minutos = (perfil.cuerpo['parametros']['inactividad_minutos'] as num).toInt();
    final inicio = DateTime(2026, 11, 18, 10);
    final cierra = sesionVencidaPorInactividad(inicio, inicio.add(Duration(minutes: minutos)), minutos: minutos);
    obtenido('CP-04', 'Parámetro en la base: $minutos minutos; a los $minutos minutos sin interacción la sesión ${cierra ? 'se cierra y pide credenciales' : 'sigue abierta'} (web: cierre; Android: bloqueo con PIN)');
    expect(minutos, 15);
    expect(cierra, isTrue);
  });

  test('CP-05 RF-05 Modificar un evento de la bitácora', () async {
    final resultados = <String>[];
    for (final rol in ['admin', 'gerente', 'op_sr', 'ejecutivo', 'cajero']) {
      final s = await Sesion.de(rol);
      final r = await s.patch('bitacora_eventos?id=gt.0', {'accion': 'alterado'});
      resultados.add('$rol: HTTP ${r.estado} ${r.codigo}');
      expect(r.estado, anyOf(401, 403), reason: '$rol $r');
    }
    obtenido('CP-05', 'UPDATE rechazado para todos los roles (${resultados.join('; ')})');
  });

  test('CP-06 RF-06 Restaurar un respaldo sin aprobación', () async {
    final admin = await Sesion.de('admin');
    final r = await admin.rpc('solicitar_restauracion', {'p_respaldo': 'respaldo-prueba', 'p_motivo': 'Prueba CP-06: restaurar sin aprobación'});
    obtenido('CP-06', '$r');
    expect(r.estado, 200);
    expect(r.cuerpo['estado'], 'pendiente');
  });

  test('CP-09 RF-07 Registrar un pesaje sin conexión', () async {
    final op = await Sesion.de('op_sr');
    // En modo avión el pesaje queda en la cola local con UUID y hora del dispositivo; al reconectar se envía
    // y un reintento (por ejemplo, tras perder la respuesta) no lo duplica.
    final id = _uuid.v4();
    final hora = DateTime.now().toUtc().subtract(const Duration(minutes: 40)).toIso8601String();
    final pesaje = {
      'id': id, 'sede_id': sedeSanRamon, 'origen': 'propio', 'grano_id': 1, 'placa': 'OFF-${sello().substring(4)}',
      'peso_bruto': 30000, 'tara': 12000, 'humedad': 15, 'impurezas': 1, 'estado': 'confirmado',
      'fecha_dispositivo': hora, 'registrado_por': op.usuarioId,
    };
    final r1 = await op.upsertIgnorar('pesajes', pesaje);
    final r2 = await op.upsertIgnorar('pesajes', pesaje);
    final l = await op.get('pesajes?id=eq.$id&select=id,fecha_dispositivo,fecha_registro');
    obtenido('CP-09', 'Envío 1: HTTP ${r1.estado}; reenvío: HTTP ${r2.estado}; filas en el servidor: ${(l.cuerpo as List).length}; '
        'hora del dispositivo conservada: ${(l.cuerpo as List).first['fecha_dispositivo']}');
    expect((l.cuerpo as List).length, 1);
  });

  test('CP-10 RF-08 Cerrar una orden de ensilado', () async {
    final op = await Sesion.de('op_sr');
    final orden = await ordenConPesajes(op, sedeSanRamon);
    final r = await op.rpc('cerrar_orden', {'p_orden': orden, 'p_rollos': 120});
    obtenido('CP-10', '$r');
    expect(r.estado, 200, reason: '$r');
    expect(r.cuerpo['estado'], 'fermentacion');
    expect(r.cuerpo['codigo'], startsWith('L-MAI-'));
  });

  test('CP-11 RF-09 Cerrar una orden sin film suficiente', () async {
    final op = await Sesion.de('op_sr');
    final orden = await ordenConPesajes(op, sedeSanRamon, film: 9999);
    final r = await op.rpc('cerrar_orden', {'p_orden': orden, 'p_rollos': 120});
    obtenido('CP-11', '$r');
    expect(r.estado, isNot(200));
    expect(r.mensaje, contains('insumos insuficientes'));
    expect(r.mensaje, contains('faltan'));
  });

  test('CP-13 RF-11 Despachar más que el saldo del lote', () async {
    final op = await Sesion.de('op_sj');
    final pend = await op.rpc('despachos_pendientes');
    final nota = (pend.cuerpo as List).firstWhere((x) => (x['reservado_sede'] as num) == 40);
    final antes = (nota['reservado_sede'] as num).toInt();
    final r = await op.rpc('registrar_despacho', {
      'p_nota': nota['nota_id'], 'p_lote': nota['lote_id'], 'p_pesos': List.filled(45, 850),
      'p_placa': '3344-PRB', 'p_receptor': 'Prueba CP-13',
    });
    final despues = ((await op.rpc('despachos_pendientes')).cuerpo as List).firstWhere((x) => x['nota_id'] == nota['nota_id'])['reservado_sede'];
    obtenido('CP-13', '$r · saldo antes $antes, después $despues');
    expect(r.estado, isNot(200));
    // Desde 20261124120000 el despacho se limita a lo reservado para ESA venta en el centro (más estricto que el saldo).
    expect(r.mensaje, anyOf(contains('supera el saldo'), contains('supera lo reservado')));
    expect((despues as num).toInt(), antes);
  });

  test('CP-14 RF-12 Ver un cambio de stock desde la oficina', () async {
    final g = await Sesion.de('gerente');
    final op = await Sesion.de('op_sj');
    final orden = await ordenConPesajes(op, sedeSanJulian, grano: 2, netoKg: 20000);
    // El canal debe unirse con el token del gerente (no como anónimo): RLS solo difunde lo que el rol puede leer.
    await g.cliente.realtime.setAuth(g.token);
    final recibido = Completer<DateTime>();
    final suscrito = Completer<void>();
    final canal = g.cliente
        .channel('cp14-${sello()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'existencias',
          callback: (p) {
            if (p.newRecord['sede_id'] == sedeSanJulian && !recibido.isCompleted) recibido.complete(DateTime.now());
          },
        )
        .subscribe((estado, [_]) {
      if (estado == RealtimeSubscribeStatus.subscribed && !suscrito.isCompleted) suscrito.complete();
    });
    await suscrito.future.timeout(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(seconds: 2));
    final t0 = DateTime.now();
    final r = await op.rpc('cerrar_orden', {'p_orden': orden, 'p_rollos': 70});
    expect(r.estado, 200, reason: '$r');
    final t1 = await recibido.future.timeout(const Duration(seconds: 10));
    final ms = t1.difference(t0).inMilliseconds;
    await g.cliente.removeChannel(canal);
    obtenido('CP-14', 'Ingreso del lote ${r.cuerpo['codigo']} en San Julián visible en la oficina en $ms ms sin recargar (Realtime)');
    expect(ms, lessThanOrEqualTo(3000));
  });

  test('CP-15 RF-13 Registrar un SKU repetido', () async {
    final e = await Sesion.de('ejecutivo');
    final r = await e.rpc('solicitar_producto', {
      'p_sku': 'ROL-MAI-850', 'p_nombre': 'Duplicado', 'p_tipo': 'rollo', 'p_grano': 1, 'p_unidad': 'rollo',
      'p_precio_tonelada': 500, 'p_precio_rollo': 430, 'p_motivo': 'Prueba CP-15',
    });
    final p = await e.rpc('solicitar_cambio_precio', {
      'p_producto': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'p_precio_tonelada': 495, 'p_precio_rollo': 425, 'p_motivo': 'Prueba CP-15: precio nuevo',
    });
    obtenido('CP-15', 'SKU repetido: $r · precio nuevo: estado ${p.cuerpo['estado']}');
    expect(r.estado, isNot(200));
    expect(r.mensaje, contains('Ya existe un producto con el SKU'));
    expect(p.cuerpo['estado'], 'pendiente');
  });

  test('CP-16 RF-14 Confirmar una guía propia', () async {
    final op = await Sesion.de('op_sr');
    final lotes = await op.get('existencias?select=lote_id,disponible&sede_id=eq.$sedeSanRamon&lote_id=not.is.null&disponible=gt.0&limit=1');
    final lote = (lotes.cuerpo as List).first['lote_id'];
    final g = await op.rpc('emitir_guia', {'p_destino': sedeSanJulian, 'p_items': [{'lote_id': lote, 'cantidad': 1}]});
    expect(g.estado, 200, reason: '$g');
    final r = await op.rpc('recibir_guia', {'p_guia': g.cuerpo['guia_id']});
    obtenido('CP-16', '$r');
    expect(r.codigo, '23514');
    expect(r.mensaje, contains('guias_transferencia_check1'));
    // Cierra la prueba: el operador del centro de destino recibe la guía.
    final ok = await (await Sesion.de('op_sj')).rpc('recibir_guia', {'p_guia': g.cuerpo['guia_id']});
    expect(ok.estado, 200, reason: '$ok');
  });

  test('CP-17 RF-15 Registrar un proveedor nuevo', () async {
    final e = await Sesion.de('ejecutivo');
    final nit = '9${sello()}';
    final r = await e.post('proveedores', {'nit_ci': nit, 'razon_social': 'Productor de prueba $nit', 'tipo': 'productor', 'telefono': '70000000'});
    final l = await e.get('proveedores?nit_ci=eq.$nit&select=estado');
    final sol = await e.rpc('mis_solicitudes');
    final pendiente = (sol.cuerpo as List).any((s) => s['tipo'] == 'activar_proveedor' && s['estado'] == 'pendiente');
    obtenido('CP-17', 'Alta HTTP ${r.estado}; estado del proveedor: ${(l.cuerpo as List).first['estado']}; solicitud de activación pendiente: $pendiente');
    expect((l.cuerpo as List).first['estado'], 'inactivo');
    expect(pendiente, isTrue);
  });

  test('CP-18 RF-16 Pagar más que el saldo de una compra', () async {
    final c = await Sesion.de('cajero');
    final compras = await c.get('compras?select=id,saldo,estado&estado=eq.aprobada&saldo=eq.5000');
    final compra = (compras.cuerpo as List).first;
    final r = await c.rpc('registrar_pago', {'p_compra': compra['id'], 'p_monto': 6000, 'p_metodo': 'transferencia'});
    obtenido('CP-18', '$r');
    expect(r.estado, isNot(200));
    expect(r.mensaje, contains('supera el saldo'));
  });

  test('CP-20 RF-18 Cobrar desde la cuenta del ejecutivo', () async {
    final e = await Sesion.de('ejecutivo');
    final notas = await e.get('notas_venta?select=id&estado=eq.emitida&saldo=gt.0&limit=1');
    final r = await e.rpc('registrar_cobro', {'p_nota': (notas.cuerpo as List).first['id'], 'p_monto': 1, 'p_metodo': 'efectivo'});
    final g = await Sesion.de('gerente');
    final ev = await g.get('bitacora_eventos?select=id,accion,tabla,usuario_id,fecha_servidor&accion=eq.acceso_denegado&tabla=eq.cobros'
        '&usuario_id=eq.${e.usuarioId}&order=id.desc&limit=1');
    final evento = (ev.cuerpo as List).first;
    obtenido('CP-20', '$r · evento de bitácora N.º ${evento['id']} (${evento['accion']}, ${evento['tabla']})');
    expect(r.estado, 403);
    expect(DateTime.now().difference(DateTime.parse(evento['fecha_servidor'])).inMinutes, lessThan(2));
  });

  test('CP-24 RF-22 Filtrar ventas por cliente y período', () async {
    final g = await Sesion.de('gerente');
    const cliente = '88888888-8888-8888-8888-888888888881';
    final rep = await g.rpc('reporte_ventas', {'p_desde': '2026-08-01', 'p_hasta': '2026-10-31', 'p_cliente': cliente});
    final totalReporte = (rep.cuerpo['notas'] as List).fold<double>(0, (a, n) => a + (n['total'] as num));
    final notas = await g.get('notas_venta?select=total,fecha_registro,estado,pedidos!inner(cliente_id)'
        '&pedidos.cliente_id=eq.$cliente&estado=neq.anulada&fecha_registro=gte.2026-08-01&fecha_registro=lt.2026-11-01');
    final suma = (notas.cuerpo as List).fold<double>(0, (a, n) => a + (n['total'] as num));
    obtenido('CP-24', 'Reporte: Bs ${totalReporte.toStringAsFixed(2)} en ${(rep.cuerpo['notas'] as List).length} notas; suma de sus notas: Bs ${suma.toStringAsFixed(2)}');
    expect(totalReporte, closeTo(suma, 0.001));
    expect(totalReporte, greaterThan(0));
  });

  test('CP-26 RF-04 Desbloquear sin conexión con PIN incorrecto', () async {
    final op = await Sesion.de('op_sr');
    final perfil = Perfil.desdeJson(Map<String, dynamic>.from((await op.rpc('mi_perfil')).cuerpo as Map));
    // Modo avión: el desbloqueo usa solo el resumen del PIN guardado en el dispositivo.
    final pin = PinLocal(AlmacenSeguro.enMemoria());
    await pin.configurar(perfil, '4826');
    final r1 = await pin.desbloquear('1111');
    final r2 = await pin.desbloquear('2222');
    final r3 = await pin.desbloquear('3333');
    final quedaPin = await pin.tienePin(perfil.id);
    obtenido('CP-26', 'Intentos: ${r1.name}, ${r2.name}, ${r3.name}; PIN borrado del dispositivo: ${!quedaPin}; exige inicio de sesión en línea');
    expect([r1, r2], everyElement(ResultadoPin.incorrecto));
    expect(r3, ResultadoPin.exigeInicioEnLinea);
    expect(quedaPin, isFalse);
  });
}
