<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Roles con acceso al panel Filament (/admin)
    |--------------------------------------------------------------------------
    |
    | Un usuario debe tener al menos uno de estos roles (Spatie) para ingresar
    | al panel administrativo. No se concede acceso por defecto al crear usuarios.
    |
    */
    'filament_panel_roles' => [
        'super-admin',
        'administrador-municipal',
    ],

    /*
    |--------------------------------------------------------------------------
    | Publicaciones (Fase 3)
    |--------------------------------------------------------------------------
    */
    'chat' => [
        'max_message_length' => 4000,
        'edit_window_minutes' => 15,
    ],

    /*
    |--------------------------------------------------------------------------
    | Autenticación app móvil (Sanctum, Fase 5.2)
    |--------------------------------------------------------------------------
    |
    | La expiración se aplica solo a tokens creados vía POST /auth/login (expires_at
    | por token). No modifica config/sanctum.php → expiration (null conserva
    | smoke tests y tokens emitidos sin expires_at).
    */
    'membership_requests' => [
        'rejection_cooldown_days' => (int) env('MEMBERSHIP_REQUEST_COOLDOWN_DAYS', 7),
        'store_per_user_per_hour' => (int) env('MEMBERSHIP_REQUEST_STORE_PER_HOUR', 20),
    ],

    'mobile_auth' => [
        'token_expiration_days' => (int) env('MOBILE_TOKEN_EXPIRATION_DAYS', 90),
        'login_attempts_per_identity_per_minute' => 5,
        'login_attempts_per_ip_per_minute' => 30,
    ],

    'posts' => [
        'max_attachments_per_revision' => 5,
        'max_attachment_size_kb' => 5120,
        'allowed_attachment_mimes' => [
            'image/jpeg',
            'image/png',
            'image/webp',
            'application/pdf',
        ],
        'disk' => env('POSTS_FILESYSTEM_DISK', 'posts_private'),
    ],

];
