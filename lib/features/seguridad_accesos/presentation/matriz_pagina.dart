import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../domain/roles_y_permisos.dart';
import 'sesion.dart';

/// RF-02 Matriz visual de permisos (solo lectura: los cinco roles son fijos).
class MatrizPagina extends ConsumerWidget {
  const MatrizPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mio = ref.watch(perfilProvider)?.rol;
    Color color(Acceso a) => switch (a) {
          Acceso.r => Colores.primario,
          Acceso.s => Colores.info,
          Acceso.a => Colores.ambarOscuro,
          Acceso.c => Colores.textoSuave,
          Acceso.v => Colores.exito,
        };
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-02',
      titulo: 'Control de acceso basado en roles',
      subtitulo: 'Matriz de permisos de la tesis. Cada control se aplica en tres lugares: la interfaz oculta la opción, '
          'la API responde 403 y la base de datos lo rechaza.',
      hijos: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in Acceso.values)
            Chip(
              avatar: CircleAvatar(backgroundColor: color(a), child: Text(a.letra, style: const TextStyle(color: Colors.white, fontSize: 11))),
              label: Text(a.descripcion),
            ),
        ]),
        const SizedBox(height: 16),
        if (mio != null) Aviso('Su rol: ${mio.nombre}. Su columna aparece resaltada.'),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: [
                const DataColumn(label: Text('Módulo')),
                const DataColumn(label: Text('Operación')),
                for (final r in Rol.values)
                  DataColumn(
                      label: SizedBox(
                          width: 96,
                          child: Text(r.nombreCorto,
                              maxLines: 2,
                              style: TextStyle(color: r == mio ? Colores.primario : null, fontWeight: r == mio ? FontWeight.w800 : null)))),
              ],
              rows: [
                for (final o in matrizPermisos)
                  DataRow(cells: [
                    DataCell(Text(o.modulo, style: const TextStyle(color: Colores.textoSuave))),
                    DataCell(SizedBox(width: 260, child: Text(o.operacion))),
                    for (final r in Rol.values)
                      DataCell(Container(
                        color: r == mio ? Colores.primarioClaro.withValues(alpha: .25) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: (o.accesos[r] ?? const []).isEmpty
                            ? const Text('—', style: TextStyle(color: Colores.borde))
                            : Wrap(spacing: 4, children: [
                                for (final a in o.accesos[r]!)
                                  CircleAvatar(
                                      radius: 12,
                                      backgroundColor: color(a),
                                      child: Text(a.letra, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
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
            _Regla('Nadie aprueba lo que registró (CHECK aprobado_por <> registrado_por).'),
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
          const Icon(Icons.shield_outlined, size: 18, color: Colores.primario),
          const SizedBox(width: 8),
          Expanded(child: Text(t)),
        ]),
      );
}
