<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('municipalities', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('slug')->unique();
            $table->string('region_code', 10);
            $table->string('commune_code', 10);
            $table->string('status', 32)->default('active');
            $table->json('settings')->nullable();
            $table->timestamps();

            $table->index(['region_code', 'commune_code']);
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('municipalities');
    }
};
