# Publicaciones comunitarias — Fase 3

## Dominio

Código en `App\Domains\Posts`. El contenido vive en **revisiones** (`post_revisions`); la publicación (`posts`) conserva el estado global y la revisión visible.

## Flujos

- Vecino: borrador → enviar → `pending` → aprobación de presidente/moderador ajeno → `published`.
- Presidente/moderador: publicación directa auditable (`published_direct`).
- Municipal: comunicados solo desde Filament (`PublishOfficialPostService`).
- Cambios sobre contenido ya publicado: nueva revisión en `pending`; el post permanece `published` hasta aprobar la enmienda.

## Formato

Markdown en `body`; la API expone `body_html` generado con renderizado seguro.

## Adjuntos

Hasta 5 archivos por revisión, 5 MB c/u (`config/red_vecinal.php`). Vinculados a `post_revision_id`.

## API

Rutas bajo `/api/v1/posts*` y catálogo `/api/v1/post-categories` (Sanctum obligatorio). Ver `backend/routes/api.php`.

### Catálogo de categorías

`GET /api/v1/post-categories` — solo lectura. Autorización: `PostPolicy::viewAny` (misma base que el feed). Devuelve categorías **activas** del ámbito global y de municipios donde el usuario tiene membresía de junta activa. Filtro opcional: `?audience=group|municipal`. Orden: `sort_order`, `name`.

### Respuesta enriquecida (`PostResource`)

Los campos originales se conservan. Adiciones (Fase 5.4B-2):

| Campo | Descripción |
|--------|-------------|
| `post_kind` | `community` o `municipal` |
| `author` | `{ id, name }` (sin email) |
| `neighborhood_group` | `{ id, name, slug }` o `null` si es municipal |
| `category` | `{ id, slug, name }` |
| `municipality` | `{ id, name, slug }` |
| `engagement` | `comments_count` (solo comentarios visibles), `reactions_count`, `my_reaction` (`null` o `{ type }`) |
| `attachments` | Metadatos de la revisión de contenido autorizada (publicada o borrador del autor) |
| `pending_attachments` | Solo si `pending_content` es visible para el usuario |

Cada adjunto en JSON:

```json
{
  "id": 7,
  "revision_id": 5,
  "original_display_name": "informe.pdf",
  "mime_type": "application/pdf",
  "size_bytes": 102400,
  "download_url": "/api/v1/posts/1/attachments/7"
}
```

`download_url` apunta al endpoint autenticado existente; no hay URLs públicas al disco. Descarga sigue gobernada por `PostPolicy::viewAttachment`.

### Ejemplo (fragmento)

```json
{
  "id": 1,
  "status": "published",
  "post_kind": "community",
  "author": { "id": 10, "name": "María" },
  "neighborhood_group": { "id": 2, "name": "Junta Centro", "slug": "junta-centro" },
  "category": { "id": 2, "slug": "aviso-comunitario", "name": "Aviso comunitario" },
  "municipality": { "id": 1, "name": "Chépica", "slug": "chepica" },
  "engagement": {
    "comments_count": 3,
    "reactions_count": 5,
    "my_reaction": { "type": "like" }
  },
  "attachments": [],
  "pending_attachments": [],
  "content": { "revision_id": 5, "title": "…", "body": "…", "body_html": "…", "category_id": 2 }
}
```

**Compatibilidad:** cambios aditivos; clientes que ignoran claves nuevas siguen funcionando. Paginación Laravel sin cambios (`data`, `links`, `meta`).

### Comentarios (engagement)

Rutas Sanctum obligatorio. Autorización de lectura: `PostPolicy::view` (post invisible → **404**). Escritura: `PostPolicy::comment` (fallo → **403**).

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/posts/{post}/comments` | Lista paginada de comentarios `visible`, orden `created_at` ascendente |
| `POST` | `/api/v1/posts/{post}/comments` | Crea comentario visible (`AddCommentService`) |

**GET — paginación:** respuesta estándar Laravel (`data`, `links`, `meta`; tamaño de página por defecto del framework).

**Elemento en `data` (`PostCommentResource`):**

```json
{
  "id": 15,
  "post_id": 1,
  "municipality_id": 1,
  "author_id": 10,
  "author": { "id": 10, "name": "María" },
  "body": "Texto del comentario",
  "status": "visible",
  "created_at": "2026-11-14T12:00:00+00:00",
  "updated_at": "2026-11-14T12:00:00+00:00"
}
```

- `author` incluye solo `id` y `name` (sin email ni datos sensibles).
- Se conservan `post_id`, `municipality_id`, `author_id` y `status` por compatibilidad con el contrato plano anterior.
- Solo se listan comentarios con `status = visible`.

**POST — cuerpo:**

```json
{ "body": "Texto requerido, máximo 5000 caracteres" }
```

**POST — respuesta:** **201** con un único objeto bajo `data` (mismo esquema que arriba; el autor va precargado).

**Errores esperados:**

| Código | Situación |
|--------|-----------|
| **401** | Sin token |
| **403** | Sin permiso `comment` (`authorize`) |
| **422** | Validación de `body` o regla de dominio posts (`PostDomainException` → JSON `{ "message" }`) |
| **404** | Sin permiso `view` del post |
Los contadores `engagement.comments_count` en `PostResource` siguen contando solo comentarios visibles.
