import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/errores/errores.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/cola_sincronizacion.dart';
import '../data/repositorio_operaciones_supabase.dart';
import '../domain/calculos_operaciones.dart';

final pesajesProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  ref.watch(pendientesSincronizarProvider);
  final repo = ref.watch(repositorioOperacionesProvider);
  return consultarConCopiaLocal(ref, 'pesajes', remoto: () => repo.pesajes(), local: filasDeCopia);
});

/// RF-07 Recepción y báscula: pesaje en 3 pasos con botones grandes y registros pendientes de sincronizar.
class BasculaPagina extends ConsumerStatefulWidget {
  const BasculaPagina({super.key});
  @override
  ConsumerState<BasculaPagina> createState() => _BasculaPaginaState();
}

class _BasculaPaginaState extends ConsumerState<BasculaPagina> {
  int _paso = 0;
  String _origen = 'propio';
  String? _productor;
  int? _grano;
  String? _orden;
  final _placa = TextEditingController();
  final _bruto = TextEditingController();
  final _tara = TextEditingController();
  final _humedad = TextEditingController(text: '14');
  final _impurezas = TextEditingController(text: '1');
  String? _error;
  bool _pidioDatos = false;

  double? _n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));

  void _reiniciar() => setState(() {
        _paso = 0;
        _placa.clear();
        _bruto.clear();
        _tara.clear();
        _humedad.text = '14';
        _impurezas.text = '1';
        _error = null;
      });

  String? _validarPaso() {
    if (_paso == 0) {
      if (_grano == null) return 'Elija el grano.';
      if (_origen == 'productor' && _productor == null) return 'Elija el productor.';
      if (!RegExp(r'^[0-9A-Za-z-]{4,10}$').hasMatch(_placa.text.trim())) return 'Escriba la placa del camión (4 a 10 caracteres).';
    }
    if (_paso == 1) {
      try {
        pesoNeto(_n(_bruto) ?? 0, _n(_tara) ?? 0);
      } on PesajeInvalido catch (e) {
        return e.mensaje;
      }
    }
    if (_paso == 2) {
      final h = _n(_humedad);
      final i = _n(_impurezas);
      if (h == null || h < 0 || h >= 100) return 'La humedad debe estar entre 0 y 100 %.';
      if (i == null || i < 0 || i >= 100) return 'Las impurezas deben estar entre 0 y 100 %.';
    }
    return null;
  }

  Future<void> _guardar(double humedadEstandar) async {
    final perfil = ref.read(perfilProvider)!;
    final datos = {
      'sede_id': perfil.sedeId,
      'origen': _origen,
      'proveedor_id': _origen == 'productor' ? _productor : null,
      'grano_id': _grano,
      'placa': _placa.text.trim().toUpperCase(),
      'peso_bruto': _n(_bruto),
      'tara': _n(_tara),
      'humedad': _n(_humedad),
      'impurezas': _n(_impurezas),
      'orden_id': _orden,
      'estado': 'confirmado',
      'fecha_dispositivo': DateTime.now().toUtc().toIso8601String(),
      'registrado_por': perfil.id,
    };
    await ref.read(colaProvider.notifier).registrar('pesajes', datos);
    if (!mounted) return;
    final enLinea = ref.read(enLineaProvider);
    avisar(context, enLinea ? 'Pesaje confirmado y enviado.' : 'Pesaje guardado en el teléfono: se enviará al recuperar la señal.');
    _reiniciar();
    ref.invalidate(pesajesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.registrarPesaje.permitida(perfil.rol);
    final datos = ref.watch(datosOperadorProvider);
    final cola = ref.watch(colaProvider);
    final pendientes = cola.where((r) => !r.rechazado).toList();
    final rechazados = cola.where((r) => r.rechazado).toList();
    if (operador && datos['granos'] == null && !_pidioDatos) {
      _pidioDatos = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(datosOperadorProvider.notifier).refrescar());
    }
    final granosRaw = ((datos['granos'] as List?) ?? const []).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final granos = granosRaw.isEmpty ? granosPredeterminados : granosRaw;
    final productores = ((datos['productores'] as List?) ?? const []).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final ordenes = ((datos['ordenes'] as List?) ?? const []).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final granoSel = granos.where((g) => g['id'] == _grano).firstOrNull;
    final estandar = aNumero(granoSel?['humedad_estandar'] ?? 14);
    final ordenesGrano = ordenes.where((o) => o['grano_id'] == _grano).toList();
    if (_orden != null && !ordenesGrano.any((o) => o['id'] == _orden)) _orden = null;

    return Pagina(
      etiquetaRf: 'Operaciones y Procesamiento · RF-07',
      titulo: 'Recepción y báscula',
      subtitulo: operador
          ? 'Registre el pesaje en 3 pasos. El peso ajustado por humedad lo calcula el servidor; un pesaje confirmado no se edita.'
          : 'Consulta de pesajes (el registro lo hace el operador del centro).',
      acciones: [
        if (operador)
          FilledButton.tonalIcon(
            onPressed: () async {
              await ref.read(colaProvider.notifier).sincronizar();
              await ref.read(datosOperadorProvider.notifier).refrescar();
              ref.invalidate(pesajesProvider);
            },
            icon: const Icon(Icons.sync),
            label: Text('Sincronizar (${pendientes.length})'),
          ),
      ],
      alRefrescar: () async => ref.invalidate(pesajesProvider),
      hijos: [
        if (operador) ...[
          FilaTarjetas([
            TarjetaDato(
              titulo: 'Pendientes de sincronizar',
              valor: '${pendientes.length}',
              icono: Icons.cloud_upload_outlined,
              color: pendientes.isEmpty ? context.paleta.exito : context.paleta.alerta,
              detalle: ref.watch(enLineaProvider) ? 'Con señal' : 'Sin señal: se guardan en el teléfono',
            ),
            TarjetaDato(titulo: 'Rechazados por el servidor', valor: '${rechazados.length}', icono: Icons.report_problem_outlined,
                color: rechazados.isEmpty ? context.paleta.exito : context.paleta.peligro),
          ]),
          for (final r in rechazados)
            Card(
              child: ListTile(
                leading: Icon(Icons.report_problem_outlined, color: context.paleta.peligro),
                title: Text(r.descripcion),
                subtitle: Text('${r.motivo ?? 'Rechazado por el servidor'}. Corrija el dato y reintente, o descártelo y '
                    'vuelva a registrarlo.'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Reintentar el envío',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.read(colaProvider.notifier).reintentar(r.id),
                  ),
                  IconButton(
                    tooltip: 'Descartar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref.read(colaProvider.notifier).descartar(r.id),
                  ),
                ]),
              ),
            ),
          for (final r in pendientes.where((x) => x.ultimoError != null))
            Aviso('${r.descripcion}: sigue guardado en el teléfono (${r.intentos} intentos). ${r.ultimoError}', tipo: 'alerta'),
          if (granos.isEmpty) const Aviso('Conéctese una vez para descargar los granos, productores y órdenes de su centro.', tipo: 'alerta'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Pasos(paso: _paso),
                const SizedBox(height: 20),
                if (_paso == 0) ...[
                  const Text('Origen del grano', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _BotonGrande('Cosecha propia', Icons.agriculture, _origen == 'propio', () => setState(() => _origen = 'propio'))),
                    const SizedBox(width: 10),
                    Expanded(child: _BotonGrande('Productor', Icons.person_pin_circle_outlined, _origen == 'productor', () => setState(() => _origen = 'productor'))),
                  ]),
                  if (_origen == 'productor') ...[
                    const SizedBox(height: 12),
                    Selector(etiqueta: 'Productor', opciones: productores, valor: _productor, texto: (p) => '${p['razon_social']}',
                        alCambiar: (v) => setState(() => _productor = v)),
                  ],
                  const SizedBox(height: 16),
                  const Text('Grano', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (final g in granos) ...[
                      Expanded(child: _BotonGrande('${g['nombre']}', null, _grano == g['id'], () => setState(() => _grano = g['id'] as int))),
                      if (g != granos.last) const SizedBox(width: 10),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _placa,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 22, letterSpacing: 2),
                    decoration: const InputDecoration(labelText: 'Placa del camión', prefixIcon: Icon(Icons.local_shipping_outlined)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _orden,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Orden de ensilado abierta (opcional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sin orden (solo acopio)')),
                      for (final o in ordenesGrano)
                        DropdownMenuItem<String?>(value: o['id'] as String, child: Text('Orden del ${fecha(o['fecha_apertura'])} · ${o['grano'] ?? ''}')),
                    ],
                    onChanged: (v) => setState(() => _orden = v),
                  ),
                ],
                if (_paso == 1) ...[
                  _CampoPeso('Peso bruto (camión cargado)', _bruto, () => setState(() {})),
                  const SizedBox(height: 14),
                  _CampoPeso('Tara (camión vacío)', _tara, () => setState(() {})),
                  const SizedBox(height: 14),
                  Builder(builder: (_) {
                    try {
                      final neto = pesoNeto(_n(_bruto) ?? 0, _n(_tara) ?? 0);
                      return Aviso('Peso neto: ${kg(neto)}', tipo: 'ok', icono: Icons.scale);
                    } on PesajeInvalido catch (e) {
                      return (_bruto.text.isEmpty || _tara.text.isEmpty) ? const SizedBox.shrink() : Aviso(e.mensaje, tipo: 'alerta');
                    }
                  }),
                ],
                if (_paso == 2) ...[
                  Row(children: [
                    Expanded(child: _CampoPeso('Humedad (%)', _humedad, () => setState(() {}), decimales: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _CampoPeso('Impurezas (%)', _impurezas, () => setState(() {}), decimales: true)),
                  ]),
                  const SizedBox(height: 14),
                  Builder(builder: (_) {
                    try {
                      final neto = pesoNeto(_n(_bruto)!, _n(_tara)!);
                      final aj = pesoAjustadoPorHumedad(neto, _n(_humedad) ?? 0, estandar);
                      return Card(
                        color: context.paleta.primarioClaro.withValues(alpha: .35),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Placa ${_placa.text.toUpperCase()} · ${granoSel?['nombre'] ?? ''} · ${etiqueta(_origen)}'),
                            const SizedBox(height: 6),
                            Text('Neto ${kg(neto)}  →  ajustado por humedad ${kg(aj)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            Text('Fórmula: neto × (100 − ${dec1(_n(_humedad))}) ÷ (100 − ${dec1(estandar)})',
                                style: TextStyle(color: context.paleta.textoSuave, fontSize: 12)),
                          ]),
                        ),
                      );
                    } catch (_) {
                      return const SizedBox.shrink();
                    }
                  }),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Aviso(_error!, tipo: 'error')),
                const SizedBox(height: 20),
                Row(children: [
                  if (_paso > 0)
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 60), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: () => setState(() {
                          _paso--;
                          _error = null;
                        }),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Atrás', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  if (_paso > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 60), padding: const EdgeInsets.symmetric(horizontal: 12)),
                      onPressed: () async {
                        final e = _validarPaso();
                        setState(() => _error = e);
                        if (e != null) return;
                        if (_paso < 2) {
                          setState(() => _paso++);
                        } else {
                          await _guardar(estandar);
                        }
                      },
                      icon: Icon(_paso < 2 ? Icons.arrow_forward : Icons.check_circle),
                      label: Text(_paso < 2 ? 'Siguiente' : 'Confirmar pesaje', style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          if (pendientes.isNotEmpty)
            Seccion(
              titulo: 'En el teléfono, esperando señal',
              icono: Icons.phone_android,
              hijo: Column(children: [
                for (final r in pendientes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule, color: context.paleta.alerta),
                    title: Text(r.descripcion),
                    subtitle: Text('Hora del dispositivo: ${fechaHora(r.creado.toIso8601String())} · id ${r.id.substring(0, 8)}'),
                  ),
              ]),
            ),
        ],
        Asincrono(ref.watch(pesajesProvider),
            alReintentar: () => ref.invalidate(pesajesProvider),
            datos: (l) => TablaDatos(
                  titulo: 'Pesajes registrados',
                  filas: l,
                  columnas: [
                    Columna('Fecha', (p) => fechaHora(p['fecha_dispositivo'])),
                    if (!operador) Columna('Centro', (p) => '${p['sedes']?['nombre'] ?? ''}'),
                    Columna('Placa', (p) => '${p['placa']}'),
                    Columna('Grano', (p) => '${p['granos']?['nombre'] ?? ''}'),
                    Columna('Origen', (p) => etiqueta(p['origen'])),
                    Columna('Neto', (p) => kg(p['peso_neto']), numerica: true),
                    Columna('Humedad', (p) => '${dec1(p['humedad'])} %', numerica: true),
                    Columna('Ajustado', (p) => kg(p['peso_ajustado']), numerica: true),
                    Columna('Estado', (p) => etiqueta(p['estado']), celda: (p) => Estado(p['estado'])),
                  ],
                  acciones: operador
                      ? (p) => [
                            if (p['estado'] == 'confirmado')
                              TextButton(onPressed: () => _correccion(context, p), child: const Text('Pedir corrección')),
                          ]
                      : null,
                )),
      ],
    );
  }

  Future<void> _correccion(BuildContext context, Fila p) async {
    final b = TextEditingController(text: '${p['peso_bruto']}');
    final t = TextEditingController(text: '${p['tara']}');
    final h = TextEditingController(text: '${p['humedad']}');
    final i = TextEditingController(text: '${p['impurezas']}');
    final m = TextEditingController();
    double n(TextEditingController c) => aNumero(c.text.replaceAll(',', '.'));
    await dialogoFormulario<bool>(
      context,
      titulo: 'Solicitar corrección de pesaje',
      guardar: 'Enviar al gerente',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Aviso('El pesaje confirmado no se modifica: el gerente revisa y aprueba la corrección con su motivo.', tipo: 'alerta'),
        TextField(controller: b, decoration: const InputDecoration(labelText: 'Peso bruto correcto (kg)')),
        const SizedBox(height: 10),
        TextField(controller: t, decoration: const InputDecoration(labelText: 'Tara correcta (kg)')),
        const SizedBox(height: 10),
        TextField(controller: h, decoration: const InputDecoration(labelText: 'Humedad (%)')),
        const SizedBox(height: 10),
        TextField(controller: i, decoration: const InputDecoration(labelText: 'Impurezas (%)')),
        const SizedBox(height: 10),
        TextField(controller: m, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        if (!ref.read(enLineaProvider)) {
          await ref.read(colaProvider.notifier).registrar('solicitar_correccion_pesaje', {
            'pesaje_id': p['id'],
            'peso_bruto': n(b),
            'tara': n(t),
            'humedad': n(h),
            'impurezas': n(i),
            'motivo': m.text.trim(),
          });
          return true;
        }
        try {
          await ref.read(repositorioOperacionesProvider).solicitarCorreccion(p['id'], n(b), n(t), n(h), n(i), m.text);
        } on ErrorNegocio catch (e) {
          if (e.codigo != 'red') rethrow;
          await ref.read(colaProvider.notifier).registrar('solicitar_correccion_pesaje', {
            'pesaje_id': p['id'],
            'peso_bruto': n(b),
            'tara': n(t),
            'humedad': n(h),
            'impurezas': n(i),
            'motivo': m.text.trim(),
          });
        }
        return true;
      }, exito: ref.read(enLineaProvider)
          ? 'Corrección enviada a la bandeja del gerente.'
          : 'Corrección guardada en el teléfono: se enviará al recuperar la señal.'),
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.paso});
  final int paso;
  @override
  Widget build(BuildContext context) {
    const nombres = ['Camión y grano', 'Pesos', 'Calidad y confirmación'];
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        CircleAvatar(
          radius: 16,
          backgroundColor: i <= paso ? context.paleta.primario : context.paleta.borde,
          child: i < paso
              ? Icon(Icons.check, size: 16, color: context.paleta.sobrePrimario)
              : Text('${i + 1}', style: TextStyle(color: i <= paso ? context.paleta.sobrePrimario : context.paleta.textoSuave)),
        ),
        const SizedBox(width: 6),
        if (esAncho(context) || i == paso) Flexible(
          child: Text(nombres[i],
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: i == paso ? FontWeight.w700 : FontWeight.w400, color: i <= paso ? context.paleta.texto : context.paleta.textoSuave)),
        ),
        if (i < 2) const Expanded(child: Divider(indent: 8, endIndent: 8)),
      ],
    ]);
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande(this.texto, this.icono, this.activo, this.alTocar);
  final String texto;
  final IconData? icono;
  final bool activo;
  final VoidCallback alTocar;
  @override
  Widget build(BuildContext context) {
    final etiqueta = FittedBox(fit: BoxFit.scaleDown, child: Text(texto, style: const TextStyle(fontSize: 16)));
    final estilo = const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)));
    return SizedBox(
      height: 72,
      child: activo
          ? (icono == null
              ? FilledButton(style: estilo, onPressed: alTocar, child: etiqueta)
              : FilledButton.icon(style: estilo, onPressed: alTocar, icon: Icon(icono), label: etiqueta))
          : (icono == null
              ? OutlinedButton(style: estilo, onPressed: alTocar, child: etiqueta)
              : OutlinedButton.icon(style: estilo, onPressed: alTocar, icon: Icon(icono), label: etiqueta)),
    );
  }
}

class _CampoPeso extends StatelessWidget {
  const _CampoPeso(this.etiqueta, this.ctrl, this.alCambiar, {this.decimales = false});
  final String etiqueta;
  final TextEditingController ctrl;
  final VoidCallback alCambiar;
  final bool decimales;
  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        decoration: InputDecoration(labelText: etiqueta, suffixText: decimales ? '%' : 'kg'),
        onChanged: (_) => alCambiar(),
      );
}
