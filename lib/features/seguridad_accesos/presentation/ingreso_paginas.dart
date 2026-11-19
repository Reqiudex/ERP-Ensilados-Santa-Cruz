import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/almacenamiento/almacen_local.dart';
import '../../../core/errores/errores.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/pin_local.dart';
import '../domain/reglas_seguridad.dart';
import 'medidor_clave.dart';
import 'sesion.dart';

/// Fondo de las pantallas de acceso.
class _Marco extends StatelessWidget {
  const _Marco({required this.hijo});
  final Widget hijo;
  @override
  Widget build(BuildContext context) {
    final ancho = esAncho(context);
    final tarjeta = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(child: Padding(padding: const EdgeInsets.all(28), child: hijo)),
    );
    return Scaffold(
      body: Row(children: [
        if (ancho)
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Colores.primarioOscuro, Colores.primario], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              padding: const EdgeInsets.all(56),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Image(image: AssetImage('assets/marca/logo_blanco.png'), height: 120),
                SizedBox(height: 24),
                Text('Ensilados Santa Cruz', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Sistema Integral de Gestión Agroindustrial', style: TextStyle(color: Colores.primarioClaro, fontSize: 18)),
                SizedBox(height: 32),
                _Punto('Trazabilidad de cada lote desde la báscula hasta el cliente'),
                _Punto('Inventario por sede en tiempo real'),
                _Punto('Quien registra no aprueba; quien vende no cobra'),
                _Punto('Registro sin conexión en los centros de acopio'),
              ]),
            ),
          ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (!ancho) ...[
                  const Image(image: AssetImage('assets/marca/logo_verde.png'), height: 88),
                  const SizedBox(height: 12),
                  const Text('Ensilados Santa Cruz',
                      style: TextStyle(color: Colores.primario, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 20),
                ],
                tarjeta,
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          const Icon(Icons.check_circle, color: Colores.ambar, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 15))),
        ]),
      );
}

/// RF-04: inicio de sesión con CI o correo.
class IngresoPagina extends ConsumerStatefulWidget {
  const IngresoPagina({super.key});
  @override
  ConsumerState<IngresoPagina> createState() => _IngresoPaginaState();
}

class _IngresoPaginaState extends ConsumerState<IngresoPagina> {
  final _id = TextEditingController();
  final _clave = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _ocupado = false;
  bool _ver = false;
  String? _error;

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await ref.read(sesionProvider.notifier).iniciarSesion(_id.text, _clave.text);
    } on ErrorNegocio catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = traducirError(e).mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mensaje = ref.watch(sesionProvider).value?.mensaje;
    return _Marco(
      hijo: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const Text('Iniciar sesión', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Ingrese con su CI o su correo institucional.', style: TextStyle(color: Colores.textoSuave)),
            const SizedBox(height: 24),
            if (mensaje != null) Aviso(mensaje, tipo: 'alerta'),
            TextFormField(
              controller: _id,
              decoration: const InputDecoration(labelText: 'CI o correo', prefixIcon: Icon(Icons.badge_outlined)),
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Escriba su CI o correo.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _clave,
              obscureText: !_ver,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                    tooltip: _ver ? 'Ocultar' : 'Mostrar',
                    onPressed: () => setState(() => _ver = !_ver),
                    icon: Icon(_ver ? Icons.visibility_off : Icons.visibility)),
              ),
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _entrar(),
              validator: (v) => (v ?? '').isEmpty ? 'Escriba su contraseña.' : null,
            ),
            if (_error != null) ...[const SizedBox(height: 14), Aviso(_error!, tipo: 'error')],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _ocupado ? null : _entrar,
              icon: _ocupado
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login),
              label: const Text('Ingresar'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tras 3 intentos fallidos la cuenta se bloquea 15 minutos. La sesión se cierra tras 15 minutos sin uso. '
              'Las cuentas las crea el administrador: no hay autorregistro.',
              style: TextStyle(fontSize: 12, color: Colores.textoSuave),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Cambio de contraseña (obligatorio en el primer ingreso).
class CambiarClavePagina extends ConsumerStatefulWidget {
  const CambiarClavePagina({super.key});
  @override
  ConsumerState<CambiarClavePagina> createState() => _CambiarClavePaginaState();
}

class _CambiarClavePaginaState extends ConsumerState<CambiarClavePagina> {
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _ocupado = false;

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(sesionProvider).value?.perfil;
    final politica = PoliticaClave.desdeParametros(perfil?.parametros ?? const {});
    final obligatorio = perfil?.debeCambiarClave ?? false;
    return _Marco(
      hijo: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Cambiar contraseña', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (obligatorio)
            const Aviso('Es su primer ingreso o el administrador restableció su contraseña: debe cambiarla para continuar.',
                tipo: 'alerta'),
          TextFormField(
              controller: _actual,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (v) => (v ?? '').isEmpty ? 'Requerido.' : null),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nueva,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nueva contraseña'),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final e = evaluarClave(v ?? '', politica);
              return e.valida ? null : 'Falta: ${e.faltantes.join(', ')}.';
            },
          ),
          const SizedBox(height: 8),
          MedidorClave(clave: _nueva.text, politica: politica),
          const SizedBox(height: 12),
          TextFormField(
              controller: _repetir,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repetir nueva contraseña'),
              validator: (v) => v != _nueva.text ? 'No coincide.' : null),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _ocupado
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    setState(() => _ocupado = true);
                    final ok = await ejecutar(context, () async {
                      await ref.read(sesionProvider.notifier).cambiarClave(_actual.text, _nueva.text);
                      return true;
                    }, exito: 'Contraseña actualizada.');
                    if (mounted) setState(() => _ocupado = false);
                    if (ok == true && context.mounted) context.go('/inicio');
                  },
            child: const Text('Guardar contraseña'),
          ),
          if (!obligatorio) TextButton(onPressed: () => context.go('/inicio'), child: const Text('Volver')),
          if (obligatorio)
            TextButton(onPressed: () => ref.read(sesionProvider.notifier).cerrarSesion(), child: const Text('Cerrar sesión')),
        ]),
      ),
    );
  }
}

