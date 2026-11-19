-- Migración 20261118183923 «parametros_y_seguridad_1», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create table if not exists app.parametros (
  clave varchar(40) primary key,
  valor jsonb not null,
  descripcion text not null,
  actualizado_por uuid references public.usuarios (id),
  actualizado_en timestamptz not null default now()
);
alter table app.parametros enable row level security;
revoke all on app.parametros from public, anon, authenticated;

insert into app.parametros (clave, valor, descripcion) values
  ('tolerancia_despacho_pct', '5', 'Peso adicional permitido en ventas por tonelada por pérdida en tránsito (%)'),
  ('peso_promedio_rollo_kg', '850', 'Peso promedio por rollo para convertir toneladas en rollos (kg)'),
  ('inactividad_minutos', '15', 'Cierre de sesión tras minutos sin uso'),
  ('clave_longitud_min', '8', 'Longitud mínima de la contraseña'),
  ('clave_mayusculas', 'true', 'La contraseña exige al menos una mayúscula'),
  ('clave_minusculas', 'true', 'La contraseña exige al menos una minúscula'),
  ('clave_numeros', 'true', 'La contraseña exige al menos un número'),
  ('clave_simbolos', 'true', 'La contraseña exige al menos un símbolo'),
  ('clave_vigencia_dias', '90', 'Días de vigencia de la contraseña'),
  ('intentos_max', '3', 'Intentos fallidos antes de bloquear la cuenta'),
  ('bloqueo_minutos', '15', 'Minutos de bloqueo tras superar los intentos'),
  ('pin_min', '4', 'Dígitos mínimos del PIN sin conexión'),
  ('pin_max', '6', 'Dígitos máximos del PIN sin conexión'),
  ('pin_intentos', '3', 'Intentos de PIN antes de exigir inicio de sesión en línea'),
  ('horas_sin_sincronizar', '12', 'Horas máximas de trabajo sin conexión'),
  ('respaldo_hora_utc', '"07:00"', 'Hora del respaldo diario (UTC)')
on conflict (clave) do nothing;

create or replace function app.parametro(p_clave text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select valor from app.parametros where clave = p_clave
$$;
