import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/reglas_seguridad.dart';
import 'confirmar_clave.dart';
import 'medidor_clave.dart';

final parametrosProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(repositorioSeguridadProvider).parametros());

/// RF-03 Políticas de contraseñas: longitud, complejidad, vigencia y bloqueo ante intentos fallidos (administrador).
/// Inactividad, sesiones simultáneas y PIN están en RF-04 (Autenticación y sesiones). El servidor valida cada valor.
class PoliticasPagina extends ConsumerStatefulWidget {
  const PoliticasPagina({super.key});
  @override
  ConsumerState<PoliticasPagina> createState() => _PoliticasPaginaState();
}

class _PoliticasPaginaState extends ConsumerState<PoliticasPagina> {
  Map<String, dynamic>? _v;
  final _prueba = TextEditingController();
  final _bloqueo = TextEditingController();

  static const _claves = [
    'bloqueo_minutos', 'clave_longitud_min', 'clave_historial', 'intentos_max', 'clave_vigencia_dias', 'clave_mayusculas', 'clave_minusculas', 'clave_numeros', 'clave_simbolos',
  ];

  int _n(String k, int defecto) => (_v?[k] as num?)?.toInt() ?? defecto;

  @override
  void dispose() {
    _prueba.dispose();
    _bloqueo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final ok = await confirmarConClave(context, ref,
        titulo: 'Confirmar cambio de política', detalle: 'Ingrese su contraseña de administrador para aplicar la nueva política.');
    if (!ok || !mounted) return;
    await ejecutar(context, () async {
      await ref.read(repositorioSeguridadProvider).guardarParametros({for (final k in _claves) k: _v![k]});
      return true;
    }, exito: 'Política guardada y registrada en la bitácora.');
    ref.invalidate(parametrosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(parametrosProvider);
    final tema = Theme.of(context);
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-03',
      titulo: 'Políticas de contraseñas',
      subtitulo: 'Longitud, complejidad y vigencia de las claves, y bloqueo de la cuenta ante intentos fallidos. Se aplican en el alta, '
          'el cambio y el restablecimiento de contraseñas y en el ingreso; el servidor las vuelve a validar.',
      hijos: [
        Asincrono(p, datos: (todo) {
          if (_v == null) {
            _v = {for (final e in todo.entries) e.key: (e.value as Map)['valor']};
            _bloqueo.text = '${_n('bloqueo_minutos', 15)}';
          }
          final pol = PoliticaClave.desdeParametros(_v!);
          final ancho = esAncho(context);
          return Wrap(spacing: 20, runSpacing: 20, children: [
            SizedBox(
              width: ancho ? 520 : double.infinity,
              child: Column(children: [
                Seccion(
                  titulo: 'Bloqueo por intentos fallidos',
                  icono: Icons.lock_clock_outlined,
                  hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(
                      controller: _bloqueo,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Desbloqueo automático (minutos)', suffixText: 'min'),
                      onChanged: (t) => setState(() => _v!['bloqueo_minutos'] = int.tryParse(t) ?? _v!['bloqueo_minutos']),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final m in const [15, 30, 60, 120])
                        ChoiceChip(
                          label: Text('${m}m'),
                          selected: _n('bloqueo_minutos', 15) == m,
                          onSelected: (_) => setState(() {
                            _v!['bloqueo_minutos'] = m;
                            _bloqueo.text = '$m';
                          }),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    DesplegableNumero(
                      etiqueta: 'Intentos fallidos antes del bloqueo',
                      valor: _n('intentos_max', 3),
                      opciones: const {3: '3 intentos', 5: '5 intentos', 10: '10 intentos'},
                      alCambiar: (x) => setState(() => _v!['intentos_max'] = x),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                Seccion(
                  titulo: 'Reglas de complejidad',
                  icono: Icons.rule,
                  hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Longitud mínima: ${_n('clave_longitud_min', 8)} caracteres', style: tema.textTheme.titleSmall),
                    Slider(
                      value: _n('clave_longitud_min', 8).clamp(8, 16).toDouble(),
                      min: 8,
                      max: 16,
                      divisions: 8,
                      label: '${_n('clave_longitud_min', 8)}',
                      onChanged: (x) => setState(() => _v!['clave_longitud_min'] = x.round()),
                    ),
                    DesplegableNumero(
                      etiqueta: 'Historial: no reutilizar las últimas (control adicional)',
                      valor: _n('clave_historial', 3),
                      opciones: const {3: '3 contraseñas', 5: '5 contraseñas', 10: '10 contraseñas'},
                      alCambiar: (x) => setState(() => _v!['clave_historial'] = x),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: '${_n('clave_vigencia_dias', 90)}',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Vigencia de la contraseña (días)', suffixText: 'días'),
                      onChanged: (t) => _v!['clave_vigencia_dias'] = int.tryParse(t) ?? _v!['clave_vigencia_dias'],
                    ),
                    const SizedBox(height: 8),
                    for (final e in const {
                      'clave_mayusculas': 'Exigir mayúsculas',
                      'clave_minusculas': 'Exigir minúsculas',
                      'clave_numeros': 'Exigir números',
                      'clave_simbolos': 'Exigir caracteres especiales (@#\$%&*)',
                    }.entries)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        value: _v![e.key] == true,
                        onChanged: (b) => setState(() => _v![e.key] = b),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar política'),
                        onPressed: _guardar,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            SizedBox(
              width: ancho ? 420 : double.infinity,
              child: Seccion(
                titulo: 'Evaluador de contraseñas',
                icono: Icons.password,
                hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _prueba,
                    decoration: const InputDecoration(labelText: 'Pruebe una contraseña'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  MedidorClave(clave: _prueba.text, politica: pol),
                  const SizedBox(height: 16),
                  const Aviso('Las contraseñas se guardan con bcrypt (sal propia por contraseña); nunca se muestran ni se registran '
                      'en la bitácora. El historial guarda solo los hashes anteriores.'),
                ]),
              ),
            ),
          ]);
        }),
      ],
    );
  }
}

class DesplegableNumero extends StatelessWidget {
  const DesplegableNumero({super.key, required this.etiqueta, required this.valor, required this.opciones, required this.alCambiar});
  final String etiqueta;
  final int valor;
  final Map<int, String> opciones;
  final ValueChanged<int> alCambiar;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        initialValue: opciones.containsKey(valor) ? valor : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiqueta),
        items: [for (final e in opciones.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (x) => x == null ? null : alCambiar(x),
      );
}
