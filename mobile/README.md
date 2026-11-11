# Red Vecinal — app móvil (Flutter)

Cliente comunitario para la API Laravel (`/api/v1`). **Fase 5.2B:** autenticación Sanctum (login, `/me`, logout, sesión segura). Las pantallas de juntas/publicaciones/chat siguen conceptuales.

## Requisitos

- Flutter 3.29+ (Dart 3.7+)
- Android SDK (desarrollo principal)
- Xcode solo si se compila para iOS

Verificar:

```bash
flutter --version
flutter doctor
```

## Instalación

```bash
cd mobile
flutter pub get
```

## Ejecución

### Chrome (validación visual Fase 5.1)

Útil cuando no hay emulador Android. Solo desarrollo local; **no sustituye** pruebas en dispositivo real.

```bash
cd mobile
flutter devices          # debe listar Chrome
flutter run -d chrome
# puerto fijo opcional:
flutter run -d chrome --web-port=7357
```

**Chrome DevTools (F12):**

1. Activar barra de dispositivos (**Toggle device toolbar**, `Ctrl+Shift+M`).
2. Probar resoluciones: 320×568, 390×844, 430×932, 768×1024.
3. Revisar consola: no deben aparecer errores rojos al navegar entre rutas.

Rutas directas (estrategia path, sin `#`):

- `/splash`, `/login`
- `/home`, `/neighborhoods`, `/posts`, `/chat`, `/profile`
- `/neighborhoods/ejemplo` (detalle conceptual, sin barra inferior)

**Limitaciones Web:** el lienzo Flutter expone poca accesibilidad DOM; los clics en la barra inferior se validan mejor con `flutter test` o manualmente en Chrome. Reverb, almacenamiento seguro y plugins nativos pueden comportarse distinto que en Android.

Compilación de comprobación:

```bash
flutter build web
```

No desplegar `build/web` a Internet sin autorización.

### Android (objetivo de producción)

```bash
cd mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2/api/v1
```

En **emulador Android**, `10.0.2.2` apunta al localhost de Windows (ajusta puerto/vhost si Laragon usa otro host).

En **dispositivo físico**, usa la IP LAN del PC, por ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.50/api/v1
```

Laragon local (misma máquina, Chrome o build web contra backend):

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://red-vecinal.test/api/v1
```

El build **debug** Android permite HTTP cleartext solo en desarrollo (`android/app/src/debug/AndroidManifest.xml`).

### Variables de entorno (`--dart-define`)

| Define | Valor por defecto | Uso |
|--------|-------------------|-----|
| `APP_ENV` | `development` | Etiqueta de entorno |
| `APP_NAME` | `Red Vecinal` | Título de la app |
| `API_BASE_URL` | *(vacío)* | Base API con sufijo `/api/v1` (obligatorio para login real) |

Ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://red-vecinal.test/api/v1
```

No incluir secretos ni contraseñas en el código.

### Autenticación (5.2B)

- Endpoints: `POST /auth/login`, `GET /me`, `POST /auth/logout` (ver `docs/mobile-auth-api.md` en el repo).
- Token Bearer en **flutter_secure_storage** (Android/iOS).
- **Web:** solo memoria RAM; al recargar la página no hay sesión persistente (no se usa `localStorage`).
- Tras login fallido por red al restaurar sesión: pantalla **Reintentar** (`/session-retry`) sin borrar el token.
- `401` en rutas autenticadas cierra sesión local; `403` no cierra sesión.

## Estructura `lib/`

```text
core/         # config, theme, routing, network (Dio), storage (token seguro)
features/     # auth, home, neighborhoods, posts, chat, profile
shared/       # widgets reutilizables
app.dart
main.dart
```

## Dependencias

- `flutter_riverpod` — estado global (sesión auth)
- `go_router` — rutas protegidas y `StatefulShellRoute`
- `dio` — cliente HTTP
- `flutter_secure_storage` — token Sanctum en móvil nativo

Pendiente: Reverb, caché offline, etc.

## Pruebas

```bash
flutter analyze
flutter test
```

### Validación REST local (5.2B)

Scripts **solo desarrollo**: no ejecutar contra producción. El usuario de prueba usa correo `flutter-e2e-*@red-vecinal.test` y contraseña aleatoria (nunca credenciales reales).

**Preparar fixture** (desde la raíz del repo, con Laragon/`.env` local):

```bash
cd backend
php scripts/dev/flutter-e2e/prepare-user.php
```

Crea un vecino con junta activa y guarda credenciales en `mobile/scripts/.flutter-e2e-credentials.json` (gitignored).

**Ejecutar smoke** (login, `/me`, logout, token revocado, credenciales incorrectas):

```bash
php mobile/scripts/rest_smoke.php
# opcional: API_BASE_URL=http://10.0.2.2/api/v1 php mobile/scripts/rest_smoke.php
```

No imprime tokens completos ni contraseñas.

**Limpiar fixture** (solo elimina usuarios `flutter-e2e-*@red-vecinal.test`):

```bash
cd backend
php scripts/dev/flutter-e2e/cleanup-user.php
```

### JDK / compilación Android

Gradle (AGP actual) requiere **JDK 17+**. Si `flutter doctor` muestra Java 11, apunte Flutter al JDK 17 sin modificar el proyecto:

```bash
flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.14.7-hotspot"
flutter build apk --debug
```

Ajuste la ruta según su instalación. No se descargan JDK automáticamente desde el repo.

## Subfases pendientes

| Subfase | Contenido |
|---------|-----------|
| 5.2 | Autenticación Sanctum (completada en app) |
| 5.3.1 | Mis juntas (`GET /me/groups`) |
| 5.3.2+ | Explorar, detalle, integrantes |
| 5.4 | Publicaciones y moderación |
| 5.5 | Chat + Reverb |
| 5.6 | Integración, pruebas E2E, estabilización |

## Android

Identificador provisional de paquete: `cl.redvecinal.red_vecinal` (revisar antes de publicación en tiendas).

HTTP cleartext solo en **debug** Android para desarrollo local.
