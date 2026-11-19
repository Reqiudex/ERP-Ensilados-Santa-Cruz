# ERP Ensilados Santa Cruz

Sistema Integral de Gestión Agroindustrial (ERP) para la Producción, Acopio y Comercialización en la Empresa Ensilados Santa Cruz.
Un solo código Flutter publicado como portal web (oficina central) y aplicación Android (centros de acopio), con base de datos
PostgreSQL en Supabase.

Autor: Jorge Luciano Ortubé Flores

- **Portal web:** https://reqiudex.github.io/ERP-Ensilados-Santa-Cruz/
- **App Android:** APK en la Release [«apk-ultima»](https://github.com/Reqiudex/ERP-Ensilados-Santa-Cruz/releases/tag/apk-ultima) (Android 8 o superior).

## Cuentas de demostración

Contraseña de todas: `Ensilados2026!` · Se ingresa con el correo o con el CI.

| Rol | Correo | CI | Sede |
|---|---|---|---|
| Administrador del sistema | admin@ensilados.demo | 6543210 | Oficina Central Santa Cruz |
| Ejecutivo comercial | ventas@ensilados.demo | 7654321 | Oficina Central Santa Cruz |
| Cajero o contador | caja@ensilados.demo | 8765432 | Oficina Central Santa Cruz |
| Gerente general | gerencia@ensilados.demo | 5432109 | Oficina Central Santa Cruz |
| Operador de centro | sanramon@ensilados.demo | 9876543 | Centro de Acopio San Ramón |
| Operador de centro | sanjulian@ensilados.demo | 9988776 | Centro de Acopio San Julián |
| Operador de centro | sanrafael@ensilados.demo | 9123456 | Centro de Acopio San Rafael de Velasco |

## Módulos

| Módulo (`lib/features/…`) | Submódulos |
|---|---|
| Seguridad y Accesos (`seguridad_accesos`) | Usuarios · RBAC y bandeja de aprobaciones · Políticas de contraseñas · Autenticación y sesiones (PIN sin conexión) · Bitácora · Mantenimiento de la base de datos |
| Operaciones y Procesamiento (`operaciones_ensilado`) | Recepción y báscula · Orden de ensilado · Consumo de insumos · Fermentación y calidad |
| Inventario y Logística (`inventario_multisede`) | Stock por lotes y trazabilidad · Gestión multisede · Catálogo · Guías de transferencia |
| Comercial y Abastecimiento (`comercial_abastecimiento`) | Clientes y proveedores · Compras y pagos · Cotización y pedidos · Facturación y ventas · Despachos |
| Reportes (`reportes`) | Rendimiento · Existencias y rotación · Ventas y cartera · Pérdidas y merma |

## Ejecutar

Requisitos: Flutter 3.50.

```bash
flutter pub get
flutter run -d chrome        # portal web
flutter run                  # teléfono Android conectado
```

La app usa la URL y la clave publicable de Supabase (`lib/core/supabase/supabase_config.dart`); la seguridad la aplican las
políticas RLS y las funciones del servidor. Ninguna clave secreta está en el repositorio.

## Base de datos

1. Aplicar las migraciones de `supabase/migrations/` en orden (`supabase db push`).
2. Cargar los datos de demostración: `supabase/seed.sql`.
3. `supabase/reiniciar_demo.sql` vuelve los datos al estado inicial.

## Pruebas

| Comando | Qué hace |
|---|---|
| `scripts/pruebas.sh` | 27 casos: 9 unitarios en Dart puro y 18 de caja negra contra Supabase |
| `scripts/auditoria.sh` | 11 controles internos con la cuenta de cada rol (y por SQL directo si existe `SUPABASE_DB_URL`) |

Los informes quedan en `build/informes/`.

## GitHub Actions

| Flujo | Qué hace |
|---|---|
| `pages.yml` | Compila y publica el portal web en GitHub Pages |
| `apk.yml` | Compila el APK y lo publica en la Release «apk-ultima» |
| `pruebas.yml` / `auditoria.yml` | Ejecutan las pruebas y la auditoría |
| `respaldo.yml` | Respaldo diario de la base con `pg_dump` |
| `restauracion.yml` | Restaura un respaldo aprobado por el gerente |
| `reiniciar-demo.yml` | Recarga los datos de demostración |

Secret necesario para respaldo, restauración, reinicio y auditoría SQL: `SUPABASE_DB_URL` (Supabase → Connect → Session pooler).

## Estructura

```
lib/core/       configuración, rutas, tema, Supabase, conexión, exportación y componentes
lib/features/   los 5 módulos (data, domain, presentation)
supabase/       migraciones, datos de demostración y reinicio
test/           pruebas unitarias, de caja negra y de auditoría
scripts/        ejecución de pruebas e informes
android/, web/  plataformas publicadas
.github/        flujos de GitHub Actions
```
