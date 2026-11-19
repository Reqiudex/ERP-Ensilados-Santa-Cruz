import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/operaciones_ensilado/data/cola_sincronizacion.dart';
import '../../features/seguridad_accesos/data/repositorio_seguridad_supabase.dart';
import '../../features/seguridad_accesos/domain/reglas_seguridad.dart';
import '../../features/seguridad_accesos/domain/roles_y_permisos.dart';
import '../../features/seguridad_accesos/presentation/sesion.dart';
import '../almacenamiento/almacen_local.dart';
import '../conexion/conexion.dart';
import '../tema/tema.dart';
import '../widgets/componentes.dart';
import 'menu.dart';

/// Estructura común: menú lateral (web) o cajón (Android), barra superior con sede, conexión y
/// registros pendientes, y cierre de sesión por inactividad.
class Estructura extends ConsumerStatefulWidget {
  const Estructura({super.key, required this.hijo, required this.ruta});
  final Widget hijo;
  final String ruta;

  @override
  ConsumerState<Estructura> createState() => _EstructuraState();
}

class _EstructuraState extends ConsumerState<Estructura> {
  DateTime _ultimaActividad = DateTime.now();
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) => _revisarInactividad());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = ref.read(perfilProvider);
      if (p?.rol == Rol.operadorCentro) {
        ref.read(datosOperadorProvider.notifier).refrescar();
        ref.read(colaProvider.notifier).sincronizar();
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _actividad([_]) => _ultimaActividad = DateTime.now();

  void _revisarInactividad() {
    final p = ref.read(perfilProvider);
    if (p == null) return;
    if (sesionVencidaPorInactividad(_ultimaActividad, DateTime.now(), minutos: p.minutosInactividad)) {
      if (esAndroid) {
        ref.read(sesionProvider.notifier).bloquear();
      } else {
        ref.read(sesionProvider.notifier).cerrarSesion(
            mensaje: 'La sesión se cerró tras ${p.minutosInactividad} minutos sin uso. Vuelva a ingresar.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider);
    if (perfil == null) return const SizedBox.shrink();
    ref.listen<bool>(enLineaProvider, (antes, ahora) {
      if (ahora && antes == false) ref.read(colaProvider.notifier).sincronizar();
    });
    final ancho = esAncho(context);
    final entrada = entradaDeRuta(widget.ruta);
    final menu = _Menu(ruta: widget.ruta, rol: perfil.rol, alElegir: (r) {
      if (!ancho) Navigator.of(context).maybePop();
      context.go(r);
    });

    final contenido = Listener(
      onPointerDown: _actividad,
      onPointerSignal: _actividad,
      behavior: HitTestBehavior.translucent,
      child: Focus(onKeyEvent: (_, _) {
        _actividad();
        return KeyEventResult.ignored;
      }, child: widget.hijo),
    );

    final barra = AppBar(
      automaticallyImplyLeading: !ancho,
      titleSpacing: ancho ? 24 : 0,
      title: Text(entrada?.nombre ?? 'Inicio', overflow: TextOverflow.ellipsis),
      actions: [
        const _IndicadorConexion(),
        if (perfil.rol == Rol.operadorCentro) const _IndicadorPendientes(),
        const SizedBox(width: 4),
        _MenuUsuario(),
        const SizedBox(width: 8),
      ],
    );

    if (ancho) {
      return Scaffold(
        body: Row(children: [
          SizedBox(width: 290, child: Material(color: Colores.superficie, child: menu)),
          const VerticalDivider(width: 1),
          Expanded(child: Scaffold(appBar: barra, body: contenido)),
        ]),
      );
    }
    return Scaffold(appBar: barra, drawer: Drawer(child: menu), body: contenido);
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.ruta, required this.rol, required this.alElegir});
  final String ruta;
  final Rol rol;
  final ValueChanged<String> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    Widget item(String titulo, IconData icono, String r, {String? rf}) {
      final activo = ruta == r || (r != '/inicio' && ruta.startsWith(r));
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: ListTile(
          dense: true,
          minTileHeight: 44,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          selected: activo,
          selectedTileColor: Colores.primarioClaro.withValues(alpha: .45),
          selectedColor: Colores.primarioOscuro,
          leading: Icon(icono, size: 20),
          title: Text(titulo, style: TextStyle(fontWeight: activo ? FontWeight.w700 : FontWeight.w500)),
          trailing: rf == null ? null : Text(rf, style: const TextStyle(fontSize: 10, color: Colores.textoSuave)),
          onTap: () => alElegir(r),
        ),
      );
    }

    return SafeArea(
      child: ListView(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Colores.primario, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.grass, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ensilados Santa Cruz', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('ERP agroindustrial', style: TextStyle(color: Colores.textoSuave, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colores.fondo, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            CircleAvatar(backgroundColor: Colores.ambar, foregroundColor: Colors.white, child: Text(perfil.iniciales)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(perfil.nombre, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(perfil.rol.nombre, style: const TextStyle(fontSize: 12, color: Colores.textoSuave), overflow: TextOverflow.ellipsis),
                Text(perfil.sede, style: const TextStyle(fontSize: 12, color: Colores.textoSuave), overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (perfil.rol == Rol.superadmin) const _SelectorSede(),
          ]),
        ),
        item('Inicio', Icons.dashboard_outlined, '/inicio'),
        item('Mis solicitudes', Icons.outbox_outlined, '/mis-solicitudes'),
        for (final m in modulosMenu)
          if (m.entradas.any((e) => e.permitido(rol))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 6),
              child: Row(children: [
                Icon(m.icono, size: 16, color: Colores.ambarOscuro),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.titulo.toUpperCase(),
                      style: const TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: Colores.ambarOscuro)),
                ),
              ]),
            ),
            for (final e in m.entradas)
              if (e.permitido(rol)) item(e.nombre, e.icono, e.ruta, rf: e.submodulo.requerimiento),
          ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _IndicadorConexion extends ConsumerWidget {
  const _IndicadorConexion();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enLinea = ref.watch(enLineaProvider);
    final simulado = ref.watch(modoSinRedProvider);
    final perfil = ref.watch(perfilProvider);
    if (!esAncho(context)) {
      final icono = Icon(enLinea ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: enLinea ? Colores.exito : Colores.peligro);
      return IconButton(
        tooltip: enLinea ? 'En línea' : 'Sin conexión${simulado ? ' (simulada)' : ''}',
        icon: icono,
        onPressed: perfil?.rol == Rol.operadorCentro ? () => ref.read(modoSinRedProvider.notifier).cambiar(!simulado) : null,
      );
    }
    final chip = Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(enLinea ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          size: 18, color: enLinea ? Colores.exito : Colores.peligro),
      label: Text(enLinea ? 'En línea' : (simulado ? 'Sin conexión (simulada)' : 'Sin conexión')),
    );
    if (perfil?.rol != Rol.operadorCentro) return chip;
    // El operador puede simular el modo avión para demostrar el registro sin conexión (CP-09).
    return Tooltip(
      message: 'Tocar para simular la falta de señal',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => ref.read(modoSinRedProvider.notifier).cambiar(!simulado),
        child: chip,
      ),
    );
  }
}

