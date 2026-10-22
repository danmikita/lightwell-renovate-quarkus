#!/usr/bin/env bash
set -euo pipefail

echo "=================================================================="
echo " Lightwell + Renovate Local Verification (OpenShift DevSpaces)"
echo "=================================================================="

# Ensure a local git repository exists so Renovate's local platform can scan the workspace
if [ ! -d ".git" ]; then
  echo "[INFO] Initializing temporary local git repository for Renovate scan..."
  git init -q
  git add .
  git -c user.name="Demo User" -c user.email="demo@redhat.com" commit -q -m "Initial commit"
fi

echo "[INFO] Running Renovate in local dry-run mode..."
echo "[INFO] Target package: org.apache.commons:commons-compress:1.20"
echo "[INFO] Custom registry: https://repo.lightwell.redhat.com/maven/public"
echo "------------------------------------------------------------------"

if command -v renovate >/dev/null 2>&1; then
  RENOVATE_CMD="renovate"
else
  RENOVATE_CMD="npx --yes renovate"
fi

LOG_LEVEL="${LOG_LEVEL:-debug}" \
$RENOVATE_CMD \
  --platform=local \
  --dry-run=true
