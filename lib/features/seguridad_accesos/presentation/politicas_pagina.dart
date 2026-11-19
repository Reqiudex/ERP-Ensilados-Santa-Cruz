import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/reglas_seguridad.dart';
import 'medidor_clave.dart';

final parametrosProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(repositorioSeguridadProvider).parametros());

/// RF-03 Políticas de contraseñas (administrador).
class PoliticasPagina extends ConsumerStatefulWidget {
  const PoliticasPagina({super.key});
  @override
  ConsumerState<PoliticasPagina> createState() => _PoliticasPaginaState();
}

class _PoliticasPaginaState extends ConsumerState<PoliticasPagina> {
  Map<String, dynamic>? _v;
  final _prueba = TextEditingController();

  static const _numericos = {
    'clave_longitud_min': 'Longitud mínima',
    'clave_vigencia_dias': 'Vigencia (días)',
    'intentos_max': 'Intentos fallidos antes de bloquear',
    'bloqueo_minutos': 'Minutos de bloqueo',
    'inactividad_minutos': 'Cierre por inactividad (minutos)',
  };
  static const _booleanos = {
    'clave_mayusculas': 'Exigir mayúsculas',
    'clave_minusculas': 'Exigir minúsculas',
    'clave_numeros': 'Exigir números',
    'clave_simbolos': 'Exigir símbolos',
  };

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(parametrosProvider);
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-03',
      titulo: 'Políticas de contraseñas',
      subtitulo: 'Se aplican en el alta de usuarios, el cambio de contraseña y el restablecimiento; el servidor las vuelve a validar.',
      hijos: [
        Asincrono(p, datos: (todo) {
          _v ??= {for (final e in todo.entries) e.key: (e.value as Map)['valor']};
          final pol = PoliticaClave.desdeParametros(_v!);
          return Wrap(spacing: 20, runSpacing: 20, children: [
            SizedBox(
              width: esAncho(context) ? 520 : double.infinity,
              child: Seccion(
                titulo: 'Parámetros',
                icono: Icons.tune,
                hijo: Column(children: [
                  for (final e in _numericos.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        initialValue: '${_v![e.key]}',
                        decoration: InputDecoration(labelText: e.value),
                        keyboardType: TextInputType.number,
                        onChanged: (t) => _v![e.key] = int.tryParse(t) ?? _v![e.key],
                      ),
                    ),
                  for (final e in _booleanos.entries)
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
                      onPressed: () async {
                        await ejecutar(context, () async {
                          await ref.read(repositorioSeguridadProvider).guardarParametros({
                            for (final k in [..._numericos.keys, ..._booleanos.keys]) k: _v![k],
                          });
                          return true;
                        }, exito: 'Política guardada y registrada en la bitácora.');
                        ref.invalidate(parametrosProvider);
                      },
                    ),
                  ),
                ]),
              ),
            ),
            SizedBox(
              width: esAncho(context) ? 420 : double.infinity,
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
                  const Aviso('Supabase Auth también exige longitud mínima de 8 caracteres. Las contraseñas se guardan con bcrypt; '
                      'nunca se muestran ni se registran en la bitácora.'),
                ]),
              ),
            ),
          ]);
        }),
      ],
    );
  }
}
