import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/operaciones_ensilado/data/cola_sincronizacion.dart';
import '../../features/seguridad_accesos/data/pin_local.dart';
import '../../features/seguridad_accesos/data/repositorio_seguridad_supabase.dart';
import '../../features/seguridad_accesos/domain/reglas_seguridad.dart';
import '../../features/seguridad_accesos/domain/roles_y_permisos.dart';
import '../../features/seguridad_accesos/presentation/sesion.dart';
import '../almacenamiento/almacen_local.dart';
import '../conexion/conexion.dart';
import '../tema/modo_tema.dart';
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
  Timer? _vigilancia;
  Timer? _reintentoSync;
  RealtimeChannel? _canalSesion;
  bool _revisando = false;
  bool _expulsando = false;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) => _revisarInactividad());
    // Sesión revocada por el administrador («matar sesión»): la base avisa por Realtime en el canal de la sesión y
    // el dispositivo sale al instante. La revisión periódica queda como respaldo si el canal se corta.
    _escucharRevocacion();
    _vigilancia = Timer.periodic(const Duration(seconds: 5), (_) => _revisarRevocacion());
    // Reintento automático de sincronización cada 15 s cuando hay registros en cola y señal disponible.
    _reintentoSync = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ref.read(enLineaProvider) && ref.read(pendientesSincronizarProvider) > 0) {
        ref.read(colaProvider.notifier).sincronizar();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(datosOperadorProvider.notifier).refrescar();
      ref.read(colaProvider.notifier).sincronizar();
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _vigilancia?.cancel();
    _reintentoSync?.cancel();
    final canal = _canalSesion;
    if (canal != null) Supabase.instance.client.removeChannel(canal);
    super.dispose();
  }

  /// Identificador de la sesión actual (claim session_id del token de acceso).
  static String? _idSesion() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return null;
    try {
      final partes = token.split('.');
      final carga = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
      return carga['session_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _escucharRevocacion() {
    final id = _idSesion();
    if (id == null) return;
    _canalSesion = Supabase.instance.client
        .channel('sesion:$id')
        .onBroadcast(event: 'revocada', callback: (_) => _expulsar())
        .subscribe();
  }

  Future<void> _expulsar() async {
    if (_expulsando || !mounted || ref.read(sesionProvider.notifier).saliendo || ref.read(perfilProvider) == null) return;
    _expulsando = true;
    try {
      await ref.read(sesionProvider.notifier).cerrarSesion(mensaje: 'Un administrador cerró su sesión. Vuelva a ingresar.');
    } catch (_) {
      ref.invalidate(sesionProvider);
    }
  }

  void _actividad([_]) => _ultimaActividad = DateTime.now();

  Future<void> _revisarRevocacion() async {
    if (_revisando || ref.read(perfilProvider) == null || !ref.read(enLineaProvider)) return;
    _revisando = true;
    try {
      final vigente = await ref.read(repositorioSeguridadProvider).sesionVigente();
      if (!vigente && mounted) await _expulsar();
    } catch (_) {
      // Sin red o error transitorio: se vuelve a revisar en el siguiente ciclo.
    } finally {
      _revisando = false;
    }
  }

  void _revisarInactividad() {
    final p = ref.read(perfilProvider);
    if (p == null) return;
    if (sesionVencidaPorInactividad(_ultimaActividad, DateTime.now(), minutos: p.minutosInactividad)) {
      if (esAndroid) {
        // Sin señal y sin PIN configurado, no se expulsa al operador para que pueda seguir trabajando 24/7.
        ref.read(pinLocalProvider).tienePin(p.id).then((tiene) {
          if (tiene || ref.read(enLineaProvider)) {
            ref.read(sesionProvider.notifier).bloquear();
          } else {
            _ultimaActividad = DateTime.now();
          }
        });
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
      if (ahora && antes == false) {
        ref.read(colaProvider.notifier).sincronizar();
        ref.read(datosOperadorProvider.notifier).refrescar();
      }
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
      }, child: Column(children: [
        _PestanasModulo(ruta: widget.ruta, rol: perfil.rol),
        const _AvisoSincronizacion(),
        Expanded(child: widget.hijo),
      ])),
    );

    final barra = AppBar(
      automaticallyImplyLeading: !ancho,
      titleSpacing: ancho ? 24 : 0,
      title: Text(entrada?.nombre ?? 'Inicio', overflow: TextOverflow.ellipsis),
      actions: [
        const _IndicadorConexion(),
        if (perfil.rol == Rol.operadorCentro || perfil.rol == Rol.superadmin || ref.watch(pendientesSincronizarProvider) > 0)
          const _IndicadorPendientes(),
        const SizedBox(width: 4),
        _MenuUsuario(),
        const SizedBox(width: 8),
      ],
    );

    if (ancho) {
      return Scaffold(
        body: Row(children: [
          SizedBox(width: 290, child: Material(color: context.paleta.superficie, child: menu)),
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
          selectedTileColor: context.paleta.primarioClaro.withValues(alpha: .45),
          selectedColor: context.paleta.primarioOscuro,
          leading: Icon(icono, size: 20),
          title: Text(titulo, style: TextStyle(fontWeight: activo ? FontWeight.w700 : FontWeight.w500)),
          trailing: rf == null ? null : Text(rf, style: TextStyle(fontSize: 10, color: context.paleta.textoSuave)),
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
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colores.primario, borderRadius: BorderRadius.circular(12)),
              child: const Image(image: AssetImage('assets/marca/logo_blanco.png')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ensilados Santa Cruz', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('ERP agroindustrial', style: TextStyle(color: context.paleta.textoSuave, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.paleta.fondo, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            CircleAvatar(backgroundColor: context.paleta.ambar, foregroundColor: context.paleta.sobreAmbar, child: Text(perfil.iniciales)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(perfil.nombre, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(perfil.rol.nombre, style: TextStyle(fontSize: 12, color: context.paleta.textoSuave), overflow: TextOverflow.ellipsis),
                Text(perfil.sede, style: TextStyle(fontSize: 12, color: context.paleta.textoSuave), overflow: TextOverflow.ellipsis),
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
                Icon(m.icono, size: 16, color: context.paleta.ambarOscuro),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.titulo.toUpperCase(),
                      style: TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: context.paleta.ambarOscuro)),
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
      final icono = Icon(enLinea ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: enLinea ? context.paleta.exito : context.paleta.peligro);
      return IconButton(
        tooltip: enLinea ? 'En línea' : 'Sin conexión${simulado ? ' (simulada)' : ''}',
        icon: icono,
        onPressed: perfil?.rol == Rol.operadorCentro ? () => ref.read(modoSinRedProvider.notifier).cambiar(!simulado) : null,
      );
    }
    final chip = Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(enLinea ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          size: 18, color: enLinea ? context.paleta.exito : context.paleta.peligro),
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

/// Aviso cuando hay registros guardados en el teléfono que no pueden enviarse sin volver a ingresar en línea.
class _AvisoSincronizacion extends ConsumerWidget {
  const _AvisoSincronizacion();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mensaje = ref.watch(avisoSincronizacionProvider);
    if (mensaje == null || !ref.watch(enLineaProvider)) return const SizedBox.shrink();
    return Material(
      color: context.paleta.ambar.withValues(alpha: .18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.cloud_upload_outlined, color: context.paleta.ambarOscuro),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje)),
          TextButton(
            // Los registros pendientes siguen guardados en el teléfono: se envían al volver a ingresar.
            onPressed: () => ref.read(sesionProvider.notifier).cerrarSesion(
                mensaje: 'Ingrese con su contraseña para enviar los registros guardados en el teléfono.'),
            child: const Text('Ingresar'),
          ),
        ]),
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
    final modoTema = ref.watch(modoTemaProvider);
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      icon: CircleAvatar(radius: 16, backgroundColor: context.paleta.primario, foregroundColor: context.paleta.sobrePrimario,
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
          case final t when t.startsWith('tema:'):
            await ref.read(modoTemaProvider.notifier).cambiar(ThemeMode.values.byName(t.substring(5)));
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
        const PopupMenuDivider(),
        const PopupMenuItem(enabled: false, height: 32, child: Text('Tema')),
        for (final m in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
          CheckedPopupMenuItem(
            value: 'tema:${m.name}',
            checked: modoTema == m,
            child: Row(children: [Icon(iconoModoTema(m), size: 20), const SizedBox(width: 12), Text(nombreModoTema(m))]),
          ),
        const PopupMenuDivider(),
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


/// Pestañas horizontales con los submódulos del módulo actual que el rol puede usar (navegación interna del módulo).
class _PestanasModulo extends StatelessWidget {
  const _PestanasModulo({required this.ruta, required this.rol});
  final String ruta;
  final Rol rol;

  @override
  Widget build(BuildContext context) {
    ModuloMenu? modulo;
    for (final m in modulosMenu) {
      if (m.entradas.any((e) => ruta.startsWith(e.ruta))) modulo = m;
    }
    if (modulo == null) return const SizedBox.shrink();
    final entradas = modulo.entradas.where((e) => e.permitido(rol)).toList();
    final indice = entradas.indexWhere((e) => ruta.startsWith(e.ruta));
    if (entradas.length < 2 || indice < 0) return const SizedBox.shrink();
    final tema = Theme.of(context);
    return Material(
      color: tema.colorScheme.surface,
      child: DefaultTabController(
        key: ValueKey('${modulo.titulo}-$indice-${entradas.length}'),
        length: entradas.length,
        initialIndex: indice,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: (i) => context.go(entradas[i].ruta),
          tabs: [
            for (final e in entradas) Tab(height: 44, icon: null, child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(e.icono, size: 18),
              const SizedBox(width: 8),
              Text(e.nombre),
            ])),
          ],
        ),
      ),
    );
  }
}
