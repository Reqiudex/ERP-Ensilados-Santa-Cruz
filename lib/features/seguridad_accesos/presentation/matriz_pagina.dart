import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../domain/roles_y_permisos.dart';
import 'sesion.dart';

/// RF-02 Roles, permisos y bandeja de aprobaciones: qué hace cada rol y matriz de permisos (solo lectura: los cinco
/// roles son fijos).
class MatrizPagina extends ConsumerWidget {
  const MatrizPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mio = ref.watch(perfilProvider)?.rol;
    // Defensa adicional a la del enrutador: solo administrador, gerente y superadministrador ven la matriz.
    if (!Submodulo.rbac.permitido(mio)) {
      return const Pagina(
        etiquetaRf: 'Seguridad y Accesos · RF-02',
        titulo: 'Roles y permisos',
        hijos: [MensajeVacio(icono: Icons.lock_outline, titulo: 'Su rol no consulta la matriz de permisos.')],
      );
    }
    // El superadministrador solo aparece para otro superadministrador.
    final roles = mio == Rol.superadmin ? Rol.values : Rol.deLaMatriz;
    Color color(Acceso a) => switch (a) {
          Acceso.r => context.paleta.primario,
          Acceso.s => context.paleta.info,
          Acceso.a => context.paleta.ambarOscuro,
          Acceso.c => context.paleta.textoSuave,
          Acceso.v => context.paleta.exito,
        };
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-02',
      titulo: 'Roles y permisos',
      subtitulo: 'Matriz de permisos de la tesis. Cada control se aplica en tres lugares: la interfaz oculta la opción, '
          'la API responde 403 y la base de datos lo rechaza.',
      hijos: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in Acceso.values)
            Chip(
              avatar: CircleAvatar(backgroundColor: color(a), child: Text(a.letra, style: TextStyle(color: context.paleta.superficie, fontSize: 11))),
              label: Text(a.descripcion),
            ),
        ]),
        const SizedBox(height: 16),
        const Aviso(
            '¿Para qué sirve? El control de acceso basado en roles (RBAC, RF-02 de la tesis) decide qué puede ver y hacer cada '
            'persona según su rol: el menú solo muestra lo autorizado, la API responde 403 y la base de datos rechaza cualquier '
            'otra operación. Los roles son fijos (cinco, según la tesis); el administrador asigna el rol a cada cuenta en '
            '«Gestión de usuarios» y los roles privilegiados los aprueba el gerente.',
            icono: Icons.help_outline),
        Seccion(
          titulo: 'Roles del sistema (toque un rol para ver todo lo que hace)',
          icono: Icons.badge_outlined,
          hijo: Column(children: [
            for (final r in roles) _RolExpandible(rol: r, propio: r == mio, color: color),
          ]),
        ),
        const SizedBox(height: 16),
        if (mio != null) Aviso('Su rol: ${mio.nombre}. Su columna aparece resaltada.'),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 48,
              columns: [
                const DataColumn(label: Text('Módulo')),
                const DataColumn(label: Text('Operación')),
                for (final r in roles)
                  DataColumn(
                      label: SizedBox(
                          width: 96,
                          child: Text(r.nombreCorto,
                              maxLines: 2,
                              style: TextStyle(color: r == mio ? context.paleta.primario : null, fontWeight: r == mio ? FontWeight.w800 : null)))),
              ],
              rows: [
                for (final o in matrizPermisos)
                  DataRow(cells: [
                    DataCell(Text(o.modulo, style: TextStyle(color: context.paleta.textoSuave))),
                    DataCell(SizedBox(width: 260, child: Text(o.operacion))),
                    for (final r in roles)
                      DataCell(Container(
                        color: r == mio ? context.paleta.primarioClaro.withValues(alpha: .25) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        alignment: Alignment.centerLeft,
                        child: r == Rol.superadmin
                            ? const Text('Total')
                            : (o.accesos[r] ?? const []).isEmpty
                            ? Text('—', style: TextStyle(color: context.paleta.borde))
                            : Wrap(spacing: 4, children: [
                                for (final a in o.accesos[r]!)
                                  CircleAvatar(
                                      radius: 12,
                                      backgroundColor: color(a),
                                      child: Text(a.letra, style: TextStyle(color: context.paleta.superficie, fontSize: 11, fontWeight: FontWeight.w700))),
                              ]),
                      )),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Seccion(
          titulo: 'Reglas de separación de funciones',
          icono: Icons.gavel_outlined,
          hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Regla('Nadie aprueba lo que registró: la base de datos exige aprobado_por distinto de registrado_por.'),
            _Regla('Quien vende no cobra: solo el cajero registra cobros y pagos.'),
            _Regla('Un pesaje confirmado no se edita: se pide una corrección que aprueba el gerente.'),
            _Regla('Las guías las confirma un operador de otro centro (receptor <> emisor).'),
            _Regla('El stock nunca se edita a mano: solo cambia por movimientos de funciones del servidor.'),
            _Regla('El administrador no tiene permisos de negocio y no puede asignarse roles.'),
            _Regla('La bitácora no admite UPDATE ni DELETE.'),
            _Regla('Cada operador solo ve los datos de su sede (RLS por sede).'),
          ]),
        ),
      ],
    );
  }
}

