#!/usr/bin/env bash
# Renders the page in headless Chromium and checks which section the URL shows.
set -euo pipefail

CHROME="${CHROME:-$(ls -d ~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell | tail -1)}"
PAGE="file://$(cd "$(dirname "$0")" && pwd)/legal/index.html"
failures=0

check() {
  local suffix="$1" tab="$2" lang="$3" toggle="$4"
  local dom visible
  dom="$("$CHROME" --headless --disable-gpu --virtual-time-budget=3000 --dump-dom "$PAGE$suffix" 2>/dev/null)"
  visible="$(grep -o '<section[^>]*>' <<<"$dom" | grep -v 'hidden' || true)"
  if [[ "$(wc -l <<<"$visible")" -ne 1 || "$visible" != *"data-tab=\"$tab\""* || "$visible" != *"data-lang=\"$lang\""* ]]; then
    echo "FAIL $suffix: expected $tab/$lang, visible: $visible"; failures=$((failures + 1))
  fi
  if [[ "$dom" != *"<html lang=\"$lang\""* ]]; then
    echo "FAIL $suffix: html lang is not $lang"; failures=$((failures + 1))
  fi
  if ! grep -q "id=\"lang-toggle\"[^>]*href=\"$toggle\"\|href=\"$toggle\"[^>]*id=\"lang-toggle\"" <<<"$dom"; then
    echo "FAIL $suffix: language toggle does not point to $toggle"; failures=$((failures + 1))
  fi
  if ! grep -q "class=\"tab\"[^>]*href=\"#privacy-$lang\"" <<<"$dom" || ! grep -q "class=\"tab\"[^>]*href=\"#deletion-$lang\"" <<<"$dom"; then
    echo "FAIL $suffix: tab links do not keep language $lang"; failures=$((failures + 1))
  fi
}

# --- Test 1: no tag shows the English privacy tab ---
check ""             privacy  en "#privacy-es"

# --- Test 2: tab tag only shows the English deletion tab ---
check "#deletion"    deletion en "#deletion-es"

# --- Test 3: Spanish privacy tab ---
check "#privacy-es"  privacy  es "#privacy-en"

# --- Test 4: Spanish deletion tab ---
check "#deletion-es" deletion es "#deletion-en"

# --- Test 5: explicit English deletion tab ---
check "#deletion-en" deletion en "#deletion-es"

# --- Test 6: unknown tab falls back to the English privacy tab ---
check "#unknown"     privacy  en "#privacy-es"

# --- Test 7: unknown language keeps the tab and falls back to English ---
check "#deletion-fr" deletion en "#deletion-es"

# --- Test 8: the email is plain text, with no link and no alias ---
if grep -q 'mailto:\|lfelipemonte+' "${PAGE#file://}" || [[ "$(grep -c 'lfelipemonte@gmail.com' "${PAGE#file://}")" -ne 4 ]]; then
  echo "FAIL email: page must show lfelipemonte@gmail.com 4 times as plain text, with no mailto link or alias"; failures=$((failures + 1))
fi

# --- Test 9: the policy states retention, region, technical data and AI scope in both languages ---
for phrase in "7 days" "7 días" "14 days" "14 días" "United States" "Estados Unidos" "message ID" "ID del mensaje" "general-purpose" "propósito general" "Last updated: 14 November 2026" "Última actualización: 14 de noviembre de 2026"; do
  if ! grep -q "$phrase" "${PAGE#file://}"; then
    echo "FAIL content: page does not contain \"$phrase\""; failures=$((failures + 1))
  fi
done

[[ $failures -eq 0 ]] && echo "OK" || exit 1
