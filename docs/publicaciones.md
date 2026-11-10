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

Rutas bajo `/api/v1/posts*` (Sanctum obligatorio). Ver `backend/routes/api.php`.
