<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CreateNeighborhoodGroupService
{
    public function execute(Municipality $municipality, array $data): NeighborhoodGroup
    {
        $slug = $data['slug'] ?? Str::slug($data['name']);

        if (NeighborhoodGroup::withTrashed()
            ->where('municipality_id', $municipality->id)
            ->where('slug', $slug)
            ->exists()) {
            throw ValidationException::withMessages([
                'slug' => 'Ya existe una junta con este identificador en la municipalidad.',
            ]);
        }

        return NeighborhoodGroup::query()->create([
            'municipality_id' => $municipality->id,
            'name' => $data['name'],
            'slug' => $slug,
            'registration_number' => $data['registration_number'] ?? null,
            'description' => $data['description'] ?? null,
            'address' => $data['address'] ?? null,
            'contact_email' => $data['contact_email'] ?? null,
            'contact_phone' => $data['contact_phone'] ?? null,
            'status' => $data['status'] ?? NeighborhoodGroupStatus::Active,
            'settings' => $data['settings'] ?? null,
        ]);
    }
}
