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
