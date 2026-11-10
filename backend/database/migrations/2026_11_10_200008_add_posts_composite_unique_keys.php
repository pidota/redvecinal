<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('posts') && ! $this->indexExists('posts', 'posts_id_municipality_unique')) {
            Schema::table('posts', function (Blueprint $table) {
                $table->unique(['id', 'municipality_id'], 'posts_id_municipality_unique');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('posts')) {
            Schema::table('posts', function (Blueprint $table) {
                $table->dropUnique('posts_id_municipality_unique');
            });
        }
    }

    private function indexExists(string $table, string $index): bool
    {
        $connection = Schema::getConnection();
        $schemaManager = $connection->getSchemaBuilder();

        return collect($schemaManager->getIndexes($table))
            ->contains(fn (array $definition) => ($definition['name'] ?? '') === $index);
    }
};
