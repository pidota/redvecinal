# Red Vecinal — app móvil (Flutter)

Cliente comunitario para la API Laravel (`/api/v1`). **Fase 5.1:** diseño, navegación y pantallas conceptuales (sin API ni autenticación real).

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
flutter run
```

Dispositivo o emulador Android. API Laravel en fases 5.2+.

### Variables de entorno (`--dart-define`)

| Define | Valor por defecto | Uso |
|--------|-------------------|-----|
| `APP_ENV` | `development` | Etiqueta de entorno |
| `APP_NAME` | `Red Vecinal` | Título de la app |

Ejemplo producción futura:

```bash
flutter run --dart-define=APP_ENV=production --dart-define=APP_NAME="Red Vecinal"
```

No incluir secretos ni URLs con credenciales en el código.

## Estructura `lib/`

```text
core/         # config, theme, routing (network/storage reservados 5.2+)
features/     # auth, home, neighborhoods, posts, chat, profile
shared/       # widgets reutilizables
app.dart
main.dart
```

## Dependencias (5.1)

- `flutter_riverpod` — estado global
- `go_router` — rutas y `StatefulShellRoute` (barra inferior)

Pendientes en subfases: Dio, almacenamiento seguro, Reverb, caché, etc.

## Pruebas

```bash
flutter analyze
flutter test
```

## Subfases pendientes

| Subfase | Contenido |
|---------|-----------|
| 5.2 | Autenticación Sanctum, `GET /me`, almacenamiento seguro |
| 5.3 | Juntas (`/me/groups`, detalle) |
| 5.4 | Publicaciones y moderación |
| 5.5 | Chat + Reverb |
| 5.6 | Integración, pruebas E2E, estabilización |

## Android

Identificador provisional de paquete: `cl.redvecinal.red_vecinal` (revisar antes de publicación en tiendas).

No se habilita tráfico HTTP cleartext global en esta subfase.
