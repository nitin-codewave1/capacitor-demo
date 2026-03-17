#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Android & iOS Signing Setup
# Safe to run multiple times — reuses existing keystore
# Keystore is committed to repo; only passwords go to GitHub Secrets
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KEYSTORE_PATH="$PROJECT_ROOT/android/app/release.keystore"
CONFIG_DIR="$PROJECT_ROOT/.signing"
CONFIG_PATH="$CONFIG_DIR/.keystore-config"

mkdir -p "$CONFIG_DIR"

# ── Preflight: check gh CLI ──
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is not installed."
  echo "Install it: https://cli.github.com"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "Error: Not logged into GitHub CLI."
  echo "Run: gh auth login"
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [ -z "$REPO" ]; then
  echo "Error: Could not detect a GitHub repository."
  echo "Make sure this repo has a GitHub remote configured."
  exit 1
fi

echo ""
echo "Target repository: $REPO"
echo ""

# ──────────────────────────────────────────────
# Android Keystore
# ──────────────────────────────────────────────
echo "=== Android Keystore Setup ==="
echo ""

if [ -f "$KEYSTORE_PATH" ]; then
  echo "Existing keystore found at: $KEYSTORE_PATH"
  echo "Reusing it. Delete android/app/release.keystore to generate a new one."
  echo ""

  if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
    echo "Loaded saved credentials from .signing/.keystore-config"
  else
    echo "No saved config found. Enter your existing keystore credentials:"
    read -rsp "Keystore password: " KEYSTORE_PASSWORD; echo
    read -rp "Key alias: " KEY_ALIAS
    read -rsp "Key password: " KEY_PASSWORD; echo
  fi
else
  echo "No existing keystore found. Generating a new one."
  echo ""

  read -rsp "Keystore password: " KEYSTORE_PASSWORD; echo
  read -rp "Key alias [release]: " KEY_ALIAS
  KEY_ALIAS="${KEY_ALIAS:-release}"
  read -rsp "Key password (press enter to use keystore password): " KEY_PASSWORD; echo
  KEY_PASSWORD="${KEY_PASSWORD:-$KEYSTORE_PASSWORD}"

  echo ""
  echo "Certificate details (press enter to skip):"
  read -rp "  Your name (CN): " CN
  read -rp "  Organization (O): " O
  read -rp "  Country code (C, e.g. US): " C

  DNAME="CN=${CN:-Unknown}, O=${O:-Unknown}, C=${C:-US}"

  keytool -genkeypair \
    -v \
    -storetype JKS \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -keystore "$KEYSTORE_PATH" \
    -alias "$KEY_ALIAS" \
    -storepass "$KEYSTORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "$DNAME"

  echo ""
  echo "Keystore generated at: $KEYSTORE_PATH"
  echo "This file is safe to commit — it's useless without the passwords."
fi

# Save credentials locally (gitignored) so re-runs don't re-prompt
cat > "$CONFIG_PATH" <<CONF
KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD"
KEY_ALIAS="$KEY_ALIAS"
KEY_PASSWORD="$KEY_PASSWORD"
CONF
chmod 600 "$CONFIG_PATH"

# ──────────────────────────────────────────────
# Push Android secrets to GitHub (passwords only, no keystore)
# ──────────────────────────────────────────────
echo ""
echo "=== Pushing Android secrets to GitHub ==="
echo "(keystore file is in the repo — only passwords need to be secrets)"
echo ""

echo "$KEYSTORE_PASSWORD" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO"
echo "  Set ANDROID_KEYSTORE_PASSWORD"

echo "$KEY_ALIAS" | gh secret set ANDROID_KEY_ALIAS --repo "$REPO"
echo "  Set ANDROID_KEY_ALIAS"

echo "$KEY_PASSWORD" | gh secret set ANDROID_KEY_PASSWORD --repo "$REPO"
echo "  Set ANDROID_KEY_PASSWORD"

echo ""
echo "Android secrets pushed (3 secrets — keystore file is in repo)."

