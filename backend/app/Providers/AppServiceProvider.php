<?php

namespace App\Providers;

use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Municipality\Observers\MunicipalityMemberObserver;
use App\Domains\Municipality\Policies\MunicipalityMemberPolicy;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Policies\GroupMemberPolicy;
use App\Domains\Neighborhoods\Policies\NeighborhoodGroupPolicy;
use App\Domains\Neighborhoods\Policies\NeighborhoodMembershipRequestPolicy;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatMessageReport;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Policies\ChatMessagePolicy;
use App\Domains\Chat\Policies\ChatMessageReportPolicy;
use App\Domains\Chat\Policies\ChatRoomPolicy;
use App\Domains\Neighborhoods\Observers\NeighborhoodGroupChatObserver;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Policies\PostPolicy;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;

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
        RateLimiter::for('membership-requests', function (Request $request) {
            $perUser = config('red_vecinal.membership_requests.store_per_user_per_hour', 20);

            return Limit::perHour($perUser)->by('membership-requests|'.$request->user()?->id.'|'.$request->ip());
        });

        RateLimiter::for('mobile-login', function (Request $request): array {
            $perIdentity = config('red_vecinal.mobile_auth.login_attempts_per_identity_per_minute', 5);
            $perIp = config('red_vecinal.mobile_auth.login_attempts_per_ip_per_minute', 30);
            $email = Str::lower(trim((string) $request->input('email')));

            return [
                Limit::perMinute($perIdentity)->by('mobile-login|'.$email.'|'.$request->ip()),
                Limit::perMinute($perIp)->by('mobile-login|ip|'.$request->ip()),
            ];
        });

        $this->app->booted(function (): void {
            $channels = base_path('routes/channels.php');
            if (file_exists($channels)) {
                require $channels;
            }
        });

        Gate::policy(NeighborhoodGroup::class, NeighborhoodGroupPolicy::class);
        Gate::policy(GroupMember::class, GroupMemberPolicy::class);
        Gate::policy(NeighborhoodMembershipRequest::class, NeighborhoodMembershipRequestPolicy::class);
        Gate::policy(MunicipalityMember::class, MunicipalityMemberPolicy::class);
        Gate::policy(Post::class, PostPolicy::class);
        Gate::policy(ChatRoom::class, ChatRoomPolicy::class);
        Gate::policy(ChatMessage::class, ChatMessagePolicy::class);
        Gate::policy(ChatMessageReport::class, ChatMessageReportPolicy::class);

        MunicipalityMember::observe(MunicipalityMemberObserver::class);
        NeighborhoodGroup::observe(NeighborhoodGroupChatObserver::class);
    }
}
