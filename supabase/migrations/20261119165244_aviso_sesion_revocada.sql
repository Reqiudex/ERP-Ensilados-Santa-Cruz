-- Aviso en tiempo real cuando una sesión se elimina (cierre por el administrador, suspensión o límite de sesiones):
-- el dispositivo de esa sesión lo recibe al instante por Realtime y vuelve a la pantalla de ingreso.
create or replace function app.avisar_sesion_revocada() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    perform realtime.send(jsonb_build_object('sesion', old.id), 'revocada', 'sesion:' || old.id::text, false);
  exception when others then null; -- el aviso nunca debe impedir el cierre de la sesión
  end;
  return old;
end $$;
revoke all on function app.avisar_sesion_revocada() from public, anon, authenticated;
drop trigger if exists aviso_sesion_revocada on auth.sessions;
create trigger aviso_sesion_revocada after delete on auth.sessions
  for each row execute function app.avisar_sesion_revocada();
