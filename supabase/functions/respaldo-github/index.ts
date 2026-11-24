// Copia de respaldo en el repositorio de GitHub vinculado por el administrador (RF-06).
// La llama la tarea programada (pg_cron, con clave interna) o el administrador desde la app (con su sesión).
// El token de GitHub está cifrado en Vault y solo lo lee esta función con la clave de servicio.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-clave-cron",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const url = Deno.env.get("SUPABASE_URL")!;
const servicio = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

function respuesta(cuerpo: unknown, estado = 200) {
  return new Response(JSON.stringify(cuerpo), { status: estado, headers: { ...cors, "Content-Type": "application/json" } });
}

function base64(texto: string): string {
  const bytes = new TextEncoder().encode(texto);
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

async function sha256(texto: string): Promise<string> {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function gh(token: string, ruta: string, init: RequestInit = {}) {
  return await fetch(`https://api.github.com${ruta}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "erp-ensilados-respaldo",
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respuesta({ error: "Método no permitido." }, 405);

  // 1. Autorización: tarea programada (clave interna) o administrador con sesión válida.
  let usuario: string | null = null;
  let origen = "manual";
  const claveCron = req.headers.get("x-clave-cron");
  if (claveCron) {
    const { data } = await servicio.rpc("clave_cron_valida", { p_clave: claveCron });
    if (data !== true) return respuesta({ error: "No autorizado." }, 401);
    origen = "programado";
  } else {
    const jwt = req.headers.get("Authorization") ?? "";
    const cliente = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: jwt } },
      auth: { persistSession: false },
    });
    const { data, error } = await cliente.rpc("autorizar_respaldo_github");
    if (error || data?.ok !== true) return respuesta({ error: data?.message ?? "Solo el administrador envía respaldos a GitHub." }, 403);
    usuario = data.usuario;
  }

  // 2. Datos, destino y token.
  const { data: p, error: e1 } = await servicio.rpc("preparar_respaldo_github");
  if (e1) return respuesta({ error: e1.message }, 500);
  if (!p?.vinculado) return respuesta({ error: "No hay una cuenta de GitHub vinculada." }, 400);

  const texto = JSON.stringify(p.datos, null, 1);
  const ahora = new Date();
  const bolivia = new Date(ahora.getTime() - 4 * 3600 * 1000).toISOString().slice(0, 16).replace("T", "_").replace(":", "");
  const archivo = `respaldos/respaldo_${bolivia}.json`;
  const huella = await sha256(texto);

  try {
    // 3a. El respaldo lleva datos de clientes, ventas y empleados: nunca se sube a un repositorio público.
    const info = await gh(p.token, `/repos/${p.repositorio}`);
    if (!info.ok) throw new Error(`No se pudo consultar el repositorio (${info.status}).`);
    if ((await info.json()).private !== true) {
      throw new Error("El repositorio de respaldos es público: hágalo privado en GitHub antes de enviar respaldos.");
    }
    // 3b. Subida del archivo (API de contenidos de GitHub).
    const r = await gh(p.token, `/repos/${p.repositorio}/contents/${archivo}`, {
      method: "PUT",
      body: JSON.stringify({ message: `Respaldo ${origen} ${bolivia}`, content: base64(texto), branch: p.rama }),
    });
    if (!r.ok) throw new Error(`GitHub respondió ${r.status}: ${(await r.text()).slice(0, 200)}`);

    // 4. Retención: borra los respaldos más antiguos que el plazo configurado.
    let borrados = 0;
    const lista = await gh(p.token, `/repos/${p.repositorio}/contents/respaldos?ref=${p.rama}`);
    if (lista.ok) {
      const limite = new Date(ahora.getTime() - (p.retencion_dias ?? 30) * 86400 * 1000).toISOString().slice(0, 10);
      for (const f of await lista.json()) {
        const m = /^respaldo_(\d{4}-\d{2}-\d{2})_/.exec(f.name ?? "");
        if (m && m[1] < limite) {
          const d = await gh(p.token, `/repos/${p.repositorio}/contents/${f.path}`, {
            method: "DELETE",
            body: JSON.stringify({ message: `Retención: elimina ${f.name}`, sha: f.sha, branch: p.rama }),
          });
          if (d.ok) borrados++;
        }
      }
    }
    const datos = { destino: "github", repositorio: p.repositorio, archivo, bytes: texto.length, sha256: huella, origen, borrados_por_retencion: borrados };
    await servicio.rpc("registrar_respaldo_github", { p_usuario: usuario, p_datos: datos });
    return respuesta({ ok: true, ...datos });
  } catch (e) {
    const datos = { destino: "github", repositorio: p.repositorio, origen, error: String((e as Error).message ?? e) };
    await servicio.rpc("registrar_respaldo_github", { p_usuario: usuario, p_datos: datos });
    return respuesta({ error: datos.error }, 502);
  }
});
