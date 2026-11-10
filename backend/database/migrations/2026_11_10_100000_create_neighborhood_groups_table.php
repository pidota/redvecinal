<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('neighborhood_groups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('municipality_id')->constrained('municipalities')->restrictOnDelete();
            $table->string('name', 180);
            $table->string('slug', 180);
            $table->string('registration_number', 50)->nullable();
            $table->text('description')->nullable();
            $table->string('address', 255)->nullable();
            $table->string('contact_email', 255)->nullable();
            $table->string('contact_phone', 30)->nullable();
            $table->string('status', 20)->default('active');
            $table->json('settings')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['municipality_id', 'slug']);
            $table->index(['municipality_id', 'status']);
            $table->unique(['id', 'municipality_id'], 'neighborhood_groups_id_municipality_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('neighborhood_groups');
    }
};
