# CI — pruebas backend (GitHub Actions)

Workflow: [`.github/workflows/backend-tests.yml`](../.github/workflows/backend-tests.yml)

## Cuándo se ejecuta

- Push a `main`
- Pull requests cuyo destino es `main`

## Jobs

| Job | Comando | Base de datos | Alcance |
|-----|---------|---------------|---------|
| **SQLite** | `php artisan test` | SQLite en memoria (`phpunit.xml`) | Suite completa: `tests/Unit` + `tests/Feature` |
| **MySQL 8.4** | `php artisan test -c phpunit.mysql.xml` | Servicio efímero `red_vecinal_testing` | `tests/Feature/Neighborhoods` + `tests/Smoke` (restricciones, membresías, concurrencia) |

Los dos jobs corren en paralelo en runners Ubuntu independientes. Cada uno usa su propia base de datos efímera.

Las ejecuciones del mismo workflow en la misma rama **no se cancelan entre sí** (`cancel-in-progress: false`), para no interrumpir suites MySQL largas en curso.

## Caché Composer

Se cachean las **descargas** de Composer (`COMPOSER_CACHE_DIR`), no el directorio `vendor`. Cada job ejecuta `composer install` completo; la clave de caché depende del SO y de `backend/composer.lock`.

## Seguridad

- **No** usa `red_vecinal` (desarrollo), bases del VPS ni secretos de producción.
- MySQL del workflow: credencial fija `ci_mysql_testing` solo dentro del contenedor del job.
- Antes de la suite MySQL se comprueba el entorno del job (`APP_ENV`, `DB_*`) y la configuración **efectiva** de Laravel (`config/database` y `APP_KEY` con prefijo `base64:`), sin imprimir contraseñas.
- **No** se ejecutan `ensure_mysql_testing_database.php` ni `reset_mysql_testing_database.php` en CI.

## Resultados en GitHub

1. Abrir el repositorio en GitHub → pestaña **Actions**.
2. Elegir la ejecución del workflow **Backend tests**.
3. Revisar los jobs **SQLite** y **MySQL 8.4** (logs por paso).

## Diferencia con pruebas locales (Laragon)

| Aspecto | Local | CI |
|---------|-------|-----|
| SQLite | `php artisan test` (misma config) | Igual |
| MySQL | Laragon, BD `red_vecinal_testing`, `phpunit.mysql.xml` | Contenedor `mysql:8.4`, mismas variables de nombre de BD |
| Workers de concurrencia | Procesos PHP secundarios con `DB_*` del `.env` | Mismas variables de entorno del job + `APP_KEY` generado en el runner |
| Desarrollo / producción | `.env` local con `red_vecinal` | **Sin conexión** |

En local, opcional: `php scripts/test/ensure_mysql_testing_database.php` (solo desarrollo). Ese script **no** forma parte del pipeline de GitHub.

## Validación en el runner

La corrección del workflow solo está plenamente verificada cuando GitHub Actions ejecuta ambos jobs con éxito. La revisión local cubre sintaxis YAML y coherencia con `phpunit*.xml`, no sustituye una corrida en GitHub.