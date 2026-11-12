<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * pending_slot: en MySQL es columna generada STORED (única fuente en producción).
 * En SQLite (PHPUnit) la columna es nullable y el modelo asigna pending_slot al guardar.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('neighborhood_membership_requests', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('municipality_id');
            $table->unsignedBigInteger('neighborhood_group_id');
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->string('status', 32);
            $table->text('request_note')->nullable();
            $table->text('review_note')->nullable();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamp('rejected_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->timestamps();

            $table->index(['neighborhood_group_id', 'status'], 'nmr_group_status_idx');
            $table->index(['user_id', 'status'], 'nmr_user_status_idx');
            $table->index(['municipality_id', 'status'], 'nmr_muni_status_idx');

            $table->foreign('municipality_id')->references('id')->on('municipalities')->restrictOnDelete();
            $table->foreign(['neighborhood_group_id', 'municipality_id'], 'nmr_group_municipality_fk')
                ->references(['id', 'municipality_id'])
                ->on('neighborhood_groups')
                ->restrictOnDelete();
        });

        $driver = Schema::getConnection()->getDriverName();

        if ($driver === 'mysql') {
            DB::statement("
                ALTER TABLE neighborhood_membership_requests
                ADD COLUMN pending_slot TINYINT UNSIGNED
                AS (
                    CASE
                        WHEN status = 'pending' THEN 1
                        ELSE NULL
                    END
                ) STORED
            ");

            DB::statement('
                CREATE UNIQUE INDEX neighborhood_membership_requests_unique_pending
                ON neighborhood_membership_requests (neighborhood_group_id, user_id, pending_slot)
            ');
        } else {
            Schema::table('neighborhood_membership_requests', function (Blueprint $table) {
                $table->unsignedTinyInteger('pending_slot')->nullable();
                $table->unique(
                    ['neighborhood_group_id', 'user_id', 'pending_slot'],
                    'neighborhood_membership_requests_unique_pending'
                );
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('neighborhood_membership_requests');
    }
};