# ──────────────────────────────────────────────
# iOS Setup
# ──────────────────────────────────────────────
echo ""
echo "=== iOS Signing Setup ==="
echo ""
read -rp "Set up iOS secrets now? (y/N): " SETUP_IOS

if [[ "$SETUP_IOS" =~ ^[Yy]$ ]]; then
  read -rp "Apple ID email: " APPLE_ID
  read -rp "Apple Developer Team ID (e.g. ABCD1234EF): " APPLE_TEAM_ID
  read -rp "App Store Connect Team ID (numeric): " ITC_TEAM_ID
  read -rp "App Store Connect API Key ID: " ASC_KEY_ID
  read -rp "App Store Connect API Issuer ID: " ASC_ISSUER_ID
  read -rp "Path to .p8 key file (e.g. ./AuthKey_XXXX.p8): " P8_PATH

  if [ -f "$P8_PATH" ]; then
    ASC_KEY_CONTENT=$(base64 -i "$P8_PATH")
  else
    echo "Warning: File not found at $P8_PATH"
    read -rp "Paste base64-encoded .p8 content: " ASC_KEY_CONTENT
  fi

  echo ""
  echo "Pushing iOS secrets to GitHub..."

  echo "$APPLE_ID" | gh secret set APPLE_ID --repo "$REPO"
  echo "  Set APPLE_ID"

  echo "$APPLE_TEAM_ID" | gh secret set APPLE_TEAM_ID --repo "$REPO"
  echo "  Set APPLE_TEAM_ID"

  echo "$ITC_TEAM_ID" | gh secret set ITC_TEAM_ID --repo "$REPO"
  echo "  Set ITC_TEAM_ID"

  echo "$ASC_KEY_ID" | gh secret set ASC_KEY_ID --repo "$REPO"
  echo "  Set ASC_KEY_ID"

  echo "$ASC_ISSUER_ID" | gh secret set ASC_ISSUER_ID --repo "$REPO"
  echo "  Set ASC_ISSUER_ID"

  echo "$ASC_KEY_CONTENT" | gh secret set ASC_KEY_CONTENT --repo "$REPO"
  echo "  Set ASC_KEY_CONTENT"

  # Optional: Fastlane Match
  echo ""
  read -rp "Set up Fastlane Match? (y/N): " SETUP_MATCH

  if [[ "$SETUP_MATCH" =~ ^[Yy]$ ]]; then
    read -rp "Match git repo URL: " MATCH_GIT_URL
    read -rsp "Match encryption password: " MATCH_PASSWORD; echo
    read -rp "Git basic auth (base64 of user:token, or press enter to skip): " MATCH_GIT_BASIC_AUTH

    echo "$MATCH_GIT_URL" | gh secret set MATCH_GIT_URL --repo "$REPO"
    echo "  Set MATCH_GIT_URL"

    echo "$MATCH_PASSWORD" | gh secret set MATCH_PASSWORD --repo "$REPO"
    echo "  Set MATCH_PASSWORD"

    if [ -n "$MATCH_GIT_BASIC_AUTH" ]; then
      echo "$MATCH_GIT_BASIC_AUTH" | gh secret set MATCH_GIT_BASIC_AUTHORIZATION --repo "$REPO"
      echo "  Set MATCH_GIT_BASIC_AUTHORIZATION"
    fi

    echo ""
    echo "Match secrets pushed. Run this once from your local machine to initialize:"
    echo "  cd ios/App && bundle exec fastlane match init"
    echo "  bundle exec fastlane match appstore"
  fi

  echo ""
  echo "iOS secrets pushed."
else
  echo "Skipped. Run this script again when you're ready for iOS."
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo ""
echo "Secrets pushed to: $REPO"
echo "Verify with: gh secret list --repo $REPO"
echo ""
echo "Keystore: $KEYSTORE_PATH (committed to repo)"
echo "Passwords: .signing/.keystore-config (local only, gitignored)"
echo ""
