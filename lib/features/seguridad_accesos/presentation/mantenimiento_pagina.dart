import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/exportar/guardar_en_ruta.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/roles_y_permisos.dart';
import 'confirmar_clave.dart';
import 'politicas_pagina.dart';
import 'sesion.dart';

final respaldosProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).respaldos());
final githubProvider = FutureProvider.autoDispose<Fila>((ref) => ref.watch(repositorioSeguridadProvider).estadoGithub());
final mantenimientoProvider = FutureProvider.autoDispose<Fila>((ref) => ref.watch(repositorioSeguridadProvider).estadoMantenimiento());

/// RF-06 Mantenimiento y operaciones de la base de datos: copias de respaldo (en la PC y en GitHub), programación,
/// restauración aprobada por el gerente y mantenimiento automático.
class MantenimientoPagina extends ConsumerWidget {
  const MantenimientoPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = Accion.pedirRespaldo.permitida(ref.watch(perfilProvider)?.rol);
    final lat = ref.watch(latenciaProvider);
    final resp = ref.watch(respaldosProvider);
    final mant = ref.watch(mantenimientoProvider);
    final repo = ref.read(repositorioSeguridadProvider);
    final ultimo = resp.value?.where((r) => r['accion'] == 'respaldo').firstOrNull;
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-06',
      titulo: 'Mantenimiento y operaciones de la base de datos',
      subtitulo: 'Copias de respaldo en su PC y en su cuenta de GitHub, programación automática y restauración con aprobación del gerente.',
      alRefrescar: () async {
        ref.invalidate(respaldosProvider);
        ref.invalidate(latenciaProvider);
        ref.invalidate(githubProvider);
        ref.invalidate(mantenimientoProvider);
      },
      hijos: [
        FilaTarjetas([
          lat.when(
            data: (l) => TarjetaDato(
              titulo: 'Conexión con Supabase',
              valor: l.ok ? '${l.ms} ms' : 'Sin conexión',
              icono: l.ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: !l.ok ? Colores.peligro : l.ms <= 2000 ? Colores.exito : Colores.alerta,
              detalle: l.ok ? 'PostgreSQL ${l.version.split(' ').first} · ${fechaHora(l.hora)}' : 'Reintente en unos segundos',
              alTocar: () => ref.invalidate(latenciaProvider),
            ),
            loading: () => const TarjetaDato(titulo: 'Conexión con Supabase', valor: 'Midiendo…', icono: Icons.speed),
            error: (_, _) => const TarjetaDato(titulo: 'Conexión con Supabase', valor: 'Error', icono: Icons.error_outline),
          ),
          TarjetaDato(
            titulo: 'Último respaldo',
            valor: ultimo == null ? '—' : fecha(ultimo['fecha']),
            icono: Icons.inventory_2_outlined,
            color: Colores.ambarOscuro,
            detalle: ultimo == null ? 'Aún no hay respaldos' : '${fechaHora(ultimo['fecha'])} · ${_destino(ultimo['datos'])}',
          ),
          TarjetaDato(
            titulo: 'Mantenimiento automático',
            valor: mant.value?['ultima'] == null ? 'Pendiente' : fecha(mant.value!['ultima']),
            icono: Icons.auto_fix_high_outlined,
            color: Colores.exito,
            detalle: '${mant.value?['ultima'] == null ? '' : 'Última: ${fechaHora(mant.value!['ultima'])} · '}'
                '${mant.value?['programacion'] ?? 'Todos los días a las 04:00 (Bolivia)'}',
          ),
        ]),
        if (admin) ...[
          const _RespaldoLocal(),
          const _RespaldoGithub(),
          const _ProgramacionRespaldos(),
        ],
        Asincrono(resp,
            datos: (l) => TablaDatos(
                  titulo: 'Historial de respaldos y mantenimiento',
                  filas: l,
                  columnas: [
                    Columna('Fecha', (r) => fechaHora(r['fecha'])),
                    Columna('Evento', (r) => switch (r['accion']) {
                          'respaldo' => 'Respaldo generado',
                          'respaldo_fallido' => 'Respaldo fallido',
                          'respaldo_pedido' => 'Respaldo manual pedido',
                          'restauracion' => 'Restauración aprobada',
                          'optimizacion' => r['datos']?['automatico'] == true ? 'Mantenimiento automático' : 'Mantenimiento manual',
                          'github_vinculado' => 'GitHub vinculado',
                          'github_desvinculado' => 'GitHub desvinculado',
                          _ => '${r['accion']}',
                        }),
                    Columna('Destino', (r) => _destino(r['datos'])),
                    Columna('Archivo', (r) => '${r['datos']?['archivo'] ?? r['datos']?['respaldo'] ?? r['datos']?['repositorio'] ?? '—'}', ancho: 260),
                    Columna('Tamaño', (r) => r['datos']?['bytes'] == null ? '—' : '${dec2(aNumero(r['datos']['bytes']) / 1048576)} MB'),
                    Columna('SHA-256 / detalle', (r) => '${r['datos']?['sha256'] ?? r['datos']?['error'] ?? r['datos']?['estado'] ?? (r['datos']?['tablas'] != null ? '${r['datos']['tablas']} tablas' : '—')}',
                        ancho: 300),
                  ],
                  acciones: admin
                      ? (r) => [
                            if (r['accion'] == 'respaldo')
                              TextButton.icon(
                                icon: const Icon(Icons.restore, size: 18),
                                label: const Text('Solicitar restauración'),
                                onPressed: () async {
                                  final m = await pedirTexto(context, 'Solicitar restauración', etiqueta: 'Motivo (lo revisa el gerente)', minimo: 10);
                                  if (m == null || !context.mounted) return;
                                  await ejecutar(context, () async {
                                    await repo.solicitarRestauracion('${r['datos']?['archivo'] ?? r['id']}', m);
                                    return true;
                                  }, exito: 'Solicitud enviada: queda pendiente del gerente.');
                                },
                              ),
                          ]
                      : null,
                )),
        if (admin)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Ejecutar el mantenimiento ahora'),
              onPressed: () async {
                final n = await ejecutar(context, repo.optimizarBase);
                if (n != null && context.mounted) avisar(context, 'Estadísticas e índices actualizados en $n tablas.');
                ref.invalidate(respaldosProvider);
                ref.invalidate(mantenimientoProvider);
              },
            ),
          ),
      ],
    );
  }

  static String _destino(dynamic d) => switch (d is Map ? d['destino'] : null) {
        'local' => 'PC del administrador',
        'github' => 'GitHub',
        _ => d is Map && d['repositorio'] != null ? 'GitHub' : 'GitHub Actions (pg_dump)',
      };
}

