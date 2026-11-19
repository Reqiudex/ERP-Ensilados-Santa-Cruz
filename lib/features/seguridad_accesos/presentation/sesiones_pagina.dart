import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/roles_y_permisos.dart';
import 'confirmar_clave.dart';
import 'politicas_pagina.dart';
import 'sesion.dart';

final sesionesProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).sesionesActivas());

/// Ubicación aproximada por IP (ciudad, región, país). Se consulta una vez por IP y se guarda en memoria.
final ubicacionIpProvider = FutureProvider.family<String, String>((ref, ip) async {
  if (ip.isEmpty || ip == '—' || RegExp(r'^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|::1|fe80)').hasMatch(ip)) {
    return 'Red local';
  }
  String unir(Map<String, dynamic> j) =>
      [j['city'], j['region'], j['country']].where((x) => x != null && '$x'.isNotEmpty).join(', ');
  // Servicio principal (GeoJS) y alternativo (ipwho.is); ambos gratuitos, sin clave y con CORS.
  try {
    final r = await http.get(Uri.parse('https://get.geojs.io/v1/ip/geo/$ip.json')).timeout(const Duration(seconds: 6));
    if (r.statusCode == 200) {
      final t = unir(jsonDecode(r.body) as Map<String, dynamic>);
      if (t.isNotEmpty) return t;
    }
  } catch (_) {}
  try {
    final r = await http.get(Uri.parse('https://ipwho.is/$ip?fields=success,city,region,country')).timeout(const Duration(seconds: 6));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['success'] == true) return unir(j);
  } catch (_) {}
  return 'No disponible';
});

/// Tipo de dispositivo, sistema operativo y navegador a partir del agente de usuario.
class Dispositivo {
  const Dispositivo(this.tipo, this.icono, this.sistema, this.navegador);
  final String tipo;
  final IconData icono;
  final String sistema;
  final String navegador;

  factory Dispositivo.desdeAgente(String? agente) {
    final a = (agente ?? '').toLowerCase();
    final sistema = a.contains('android')
        ? 'Android'
        : a.contains('iphone') || a.contains('ipad')
            ? 'iOS'
            : a.contains('windows')
                ? 'Windows'
                : a.contains('mac os') || a.contains('macintosh')
                    ? 'macOS'
                    : a.contains('linux')
                        ? 'Linux'
                        : a.contains('dart')
                            ? 'Android'
                            : 'Otro';
    final navegador = a.contains('edg')
        ? 'Edge'
        : a.contains('firefox')
            ? 'Firefox'
            : a.contains('chrome')
                ? 'Chrome'
                : a.contains('dart')
                    ? 'App Android'
                    : a.contains('safari')
                        ? 'Safari'
                        : 'Otro';
    if (a.contains('ipad') || a.contains('tablet') || (a.contains('android') && !a.contains('mobile') && !a.contains('dart'))) {
      return Dispositivo('Tablet', Icons.tablet_android, sistema, navegador);
    }
    if (a.contains('mobile') || a.contains('iphone') || a.contains('dart') || sistema == 'Android') {
      return Dispositivo('Smartphone', Icons.smartphone, sistema, navegador);
    }
    if (sistema == 'macOS') return Dispositivo('Laptop', Icons.laptop_mac, sistema, navegador);
    return Dispositivo('PC', Icons.desktop_windows_outlined, sistema, navegador);
  }
}

/// RF-04 Monitoreo de sesiones activas: dispositivo, sistema, IP, ubicación aproximada y revocación inmediata.
class SesionesPagina extends ConsumerStatefulWidget {
  const SesionesPagina({super.key});
  @override
  ConsumerState<SesionesPagina> createState() => _SesionesPaginaState();
}

class _SesionesPaginaState extends ConsumerState<SesionesPagina> {
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    // Panel en tiempo real: se actualiza solo cada 15 segundos.
    _refresco = Timer.periodic(const Duration(seconds: 15), (_) => ref.invalidate(sesionesProvider));
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  Future<void> _matar(Fila f) async {
    if (!await confirmar(context, 'Matar sesión',
        'La sesión de ${f['usuario']} se revocará al instante y su dispositivo volverá a la pantalla de ingreso.',
        si: 'Matar sesión')) {
      return;
    }
    if (!mounted) return;
    await ejecutar(context, () => ref.read(repositorioSeguridadProvider).revocarSesion('${f['id']}'),
        exito: 'Sesión revocada. El usuario fue expulsado.');
    ref.invalidate(sesionesProvider);
  }