class _IndicadorPendientes extends ConsumerWidget {
  const _IndicadorPendientes();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(pendientesSincronizarProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: IconButton(
          tooltip: '$n registros por sincronizar',
          icon: const Icon(Icons.sync),
          onPressed: () async {
            await ref.read(colaProvider.notifier).sincronizar();
            if (context.mounted) context.go('/operaciones/bascula');
          },
        ),
      ),
    );
  }
}

class _MenuUsuario extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      icon: CircleAvatar(radius: 16, backgroundColor: Colores.primario, foregroundColor: Colors.white,
          child: Text(perfil.iniciales, style: const TextStyle(fontSize: 12))),
      onSelected: (v) async {
        switch (v) {
          case 'clave':
            context.go('/cambiar-clave');
          case 'pin':
            context.go('/pin?configurar=1');
          case 'bloquear':
            ref.read(sesionProvider.notifier).bloquear();
          case 'salir':
            await ref.read(sesionProvider.notifier).cerrarSesion();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text('${perfil.nombre}\n${perfil.correo}')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'clave', child: ListTile(leading: Icon(Icons.key_outlined), title: Text('Cambiar contraseña'))),
        if (esAndroid || Uri.base.queryParameters['vista'] == 'movil')
          const PopupMenuItem(value: 'pin', child: ListTile(leading: Icon(Icons.pin_outlined), title: Text('PIN sin conexión'))),
        if (esAndroid)
          const PopupMenuItem(value: 'bloquear', child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Bloquear'))),
        const PopupMenuItem(value: 'salir', child: ListTile(leading: Icon(Icons.logout), title: Text('Cerrar sesión'))),
      ],
    );
  }
}



/// Superadministrador: elige la sede desde la que trabaja (para operar como cualquier centro de acopio).
class _SelectorSede extends ConsumerWidget {
  const _SelectorSede();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Cambiar sede de trabajo',
      icon: const Icon(Icons.swap_horiz),
      onPressed: () async {
        final sedes = await ref.read(repositorioSeguridadProvider).sedes();
        if (!context.mounted) return;
        final elegida = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Sede de trabajo'),
            children: [
              for (final s in sedes.where((s) => s['activa'] != false))
                SimpleDialogOption(onPressed: () => Navigator.pop(c, '${s['id']}'), child: Text('${s['nombre']}')),
            ],
          ),
        );
        if (elegida == null) return;
        try {
          await ref.read(sesionProvider.notifier).cambiarSede(elegida);
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      },
    );
  }
}
