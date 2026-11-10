<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('post_revisions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('post_id')->constrained('posts')->cascadeOnDelete();
            $table->foreignId('municipality_id')->constrained('municipalities')->restrictOnDelete();
            $table->unsignedInteger('revision_number');
            $table->foreignId('category_id')->constrained('post_categories')->restrictOnDelete();
            $table->string('title', 200);
            $table->text('body');
            $table->string('status', 30)->default('draft');
            $table->foreignId('created_by')->constrained('users')->restrictOnDelete();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->text('rejection_reason')->nullable();
            $table->timestamps();

            $table->unique(['post_id', 'revision_number']);
            $table->index(['post_id', 'status']);
            $table->index('status');
        });

        Schema::table('posts', function (Blueprint $table) {
            $table->foreign('current_published_revision_id')
                ->references('id')
                ->on('post_revisions')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('posts', function (Blueprint $table) {
            $table->dropForeign(['current_published_revision_id']);
        });

        Schema::dropIfExists('post_revisions');
    }
};
