<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_messages', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('municipality_id');
            $table->unsignedBigInteger('chat_room_id');
            $table->foreignId('sender_id')->constrained('users')->restrictOnDelete();
            $table->text('body');
            $table->string('status', 30);
            $table->uuid('client_message_id')->nullable();
            $table->unsignedBigInteger('version')->default(1);
            $table->timestamp('edited_at')->nullable();
            $table->timestamp('deleted_at')->nullable();
            $table->timestamps();

            $table->unique(['municipality_id', 'id'], 'chat_messages_municipality_id_id_unique');
            $table->unique(['chat_room_id', 'sender_id', 'client_message_id'], 'chat_messages_client_idempotency_unique');
            $table->index(['chat_room_id', 'id']);
            $table->index(['chat_room_id', 'created_at', 'id']);
            $table->index(['chat_room_id', 'status', 'id']);

            $table->foreign(['municipality_id', 'chat_room_id'], 'chat_messages_room_municipality_fk')
                ->references(['municipality_id', 'id'])
                ->on('chat_rooms')
                ->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_messages');
    }
};