/// Copia en la PC: el administrador elige la carpeta (por ejemplo C:\Documentos\Respaldos) y el nombre del archivo.
class _RespaldoLocal extends ConsumerStatefulWidget {
  const _RespaldoLocal();
  @override
  ConsumerState<_RespaldoLocal> createState() => _RespaldoLocalState();
}

class _RespaldoLocalState extends ConsumerState<_RespaldoLocal> {
  bool _trabajando = false;
  String? _ultimo;

  Future<void> _guardar() async {
    setState(() => _trabajando = true);
    try {
      final datos = await ref.read(repositorioSeguridadProvider).exportarRespaldo();
      final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(datos)));
      final ahora = DateTime.now();
      String dos(int n) => n.toString().padLeft(2, '0');
      final nombre = 'respaldo_ensilados_${ahora.year}-${dos(ahora.month)}-${dos(ahora.day)}_${dos(ahora.hour)}${dos(ahora.minute)}';
      final (r, ruta) = await guardarEnRuta(nombre, bytes);
      if (!mounted) return;
      switch (r) {
        case ResultadoGuardado.guardado:
          setState(() => _ultimo = ruta ?? '$nombre.json');
          avisar(context, 'Respaldo guardado: ${ruta ?? '$nombre.json'} (${dec2(bytes.length / 1048576)} MB).');
        case ResultadoGuardado.descargado:
          setState(() => _ultimo = '$nombre.json');
          avisar(context, 'Su navegador no permite elegir la carpeta: el respaldo se descargó en «Descargas».');
        case ResultadoGuardado.cancelado:
          avisar(context, 'Guardado cancelado.');
      }
      ref.invalidate(respaldosProvider);
    } catch (e) {
      if (mounted) avisar(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Seccion(
        titulo: 'Copia de respaldo en esta PC',
        icono: Icons.computer_outlined,
        hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Genera una copia completa de los datos (todas las tablas y los parámetros) en formato JSON y le pide '
              'elegir la carpeta donde guardarla, por ejemplo C:\\Documentos\\Respaldos. En Chrome y Edge se abre el '
              'diálogo «Guardar como»; en otros navegadores se guarda en «Descargas».'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              icon: _trabajando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_alt_outlined),
              label: const Text('Guardar respaldo en mi PC…'),
              onPressed: _trabajando ? null : _guardar,
            ),
            if (_ultimo != null) Text('Último guardado: $_ultimo', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
      );
}

