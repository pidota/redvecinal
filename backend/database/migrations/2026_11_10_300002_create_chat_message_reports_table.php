<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_message_reports', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('municipality_id');
            $table->unsignedBigInteger('chat_message_id');
            $table->foreignId('reporter_id')->constrained('users')->restrictOnDelete();
            $table->string('reason_code', 60);
            $table->text('details')->nullable();
            $table->string('status', 30);
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->text('resolution_note')->nullable();
            $table->timestamps();

            $table->index(['municipality_id', 'status']);
            $table->unique(['chat_message_id', 'reporter_id'], 'chat_message_reports_message_reporter_unique');

            $table->foreign('municipality_id')->references('id')->on('municipalities')->restrictOnDelete();
            $table->foreign(['municipality_id', 'chat_message_id'], 'chat_message_reports_message_municipality_fk')
                ->references(['municipality_id', 'id'])
                ->on('chat_messages')
                ->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_message_reports');
    }
};
