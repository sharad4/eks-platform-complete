#!/usr/bin/env bash
# Creates the Laravel app in apps/backend and applies the platform overlay
# (health checks, Prometheus metrics, tests). Run ONCE, then commit the result.
#
# Requires: php 8.3+, composer. Works against the Laravel 11/12 skeleton.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/apps/backend"
OVERLAY="$APP/overlay"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -f "$APP/composer.json" ]; then
  echo "apps/backend already contains a Laravel app (composer.json found). Nothing to do."
  exit 0
fi

echo "==> Creating Laravel skeleton"
composer create-project laravel/laravel "$TMP/app" --no-interaction --prefer-dist
composer --working-dir="$TMP/app" require promphp/prometheus_client_php --no-interaction

echo "==> Copying skeleton into apps/backend (keeping our Dockerfile, README and overlay)"
tar -C "$TMP/app" --exclude=./README.md --exclude=./vendor --exclude=./.dockerignore -cf - . | tar -C "$APP" -xf -

echo "==> Applying overlay"
cp -R "$OVERLAY"/. "$APP"/

BOOT="$APP/bootstrap/app.php"
echo "==> Patching bootstrap/app.php"
if grep -q "platform.php" "$BOOT"; then
  echo "already patched"
elif grep -q "health: '/up'," "$BOOT" && grep -q "//" "$BOOT"; then
  perl -0pi -e "s|health: '/up',|health: '/up',\n        then: function () {\n            \\\\Illuminate\\\\Support\\\\Facades\\\\Route::group([], base_path('routes/platform.php'));\n        },|" "$BOOT"
  perl -0pi -e 's|(withMiddleware\(function \(Middleware \$middleware\)[^{]*\{\s*)//|$1\$middleware->append(\\App\\Http\\Middleware\\RecordMetrics::class);|' "$BOOT"
else
  cat <<'EOF'
!! Could not patch bootstrap/app.php automatically. Add by hand:

    ->withRouting(
        ...,
        health: '/up',
        then: function () {
            \Illuminate\Support\Facades\Route::group([], base_path('routes/platform.php'));
        },
    )
    ->withMiddleware(function (Middleware $middleware) {
        $middleware->append(\App\Http\Middleware\RecordMetrics::class);
    })
EOF
fi

echo "==> .env.example: container-friendly logging"
sed -i 's/^LOG_CHANNEL=.*/LOG_CHANNEL=stderr/' "$APP/.env.example"
grep -q '^LOG_STDERR_FORMATTER=' "$APP/.env.example" || \
  echo 'LOG_STDERR_FORMATTER=Monolog\Formatter\JsonFormatter' >> "$APP/.env.example"

echo
echo "Done. Next:  cd apps/backend && php artisan test"
echo "Then:        git add apps/backend && commit (composer.lock must be committed)."
