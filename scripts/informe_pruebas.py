#!/usr/bin/env python3
"""Convierte la salida JSON de `dart test` / `flutter test` en build/informes/resultados_pruebas.md o build/informes/resultados_auditoria.md.

Uso:
  python3 scripts/informe_pruebas.py pruebas  salida_unitarias.json salida_integracion.json > build/informes/resultados_pruebas.md
  python3 scripts/informe_pruebas.py auditoria salida_auditoria.json [salida_sql.txt] > build/informes/resultados_auditoria.md
"""
import json
import re
import sys
from datetime import datetime, timedelta, timezone

BOLIVIA = timezone(timedelta(hours=-4))

CASOS = {
    'CP-01': ('RF-01', 'Caja negra', 'Crear una cuenta con un CI ya registrado', 'Rechazo con mensaje de duplicado'),
    'CP-02': ('RF-02', 'Caja negra', 'Aprobar una solicitud que el mismo usuario registró', 'Rechazo por la restricción CHECK'),
    'CP-03': ('RF-03', 'Caja negra', 'Guardar una clave débil «abc123»', 'Rechazo: menos de 8 caracteres'),
    'CP-04': ('RF-04', 'Caja negra', 'Dejar la sesión sin uso 15 minutos', 'Sesión cerrada; pide credenciales'),
    'CP-05': ('RF-05', 'Caja negra', 'Modificar un evento de la bitácora', 'Operación rechazada'),
    'CP-06': ('RF-06', 'Caja negra', 'Restaurar un respaldo sin aprobación', 'Queda pendiente del gerente'),
    'CP-07': ('RF-07', 'Unitaria', 'Calcular el peso neto (32.000 − 12.000)', 'Neto 20.000 kg; tara ≥ bruto lanza error'),
    'CP-08': ('RF-07', 'Unitaria', 'Ajustar el peso por humedad (18 %, estándar 14 %)', '19.069,8 kg'),
    'CP-09': ('RF-07', 'Caja negra', 'Registrar un pesaje sin conexión', 'Pendiente en el dispositivo; un solo registro en el servidor'),
    'CP-10': ('RF-08', 'Caja negra', 'Cerrar una orden de ensilado (3 pesajes, 120 rollos)', 'Lote con código único «en fermentación»'),
    'CP-11': ('RF-09', 'Caja negra', 'Cerrar una orden sin film suficiente', 'Cierre bloqueado; indica el faltante'),
    'CP-12': ('RF-10', 'Unitaria', 'Evaluar si un lote está apto (15 y 21 días)', 'No apto / apto'),
    'CP-13': ('RF-11', 'Caja negra', 'Despachar más que el saldo del lote (40 → 45)', 'Rechazo; saldo sin cambios'),
    'CP-14': ('RF-12', 'Caja negra', 'Ver un cambio de stock desde la oficina', 'Visible en 3 s o menos sin recargar'),
    'CP-15': ('RF-13', 'Caja negra', 'Registrar un SKU repetido', 'Rechazo; precio nuevo queda pendiente'),
    'CP-16': ('RF-14', 'Caja negra', 'Confirmar una guía propia', 'Rechazo por la restricción CHECK'),
    'CP-17': ('RF-15', 'Caja negra', 'Registrar un proveedor nuevo', 'Proveedor inactivo hasta su aprobación'),
    'CP-18': ('RF-16', 'Caja negra', 'Pagar más que el saldo (Bs 5.000 → Bs 6.000)', 'Rechazo del pago'),
    'CP-19': ('RF-17', 'Unitaria', 'Convertir 8,5 t con 850 kg por rollo', '10 rollos'),
    'CP-20': ('RF-18', 'Caja negra', 'Cobrar desde la cuenta del ejecutivo', 'Respuesta 403; evento en bitácora'),
    'CP-21': ('RF-19', 'Unitaria', 'Elegir el lote de despacho (PEPS)', 'Propone el lote del 1 de septiembre'),
    'CP-22': ('RF-20', 'Unitaria', 'Calcular el rendimiento (120 rollos; 102 t)', '1,18 rollos por tonelada'),
    'CP-23': ('RF-21', 'Unitaria', 'Calcular la rotación (300; 150)', 'Rotación 2,0'),
    'CP-24': ('RF-22', 'Caja negra', 'Filtrar ventas por cliente y período', 'Totales iguales a la suma de sus notas'),
    'CP-25': ('RF-23', 'Unitaria', 'Calcular el porcentaje de merma (12 de 400)', '3,0 %'),
    'CP-26': ('RF-04', 'Caja negra', 'Desbloquear sin conexión con PIN incorrecto (3 veces)', 'Bloqueo; exige inicio de sesión en línea'),
    'CP-27': ('RF-19', 'Unitaria', 'Peso a despachar por tonelada (10 t; 5 %)', 'Mínimo 10.500 kg; con más de 5 % requiere aprobación'),
}

CONTROLES = {
    1: ('Pesaje confirmado inmutable', 'AC-5', 'Rechazo y evento en la bitácora.'),
    2: ('Doble control registro–aprobación', 'AC-5', 'Rechazo por la restricción CHECK.'),
    3: ('Quien vende no cobra', 'AC-5', 'Respuesta 403.'),
    4: ('Pagos solo sobre compras aprobadas', 'AC-5', 'Ambos pagos rechazados.'),
    5: ('Mermas aprobadas por el gerente', 'AC-5', 'Stock sin cambios hasta la aprobación.'),
    6: ('Recepción de guías por otra sede', 'AC-5', 'Rechazo por la restricción CHECK.'),
    7: ('Sin edición directa del stock', 'AC-6', 'Permiso denegado.'),
    8: ('Administrador sin permisos de negocio', 'AC-6', 'Sin acceso; asignación rechazada.'),
    9: ('Aislamiento por sede', 'AC-6', 'Cero filas devueltas por RLS.'),
    10: ('Bitácora inalterable', 'AU-9', 'Operación rechazada.'),
    11: ('Registros sin conexión validados', 'AC-5', 'Rechazo y devolución al operador.'),
}


