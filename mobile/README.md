# Red Vecinal — app móvil (Flutter)

Cliente comunitario para la API Laravel (`/api/v1`). **Fase 5.2B:** autenticación Sanctum. **5.3.x–5.4F-5B:** juntas, feed, edición propia y moderación comunitaria móvil (ver secciones siguientes). Chat sigue pendiente de integración Reverb.

## Requisitos

- Flutter 3.29+ (Dart 3.7+)
- Android SDK (desarrollo principal)
- Xcode solo si se compila para iOS

Verificar:

```bash
flutter --version
flutter doctor
```

## Instalación

```bash
cd mobile
flutter pub get
```

## Ejecución

### Chrome (validación visual Fase 5.1)

Útil cuando no hay emulador Android. Solo desarrollo local; **no sustituye** pruebas en dispositivo real.

```bash
cd mobile
flutter devices          # debe listar Chrome
flutter run -d chrome
# puerto fijo opcional:
flutter run -d chrome --web-port=7357
```

**Chrome DevTools (F12):**

1. Activar barra de dispositivos (**Toggle device toolbar**, `Ctrl+Shift+M`).
2. Probar resoluciones: 320×568, 390×844, 430×932, 768×1024.
3. Revisar consola: no deben aparecer errores rojos al navegar entre rutas.

Rutas directas (estrategia path, sin `#`):

- `/splash`, `/login`
- `/home`, `/neighborhoods`, `/posts`, `/chat`, `/profile`
- `/neighborhoods/{id}` (detalle de junta, sin barra inferior)

**Limitaciones Web:** el lienzo Flutter expone poca accesibilidad DOM; los clics en la barra inferior se validan mejor con `flutter test` o manualmente en Chrome. Reverb, almacenamiento seguro y plugins nativos pueden comportarse distinto que en Android.

Compilación de comprobación:

```bash
flutter build web
```

No desplegar `build/web` a Internet sin autorización.

### Android (objetivo de producción)

```bash
cd mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2/api/v1
```

En **emulador Android**, `10.0.2.2` apunta al localhost de Windows (ajusta puerto/vhost si Laragon usa otro host).

En **dispositivo físico**, usa la IP LAN del PC, por ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.50/api/v1
```

Laragon local (misma máquina, Chrome o build web contra backend):

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://red-vecinal.test/api/v1
```

El build **debug** Android permite HTTP cleartext solo en desarrollo (`android/app/src/debug/AndroidManifest.xml`).

### Variables de entorno (`--dart-define`)

| Define | Valor por defecto | Uso |
|--------|-------------------|-----|
| `APP_ENV` | `development` | Etiqueta de entorno |
| `APP_NAME` | `Red Vecinal` | Título de la app |
| `API_BASE_URL` | *(vacío)* | Base API con sufijo `/api/v1` (obligatorio para login real) |

Ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://red-vecinal.test/api/v1
```

No incluir secretos ni contraseñas en el código.

### Autenticación (5.2B)

- Endpoints: `POST /auth/login`, `GET /me`, `POST /auth/logout` (ver `docs/mobile-auth-api.md` en el repo).
- Token Bearer en **flutter_secure_storage** (Android/iOS).
- **Web:** solo memoria RAM; al recargar la página no hay sesión persistente (no se usa `localStorage`).
- Tras login fallido por red al restaurar sesión: pantalla **Reintentar** (`/session-retry`) sin borrar el token.
- `401` en rutas autenticadas cierra sesión local; `403` no cierra sesión.

## Estructura `lib/`

```text
core/         # config, theme, routing, network (Dio), storage (token seguro)
features/     # auth, home, neighborhoods, posts, chat, profile
shared/       # widgets reutilizables
app.dart
main.dart
```

## Dependencias

- `flutter_riverpod` — estado global (sesión auth)
- `go_router` — rutas protegidas y `StatefulShellRoute`
- `dio` — cliente HTTP
- `flutter_secure_storage` — token Sanctum en móvil nativo

Pendiente: Reverb, caché offline, etc.

## Pruebas

```bash
flutter analyze
flutter test
```

### Integración continua (GitHub Actions)

En cada **push** o **pull request** hacia `main`, el workflow **Flutter tests** (`.github/workflows/flutter-tests.yml`) ejecuta en `ubuntu-latest` con **Flutter 3.29.2** (stable):

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`

