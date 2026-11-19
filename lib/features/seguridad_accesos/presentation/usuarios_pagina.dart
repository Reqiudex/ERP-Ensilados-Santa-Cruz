import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/reglas_seguridad.dart';
import '../domain/roles_y_permisos.dart';
import 'medidor_clave.dart';
import 'sesion.dart';

final usuariosProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).usuarios());
final sedesProvider = FutureProvider<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).sedes());

/// RF-01 Gestión de usuarios (solo el administrador registra; el gerente consulta).
class UsuariosPagina extends ConsumerStatefulWidget {
  const UsuariosPagina({super.key});
  @override
  ConsumerState<UsuariosPagina> createState() => _UsuariosPaginaState();
}

class _UsuariosPaginaState extends ConsumerState<UsuariosPagina> {
  String? _rol;
  String? _sede;
  String? _estado;

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider)!;
    final puede = Accion.crearUsuario.permitida(perfil.rol);
    // El rol de superadministrador solo lo ve otro superadministrador.
    final rolesVisibles = perfil.rol == Rol.superadmin ? Rol.values : Rol.deLaMatriz;
    final usuarios = ref.watch(usuariosProvider);
    final sedes = ref.watch(sedesProvider).value ?? const [];
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-01',
      titulo: 'Gestión de usuarios',
      subtitulo: puede
          ? 'Alta, edición, suspensión, desbloqueo y restablecimiento de contraseñas. Los roles privilegiados los aprueba el gerente.'
          : 'Consulta de cuentas (solo el administrador las registra).',
      acciones: [
        if (puede) FilledButton.icon(onPressed: () => _formulario(context, null, sedes), icon: const Icon(Icons.person_add_alt), label: const Text('Nueva cuenta')),
      ],
      alRefrescar: () async => ref.invalidate(usuariosProvider),
      hijos: [
        Asincrono(usuarios, alReintentar: () => ref.invalidate(usuariosProvider), datos: (lista) {
          int cuenta(String e) => lista.where((u) => u['estado'] == e).length;
          final filtrados = lista
              .where((u) =>
                  (_rol == null || u['roles']?['codigo'] == _rol) &&
                  (_sede == null || u['sede_id'] == _sede) &&
                  (_estado == null || u['estado'] == _estado))
              .toList();
          return Column(children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Total de usuarios', valor: '${lista.length}', icono: Icons.people_alt_outlined),
              TarjetaDato(titulo: 'Activos', valor: '${cuenta('activo')}', icono: Icons.verified_user_outlined, color: Colores.exito),
              TarjetaDato(titulo: 'Suspendidos', valor: '${cuenta('suspendido')}', icono: Icons.pause_circle_outline, color: Colores.alerta),
              TarjetaDato(titulo: 'Bloqueados', valor: '${cuenta('bloqueado')}', icono: Icons.lock_clock_outlined, color: Colores.peligro),
            ]),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in rolesVisibles)
                  Chip(
                    avatar: CircleAvatar(
                        backgroundColor: Colores.primarioClaro,
                        child: Text('${lista.where((u) => u['roles']?['codigo'] == r.codigo).length}', style: const TextStyle(fontSize: 11))),
                    label: Text(r.nombre),
                  ),
              ]),
            ),
            TablaDatos(
              titulo: 'Cuentas',
              filas: filtrados,
              filtros: [
                _Filtro('Rol', _rol, {for (final r in rolesVisibles) r.codigo: r.nombre}, (v) => setState(() => _rol = v)),
                _Filtro('Sede', _sede, {for (final s in sedes) '${s['id']}': '${s['nombre']}'}, (v) => setState(() => _sede = v)),
                _Filtro('Estado', _estado, const {'activo': 'Activo', 'suspendido': 'Suspendido', 'bloqueado': 'Bloqueado'},
                    (v) => setState(() => _estado = v)),
              ],
              columnas: [
                Columna('Nombre', (u) => '${u['nombre_completo']}'),
                Columna('CI', (u) => '${u['ci']}'),
                Columna('Correo', (u) => '${u['correo']}'),
                Columna('Rol', (u) => '${u['roles']?['nombre'] ?? ''}'),
                Columna('Sede', (u) => '${u['sedes']?['nombre'] ?? ''}'),
                Columna('Estado', (u) => etiqueta(u['estado']), celda: (u) => Estado(u['estado'])),
              ],
              acciones: puede ? (u) => _acciones(context, u, perfil.id, sedes) : null,
            ),
          ]);
        }),
      ],
    );
  }

  List<Widget> _acciones(BuildContext context, Fila u, String miId, List<Fila> sedes) {
    final repo = ref.read(repositorioSeguridadProvider);
    final propio = u['id'] == miId;
    Future<void> hacer(Future<void> Function() f, String ok) async {
      await ejecutar(context, f, exito: ok);
      ref.invalidate(usuariosProvider);
    }

    return [
      IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _formulario(context, u, sedes)),
      if (!propio && u['estado'] == 'activo')
        IconButton(
          tooltip: 'Suspender (baja lógica)',
          icon: const Icon(Icons.pause_circle_outline, color: Colores.alerta),
          onPressed: () async {
            if (await confirmar(context, 'Suspender cuenta', 'La cuenta de ${u['nombre_completo']} quedará suspendida y se cerrarán sus sesiones. No se borra.')) {
              await hacer(() => repo.cambiarEstadoUsuario(u['id'], 'suspender'), 'Cuenta suspendida.');
            }
          },
        ),
      if (!propio && u['estado'] != 'activo')
        IconButton(
          tooltip: u['estado'] == 'bloqueado' ? 'Desbloquear' : 'Activar',
          icon: const Icon(Icons.lock_open_outlined, color: Colores.exito),
          onPressed: () => hacer(() => repo.cambiarEstadoUsuario(u['id'], u['estado'] == 'bloqueado' ? 'desbloquear' : 'activar'), 'Cuenta activada.'),
        ),
      if (!propio)
        IconButton(
          tooltip: 'Restablecer contraseña',
          icon: const Icon(Icons.key_outlined),
          onPressed: () => _restablecer(context, u),
        ),
    ];
  }

  Future<void> _restablecer(BuildContext context, Fila u) async {
    final ctrl = TextEditingController();
    final form = GlobalKey<FormState>();
    final perfil = ref.read(perfilProvider)!;
    final pol = PoliticaClave.desdeParametros(perfil.parametros);
    await dialogoFormulario<bool>(
      context,
      titulo: 'Restablecer contraseña',
      formulario: form,
      contenido: (c, set) => Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Contraseña temporal para ${u['nombre_completo']}. Deberá cambiarla en su próximo ingreso.'),
          const SizedBox(height: 12),
          TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Contraseña temporal'),
            onChanged: (_) => set(() {}),
            validator: (v) => evaluarClave(v ?? '', pol).valida ? null : 'No cumple la política.',
          ),
          const SizedBox(height: 8),
          MedidorClave(clave: ctrl.text, politica: pol),
        ]),
      ),
      alGuardar: () => ejecutar(context, () async {
        await ref.read(repositorioSeguridadProvider).restablecerClave(u['id'], ctrl.text);
        return true;
      }, exito: 'Contraseña restablecida; se cerraron sus sesiones.'),
    );
  }

  Future<void> _formulario(BuildContext context, Fila? u, List<Fila> sedes) async {
    final form = GlobalKey<FormState>();
    final nombre = TextEditingController(text: u?['nombre_completo']);
    final ci = TextEditingController(text: u?['ci']);
    final correo = TextEditingController(text: u?['correo']);
    final clave = TextEditingController();
    String? rol = u?['roles']?['codigo'];
    String? sede = u?['sede_id'];
    final perfil = ref.read(perfilProvider)!;
    final pol = PoliticaClave.desdeParametros(perfil.parametros);
    final propio = u?['id'] == perfil.id;
    final r = await dialogoFormulario<Fila>(
      context,
      titulo: u == null ? 'Nueva cuenta' : 'Editar cuenta',
      formulario: form,
      guardar: u == null ? 'Crear cuenta' : 'Guardar cambios',
      contenido: (c, set) => Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre completo'), validator: (v) => validarNombre(v ?? '')),
          const SizedBox(height: 12),
          TextFormField(controller: ci, decoration: const InputDecoration(labelText: 'CI'), keyboardType: TextInputType.number, validator: (v) => validarCi(v ?? '')),
          const SizedBox(height: 12),
          TextFormField(controller: correo, decoration: const InputDecoration(labelText: 'Correo'), keyboardType: TextInputType.emailAddress, validator: (v) => validarCorreo(v ?? '')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: rol,
            decoration: const InputDecoration(labelText: 'Rol'),
            items: [
              for (final r in Rol.deLaMatriz)
                DropdownMenuItem(value: r.codigo, enabled: !propio, child: Text(r.privilegiado ? '${r.nombre} (requiere aprobación)' : r.nombre)),
            ],
            onChanged: propio ? null : (v) => set(() => rol = v),
            validator: (v) => v == null ? 'Seleccione el rol.' : null,
          ),
          if (propio) const Padding(padding: EdgeInsets.only(top: 6), child: Aviso('El administrador no puede asignarse roles.')),
          const SizedBox(height: 12),
          Selector(etiqueta: 'Sede', opciones: sedes, valor: sede, alCambiar: (v) => set(() => sede = v)),
          if (u == null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: clave,
              decoration: const InputDecoration(labelText: 'Contraseña inicial'),
              onChanged: (_) => set(() {}),
              validator: (v) => evaluarClave(v ?? '', pol).valida ? null : 'No cumple la política.',
            ),
            const SizedBox(height: 8),
            MedidorClave(clave: clave.text, politica: pol),
            const SizedBox(height: 8),
            const Aviso('La persona deberá cambiar esta contraseña en su primer ingreso.'),
          ],
          if (rol != null && Rol.desdeCodigo(rol)!.privilegiado)
            const Aviso('Un rol privilegiado (administrador o gerente) crea una solicitud: la cuenta queda suspendida hasta que el gerente la apruebe.',
                tipo: 'alerta'),
        ]),
      ),
      alGuardar: () => ejecutar(context, () {
        final repo = ref.read(repositorioSeguridadProvider);
        final d = {'nombre': nombre.text, 'ci': ci.text, 'correo': correo.text, 'rol': rol, 'sede_id': sede, 'clave': clave.text};
        return u == null ? repo.crearUsuario(d) : repo.editarUsuario(u['id'], d);
      }),
    );
    if (r != null && context.mounted) {
      avisar(context, r['pendiente_aprobacion'] == true ? 'Guardado. El rol privilegiado quedó pendiente de aprobación del gerente.' : 'Cuenta guardada.');
      ref.invalidate(usuariosProvider);
    }
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro(this.etiqueta, this.valor, this.opciones, this.alCambiar);
  final String etiqueta;
  final String? valor;
  final Map<String, String> opciones;
  final ValueChanged<String?> alCambiar;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: DropdownButtonFormField<String?>(
          initialValue: valor,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(labelText: etiqueta, isDense: true),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
            for (final e in opciones.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: alCambiar,
        ),
      );
}

/// Filtro desplegable reutilizable por otras pantallas.
Widget filtroDesplegable(String etiqueta, String? valor, Map<String, String> opciones, ValueChanged<String?> alCambiar) =>
    _Filtro(etiqueta, valor, opciones, alCambiar);
