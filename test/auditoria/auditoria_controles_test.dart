// Pruebas de auditoría de los 11 controles internos (NIST SP 800-53 AC-5, AC-6, AU-9).
// Cada operación prohibida se intenta con la cuenta de cada rol por la API; scripts/auditoria.sh agrega la
// verificación por SQL directo cuando el Secret SUPABASE_DB_URL está disponible.
@Timeout(Duration(minutes: 3))
library;

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../apoyo/cliente_prueba.dart';

const _roles = ['admin', 'op_sr', 'ejecutivo', 'cajero', 'gerente'];
const _uuid = Uuid();

void main() {
  test('Auditoría 1 AC-5 Pesaje confirmado inmutable', () async {
    final op = await Sesion.de('op_sr');
    final p = (await op.get('pesajes?select=id,peso_bruto&estado=eq.confirmado&sede_id=eq.$sedeSanRamon&limit=1')).cuerpo as List;
    final id = p.first['id'];
    final r = <String>[];
    for (final rol in _roles) {
      final s = await Sesion.de(rol);
      final x = await s.patch('pesajes?id=eq.$id', {'peso_bruto': 99999});
      r.add('$rol: HTTP ${x.estado} ${x.codigo}');
      expect(x.estado, anyOf(401, 403), reason: '$rol $x');
    }
    final despues = ((await op.get('pesajes?select=peso_bruto&id=eq.$id')).cuerpo as List).first['peso_bruto'];
    final g = await Sesion.de('gerente');
    final bit = (await g.get('bitacora_eventos?select=id,accion&tabla=eq.pesajes&registro_id=eq.$id')).cuerpo as List;
    evidencia(1, 'UPDATE directo rechazado (${r.join('; ')}); peso sin cambios (${p.first['peso_bruto']} → $despues); '
        'bitácora del pesaje: ${bit.map((b) => '${b['accion']} N.º ${b['id']}').join(', ')} (ningún cambio registrado). '
        'La corrección solo procede por solicitud_correccion_pesaje y aprobación del gerente.');
    expect(despues, p.first['peso_bruto']);
    expect(bit.where((b) => b['accion'] == 'update'), isEmpty);
  });

  test('Auditoría 2 AC-5 Doble control registro–aprobación', () async {
    final g = await Sesion.de('gerente');
    final ins = await g.post('solicitudes_aprobacion', {
      'tipo': 'prueba_control', 'entidad': 'pruebas', 'entidad_id': _uuid.v4(), 'datos_propuestos': {'auditoria': 2},
      'motivo': 'Auditoría 2: aprobar lo propio', 'registrado_por': g.usuarioId, 'estado': 'pendiente',
    });
    // La solicitud no puede ni crearse directamente (C1 de la auditoría): quien aprueba no registra.
    final directo = await g.patch('solicitudes_aprobacion?estado=eq.pendiente', {'estado': 'aprobada', 'aprobado_por': g.usuarioId});
    evidencia(2, 'INSERT directo: $ins · UPDATE directo: $directo');
    expect(ins.estado, anyOf(401, 403));
    expect(directo.estado, anyOf(401, 403));
  });

  test('Auditoría 3 AC-5 Quien vende no cobra', () async {
    final e = await Sesion.de('ejecutivo');
    final nota = ((await e.get('notas_venta?select=id&estado=eq.emitida&saldo=gt.0&limit=1')).cuerpo as List).first['id'];
    final r = await e.rpc('registrar_cobro', {'p_nota': nota, 'p_monto': 10, 'p_metodo': 'efectivo'});
    final directo = await e.post('cobros', {'nota_venta_id': nota, 'monto': 10, 'metodo': 'efectivo', 'estado': 'vigente', 'registrado_por': e.usuarioId});
    evidencia(3, 'Función registrar_cobro: $r · INSERT directo en cobros: $directo');
    expect(r.estado, 403);
    expect(directo.estado, anyOf(401, 403));
  });

  test('Auditoría 4 AC-5 Pagos solo sobre compras aprobadas', () async {
    final c = await Sesion.de('cajero');
    final pendiente = ((await c.get('compras?select=id,saldo&estado=eq.pendiente&limit=1')).cuerpo as List).first;
    final aprobada = ((await c.get('compras?select=id,saldo&estado=eq.aprobada&limit=1')).cuerpo as List).first;
    final r1 = await c.rpc('registrar_pago', {'p_compra': pendiente['id'], 'p_monto': 100, 'p_metodo': 'qr'});
    final r2 = await c.rpc('registrar_pago', {'p_compra': aprobada['id'], 'p_monto': (aprobada['saldo'] as num) + 1, 'p_metodo': 'qr'});
    evidencia(4, 'Compra pendiente: $r1 · Pago sobre el saldo (${aprobada['saldo']} + 1): $r2');
    expect(r1.estado, isNot(200));
    expect(r2.estado, isNot(200));
  });

  test('Auditoría 5 AC-5 Mermas aprobadas por el gerente', () async {
    final op = await Sesion.de('op_sr');
    final ex = ((await op.get('existencias?select=id,lote_id,disponible&sede_id=eq.$sedeSanRamon&lote_id=not.is.null&disponible=gt.2&limit=1')).cuerpo as List).first;
    final r = await op.rpc('solicitar_merma', {'p_lote': ex['lote_id'], 'p_cantidad': 1, 'p_causa': 'manipuleo', 'p_descripcion': 'Auditoría 5: baja sin aprobación'});
    final directo = await op.patch('existencias?id=eq.${ex['id']}', {'disponible': (ex['disponible'] as num) - 1});
    final despues = ((await op.get('existencias?select=disponible&id=eq.${ex['id']}')).cuerpo as List).first['disponible'];
    evidencia(5, 'Solicitud de baja: estado ${r.cuerpo['estado']}; UPDATE directo: $directo; stock ${ex['disponible']} → $despues (sin cambios hasta la aprobación)');
    expect(r.cuerpo['estado'], 'pendiente');
    expect(despues, ex['disponible']);
  });

  test('Auditoría 6 AC-5 Recepción de guías por otra sede', () async {
    final op = await Sesion.de('op_sr');
    final lote = ((await op.get('existencias?select=lote_id&sede_id=eq.$sedeSanRamon&lote_id=not.is.null&disponible=gt.0&limit=1')).cuerpo as List).first['lote_id'];
    final g = await op.rpc('emitir_guia', {'p_destino': sedeSanJulian, 'p_items': [{'lote_id': lote, 'cantidad': 1}]});
    final r = await op.rpc('recibir_guia', {'p_guia': g.cuerpo['guia_id']});
    final directo = await op.patch('guias_transferencia?id=eq.${g.cuerpo['guia_id']}', {'recibido_por': op.usuarioId, 'estado': 'recibida'});
    evidencia(6, 'Emisor confirma su guía: $r · UPDATE directo: $directo');
    expect(r.codigo, '23514');
    expect(directo.estado, anyOf(401, 403));
    await (await Sesion.de('op_sj')).rpc('recibir_guia', {'p_guia': g.cuerpo['guia_id']});
  });

  test('Auditoría 7 AC-6 Sin edición directa del stock', () async {
    final r = <String>[];
    for (final rol in _roles) {
      final s = await Sesion.de(rol);
      final x = await s.patch('existencias?disponible=gte.0', {'disponible': 999});
      final y = await s.post('existencias', {'sede_id': sedeSanRamon, 'producto_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'disponible': 999, 'reservado': 0, 'en_transito': 0});
      r.add('$rol: UPDATE ${x.estado} ${x.codigo}, INSERT ${y.estado} ${y.codigo}');
      expect(x.estado, anyOf(401, 403));
      expect(y.estado, anyOf(401, 403));
    }
    evidencia(7, 'Permiso denegado: ${r.join('; ')}');
  });

  test('Auditoría 8 AC-6 Administrador sin permisos de negocio', () async {
    final a = await Sesion.de('admin');
    final notas = await a.get('notas_venta?select=id');
    final rep = await a.rpc('reporte_ventas', {'p_desde': '2026-08-01', 'p_hasta': '2026-12-31'});
    final rol = await a.rpc('editar_usuario', {
      'p_usuario': a.usuarioId, 'p_nombre': 'Carla Méndez Rojas', 'p_ci': '6543210', 'p_correo': 'admin@ensilados.demo',
      'p_rol': 'gerente_general', 'p_sede': '11111111-1111-1111-1111-111111111111',
    });
    evidencia(8, 'Consulta de ventas: ${(notas.cuerpo as List).length} filas; reporte de ventas: $rep; asignarse rol de gerente: $rol');
    expect((notas.cuerpo as List), isEmpty);
    expect(rep.estado, 403);
    expect(rol.estado, 403);
  });

  test('Auditoría 9 AC-6 Aislamiento por sede', () async {
    final op = await Sesion.de('op_sr');
    final otra = await op.get('existencias?select=id&sede_id=eq.$sedeSanJulian');
    final pes = await op.get('pesajes?select=id&sede_id=eq.$sedeSanRafael');
    final propia = await op.get('existencias?select=id&sede_id=eq.$sedeSanRamon');
    evidencia(9, 'Operador de San Ramón: stock de San Julián ${(otra.cuerpo as List).length} filas; pesajes de San Rafael '
        '${(pes.cuerpo as List).length} filas; su propio stock ${(propia.cuerpo as List).length} filas');
    expect(otra.cuerpo, isEmpty);
    expect(pes.cuerpo, isEmpty);
    expect((propia.cuerpo as List), isNotEmpty);
  });

  test('Auditoría 10 AU-9 Bitácora inalterable', () async {
    final r = <String>[];
    for (final rol in _roles) {
      final s = await Sesion.de(rol);
      final u = await s.patch('bitacora_eventos?id=gt.0', {'accion': 'borrado'});
      final d = await s.delete('bitacora_eventos?id=gt.0');
      r.add('$rol: UPDATE ${u.estado}, DELETE ${d.estado}');
      expect(u.estado, anyOf(401, 403));
      expect(d.estado, anyOf(401, 403));
    }
    evidencia(10, 'Operación rechazada: ${r.join('; ')}');
  });

  test('Auditoría 11 AC-5 Registros sin conexión validados', () async {
    final op = await Sesion.de('op_sr');
    final base = {
      'sede_id': sedeSanRamon, 'origen': 'propio', 'grano_id': 1, 'placa': 'OFF-1111', 'humedad': 14, 'impurezas': 1,
      'estado': 'confirmado', 'fecha_dispositivo': DateTime.now().toUtc().toIso8601String(), 'registrado_por': op.usuarioId,
    };
    final r1 = await op.upsertIgnorar('pesajes', {...base, 'id': _uuid.v4(), 'peso_bruto': 10000, 'tara': 12000});
    final r2 = await op.upsertIgnorar('pesajes', {...base, 'id': _uuid.v4(), 'sede_id': sedeSanJulian, 'peso_bruto': 30000, 'tara': 12000});
    evidencia(11, 'Pesaje sin conexión con tara mayor que el bruto: $r1 · pesaje de otra sede: $r2. '
        'La app marca el registro como «rechazado» con el motivo y lo devuelve al operador.');
    expect(r1.estado, 400);
    expect(r1.codigo, '23514');
    expect(r2.estado, anyOf(401, 403));
  });
}