Solo pruebas unitarias y de widgets; sin emulador Android, sin compilación APK ni despliegue.

### Validación REST local (5.2B)

Scripts **solo desarrollo**: no ejecutar contra producción. El usuario de prueba usa correo `flutter-e2e-*@red-vecinal.test` y contraseña aleatoria (nunca credenciales reales).

**Preparar fixture** (desde la raíz del repo, con Laragon/`.env` local):

```bash
cd backend
php scripts/dev/flutter-e2e/prepare-user.php
```

Crea un vecino con junta activa y guarda credenciales en `mobile/scripts/.flutter-e2e-credentials.json` (gitignored).

**Ejecutar smoke** (login, `/me`, logout, token revocado, credenciales incorrectas):

```bash
php mobile/scripts/rest_smoke.php
# opcional: API_BASE_URL=http://10.0.2.2/api/v1 php mobile/scripts/rest_smoke.php
```

No imprime tokens completos ni contraseñas.

**Limpiar fixture** (solo elimina usuarios `flutter-e2e-*@red-vecinal.test`):

```bash
cd backend
php scripts/dev/flutter-e2e/cleanup-user.php
```

### JDK / compilación Android

Gradle (AGP actual) requiere **JDK 17+**. Si `flutter doctor` muestra Java 11, apunte Flutter al JDK 17 sin modificar el proyecto:

```bash
flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.14.7-hotspot"
flutter build apk --debug
```

Ajuste la ruta según su instalación. No se descargan JDK automáticamente desde el repo.

## Fase 5.4F-4C — Edición de publicaciones propias

Flujo en app: **Mis publicaciones** (ruta `go_router` `/posts/mine`) → editor `/posts/:id/edit` → PATCH contenido → adjuntos (`revision_id` en multipart) → submit a moderación (borrador o rechazada).

Contratos API usados por el cliente (base `API_BASE_URL` = `…/api/v1`):

| Acción | Método y ruta |
|--------|----------------|
| Detalle | `GET /posts/{id}` |
| Mis publicaciones | **`GET /me/posts`** (paginado; no usar `/posts/mine` como endpoint REST) |
| Guardar contenido | `PATCH /posts/{id}` |
| Adjuntar archivo | `POST /posts/{id}/attachments` (`revision_id` + `file`) |
| Enviar a moderación | `POST /posts/{id}/submit` (sin body) |

Estados editables en app: `draft` y `rejected`. Tras submit exitoso el post pasa a `pending` y el editor deja de ser editable.

## Moderación de publicaciones comunitarias (5.4F-5B)

Flujo para **presidentes y moderadores** autorizados por el backend (no inferidos solo desde la app).

### Flujo de usuario

1. **Mis juntas** → detalle de junta (`/neighborhoods/{groupId}`).
2. Si la junta está **activa** y el sondeo de permiso lo permite, aparece **Moderar publicaciones**.
3. Cola de pendientes (`/neighborhoods/{groupId}/posts/pending?groupName=…`).
4. Detalle de revisión (`/neighborhoods/{groupId}/posts/pending/{postId}`).
5. **Aprobar** o **Rechazar** (con confirmación y reglas de concurrencia).
6. Volver a la cola o al detalle de junta (`go_router` / `parentNavigatorKey`).

También se puede abrir la cola por **deep link**; la autorización definitiva la valida el backend en cada pantalla.

### Roles autorizados (backend)

- Quién puede moderar lo define **PostPolicy** en Laravel (presidente/moderador activos de la junta, etc.).
- El cliente **no** recibe rol comunitario en `GET /me/groups` ni en el detalle de junta.
- Un miembro normal no debe ver la entrada si el sondeo responde **403**.

### Endpoints utilizados

| Acción | Método y ruta |
|--------|----------------|
| Sondeo / cola (pág. 1+) | `GET /groups/{groupId}/posts/pending?page=` |
| Detalle en moderación | `GET /posts/{postId}` |
| Aprobar | `POST /posts/{postId}/approve` (sin body en el cliente actual) |
| Rechazar | `POST /posts/{postId}/reject` (`rejection_reason` obligatorio) |

Otros usados en el mismo dominio: `GET /me/groups`, `GET /groups/{id}` (detalle de junta).

### Propuestas nuevas vs enmiendas

