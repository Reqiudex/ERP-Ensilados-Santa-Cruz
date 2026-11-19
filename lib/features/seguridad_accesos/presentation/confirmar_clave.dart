import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositorio_seguridad_supabase.dart';

/// Pide la contraseña del usuario actual antes de una acción sensible y la verifica en el servidor (bcrypt).
/// Devuelve true solo si la contraseña es correcta.
Future<bool> confirmarConClave(BuildContext context, WidgetRef ref,
    {required String titulo, required String detalle}) async {
  final ctrl = TextEditingController();
  String? error;
  var verificando = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        Future<void> verificar() async {
          if (ctrl.text.isEmpty) return;
          set(() => verificando = true);
          bool bien;
          try {
            bien = await ref.read(repositorioSeguridadProvider).verificarMiClave(ctrl.text);
          } catch (_) {
            bien = false;
          }
          if (!c.mounted) return;
          if (bien) {
            Navigator.pop(c, true);
          } else {
            set(() {
              verificando = false;
              error = 'Contraseña incorrecta.';
            });
          }
        }

        return AlertDialog(
          icon: Icon(Icons.lock_outline, color: Theme.of(c).colorScheme.primary),
          title: Text(titulo),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(detalle),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(labelText: 'Su contraseña', errorText: error),
                onSubmitted: (_) => verificar(),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: verificando ? null : () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: verificando ? null : verificar, child: const Text('Confirmar')),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
  return ok == true;
}