  Future<void> _cerrarTodas() async {
    final ok = await confirmarConClave(context, ref,
        titulo: 'Cerrar todas las demás sesiones', detalle: 'Se revocarán todas las sesiones excepto la suya. Confirme con su contraseña.');
    if (!ok || !mounted) return;
    final n = await ejecutar(context, () => ref.read(repositorioSeguridadProvider).cerrarSesiones(null));
    if (n != null && mounted) avisar(context, '$n sesiones cerradas.');
    ref.invalidate(sesionesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(sesionesProvider);
    final perfil = ref.watch(perfilProvider);
    final puede = Accion.cerrarSesiones.permitida(perfil?.rol);
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-04',
      titulo: 'Autenticación y sesiones',
      subtitulo: 'Validación de credenciales, cierre por inactividad, PIN sin conexión (Android) y monitoreo de las sesiones '
          'abiertas, con cierre inmediato.',
      acciones: [
        if (puede) FilledButton.icon(icon: const Icon(Icons.logout), label: const Text('Cerrar todas las demás'), onPressed: _cerrarTodas),
      ],
      alRefrescar: () async => ref.invalidate(sesionesProvider),
      hijos: [
        if (puede) const _PoliticaSesiones(),
        Asincrono(v, datos: (l) {
          if (l.isEmpty) return const MensajeVacio(titulo: 'No hay sesiones activas.');
          final tipos = <String, int>{};
          for (final f in l) {
            final t = Dispositivo.desdeAgente(f['agente'] as String?).tipo;
            tipos[t] = (tipos[t] ?? 0) + 1;
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Sesiones activas', valor: '${l.length}', icono: Icons.devices_outlined),
              TarjetaDato(titulo: 'Usuarios conectados', valor: '${l.map((f) => f['usuario_id']).toSet().length}', icono: Icons.people_alt_outlined),
              for (final e in tipos.entries) TarjetaDato(titulo: e.key, valor: '${e.value}', icono: Dispositivo(e.key, Icons.devices, '', '').iconoTipo),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final f in l) _TarjetaSesion(sesion: f, puedeMatar: puede && f['actual'] != true, alMatar: () => _matar(f)),
            ]),
          ]);
        }),
      ],
    );
  }
}

extension on Dispositivo {
  IconData get iconoTipo => switch (tipo) {
        'Smartphone' => Icons.smartphone,
        'Tablet' => Icons.tablet_android,
        'Laptop' => Icons.laptop_mac,
        _ => Icons.desktop_windows_outlined,
      };
}

class _TarjetaSesion extends ConsumerWidget {
  const _TarjetaSesion({required this.sesion, required this.puedeMatar, required this.alMatar});
  final Fila sesion;
  final bool puedeMatar;
  final VoidCallback alMatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final d = Dispositivo.desdeAgente(sesion['agente'] as String?);
    final ip = '${sesion['ip'] ?? '—'}';
    final ubicacion = ref.watch(ubicacionIpProvider(ip));
    final actual = sesion['actual'] == true;
    Widget dato(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(i, size: 16, color: tema.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(t, overflow: TextOverflow.ellipsis)),
          ]),
        );
    return SizedBox(
      width: esAncho(context) ? 360 : double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: tema.colorScheme.primaryContainer,
                foregroundColor: tema.colorScheme.onPrimaryContainer,
                child: Icon(d.icono),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${sesion['usuario']}', style: tema.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                  Text('${sesion['rol']}', style: tema.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (actual) Chip(label: const Text('Esta sesión'), visualDensity: VisualDensity.compact),
            ]),
            const SizedBox(height: 6),
            dato(d.icono, '${d.tipo} · ${d.sistema} · ${d.navegador}'),
            dato(Icons.lan_outlined, 'IP $ip'),
            dato(Icons.place_outlined, ubicacion.when(data: (u) => u, loading: () => 'Buscando ubicación…', error: (_, _) => 'No disponible')),
            dato(Icons.login, 'Inicio: ${fechaHora(sesion['inicio'])}'),
            dato(Icons.update, 'Última actividad: ${fechaHora(sesion['ultima_actividad'])}'),
            if (puedeMatar) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: tema.colorScheme.error),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Matar sesión'),
                  onPressed: alMatar,
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Política de sesiones (RF-04): inactividad, sesiones simultáneas y PIN sin conexión de Android.
class _PoliticaSesiones extends ConsumerStatefulWidget {
  const _PoliticaSesiones();
  @override
  ConsumerState<_PoliticaSesiones> createState() => _PoliticaSesionesState();
}