/// Copia externa en un repositorio de GitHub del administrador (otra cuenta u organización).
class _RespaldoGithub extends ConsumerStatefulWidget {
  const _RespaldoGithub();
  @override
  ConsumerState<_RespaldoGithub> createState() => _RespaldoGithubState();
}

class _RespaldoGithubState extends ConsumerState<_RespaldoGithub> {
  bool _enviando = false;

  Future<void> _vincular() async {
    final repo = TextEditingController();
    final token = TextEditingController();
    final rama = TextEditingController(text: 'main');
    String? error;
    var verificando = false;
    final vinculo = await showDialog<(String, String, String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        Future<void> verificar() async {
          final r = repo.text.trim(), t = token.text.trim();
          if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(r)) {
            set(() => error = 'Escriba el repositorio como usuario/repositorio.');
            return;
          }
          set(() {
            verificando = true;
            error = null;
          });
          try {
            final h = {'Authorization': 'Bearer $t', 'Accept': 'application/vnd.github+json'};
            final u = await http.get(Uri.parse('https://api.github.com/user'), headers: h).timeout(const Duration(seconds: 15));
            if (u.statusCode != 200) throw 'GitHub rechazó el token (código ${u.statusCode}).';
            final cuenta = (jsonDecode(u.body) as Map)['login'] as String;
            final rp = await http.get(Uri.parse('https://api.github.com/repos/$r'), headers: h).timeout(const Duration(seconds: 15));
            if (rp.statusCode != 200) throw 'El token no tiene acceso al repositorio $r (código ${rp.statusCode}).';
            final permisos = (jsonDecode(rp.body) as Map)['permissions'] as Map?;
            if (permisos != null && permisos['push'] != true) throw 'El token puede leer $r pero no escribir en él.';
            if (c.mounted) Navigator.pop(c, (r, cuenta, t, rama.text.trim().isEmpty ? 'main' : rama.text.trim()));
          } catch (e) {
            set(() {
              verificando = false;
              error = '$e';
            });
          }
        }

        return AlertDialog(
          icon: const Icon(Icons.link),
          title: const Text('Vincular cuenta de GitHub'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('1. Cree (o elija) un repositorio privado en su cuenta, por ejemplo respaldos-ensilados.\n'
                    '2. Cree un token de acceso «fine-grained» con permiso Contents: Read and write solo para ese repositorio.\n'
                    '3. Péguelo aquí. Se guarda cifrado en el servidor (Vault) y nunca vuelve a mostrarse.'),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Crear token en GitHub'),
                  onPressed: () => launchUrl(Uri.parse('https://github.com/settings/personal-access-tokens/new')),
                ),
                const SizedBox(height: 8),
                TextField(controller: repo, decoration: const InputDecoration(labelText: 'Repositorio (usuario/repositorio)')),
                const SizedBox(height: 10),
                TextField(controller: rama, decoration: const InputDecoration(labelText: 'Rama')),
                const SizedBox(height: 10),
                TextField(
                  controller: token,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Token de acceso', errorText: error, errorMaxLines: 3),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: verificando ? null : () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(onPressed: verificando ? null : verificar, child: Text(verificando ? 'Verificando…' : 'Verificar y vincular')),
          ],
        );
      }),
    );
    repo.dispose();
    token.dispose();
    rama.dispose();
    if (vinculo == null || !mounted) return;
    final ok = await confirmarConClave(context, ref,
        titulo: 'Confirmar vínculo con GitHub', detalle: 'Los respaldos se enviarán a ${vinculo.$1} (cuenta ${vinculo.$2}). Confirme con su contraseña.');
    if (!ok || !mounted) return;
    await ejecutar(context, () async {
      await ref
          .read(repositorioSeguridadProvider)
          .vincularGithub(repositorio: vinculo.$1, cuenta: vinculo.$2, token: vinculo.$3, rama: vinculo.$4);
      return true;
    }, exito: 'Cuenta de GitHub vinculada.');
    ref.invalidate(githubProvider);
    ref.invalidate(respaldosProvider);
  }

  Future<void> _desvincular() async {
    final ok = await confirmarConClave(context, ref,
        titulo: 'Desvincular GitHub', detalle: 'Se borrará el token guardado. Las copias que ya están en GitHub no se tocan.');
    if (!ok || !mounted) return;
    await ejecutar(context, () async {
      await ref.read(repositorioSeguridadProvider).desvincularGithub();
      return true;
    }, exito: 'Cuenta de GitHub desvinculada.');
    ref.invalidate(githubProvider);
    ref.invalidate(respaldosProvider);
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final r = await ejecutar(context, ref.read(repositorioSeguridadProvider).enviarRespaldoGithub);
    if (mounted) {
      setState(() => _enviando = false);
      if (r != null) avisar(context, 'Respaldo enviado a GitHub: ${r['archivo']} (${dec2(aNumero(r['bytes']) / 1048576)} MB).');
    }
    ref.invalidate(respaldosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(githubProvider);
    return Seccion(
      titulo: 'Copia de respaldo en GitHub',
      icono: Icons.cloud_upload_outlined,
      hijo: Asincrono(g, datos: (e) {
        if (e['vinculado'] != true) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vincule una cuenta de GitHub distinta a la del sistema para guardar ahí una copia externa. '
                'Con la programación activa, la copia se envía sola cada día (o semana, o mes) a la hora elegida.'),
            const SizedBox(height: 12),
            FilledButton.icon(icon: const Icon(Icons.link), label: const Text('Vincular cuenta de GitHub'), onPressed: _vincular),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.verified_user_outlined)),
            title: Text('${e['cuenta']} · ${e['repositorio']}'),
            subtitle: Text('Rama ${e['rama']} · carpeta respaldos/ · vinculado el ${fechaHora(e['vinculado_en'])}'),
          ),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              icon: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Enviar copia ahora'),
              onPressed: _enviando ? null : _enviar,
            ),
            OutlinedButton.icon(icon: const Icon(Icons.link_off), label: const Text('Desvincular'), onPressed: _desvincular),
          ]),
        ]);
      }),
    );
  }
}