class _Regla extends StatelessWidget {
  const _Regla(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield_outlined, size: 18, color: context.paleta.primario),
          const SizedBox(width: 8),
          Expanded(child: Text(t)),
        ]),
      );
}

/// Un rol con su descripción operativa completa; al expandirlo muestra cada operación que hace, por módulo, y los
/// submódulos del menú a los que entra.
class _RolExpandible extends StatelessWidget {
  const _RolExpandible({required this.rol, required this.propio, required this.color});
  final Rol rol;
  final bool propio;
  final Color Function(Acceso) color;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final operaciones = rol == Rol.superadmin ? matrizPermisos : matrizPermisos.where((o) => (o.accesos[rol] ?? const []).isNotEmpty).toList();
    final modulos = <String, List<OperacionMatriz>>{};
    for (final o in operaciones) {
      (modulos[o.modulo] ??= []).add(o);
    }
    final submodulos = Submodulo.values.where((s) => s.permitido(rol)).toList();
    final sinAcceso = rol == Rol.superadmin ? const <OperacionMatriz>[] : matrizPermisos.where((o) => (o.accesos[rol] ?? const []).isEmpty).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: propio ? tema.colorScheme.primaryContainer.withValues(alpha: .35) : null,
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: tema.colorScheme.primaryContainer,
          foregroundColor: tema.colorScheme.onPrimaryContainer,
          child: Text(rol.nombreCorto.substring(0, 1)),
        ),
        title: Text(propio ? '${rol.nombre} (su rol)' : rol.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(descripcionRol(rol)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Entra a ${submodulos.length} submódulos', style: tema.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in submodulos) Chip(visualDensity: VisualDensity.compact, label: Text('${s.requerimiento} ${s.titulo}')),
          ]),
          const SizedBox(height: 14),
          Text('Qué hace en cada operación', style: tema.textTheme.titleSmall),
          for (final m in modulos.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(m.key, style: tema.textTheme.labelLarge?.copyWith(color: tema.colorScheme.primary)),
            ),
            for (final o in m.value)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 260, child: Text(o.operacion)),
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      if (rol == Rol.superadmin)
                        const Text('Todo (registra, solicita, aprueba, consulta y verifica)')
                      else
                        for (final a in o.accesos[rol]!)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            CircleAvatar(
                                radius: 10,
                                backgroundColor: color(a),
                                child: Text(a.letra, style: TextStyle(color: context.paleta.superficie, fontSize: 10, fontWeight: FontWeight.w700))),
                            const SizedBox(width: 4),
                            Text(a.descripcion),
                          ]),
                    ]),
                  ),
                ]),
              ),
          ],
          if (sinAcceso.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('No puede (${sinAcceso.length} operaciones)', style: tema.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(sinAcceso.map((o) => o.operacion).join(' · '), style: tema.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          Text('Eliminación: ninguna. Las bajas son lógicas (suspender, anular) y quedan en la bitácora.', style: tema.textTheme.bodySmall),
        ],
      ),
    );
  }
}
