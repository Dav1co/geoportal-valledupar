# Patch propuesto: que la pausa global surta efecto de inmediato

**Archivo objetivo:** `~/geoportal-web/supabase/functions/_shared/auth.ts`
**Estado:** PROPUESTO — pendiente de decisión de David.
**Origen:** hallazgo #14 de la auditoría del 2026-08-11.

## El problema

`autorizar()` cachea `token -> email` durante 5 minutos y en el camino
cacheado **retorna antes** de consultar `geoportal_estado_acceso`:

```ts
const cached = cacheTokens.get(token);
if (cached && cached.expira > Date.now()) {
  return { email: cached.email, ip };     // <-- sale sin revalidar
}
```

Consecuencia: desactivar un usuario, cambiarle el rol, cortar por horario
o **pausar el geoportal entero** no surte efecto hasta 5 minutos, y por
cada isolate de Deno vivo por separado. Una suspensión de emergencia que
tarda cinco minutos no es una suspensión de emergencia.

En la auditoría, `pausa_quitar` aparece 5 veces en el registro: es un
control que se usa de verdad.

## Qué se gana y qué se paga

El caché sirve para dos cosas distintas, y solo una vale la pena:

| Lo que evita el caché | Coste real | ¿Vale cachearlo? |
|---|---|---|
| `fetch /auth/v1/user` — valida el JWT contra la API de auth | Round-trip HTTP a un servicio externo | **Sí**, es la parte cara |
| `rpc geoportal_estado_acceso` — lee la lista blanca y la pausa | Un RPC contra la misma base | **No**, es barato y es justo lo que debe estar fresco |

La propuesta separa las dos: **se conserva el caché del token** (lo caro)
y **se revalida siempre el estado de acceso** (lo barato).

Medición del RPC: **137–148 ms desde mi máquina**, pero ese número
incluye la latencia de mi conexión y **no es el que pagaría la Edge
Function**, que corre en la red de Supabase. No puedo medir desde dentro
del isolate; el orden de magnitud real estará entre 10 y 40 ms.

Contexto de volumen: `geoportal-tiles` llama `autorizar()` **en cada
tesela** y no deja registro, así que el número de llamadas es muy
superior a los 5.544 `login` del último mes. Un paneo del mapa son
varias teselas. Ahora bien, generar una tesela cuesta hoy entre 200 ms y
6 s, así que sumarle un RPC de 10–40 ms es ruido en ese camino.

## El diff

```diff
 export async function autorizar(req: Request): Promise<Autorizado> {
   ...
   const cached = cacheTokens.get(token);
-  if (cached && cached.expira > Date.now()) {
-    return { email: cached.email, ip };
-  }
+  if (cached && cached.expira > Date.now()) {
+    // El token sigue siendo valido -eso es lo caro de comprobar y por eso
+    // se cachea-, pero el PERMISO puede haber cambiado hace un segundo:
+    // una desactivacion, un cambio de rol o la pausa global. Se revalida
+    // siempre, para que una suspension de emergencia sea inmediata.
+    const estadoCache = await rpc<string>("geoportal_estado_acceso", {
+      p_email: cached.email,
+    });
+    if (estadoCache !== "ok") {
+      cacheTokens.delete(token);
+      throw mensajeEstado(estadoCache);
+    }
+    return { email: cached.email, ip };
+  }
```

Y se extrae el mapeo de estado a mensaje, que hoy está repetido en el
camino frío, para no duplicarlo:

```diff
+function mensajeEstado(estado: string): Response {
+  if (estado === "pausado") return json(403, "El geoportal está temporalmente fuera de servicio.");
+  if (estado === "fuera_horario") return json(403, "El geoportal está disponible de 7:50 a. m. a 6:00 p. m.");
+  return json(403, "Usuario no autorizado en el geoportal.");
+}
```

El camino frío pasa a usar el mismo helper, conservando sus tres
`registrar(...)` de auditoría tal como están.

## La alternativa barata, por si prefieres no redesplegar

Cambiar una sola constante:

```diff
-const TTL_MS = 5 * 60 * 1000; // 5 minutos
+const TTL_MS = 30 * 1000;     // 30 segundos
```

Baja la ventana de 5 min a 30 s sin añadir ni un RPC. No cierra el
agujero, lo estrecha diez veces. Requiere el mismo redespliegue, así que
el ahorro es de riesgo, no de trabajo.

## El coste del redespliegue

`_shared/auth.ts` lo importan **las 13 funciones**, así que hay que
redesplegarlas todas. Dos consideraciones:

- **Es el guardián de todo el sistema.** Un error aquí deja fuera a los
  39 usuarios. El cambio son ~12 líneas y no toca la ruta de validación
  del JWT ni los dominios.
- **Ahora es reversible.** Hasta ayer `~/geoportal-web` no tenía control
  de versiones; desde el commit inicial de hoy sí, así que volver atrás
  es un `git revert` más un redespliegue.

Sugerencia de orden: desplegar primero **una sola** función de bajo
tráfico (`geoportal-rutas-lista`), comprobar que autoriza y que la pausa
la corta al instante, y solo entonces las doce restantes.

## Recomendación

La revalidación siempre. La pausa global es un control de emergencia y
existe precisamente para los momentos en que cinco minutos importan; el
caché seguirá evitando la llamada cara, que es para lo que se puso.

Si el coste por tesela preocupa, la variante mixta es defendible:
revalidar siempre en las doce funciones y dejar `geoportal-tiles` con TTL
de 30 s. Pero añade una excepción que hay que recordar, y la tesela es
justo el camino por el que se fuga más dato — así que no la recomiendo.
