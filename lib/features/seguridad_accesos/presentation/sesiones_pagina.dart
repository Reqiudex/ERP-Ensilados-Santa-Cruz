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
      titulo: 'Sesiones activas',
      subtitulo: 'Monitoreo en tiempo real de las sesiones del portal y de la app. Cierre por inactividad: '
          '${perfil?.minutosInactividad ?? 15} minutos. PIN sin conexión: solo Android.',
      acciones: [
        if (puede) FilledButton.icon(icon: const Icon(Icons.logout), label: const Text('Cerrar todas las demás'), onPressed: _cerrarTodas),
      ],
      alRefrescar: () async => ref.invalidate(sesionesProvider),
      hijos: [
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
