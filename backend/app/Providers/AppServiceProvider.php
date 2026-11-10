<?php

namespace App\Providers;

use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Municipality\Observers\MunicipalityMemberObserver;
use App\Domains\Municipality\Policies\MunicipalityMemberPolicy;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Policies\GroupMemberPolicy;
use App\Domains\Neighborhoods\Policies\NeighborhoodGroupPolicy;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Gate::policy(NeighborhoodGroup::class, NeighborhoodGroupPolicy::class);
        Gate::policy(GroupMember::class, GroupMemberPolicy::class);
        Gate::policy(MunicipalityMember::class, MunicipalityMemberPolicy::class);

        MunicipalityMember::observe(MunicipalityMemberObserver::class);
    }
}
