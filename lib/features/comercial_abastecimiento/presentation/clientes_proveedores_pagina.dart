import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/widgets/componentes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/repositorio_comercial_supabase.dart';

final clientesProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioComercialProvider).clientes());
final proveedoresProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioComercialProvider).proveedores());

/// RF-15 Gestión de clientes y proveedores.
class ClientesProveedoresPagina extends ConsumerStatefulWidget {
  const ClientesProveedoresPagina({super.key});
  @override
  ConsumerState<ClientesProveedoresPagina> createState() => _ClientesProveedoresPaginaState();
}

class _ClientesProveedoresPaginaState extends ConsumerState<ClientesProveedoresPagina> {
  bool _clientes = true;

  @override
  Widget build(BuildContext context) {
    final ejecutivo = Accion.registrarClienteProveedor.permitida(ref.watch(perfilProvider)?.rol);
    return Pagina(
        etiquetaRf: 'Comercial y Abastecimiento · RF-15',
        titulo: 'Clientes y proveedores',
        subtitulo: 'Un proveedor nuevo nace inactivo y un cliente nuevo sin crédito: la activación y el límite los aprueba el gerente.',
        acciones: [
          if (ejecutivo) ...[
            FilledButton.icon(onPressed: () => _formulario(context, true), icon: const Icon(Icons.person_add_alt), label: const Text('Nuevo cliente')),
            OutlinedButton.icon(onPressed: () => _formulario(context, false), icon: const Icon(Icons.add_business_outlined), label: const Text('Nuevo proveedor')),
          ],
        ],
        alRefrescar: () async {
          ref.invalidate(clientesProvider);
          ref.invalidate(proveedoresProvider);
        },
        hijos: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Clientes'), icon: Icon(Icons.groups_outlined)),
                ButtonSegment(value: false, label: Text('Proveedores'), icon: Icon(Icons.agriculture_outlined)),
              ],
              selected: {_clientes},
              onSelectionChanged: (v) => setState(() => _clientes = v.first),
            ),
          ),
          const SizedBox(height: 16),
          if (_clientes)
              Asincrono(ref.watch(clientesProvider),
                  datos: (l) => TablaDatos(
                        titulo: 'Clientes',
                        filas: l,
                        columnas: [
                          Columna('Razón social', (c) => '${c['razon_social']}'),
                          Columna('NIT o CI', (c) => '${c['nit_ci']}'),
                          Columna('Tipo', (c) => etiqueta(c['tipo'])),
                          Columna('Teléfono', (c) => '${c['telefono'] ?? '—'}'),
                          Columna('Límite de crédito', (c) => bs(c['limite_credito']), numerica: true),
                        ],
                        acciones: ejecutivo
                            ? (c) => [TextButton(onPressed: () => _credito(context, c), child: const Text('Pedir límite'))]
                            : null,
                      ))
          else
              Asincrono(ref.watch(proveedoresProvider),
                  datos: (l) => TablaDatos(
                        titulo: 'Proveedores',
                        filas: l,
                        columnas: [
                          Columna('Razón social', (p) => '${p['razon_social']}'),
                          Columna('NIT o CI', (p) => '${p['nit_ci']}'),
                          Columna('Tipo', (p) => etiqueta(p['tipo'])),
                          Columna('Teléfono', (p) => '${p['telefono'] ?? '—'}'),
                          Columna('Estado', (p) => etiqueta(p['estado']), celda: (p) => Estado(p['estado'])),
                        ],
                      )),
        ],
    );
  }

  Future<void> _credito(BuildContext context, Fila c) async {
    final m = TextEditingController(text: '${c['limite_credito']}');
    final mot = TextEditingController();
    await dialogoFormulario<bool>(
      context,
      titulo: 'Límite de crédito · ${c['razon_social']}',
      guardar: 'Enviar al gerente',
      contenido: (x, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: m, decoration: const InputDecoration(labelText: 'Nuevo límite (Bs)')),
        const SizedBox(height: 10),
        TextField(controller: mot, decoration: const InputDecoration(labelText: 'Motivo')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        await ref.read(repositorioComercialProvider).solicitarLimiteCredito(c['id'], aNumero(m.text.replaceAll(',', '.')), mot.text);
        return true;
      }, exito: 'Solicitud enviada al gerente.'),
    );
  }

  Future<void> _formulario(BuildContext context, bool cliente) async {
    final form = GlobalKey<FormState>();
    final nit = TextEditingController();
    final razon = TextEditingController();
    final tel = TextEditingController();
    String tipo = cliente ? 'mayorista' : 'productor';
    await dialogoFormulario<bool>(
      context,
      titulo: cliente ? 'Nuevo cliente' : 'Nuevo proveedor',
      formulario: form,
      contenido: (c, s) => Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: razon, decoration: const InputDecoration(labelText: 'Razón social o nombre'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Requerido.' : null),
          const SizedBox(height: 10),
          TextFormField(controller: nit, decoration: const InputDecoration(labelText: 'NIT o CI'), keyboardType: TextInputType.number,
              validator: (v) => RegExp(r'^[0-9]{5,15}$').hasMatch((v ?? '').trim()) ? null : 'Solo números (5 a 15).'),
          const SizedBox(height: 10),
          TextFormField(controller: tel, decoration: const InputDecoration(labelText: 'Teléfono'), keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: tipo,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [
              for (final t in cliente ? ['mayorista', 'minorista'] : ['productor', 'insumos'])
                DropdownMenuItem(value: t, child: Text(etiqueta(t))),
            ],
            onChanged: (v) => tipo = v ?? tipo,
          ),
          const SizedBox(height: 10),
          Aviso(cliente
              ? 'El cliente nace con límite de crédito 0; pida un límite al gerente si comprará a crédito.'
              : 'El proveedor nace inactivo: la solicitud de activación llega sola a la bandeja del gerente.'),
        ]),
      ),
      alGuardar: () => ejecutar(context, () async {
        final d = {'nit_ci': nit.text.trim(), 'razon_social': razon.text.trim(), 'telefono': tel.text.trim(), 'tipo': tipo};
        final repo = ref.read(repositorioComercialProvider);
        cliente ? await repo.registrarCliente(d) : await repo.registrarProveedor(d);
        ref.invalidate(cliente ? clientesProvider : proveedoresProvider);
        return true;
      }, exito: cliente ? 'Cliente registrado.' : 'Proveedor registrado como inactivo; espera la aprobación del gerente.'),
    );
  }
}
