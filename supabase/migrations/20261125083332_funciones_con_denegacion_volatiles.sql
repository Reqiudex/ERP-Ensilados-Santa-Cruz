-- Las funciones que niegan el acceso escriben el intento en la bitácora (app.denegar). Declaradas STABLE, PostgREST
-- las ejecuta en una transacción de solo lectura y la denegación terminaba en un error 405 («cannot execute INSERT in
-- a read-only transaction») en lugar del 403 con el motivo, y el intento no quedaba en la bitácora.
alter function public.despachos_registrados() volatile;
alter function public.verificar_duplicados_usuario(text, text, text, uuid) volatile;
