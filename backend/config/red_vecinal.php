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
