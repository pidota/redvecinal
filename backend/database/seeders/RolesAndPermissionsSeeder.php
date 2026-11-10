<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;

class RolesAndPermissionsSeeder extends Seeder
{
    public const PERMISSIONS = [
        'municipalities.view',
        'neighborhood-groups.view',
        'neighborhood-groups.create',
        'neighborhood-groups.update',
        'neighborhood-groups.delete',
        'group-members.view',
        'group-members.create',
        'group-members.approve',
        'group-members.update',
        'group-members.suspend',
        'group-presidents.assign',
    ];

    public const ROLES = [
        'super-admin',
        'administrador-municipal',
        'presidente-junta',
        'moderador-junta',
        'vecino',
    ];

    public function run(): void
    {
        app(PermissionRegistrar::class)->forgetCachedPermissions();

        foreach (self::PERMISSIONS as $permission) {
            Permission::findOrCreate($permission, 'web');
        }

        $superAdmin = Role::findOrCreate('super-admin', 'web');
        $superAdmin->syncPermissions(self::PERMISSIONS);

        $municipalAdmin = Role::findOrCreate('administrador-municipal', 'web');
        $municipalAdmin->syncPermissions([
            'municipalities.view',
            'neighborhood-groups.view',
            'neighborhood-groups.create',
            'neighborhood-groups.update',
            'neighborhood-groups.delete',
            'group-members.view',
            'group-members.create',
            'group-members.approve',
            'group-members.update',
            'group-members.suspend',
            'group-presidents.assign',
        ]);

        Role::findOrCreate('presidente-junta', 'web');
        Role::findOrCreate('moderador-junta', 'web');
        Role::findOrCreate('vecino', 'web');
    }
}
