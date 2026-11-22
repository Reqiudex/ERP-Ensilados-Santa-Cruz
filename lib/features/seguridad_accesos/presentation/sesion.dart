import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/almacenamiento/almacen_local.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/errores/errores.dart';
import '../data/pin_local.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/perfil.dart';
import '../domain/reglas_seguridad.dart';

/// Estado de la sesión: perfil en línea, bloqueada por PIN (Android sin conexión) o sin sesión.
class EstadoSesion {
  const EstadoSesion({this.perfil, this.bloqueadaPorPin = false, this.sinConexion = false, this.mensaje});
  final Perfil? perfil;
  final bool bloqueadaPorPin;
  final bool sinConexion;
  final String? mensaje;
  bool get autenticado => perfil != null && !bloqueadaPorPin;
}

class SesionControlador extends AsyncNotifier<EstadoSesion> {
  @override
  Future<EstadoSesion> build() async {
    final repo = ref.read(repositorioSeguridadProvider);
    final pin = ref.read(pinLocalProvider);
    final enLinea = ref.read(enLineaProvider);

    Future<EstadoSesion> respaldoLocal() async {
      if (!esAndroid) return const EstadoSesion();
      final guardado = await pin.perfilGuardado();
      if (guardado == null) return const EstadoSesion();
      final conPin = await pin.tienePin(guardado.id);
      return EstadoSesion(perfil: guardado, bloqueadaPorPin: conPin, sinConexion: true);
    }

    if (!enLinea && esAndroid) {
      return await respaldoLocal();
    }

    try {
      final p = await repo.perfilActual();
      if (p != null) {
        if (esAndroid) await pin.guardarPerfil(p);
        return EstadoSesion(perfil: p);
      }
      if (esAndroid && !ref.read(enLineaProvider)) {
        return await respaldoLocal();
      }
      return const EstadoSesion();
    } on ErrorNegocio catch (e) {
      // Android sin señal o sesión expirada estando sin señal: recupera el perfil del operador en el dispositivo.
      if (esAndroid && (e.codigo == 'red' || !ref.read(enLineaProvider))) {
        return await respaldoLocal();
      }
      return const EstadoSesion();
    } catch (_) {
      if (esAndroid) return await respaldoLocal();
      return const EstadoSesion();
    }
  }

  Future<void> iniciarSesion(String identificador, String clave) async {
    final pin = ref.read(pinLocalProvider);
    try {
      final p = await ref.read(repositorioSeguridadProvider).iniciarSesion(identificador, clave);
      if (esAndroid) await pin.guardarCredencialesOffline(p, clave);
      state = AsyncData(EstadoSesion(perfil: p));
    } on ErrorNegocio catch (e) {
      if (esAndroid && (e.codigo == 'red' || !ref.read(enLineaProvider))) {
        final local = await pin.verificarCredencialesOffline(identificador, clave);
        if (local != null) {
          state = AsyncData(EstadoSesion(perfil: local, sinConexion: true));
          return;
        }
      }
      rethrow;
    }
  }

  /// true mientras el propio usuario sale: así el aviso de «sesión revocada» de su propio cierre se ignora.
  bool saliendo = false;

  Future<void> cerrarSesion({String? mensaje}) async {
    if (saliendo) return;
    saliendo = true;
    try {
      await ref.read(repositorioSeguridadProvider).cerrarSesion();
    } catch (_) {
      // La sesión pudo haber sido revocada en el servidor: igual se sale localmente.
    } finally {
      state = AsyncData(EstadoSesion(mensaje: mensaje));
      saliendo = false;
    }
  }

  Future<void> cambiarClave(String actual, String nueva) async {
    await ref.read(repositorioSeguridadProvider).cambiarMiClave(actual, nueva);
    final p = state.value?.perfil;
    if (p != null) state = AsyncData(EstadoSesion(perfil: p.copiar(debeCambiarClave: false)));
  }

  /// Superadministrador: cambia la sede de trabajo y recarga el perfil.
  Future<void> cambiarSede(String sedeId) async {
    final repo = ref.read(repositorioSeguridadProvider);
    await repo.cambiarSedeTrabajo(sedeId);
    final p = await repo.perfilActual();
    if (p != null) state = AsyncData(EstadoSesion(perfil: p));
  }

  /// Bloqueo manual o al quedarse sin señal (Android).
  void bloquear() {
    final s = state.value;
    if (s?.perfil != null && esAndroid) {
      state = AsyncData(EstadoSesion(perfil: s!.perfil, bloqueadaPorPin: true, sinConexion: !ref.read(enLineaProvider)));
    }
  }

  Future<ResultadoPin> desbloquearConPin(String pin) async {
    final p = state.value?.perfil;
    final par = p?.parametros ?? const {};
    final enLinea = ref.read(enLineaProvider);
    // En operación sin conexión 24/7 no se expulsa al operador por el reloj de sincronización mientras esté sin señal.
    final horasMax = enLinea ? ((par['horas_sin_sincronizar'] as num?)?.toInt() ?? 12) : 24 * 365;
    final r = await ref.read(pinLocalProvider).desbloquear(pin,
        intentos: (par['pin_intentos'] as num?)?.toInt() ?? 3, horas: horasMax);
    if (r == ResultadoPin.desbloqueado) {
      state = AsyncData(EstadoSesion(perfil: p, sinConexion: !enLinea));
    } else if (r == ResultadoPin.exigeInicioEnLinea) {
      try {
        await ref.read(repositorioSeguridadProvider).cerrarSesion();
      } catch (_) {}
      state = const AsyncData(EstadoSesion(
          mensaje: 'Por seguridad debe iniciar sesión con su contraseña (tres PIN erróneos o más de 12 horas sin sincronizar).'));
    }
    return r;
  }
}

final sesionProvider = AsyncNotifierProvider<SesionControlador, EstadoSesion>(SesionControlador.new);

/// Perfil del usuario autenticado (null si no hay sesión).
final perfilProvider = Provider<Perfil?>((ref) {
  final s = ref.watch(sesionProvider).value;
  return s?.autenticado == true ? s!.perfil : null;
});
