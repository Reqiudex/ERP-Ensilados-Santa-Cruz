import 'package:flutter/material.dart';

import '../../../core/tema/tema.dart';
import '../domain/reglas_seguridad.dart';

/// Evaluador de contraseña en vivo (puntaje 0 a 100 y reglas que faltan), RF-03.
class MedidorClave extends StatelessWidget {
  const MedidorClave({super.key, required this.clave, this.politica = const PoliticaClave()});
  final String clave;
  final PoliticaClave politica;

  @override
  Widget build(BuildContext context) {
    final e = evaluarClave(clave, politica);
    final color = e.puntaje >= 85 ? Colores.exito : e.puntaje >= 60 ? Colores.info : e.puntaje >= 30 ? Colores.alerta : Colores.peligro;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: e.puntaje / 100, minHeight: 8, color: color, backgroundColor: Colores.borde),
          ),
        ),
        const SizedBox(width: 10),
        Text('${e.puntaje}/100 · ${e.nivel}', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      if (e.faltantes.isEmpty)
        const Text('Cumple la política de contraseñas.', style: TextStyle(color: Colores.exito, fontSize: 12))
      else
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final f in e.faltantes)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.close, size: 14, color: Colores.peligro),
              label: Text(f, style: const TextStyle(fontSize: 11)),
            ),
        ]),
    ]);
  }
}
