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
    try {
      final p = await repo.perfilActual();
      if (p != null && esAndroid) await pin.guardarPerfil(p);
      return EstadoSesion(perfil: p);
    } on ErrorNegocio catch (e) {
      // Android sin señal: se permite desbloquear con el PIN personal del operador que inició el turno.
      if (esAndroid && e.codigo == 'red') {
        final guardado = await pin.perfilGuardado();
        if (guardado != null && await pin.tienePin(guardado.id)) {
          return EstadoSesion(perfil: guardado, bloqueadaPorPin: true, sinConexion: true);
        }
      }
      return const EstadoSesion();
    } catch (_) {
      return const EstadoSesion();
    }
  }

  Future<void> iniciarSesion(String identificador, String clave) async {
    final p = await ref.read(repositorioSeguridadProvider).iniciarSesion(identificador, clave);
    if (esAndroid) await ref.read(pinLocalProvider).guardarPerfil(p);
    state = AsyncData(EstadoSesion(perfil: p));
  }

  Future<void> cerrarSesion({String? mensaje}) async {
    await ref.read(repositorioSeguridadProvider).cerrarSesion();
    state = AsyncData(EstadoSesion(mensaje: mensaje));
  }

  Future<void> cambiarClave(String actual, String nueva) async {
    await ref.read(repositorioSeguridadProvider).cambiarMiClave(actual, nueva);
    final p = state.value?.perfil;
    if (p != null) state = AsyncData(EstadoSesion(perfil: p.copiar(debeCambiarClave: false)));
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
    final r = await ref.read(pinLocalProvider).desbloquear(pin,
        intentos: (par['pin_intentos'] as num?)?.toInt() ?? 3, horas: (par['horas_sin_sincronizar'] as num?)?.toInt() ?? 12);
    if (r == ResultadoPin.desbloqueado) {
      state = AsyncData(EstadoSesion(perfil: p, sinConexion: !ref.read(enLineaProvider)));
    } else if (r == ResultadoPin.exigeInicioEnLinea) {
      try {
        await ref.read(repositorioSeguridadProvider).cerrarSesion();
      } catch (_) {}
      state = const AsyncData(EstadoSesion(
          mensaje: 'Por seguridad debe iniciar sesión en línea (tres PIN erróneos o más de 12 horas sin sincronizar).'));
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
