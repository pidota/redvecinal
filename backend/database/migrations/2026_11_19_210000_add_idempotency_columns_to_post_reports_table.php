<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('post_reports', function (Blueprint $table) {
            $table->string('idempotency_key', 36)->nullable();
            $table->string('payload_fingerprint', 64)->nullable();
            $table->unique(['reporter_id', 'idempotency_key'], 'post_reports_reporter_idempotency_unique');
        });
    }

    public function down(): void
    {
        Schema::table('post_reports', function (Blueprint $table) {
            $table->dropUnique('post_reports_reporter_idempotency_unique');
            $table->dropColumn(['idempotency_key', 'payload_fingerprint']);
        });
    }
};
