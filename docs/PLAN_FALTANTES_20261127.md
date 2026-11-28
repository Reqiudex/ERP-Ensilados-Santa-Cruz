# Plan de trabajo — ERP Ensilados (erp.cerice360.com)

Basado en `FALTANTES_ERP_20261125.md`. Solo incluye las tareas de esa lista.
Horas estimadas según el tamaño de la lista: S = 6 h, M = 24 h (2 a 4 días), L = 60 h (1 a 2 semanas).

| n° | Tarea | Prioridad | Horas | Riesgo si no se hace | Depende de |
|---|---|---|---|---|---|
| 1 | Separar demo y producción: proyecto Supabase propio para producción, sin cuentas `*@ensilados.demo`, sin la clave demo y sin «reiniciar-demo» apuntando a esa base | Crítico | 24 | Un reinicio de la demo borra los datos reales, y la clave es pública | — |
| 2 | Plan pago de Supabase con respaldos gestionados, PITR y sin pausa por inactividad | Crítico | 6 (+ costo) | El proyecto se pausa y no hay recuperación a un punto en el tiempo | 1 |
| 3 | Agregar la base de producción a `~/respaldo/respaldo.sh` (cifrado + R2) y probar una restauración completa | Crítico | 6 | Sin respaldo del servidor para la base en la nube | 1 |
| 4 | Agregar erp.cerice360.com a `~/check-webs.sh` y al guardián (alerta por correo) | Crítico | 6 | Si se cae, nadie se entera | — |
| 5 | MFA (TOTP) obligatorio para administrador, gerente y cajero, y límite de intentos también en el servidor | Crítico | 24 | Alguien puede entrar a una cuenta que aprueba o cobra | 1 |
| 6 | Despliegue reproducible: CI que compile la web y publique `publicado/web` (o una imagen en GHCR) | Crítico | 24 | Compilar a mano llenó el disco `/` el 25-11 | — |
| 7 | Facturación electrónica real con el SIN o con un sistema externo | Crítico | 60 | No se puede facturar legalmente | 1 |
| 9 | Cabeceras completas en nginx: CSP (con el beacon de Cloudflare), HSTS, Permissions-Policy, frame-ancestors | Importante | 6 | Más expuesto a XSS y a clickjacking | — |
| 8 | Registro de errores del cliente (Sentry o tabla en Supabase, como en cerice360-web) | Importante | 6 | Los fallos del navegador y del APK no se ven | 1 |
| 14 | Auditoría de cambios de datos maestros (precios, clientes, catálogo) con antes y después | Importante | 24 | No se sabe quién cambió un precio | 1 |
| 10 | Paginación del lado del servidor (ventas, bitácora, pesajes, lotes) | Importante | 24 | Con un año de datos, la web se pone lenta | — |
| 15 | Política de retención y archivo (bitácora, sesiones, operaciones del teléfono) | Importante | 6 | Las tablas crecen sin límite | 14 |
| 12 | Pruebas de interfaz automáticas por rol en CI, con tema claro y oscuro | Importante | 24 | Los errores de pantalla llegan a producción | 6 |
| 13 | Exportaciones pesadas (PDF y Excel) en el servidor o en un isolate | Importante | 24 | La pantalla se congela con muchos datos | — |
| 16 | Manual de usuario por rol y procedimiento para dar de alta una sede nueva | Importante | 24 | Lo que se sabe del sistema está solo en la tesis | — |
| 11 | Modo sin conexión en la web (PWA): service worker y cola en IndexedDB | Importante | 60 | Sin señal, la web no funciona (el APK sí) | — |
| 23 | Versión visible y aviso «hay una versión nueva, recargar» | Deseable | 6 | No se sabe qué versión tiene cada usuario | 6 |
| 21 | Accesibilidad: lector de pantalla, teclado y contraste AA del tema claro | Deseable | 6 | El tema claro no cumple el contraste | — |
| 17 | Avisos por correo o WhatsApp: aprobaciones pendientes, stock bajo, lotes aptos | Deseable | 24 | El gerente tiene que entrar a mirar | — |
| 18 | Tablero con tendencias por mes y comparación entre sedes | Deseable | 24 | Solo hay reportes de un período | 10 |
| 19 | Lector de QR y código de barras con la cámara (web y APK) | Deseable | 24 | Las etiquetas QR se escriben a mano | — |
| 22 | Textos en archivo ARB | Deseable | 24 | Cambiar un texto obliga a tocar el código | — |
| 20 | Conexión directa con la báscula (serie o Bluetooth) | Deseable | 60 | Errores al escribir el peso | — |

**Total:** unas 510 horas. A una persona con 40 horas por semana, **en 3 semanas entran unas 120 horas**: la parte crítica que no depende de terceros, más tareas rápidas. Todo lo demás queda para después.

## Semana 1: proteger los datos (42 h)
| Tarea | Horas | Terminado cuando… |
|---|---|---|
| 1. Separar demo y producción | 24 | erp.cerice360.com usa su propio proyecto y reiniciar la demo no lo toca |
| 2. Plan con PITR | 6 | El plan está activo y el PITR aparece habilitado |
| 3. Respaldo y prueba de restauración | 6 | La restauración en una base temporal funcionó y quedó anotada |
| 4. Monitoreo | 6 | Una caída de prueba manda el correo |

## Semana 2: seguridad (36 h)
| Tarea | Horas | Terminado cuando… |
|---|---|---|
| 5. MFA y límite de intentos | 24 | Los 3 roles no pueden entrar sin TOTP y el servidor bloquea tras N intentos |
| 9. Cabeceras nginx | 6 | Las cabeceras aparecen en la respuesta y la web funciona igual |
| 8. Registro de errores | 6 | Un error de prueba aparece en el registro |

## Semana 3: despliegue y orden (42 h)
| Tarea | Horas | Terminado cuando… |
|---|---|---|
| 6. CI de despliegue | 24 | Un push publica la web sin compilar en el servidor |
| 23. Versión visible | 6 | La versión se ve en la app y aparece el aviso de recarga |
| 21. Accesibilidad del tema claro | 6 | Todos los colores pasan 4,5:1 |
| 15. Retención | 6 | La política está escrita y la limpieza automática funciona |

## Después de la semana 3
Este orden: **7** (facturación, primero hay que decidir si es con el SIN directo o con un sistema externo) → 14 → 10 → 12 → 13 → 16 → 11 → 17 → 18 → 19 → 22 → 20.

**Por decidir:**
- el costo del plan de Supabase (tarea 2);
- cómo se hace la facturación (tarea 7);
- Sentry o tabla propia (tarea 8).
