<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_rooms', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('municipality_id');
            $table->unsignedBigInteger('neighborhood_group_id');
            $table->string('type', 30);
            $table->string('status', 30);
            $table->timestamps();

            $table->unique('neighborhood_group_id');
            $table->unique(['municipality_id', 'id'], 'chat_rooms_municipality_id_id_unique');
            $table->index('municipality_id');

            $table->foreign('municipality_id')->references('id')->on('municipalities')->restrictOnDelete();
            $table->foreign(['neighborhood_group_id', 'municipality_id'], 'chat_rooms_group_municipality_fk')
                ->references(['id', 'municipality_id'])
                ->on('neighborhood_groups')
                ->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_rooms');
    }
};
