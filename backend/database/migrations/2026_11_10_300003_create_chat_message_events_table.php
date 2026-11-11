<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_message_events', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('municipality_id');
            $table->unsignedBigInteger('chat_message_id');
            $table->unsignedBigInteger('chat_room_id');
            $table->foreignId('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('event', 60);
            $table->string('from_status', 30)->nullable();
            $table->string('to_status', 30)->nullable();
            $table->json('payload')->nullable();
            $table->timestamp('created_at');

            $table->index(['chat_room_id', 'created_at']);
            $table->index(['chat_message_id', 'event']);

            $table->foreign('municipality_id')->references('id')->on('municipalities')->restrictOnDelete();
            $table->foreign(['municipality_id', 'chat_message_id'], 'chat_message_events_message_municipality_fk')
                ->references(['municipality_id', 'id'])
                ->on('chat_messages')
                ->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_message_events');
    }
};
