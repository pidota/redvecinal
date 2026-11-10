<?php

namespace Tests\Concerns;

use App\Models\User;
use Filament\Facades\Filament;

trait InteractsWithFilamentPanel
{
    protected function authenticateForFilament(User $user): void
    {
        $this->actingAs($user);
        Filament::setCurrentPanel(Filament::getPanel('admin'));
        Filament::auth()->login($user);
    }
}