- La cola puede incluir publicaciones nuevas en revisión y **enmiendas** de contenido ya publicado.
- El modelo parsea `pending_content`, adjuntos pendientes y título pendiente; entradas sin contenido pendiente válido se **omiten** de la lista (con `debugPrint` solo en modo debug).

### Aprobación y rechazo

- **Aprobar:** confirmación, bloqueo mutuo con rechazo, `ref.keepAlive()` durante el POST.
- **Rechazar:** diálogo con motivo obligatorio (validación local + 422 del servidor).

### Motivo obligatorio de rechazo

- Longitud y vacío validados en cliente (`validatePostRejectionReason`).
- El motivo se envía en el POST; **no** se persiste en almacenamiento local tras cerrar sesión.

### Exclusión mutua

- Durante approve o reject en curso, la otra acción queda deshabilitada en UI y controlador (`_activeDecisionGeneration`).

### Incertidumbre y reconciliación

- Tras POST con resultado ambiguo (red/timeout), se registra estado **incierto** en memoria (`PostModerationUncertainApprovePersistence`), atado a `userId` + `sessionEpoch`.
- La UI ofrece reconciliación (reconsultar `GET /posts/{id}`) antes de permitir otra decisión.
- **No** hay reintentos automáticos de POST ambiguos.

### Seguridad de sesión

- Controladores de cola, detalle y descubrimiento usan `neighborhoodSessionEpoch` (y `authController` donde aplica).
- Tras `await`, se descartan respuestas si cambió la sesión o el usuario.
- Logout limpia persistencia incierta de moderación en memoria.

### Descubrimiento desde detalle de junta (5B.8)

**Contratos insuficientes para permisos locales:**

- `GET /me/groups` devuelve junta (`id`, `name`, `status`, etc.) **sin** rol de membresía.
- **`GET /me/reviewable-groups` NO debe usarse** para moderación de publicaciones (solo solicitudes de incorporación).

**Sondeo autorizado (una junta, página 1):**

- Si `status == active`, el cliente llama una vez a `GET /groups/{id}/posts/pending?page=1`.
- **200:** mostrar entrada «Moderar publicaciones».
- **403 / 404:** no mostrar entrada.
- **Red / timeout / 5xx:** autorización **indeterminada**; la entrada permanece oculta (el usuario aún puede llegar por deep link; la cola aplicará 403/404).

El **backend sigue siendo la autoridad definitiva** en cola, detalle y decisiones.

### Riesgos residuales (no resueltos en app)

| ID | Descripción |
|----|-------------|
| **MOD-08** | `approve` / `reject` no envían `revision_id`; el cliente no puede garantizar que la revisión procesada sea exactamente la mostrada en pantalla. |
| MOD-09 | Al abrir la cola desde detalle: posible **doble GET** (sondeo + carga de `PostPendingQueueController`). |
| MOD-10 | Fallo de red en sondeo oculta la entrada aunque el usuario sea moderador. |
| MOD-11 | Reconciliación sin atribución causal perfecta del resultado del POST. |
| MOD-12 | Sin E2E real multiinstancia Android en CI (solo `flutter test` en Ubuntu). |

## Reportes de publicaciones — Fase 5.4F-5C / 5E.4

Flujo para **vecinos autenticados** que reportan una publicación comunitaria publicada. El cliente no afirma resolución ni moderación automática.

### Funcionalidad

1. En el detalle de una publicación **publicada**, con sesión activa, aparece **Reportar publicación**.
2. El formulario ofrece motivos **locales** `spam` e `inappropriate` (catálogo provisional de la app; no es un enum municipal ni un catálogo oficial del backend).
3. El campo **Detalles** es opcional (máx. 2000 caracteres; no se trunca en silencio).
4. **Enviar reporte** abre una confirmación explícita. El POST **no** se ejecuta al validar, navegar ni reconstruir widgets.
5. Tras confirmar, un único `POST` con cabecera `Idempotency-Key` (UUID v4 persistida antes del envío). Si el servidor responde **HTTP 201** con `{ id, status }`, la app muestra «Reporte recibido» y no exhibe el identificador interno.

### Contrato

`POST /api/v1/posts/{post}/reports`

Request:

```json
{
  "reason_code": "spam",
  "details": "Contenido dudoso"
}
```

`details` se omite si el vecino no escribe nada. Cabecera `Idempotency-Key: <uuid-v4>`. Flutter **no** envía `reporter_id` ni `user_id`; el backend atribuye el reporte al token Sanctum.

