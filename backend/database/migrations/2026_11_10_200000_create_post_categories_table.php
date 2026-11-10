<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('post_categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('municipality_id')->nullable()->constrained('municipalities')->restrictOnDelete();
            $table->string('catalog_scope', 64);
            $table->string('slug', 80);
            $table->string('name');
            $table->text('description')->nullable();
            $table->string('default_audience', 30)->default('group');
            $table->boolean('is_system')->default(false);
            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['catalog_scope', 'slug']);
            $table->index(['municipality_id', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('post_categories');
    }
};
