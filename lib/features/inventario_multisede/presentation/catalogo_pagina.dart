import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/widgets/componentes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/repositorio_inventario_supabase.dart';

final catalogoProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioInventarioProvider).catalogo());

/// RF-13 Catálogo de productos y lista de precios (el ejecutivo propone; el gerente aprueba).
class CatalogoPagina extends ConsumerWidget {
  const CatalogoPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ejecutivo = Accion.proponerProducto.permitida(ref.watch(perfilProvider)?.rol);
    final v = ref.watch(catalogoProvider);
    return Pagina(
      etiquetaRf: 'Inventario y Logística · RF-13',
      titulo: 'Catálogo de productos',
      subtitulo: 'Rollos por grano e insumos. El precio de venta sale de este catálogo aprobado; todo cambio pasa por el gerente.',
      acciones: [
        if (ejecutivo) FilledButton.icon(onPressed: () => _nuevo(context, ref), icon: const Icon(Icons.add), label: const Text('Proponer producto')),
      ],
      alRefrescar: () async => ref.invalidate(catalogoProvider),
      hijos: [
        Asincrono(v,
            datos: (l) => TablaDatos(
                  titulo: 'Productos',
                  filas: l,
                  columnas: [
                    Columna('SKU', (p) => '${p['sku']}'),
                    Columna('Nombre', (p) => '${p['nombre']}', ancho: 320),
                    Columna('Tipo', (p) => etiqueta(p['tipo'])),
                    Columna('Grano', (p) => '${p['grano'] ?? '—'}'),
                    Columna('Precio por tonelada', (p) => bs(p['precio_tonelada']), numerica: true),
                    Columna('Precio por rollo / unidad', (p) => bs(p['precio_rollo']), numerica: true),
                    Columna('Estado', (p) => p['pendiente'] == true ? 'Cambio pendiente' : (p['activo'] == true ? 'Activo' : 'Inactivo'),
                        celda: (p) => Estado(p['pendiente'] == true ? 'pendiente' : (p['activo'] == true ? 'activo' : 'inactivo'))),
                  ],
                  acciones: ejecutivo
                      ? (p) => [
                            TextButton(onPressed: () => _precio(context, ref, p), child: const Text('Proponer precio')),
                          ]
                      : null,
                )),
      ],
    );
  }

  Future<void> _precio(BuildContext context, WidgetRef ref, Fila p) async {
    final t = TextEditingController(text: '${p['precio_tonelada']}');
    final r = TextEditingController(text: '${p['precio_rollo']}');
    final m = TextEditingController();
    await dialogoFormulario<bool>(
      context,
      titulo: 'Nuevo precio · ${p['sku']}',
      guardar: 'Enviar al gerente',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: t, decoration: const InputDecoration(labelText: 'Precio por tonelada (Bs)')),
        const SizedBox(height: 10),
        TextField(controller: r, decoration: const InputDecoration(labelText: 'Precio por rollo o unidad (Bs)')),
        const SizedBox(height: 10),
        TextField(controller: m, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        await ref.read(repositorioInventarioProvider).solicitarCambioPrecio(p['id'], aNumero(t.text.replaceAll(',', '.')), aNumero(r.text.replaceAll(',', '.')), m.text);
        ref.invalidate(catalogoProvider);
        return true;
      }, exito: 'Precio enviado: queda pendiente de aprobación del gerente.'),
    );
  }

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final sku = TextEditingController();
    final nombre = TextEditingController();
    final t = TextEditingController(text: '0');
    final r = TextEditingController(text: '0');
    final m = TextEditingController();
    String tipo = 'rollo';
    String? grano = '1';
    await dialogoFormulario<bool>(
      context,
      titulo: 'Proponer producto',
      guardar: 'Enviar al gerente',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: sku, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'SKU')),
        const SizedBox(height: 10),
        TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: tipo,
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: const [DropdownMenuItem(value: 'rollo', child: Text('Rollo')), DropdownMenuItem(value: 'insumo', child: Text('Insumo'))],
          onChanged: (v) => s(() => tipo = v!),
        ),
        if (tipo == 'rollo') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: grano,
            decoration: const InputDecoration(labelText: 'Grano'),
            items: const [
              DropdownMenuItem(value: '1', child: Text('Maíz')),
              DropdownMenuItem(value: '2', child: Text('Sorgo')),
              DropdownMenuItem(value: '3', child: Text('Soya')),
            ],
            onChanged: (v) => grano = v,
          ),
        ],
        const SizedBox(height: 10),
        TextField(controller: t, decoration: const InputDecoration(labelText: 'Precio por tonelada (Bs)')),
        const SizedBox(height: 10),
        TextField(controller: r, decoration: const InputDecoration(labelText: 'Precio por rollo o unidad (Bs)')),
        const SizedBox(height: 10),
        TextField(controller: m, decoration: const InputDecoration(labelText: 'Motivo')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        await ref.read(repositorioInventarioProvider).solicitarProducto({
          'sku': sku.text,
          'nombre': nombre.text,
          'tipo': tipo,
          'grano_id': tipo == 'rollo' ? int.tryParse(grano ?? '') : null,
          'unidad': tipo == 'rollo' ? 'rollo' : 'unidad',
          'precio_tonelada': aNumero(t.text.replaceAll(',', '.')),
          'precio_rollo': aNumero(r.text.replaceAll(',', '.')),
          'motivo': m.text.isEmpty ? null : m.text,
        });
        ref.invalidate(catalogoProvider);
        return true;
      }, exito: 'Producto propuesto: queda inactivo hasta la aprobación del gerente.'),
    );
  }
}