Response (201):

```json
{
  "id": 42,
  "status": "open"
}
```

### Seguridad

- Autenticación **Sanctum**; el backend (PostPolicy) es la autoridad de quién puede reportar.
- Un POST por intento: sin reintentos automáticos en Dio, repositorio ni controlador.
- Exclusión compartida por **usuario autenticado + publicación** (coordinador, no un booleano del widget).
- Protección de sesión (`neighborhoodSessionEpoch`): un resultado tardío no se muestra como éxito en otra sesión.
- La marca `inFlight` se persiste **antes** de despachar el POST. Si esa escritura falla, **no** se envía.
- Si el almacenamiento local no puede interpretarse de forma fiable (JSON corrupto o un registro ilegible), se bloquean nuevos POST. No se ignoran registros malformados ni se convierte la corrupción en lista vacía.

### Incertidumbre

Tras despachar el POST, timeout, error de red, HTTP 5xx o un 201 malformado **no** demuestran que el servidor haya rechazado la creación. La app:

- registra estado local **uncertain** con la UUID y el payload originales;
- muestra **Comprobar envío** (replay explícito, misma clave y mismo contenido; el servidor puede crear el reporte si el primero nunca llegó);
- **no** reintenta al arrancar ni desde Dio;
- **no** reconcilia con un GET ficticio.

Los registros **v1** inciertos (sin UUID) siguen bloqueados y no se recuperan. 409 deja el intento en conflicto. 401/403/404 y un 422 de `reason_code`/`details` o de clave inválida reconocible no son éxito y **liberan** el vuelo. Un 422 genérico, 429 o respuesta de proxy se tratan como **uncertain** (misma UUID).

### Persistencia local

Almacén `rv_post_report_outcomes_v2` (schema 2). Antes del POST: `userId`, `postId`, UUID, `reason_code`, `details`, estado, `generation`, `recordedAt`. El 201 se persiste como `confirmed` **con** payload; después se borran UUID/`reason_code`/`details` (se conserva `reportId`). Si esa limpieza falla, el estado sigue `confirmed` (bloquea duplicados) y la hidratación posterior reintenta el borrado. El almacenamiento seguro reduce el acceso casual; no impide todo acceso al dispositivo. Sin token ni body HTTP completo.

Migración: si no hay v2 se lee `rv_post_report_outcomes_v1`. `confirmed` se conserva. `uncertain`/`inFlight` sin clave **no** reciben UUID inventada. v1 no se elimina.

En **web** el almacén es en memoria (se pierde al recargar; la recuperación vale solo mientras el intento sigue en esa sesión). En Android/iOS se usa almacenamiento seguro. No se degrada el móvil para igualar web.

### Limitaciones

- El backend es idempotente **solo** con `Idempotency-Key`. Sin cabecera, cada POST crea un reporte. No hay `UNIQUE(reporter_id, post_id)`.
- Otro dispositivo, o borrar los datos de la aplicación, elimina las marcas locales.
- No hay endpoint para consultar si el vecino ya reportó.
- Filament gestiona reportes en 5D; el catálogo de motivos de la app es provisional y local.

### Riesgos residuales

| ID | Descripción |
|----|-------------|
| RPT-P0-01 | Mitigado en un mismo dispositivo con clave persistida; otro dispositivo puede crear otro reporte. |
| RPT-5C5-R1 | Si falla persistir `inFlight` **antes** del POST, no se envía. |
| RPT-WEB | En web no hay persistencia entre recargas. |
| RPT-LEGACY | Intentos inciertos v1 no se pueden comprobar. |
| RPT-MYSQL | La carrera InnoDB a dos procesos **no** se ha ejecutado en CI. |

## Subfases pendientes

| Subfase | Contenido |
|---------|-----------|
| 5.2 | Autenticación Sanctum (completada en app) |
| 5.3.1 | Mis juntas (`GET /me/groups`) |
| 5.3.2+ | Explorar, detalle, integrantes |
| 5.4 | Publicaciones (feed, detalle, edición propia; moderación 5.4F-5B en app) |
| 5.5 | Chat + Reverb |
| 5.6 | Integración, pruebas E2E, estabilización |

## Android

Identificador provisional de paquete: `cl.redvecinal.red_vecinal` (revisar antes de publicación en tiendas).

HTTP cleartext solo en **debug** Android para desarrollo local.
