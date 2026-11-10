# Acceso al panel Filament (`/admin`)

## Principio

No todo usuario autenticado puede entrar al panel. El modelo `User` implementa `FilamentUser` y define `canAccessPanel()` según **roles Spatie**, configurados en `config/red_vecinal.php`.

## Roles habilitados (Fase 1)

| Rol | Uso previsto |
|-----|----------------|
| `super-admin` | Administración técnica / plataforma |
| `administrador-municipal` | Personal municipal con acceso al backoffice |

Lista editable en `backend/config/red_vecinal.php` → `filament_panel_roles`.

## Flujo recomendado al crear un administrador

1. Crear el usuario (sin contraseñas por defecto en código):
   ```bash
   cd D:\laragon\www\red-vecinal\backend
   php artisan make:filament-user
   ```
2. Asignar rol en Tinker o desde un seeder controlado en Fase 2:
   ```php
   $user = User::where('email', '...')->first();
   $user->assignRole('administrador-municipal');
   ```

## Roles y permisos (Fase 2)

- Definir permisos granulares (`municipality.view`, etc.) y agruparlos en roles.
- **No** asignar `super-admin` salvo personal autorizado.
- Usuarios de API móvil (Sanctum) normalmente **no** llevan roles de panel.

## Registro público

El panel solo expone `->login()`; no hay registro abierto de administradores.
