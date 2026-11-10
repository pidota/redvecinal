<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('group_members', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('municipality_id');
            $table->unsignedBigInteger('neighborhood_group_id');
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->string('membership_role', 30)->default('member');
            $table->string('status', 30)->default('pending');
            $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('joined_at')->nullable();
            $table->timestamps();

            $table->unique(['neighborhood_group_id', 'user_id']);
            $table->index('neighborhood_group_id');
            $table->index('user_id');
            $table->index('status');
            $table->index('municipality_id');

            $table->foreign('municipality_id')->references('id')->on('municipalities')->restrictOnDelete();

            $table->foreign(['neighborhood_group_id', 'municipality_id'], 'group_members_group_municipality_fk')
                ->references(['id', 'municipality_id'])
                ->on('neighborhood_groups')
                ->restrictOnDelete();
        });

        DB::statement("
            ALTER TABLE group_members
            ADD COLUMN active_president_key BIGINT UNSIGNED
            AS (
                CASE
                    WHEN membership_role = 'president' AND status = 'active'
                    THEN neighborhood_group_id
                    ELSE NULL
                END
            ) STORED
        ");

        DB::statement('
            CREATE UNIQUE INDEX group_members_unique_active_president
            ON group_members (active_president_key)
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('group_members');
    }
};