/// Programación automática de respaldos. La revisa cada hora una tarea del servidor (pg_cron) y envía la copia a
/// GitHub; el flujo «Respaldo de la base de datos» de GitHub Actions usa la misma programación para el pg_dump.
class _ProgramacionRespaldos extends ConsumerStatefulWidget {
  const _ProgramacionRespaldos();
  @override
  ConsumerState<_ProgramacionRespaldos> createState() => _ProgramacionRespaldosState();
}

class _ProgramacionRespaldosState extends ConsumerState<_ProgramacionRespaldos> {
  Map<String, dynamic>? _v;
  static const _claves = ['respaldo_activo', 'respaldo_frecuencia', 'respaldo_hora_utc', 'respaldo_retencion_dias', 'respaldo_estrategia'];

  /// Bolivia está en UTC−4 todo el año.
  static int _horaLocal(String utc) => ((int.tryParse(utc.split(':').first) ?? 7) - 4 + 24) % 24;
  static String _horaUtc(int local) => '${((local + 4) % 24).toString().padLeft(2, '0')}:00';

  Future<void> _guardar() async {
    final ok = await confirmarConClave(context, ref,
        titulo: 'Confirmar programación de respaldos', detalle: 'Ingrese su contraseña de administrador para guardar la programación.');
    if (!ok || !mounted) return;
    await ejecutar(context, () async {
      await ref.read(repositorioSeguridadProvider).guardarParametros({for (final k in _claves) k: _v![k]});
      return true;
    }, exito: 'Programación guardada y registrada en la bitácora.');
    ref.invalidate(parametrosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(parametrosProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Asincrono(p, datos: (todo) {
        _v ??= {for (final k in _claves) k: (todo[k] as Map?)?['valor']};
        final activo = _v!['respaldo_activo'] == true;
        return Seccion(
          titulo: 'Programación automática de respaldos',
          icono: Icons.schedule_outlined,
          hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Estrategia'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'completo', label: Text('Completo (Full)'), icon: Icon(Icons.storage)),
                ButtonSegment(value: 'incremental', label: Text('Incremental'), enabled: false),
                ButtonSegment(value: 'diferencial', label: Text('Diferencial'), enabled: false),
              ],
              selected: {'${_v!['respaldo_estrategia'] ?? 'completo'}'},
              onSelectionChanged: (x) => setState(() => _v!['respaldo_estrategia'] = x.first),
            ),
            const SizedBox(height: 6),
            Text('Incremental y diferencial no están disponibles: Supabase (plan gratuito) no da acceso a los registros WAL; '
                'cada respaldo es una copia completa.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Respaldo automático en segundo plano'),
              subtitle: const Text('Envía la copia a la cuenta de GitHub vinculada a la hora elegida, sin que nadie tenga que entrar.'),
              value: activo,
              onChanged: (b) => setState(() => _v!['respaldo_activo'] = b),
            ),
            Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: '${_v!['respaldo_frecuencia'] ?? 'diaria'}',
                  decoration: const InputDecoration(labelText: 'Frecuencia'),
                  items: const [
                    DropdownMenuItem(value: 'diaria', child: Text('Diario')),
                    DropdownMenuItem(value: 'semanal', child: Text('Semanal (lunes)')),
                    DropdownMenuItem(value: 'mensual', child: Text('Mensual (día 1)')),
                  ],
                  onChanged: activo ? (x) => setState(() => _v!['respaldo_frecuencia'] = x) : null,
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  initialValue: _horaLocal('${_v!['respaldo_hora_utc'] ?? '07:00'}'),
                  decoration: const InputDecoration(labelText: 'Hora de ejecución (Bolivia)'),
                  items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                  onChanged: activo ? (x) => setState(() => _v!['respaldo_hora_utc'] = _horaUtc(x ?? 3)) : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Retención'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final d in const [7, 15, 30])
                ChoiceChip(
                  label: Text('Últimos $d días'),
                  selected: (_v!['respaldo_retencion_dias'] as num?)?.toInt() == d,
                  onSelected: (_) => setState(() => _v!['respaldo_retencion_dias'] = d),
                ),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('Guardar programación'), onPressed: _guardar),
            ),
          ]),
        );
      }),
    );
  }
}
