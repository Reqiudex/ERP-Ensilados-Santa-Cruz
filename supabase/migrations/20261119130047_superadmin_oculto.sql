-- El superadministrador solo es visible para otro superadministrador: no aparece en usuarios, roles, sesiones,
-- bitácora, bandeja ni reportes de los demás, y nadie más puede editarlo, suspenderlo ni cerrarle la sesión.

create or replace function app.oculto(p_usuario uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_usuario is not null and app.rol() is distinct from 'superadmin'
     and exists (select 1 from public.usuarios u join public.roles r on r.id = u.rol_id
                  where u.id = p_usuario and r.codigo = 'superadmin')
$$;
revoke all on function app.oculto(uuid) from public, anon;
grant execute on function app.oculto(uuid) to authenticated;

-- Políticas restrictivas de lectura (se suman a las existentes).
drop policy if exists usuarios_superadmin_oculto on public.usuarios;
create policy usuarios_superadmin_oculto on public.usuarios as restrictive for select to authenticated
  using (not app.oculto(id));
drop policy if exists roles_superadmin_oculto on public.roles;
create policy roles_superadmin_oculto on public.roles as restrictive for select to authenticated
  using (codigo <> 'superadmin' or app.rol() = 'superadmin');
drop policy if exists bitacora_superadmin_oculto on public.bitacora_eventos;
create policy bitacora_superadmin_oculto on public.bitacora_eventos as restrictive for select to authenticated
  using (not app.oculto(usuario_id) and not app.oculto(aprobador_id) and not app.oculto(registro_id));
drop policy if exists solicitudes_superadmin_oculto on public.solicitudes_aprobacion;
create policy solicitudes_superadmin_oculto on public.solicitudes_aprobacion as restrictive for select to authenticated
  using (not app.oculto(registrado_por));

-- Funciones del servidor que muestran usuarios o sesiones.
do $$
declare
  c record;
  d text;
begin
  for c in select * from (values
    ('sesiones_activas', 'where s.not_after is null or s.not_after > now()',
                         'where (s.not_after is null or s.not_after > now()) and not app.oculto(s.user_id)'),
    ('cerrar_sesiones', 'delete from auth.sessions where id::text <> coalesce(v_actual, '''');',
                        'delete from auth.sessions where id::text <> coalesce(v_actual, '''') and not app.oculto(user_id);'),
    ('bandeja_aprobaciones', 'where p_estado = ''todas'' or s.estado = p_estado',
                             'where (p_estado = ''todas'' or s.estado = p_estado) and not app.oculto(s.registrado_por)'),
    ('bandeja_aprobaciones', '''aprobado_por'', a.nombre_completo',
                             '''aprobado_por'', case when app.oculto(s.aprobado_por) then null else a.nombre_completo end'),
    ('reporte_mermas', '''solicitado_por'', ur.nombre_completo',
                       '''solicitado_por'', case when app.oculto(ur.id) then null else ur.nombre_completo end'),
    ('reporte_mermas', '''aprobado_por'', ua.nombre_completo',
                       '''aprobado_por'', case when app.oculto(ua.id) then null else ua.nombre_completo end'),
    ('reporte_ventas', '''ejecutivo'', u.nombre_completo',
                       '''ejecutivo'', case when app.oculto(u.id) then null else u.nombre_completo end'),
    ('correo_para_ingreso', 'select correo into v from public.usuarios where ci = p_identificador;',
                            'select correo into v from public.usuarios where ci = p_identificador and rol_id <> 6;')
  ) t(fn, viejo, nuevo) loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = c.fn;
    if position(c.viejo in d) = 0 then raise exception 'No se encontró el texto a reemplazar en %', c.fn; end if;
    execute replace(d, c.viejo, c.nuevo);
  end loop;

  -- Nadie más que un superadministrador edita, suspende, restablece o cierra la sesión de un superadministrador.
  for c in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('editar_usuario', 'cambiar_estado_usuario', 'restablecer_clave', 'cerrar_sesiones') loop
    d := pg_get_functiondef(c.oid);
    if position('app.oculto(p_usuario) then' in d) = 0 then
      d := regexp_replace(d, E'\nbegin\n',
             E'\nbegin\n  if app.oculto(p_usuario) then raise exception ''El usuario no existe.''; end if;\n');
      execute d;
    end if;
  end loop;
end $$;
