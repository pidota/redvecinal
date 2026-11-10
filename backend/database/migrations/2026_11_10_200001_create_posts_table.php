<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('posts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('municipality_id')->constrained('municipalities')->restrictOnDelete();
            $table->unsignedBigInteger('neighborhood_group_id')->nullable();
            $table->foreignId('author_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('category_id')->constrained('post_categories')->restrictOnDelete();
            $table->string('status', 30)->default('draft');
            $table->string('visibility', 30)->default('members_only');
            $table->unsignedBigInteger('current_published_revision_id')->nullable();
            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('published_at')->nullable();
            $table->timestamp('hidden_at')->nullable();
            $table->timestamp('archived_at')->nullable();
            $table->boolean('comments_enabled')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['municipality_id', 'status', 'published_at']);
            $table->index(['neighborhood_group_id', 'status']);
            $table->index(['author_id', 'status']);
            $table->index('status');

            $table->foreign(['neighborhood_group_id', 'municipality_id'], 'posts_group_municipality_fk')
                ->references(['id', 'municipality_id'])
                ->on('neighborhood_groups')
                ->restrictOnDelete();

            $table->unique(['id', 'municipality_id'], 'posts_id_municipality_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('posts');
    }
};
