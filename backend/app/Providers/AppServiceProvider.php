<?php

namespace App\Providers;

use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Municipality\Observers\MunicipalityMemberObserver;
use App\Domains\Municipality\Policies\MunicipalityMemberPolicy;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Policies\GroupMemberPolicy;
use App\Domains\Neighborhoods\Policies\NeighborhoodGroupPolicy;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatMessageReport;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Policies\ChatMessagePolicy;
use App\Domains\Chat\Policies\ChatMessageReportPolicy;
use App\Domains\Chat\Policies\ChatRoomPolicy;
use App\Domains\Neighborhoods\Observers\NeighborhoodGroupChatObserver;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Policies\PostPolicy;
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
        $this->app->booted(function (): void {
            $channels = base_path('routes/channels.php');
            if (file_exists($channels)) {
                require $channels;
            }
        });

        Gate::policy(NeighborhoodGroup::class, NeighborhoodGroupPolicy::class);
        Gate::policy(GroupMember::class, GroupMemberPolicy::class);
        Gate::policy(MunicipalityMember::class, MunicipalityMemberPolicy::class);
        Gate::policy(Post::class, PostPolicy::class);
        Gate::policy(ChatRoom::class, ChatRoomPolicy::class);
        Gate::policy(ChatMessage::class, ChatMessagePolicy::class);
        Gate::policy(ChatMessageReport::class, ChatMessageReportPolicy::class);

        MunicipalityMember::observe(MunicipalityMemberObserver::class);
        NeighborhoodGroup::observe(NeighborhoodGroupChatObserver::class);
    }
}
