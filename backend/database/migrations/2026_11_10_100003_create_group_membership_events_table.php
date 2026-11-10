<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('group_membership_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('group_member_id')->constrained('group_members')->cascadeOnDelete();
            $table->foreignId('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('event', 64);
            $table->json('payload')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['group_member_id', 'event']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('group_membership_events');
    }
};