/// PIN sin conexión (solo Android): configurar o desbloquear.
class PinPagina extends ConsumerStatefulWidget {
  const PinPagina({super.key, this.configurar = false});
  final bool configurar;
  @override
  ConsumerState<PinPagina> createState() => _PinPaginaState();
}

class _PinPaginaState extends ConsumerState<PinPagina> {
  String _pin = '';
  String? _primero;
  String? _mensaje;
  bool _error = false;

  int get _max => ((ref.read(sesionProvider).value?.perfil?.parametros['pin_max']) as num?)?.toInt() ?? 6;
  int get _min => ((ref.read(sesionProvider).value?.perfil?.parametros['pin_min']) as num?)?.toInt() ?? 4;

  Future<void> _aceptar() async {
    if (!pinConFormatoValido(_pin, minimo: _min, maximo: _max)) {
      setState(() {
        _mensaje = 'El PIN debe tener entre $_min y $_max dígitos.';
        _error = true;
      });
      return;
    }
    if (widget.configurar) {
      if (_primero == null) {
        setState(() {
          _primero = _pin;
          _pin = '';
          _mensaje = 'Repita el PIN para confirmarlo.';
          _error = false;
        });
        return;
      }
      if (_primero != _pin) {
        setState(() {
          _primero = null;
          _pin = '';
          _mensaje = 'Los PIN no coinciden. Empiece de nuevo.';
          _error = true;
        });
        return;
      }
      final perfil = ref.read(sesionProvider).value!.perfil!;
      await ref.read(pinLocalProvider).configurar(perfil, _pin);
      if (mounted) {
        avisar(context, 'PIN guardado. Podrá desbloquear la app sin señal hasta 12 horas.');
        context.go('/inicio');
      }
      return;
    }
    final r = await ref.read(sesionProvider.notifier).desbloquearConPin(_pin);
    if (!mounted) return;
    switch (r) {
      case ResultadoPin.desbloqueado:
        context.go('/inicio');
      case ResultadoPin.incorrecto:
        final est = await ref.read(pinLocalProvider).estado();
        setState(() {
          _pin = '';
          _error = true;
          _mensaje = 'PIN incorrecto. Le quedan ${3 - est.intentosFallidos} intentos.';
        });
      case ResultadoPin.exigeInicioEnLinea:
        context.go('/ingresar');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(sesionProvider).value?.perfil;
    Widget tecla(String t, {VoidCallback? accion, IconData? icono}) => SizedBox(
          width: 76,
          height: 64,
          child: OutlinedButton(
            onPressed: accion ??
                () {
                  if (_pin.length < _max) setState(() => _pin += t);
                },
            child: icono != null ? Icon(icono) : Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          ),
        );
    return _Marco(
      hijo: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(widget.configurar ? Icons.pin_outlined : Icons.lock_outline, size: 40, color: Colores.primario),
        const SizedBox(height: 8),
        Text(widget.configurar ? 'Configurar PIN sin conexión' : 'Desbloquear con PIN',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (perfil != null) Text('${perfil.nombre} · ${perfil.sede}', style: const TextStyle(color: Colores.textoSuave)),
        const SizedBox(height: 8),
        if (!widget.configurar)
          const Text('Sin señal: use su PIN personal. Tres errores o 12 horas sin sincronizar exigen iniciar sesión en línea.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colores.textoSuave)),
        if (!esAndroid && !widget.configurar)
          const Padding(padding: EdgeInsets.only(top: 8), child: Aviso('El PIN sin conexión solo existe en la app Android.')),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _max; i++)
            Container(
              margin: const EdgeInsets.all(6),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? Colores.primario : Colores.borde),
            ),
        ]),
        if (_mensaje != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_mensaje!, style: TextStyle(color: _error ? Colores.peligro : Colores.textoSuave)),
          ),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          for (final n in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) tecla(n),
          tecla('', icono: Icons.backspace_outlined, accion: () {
            if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
          }),
          tecla('0'),
          tecla('', icono: Icons.check, accion: _aceptar),
        ]),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => widget.configurar ? context.go('/inicio') : ref.read(sesionProvider.notifier).cerrarSesion(),
          child: Text(widget.configurar ? 'Volver' : 'Iniciar sesión en línea'),
        ),
      ]),
    );
  }
}
