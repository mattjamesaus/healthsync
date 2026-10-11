#!/bin/sh
# Uploads the archive's dSYMs so Sentry can symbolicate native crashes.
# SENTRY_AUTH_TOKEN is not stored in git. Set it in the build environment or in
# Config/SentryAuth.local.xcconfig (gitignored). Org and project come from
# Config/Secrets.xcconfig.

if [ "$(uname -m)" = "arm64" ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  echo "warning: SENTRY_AUTH_TOKEN is not set; skipping dSYM upload. Add it to Config/SentryAuth.local.xcconfig or the build environment."
  exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "warning: sentry-cli not installed, download from https://github.com/getsentry/sentry-cli/releases"
  exit 0
fi

export SENTRY_ORG="${SENTRY_ORG:-null-pointer-group}"
export SENTRY_PROJECT="${SENTRY_PROJECT:-health-sync}"

if ! ERROR=$(sentry-cli debug-files upload --include-sources "$DWARF_DSYM_FOLDER_PATH" 2>&1); then
  echo "warning: sentry-cli - $ERROR"
fi
