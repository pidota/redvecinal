# Moderación de contenido — Fase 3

## Reglas

- La aprobación de propuestas vecinales la realizan **presidente o moderador activo** de la misma junta.
- **Prohibida** la autoaprobación (`author_id === reviewer`).
- Los **administradores municipales** supervisan, ocultan y archivan; **no aprueban** propuestas comunitarias.
- Juntas suspendidas/inactivas: sin nuevas publicaciones ni aprobaciones.

## Auditoría

Eventos en `post_moderation_events` y eventos Laravel (`PostRevisionSubmitted`, `PostRevisionApproved`, etc.) para futuras notificaciones.

## Panel

- Cola de moderación: solo lectura municipal.
- Reportes: resolución desde Filament.