class _PoliticaSesionesState extends ConsumerState<_PoliticaSesiones> {
  Map<String, dynamic>? _v;
  static const _claves = ['inactividad_minutos', 'sesiones_max', 'pin_min', 'pin_max', 'pin_intentos', 'horas_sin_sincronizar'];

  int _n(String k, int d) => (_v?[k] as num?)?.toInt() ?? d;

  Future<void> _guardar() async {
    final ok = await confirmarConClave(context, ref,
        titulo: 'Confirmar política de sesiones', detalle: 'Ingrese su contraseña de administrador para aplicar los cambios.');
    if (!ok || !mounted) return;
    await ejecutar(context, () async {
      await ref.read(repositorioSeguridadProvider).guardarParametros({for (final k in _claves) k: _v![k]});
      return true;
    }, exito: 'Política de sesiones guardada y registrada en la bitácora.');
    ref.invalidate(parametrosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(parametrosProvider);
    return Asincrono(p, datos: (todo) {
      _v ??= {for (final k in _claves) k: (todo[k] as Map?)?['valor']};
      Widget campo(Widget w) => SizedBox(width: esAncho(context) ? 260 : double.infinity, child: w);
      return Seccion(
        titulo: 'Política de sesiones y PIN sin conexión',
        icono: Icons.timer_outlined,
        hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            campo(DesplegableNumero(
              etiqueta: 'Cierre por inactividad',
              valor: _n('inactividad_minutos', 15),
              opciones: const {5: '5 minutos', 10: '10 minutos', 15: '15 minutos', 30: '30 minutos'},
              alCambiar: (x) => setState(() => _v!['inactividad_minutos'] = x),
            )),
            campo(DesplegableNumero(
              etiqueta: 'Sesiones simultáneas por usuario',
              valor: _n('sesiones_max', 0),
              opciones: const {1: '1 dispositivo', 2: '2 dispositivos', 3: '3 dispositivos', 0: 'Ilimitado'},
              alCambiar: (x) => setState(() => _v!['sesiones_max'] = x),
            )),
            campo(DesplegableNumero(
              etiqueta: 'PIN: dígitos mínimos',
              valor: _n('pin_min', 4),
              opciones: const {4: '4 dígitos', 5: '5 dígitos', 6: '6 dígitos'},
              alCambiar: (x) => setState(() => _v!['pin_min'] = x),
            )),
            campo(DesplegableNumero(
              etiqueta: 'PIN: dígitos máximos',
              valor: _n('pin_max', 6),
              opciones: const {4: '4 dígitos', 5: '5 dígitos', 6: '6 dígitos'},
              alCambiar: (x) => setState(() => _v!['pin_max'] = x),
            )),
            campo(DesplegableNumero(
              etiqueta: 'PIN: intentos antes de exigir ingreso en línea',
              valor: _n('pin_intentos', 3),
              opciones: const {3: '3 intentos', 5: '5 intentos'},
              alCambiar: (x) => setState(() => _v!['pin_intentos'] = x),
            )),
            campo(DesplegableNumero(
              etiqueta: 'Horas máximas sin sincronizar (PIN)',
              valor: _n('horas_sin_sincronizar', 12),
              opciones: const {4: '4 horas', 8: '8 horas', 12: '12 horas', 24: '24 horas'},
              alCambiar: (x) => setState(() => _v!['horas_sin_sincronizar'] = x),
            )),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('Guardar política'), onPressed: _guardar),
          ),
        ]),
      );
    });
  }
}
