-- La bitácora tampoco muestra a los demás roles los eventos cuyo contenido menciona al superadministrador
-- (su identificador o el rol), aunque los haya registrado otra cuenta. Los eventos no se borran.
create or replace function app.menciona_oculto(p_texto text) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.rol() is distinct from 'superadmin' and p_texto is not null
     and (p_texto ilike '%superadmin%'
          or exists (select 1 from public.usuarios u join public.roles r on r.id = u.rol_id
                      where r.codigo = 'superadmin' and position(u.id::text in p_texto) > 0))
$$;
revoke all on function app.menciona_oculto(text) from public, anon;
grant execute on function app.menciona_oculto(text) to authenticated;

drop policy if exists bitacora_superadmin_oculto on public.bitacora_eventos;
create policy bitacora_superadmin_oculto on public.bitacora_eventos as restrictive for select to authenticated
  using (not app.oculto(usuario_id) and not app.oculto(aprobador_id) and not app.oculto(registro_id)
         and not app.menciona_oculto(coalesce(datos_antes::text, '') || ' ' || coalesce(datos_despues::text, '')));