def leer(archivo):
    pruebas, resultados, mensajes = {}, {}, {}
    with open(archivo, encoding='utf-8') as f:
        for linea in f:
            linea = linea.strip()
            if not linea.startswith('{'):
                continue
            try:
                e = json.loads(linea)
            except json.JSONDecodeError:
                continue
            t = e.get('type')
            if t == 'testStart':
                pruebas[e['test']['id']] = e['test']['name']
            elif t == 'testDone' and not e.get('hidden'):
                resultados[e['testID']] = e['result']
            elif t == 'print':
                mensajes.setdefault(e['testID'], []).append(e['message'])
            elif t == 'error':
                mensajes.setdefault(e['testID'], []).append('ERROR: ' + e['error'].split('\n')[0])
    return pruebas, resultados, mensajes


def celda(t):
    return str(t).replace('|', '\\|').replace('\n', ' ')


def ahora():
    return datetime.now(BOLIVIA).strftime('%d/%m/%Y %H:%M')


def informe_pruebas(archivos):
    filas = {}
    for a in archivos:
        pruebas, res, msj = leer(a)
        for tid, nombre in pruebas.items():
            m = re.match(r'(CP-\d\d)', nombre)
            if not m or tid not in res:
                continue
            cp = m.group(1)
            ok = res[tid] == 'success'
            obt = [x.split('|', 2)[2] for x in msj.get(tid, []) if x.startswith('OBTENIDO|')]
            err = [x for x in msj.get(tid, []) if x.startswith('ERROR')]
            if obt:
                texto = obt[-1]
            elif ok:
                texto = 'Igual al esperado: ' + CASOS[cp][3]
            else:
                texto = err[0] if err else 'Falló'
            filas[cp] = (ok, texto)
    fecha = ahora()
    conformes = sum(1 for ok, _ in filas.values() if ok)
    print('# Resultados de las pruebas CP-01 a CP-27\n')
    print(f'Generado por `scripts/pruebas.sh` el {fecha} (hora de Bolivia) contra el proyecto de Supabase en línea.')
    print('Las 9 pruebas unitarias prueban el dominio en Dart puro; las 18 de caja negra inician sesión con la cuenta del rol que indica cada caso.\n')
    print(f'**Resumen:** {conformes} de {len(CASOS)} casos conformes; {len(filas)} ejecutados.\n')
    print('| ID | RF | Tipo | Caso | Resultado esperado | Resultado obtenido | Conformidad | Fecha y hora |')
    print('|---|---|---|---|---|---|---|---|')
    for cp, (rf, tipo, caso, esperado) in CASOS.items():
        if cp in filas:
            ok, texto = filas[cp]
            print(f'| {cp} | {rf} | {tipo} | {celda(caso)} | {celda(esperado)} | {celda(texto)} | {"Conforme" if ok else "No conforme"} | {fecha} |')
        else:
            print(f'| {cp} | {rf} | {tipo} | {celda(caso)} | {celda(esperado)} | No ejecutado | No conforme | {fecha} |')


def informe_auditoria(archivo, sql=None):
    pruebas, res, msj = leer(archivo)
    filas = {}
    for tid, nombre in pruebas.items():
        m = re.match(r'Auditoría (\d+)', nombre)
        if not m or tid not in res:
            continue
        n = int(m.group(1))
        ev = [x.split('|', 2)[2] for x in msj.get(tid, []) if x.startswith('EVIDENCIA|')]
        err = [x for x in msj.get(tid, []) if x.startswith('ERROR')]
        filas[n] = (res[tid] == 'success', ev[-1] if ev else (err[0] if err else ''))
    fecha = ahora()
    conformes = sum(1 for ok, _ in filas.values() if ok)
    print('# Resultados de la auditoría de controles internos\n')
    print(f'Generado por `scripts/auditoria.sh` el {fecha} (hora de Bolivia). Criterios NIST SP 800-53 Rev. 5 (AC-5, AC-6, AU-9).')
    print('Cada operación prohibida se intentó con la cuenta de cada rol por la API de Supabase (PostgREST); la evidencia muestra el')
    print('código de respuesta, el mensaje de la base de datos, las filas devueltas y el evento de bitácora cuando corresponde.\n')
    print(f'**Resumen:** {conformes} de {len(CONTROLES)} controles conformes.\n')
    print('| N.º | Control auditado | Criterio | Evidencia esperada | Evidencia obtenida | Resultado |')
    print('|---|---|---|---|---|---|')
    for n, (control, criterio, esperado) in CONTROLES.items():
        ok, ev = filas.get(n, (False, 'No ejecutado'))
        print(f'| {n} | {control} | {criterio} | {esperado} | {celda(ev)} | {"Conforme" if ok else "No conforme"} |')
    print('\n## Verificación por SQL directo\n')
    if sql:
        with open(sql, encoding='utf-8') as f:
            print('```text')
            print(f.read().strip())
            print('```')
    else:
        print('Ver [evidencia_auditoria_sql.md](evidencia_auditoria_sql.md) (se regenera aquí cuando el flujo tiene el Secret `SUPABASE_DB_URL`).')


if __name__ == '__main__':
    if sys.argv[1] == 'pruebas':
        informe_pruebas(sys.argv[2:])
    else:
        informe_auditoria(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
