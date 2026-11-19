-- pg_net fuera del esquema public (recomendación del asesor de seguridad de Supabase).
drop extension if exists pg_net;
create extension pg_net schema extensions;
