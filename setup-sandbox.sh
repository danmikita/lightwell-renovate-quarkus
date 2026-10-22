#!/usr/bin/env bash
set -euo pipefail

echo "=================================================================="
echo " Lightwell + Renovate OpenShift Sandbox 1-Click Bootstrap"
echo "=================================================================="

# 1. Verify OpenShift login
if ! oc whoami >/dev/null 2>&1; then
  echo "[ERROR] Not logged into an OpenShift cluster. Inside OpenShift DevSpaces you are logged in automatically."
  exit 1
fi

NAMESPACE=$(oc project -q)
echo "[INFO] Active OpenShift Sandbox Namespace: ${NAMESPACE}"

# 2. Apply Tekton Task, EventListener, TriggerBinding, TriggerTemplate, and Route
echo "[INFO] Applying Tekton Task and Webhook EventListener in ${NAMESPACE}..."
oc apply -f tekton/tekton-renovate-task.yaml
oc apply -f tekton/tekton-triggers.yaml

# 3. Wait briefly for the Route host to be assigned
WEBHOOK_HOST=$(oc get route el-renovate-listener -o jsonpath='{.spec.host}' 2>/dev/null || true)
WEBHOOK_URL="https://${WEBHOOK_HOST}"
echo "[INFO] Tekton EventListener Webhook URL: ${WEBHOOK_URL}"

# 4. Detect GitHub Repo (owner/repo) from git remote if not set
if [ -z "${GITHUB_REPO:-}" ]; then
  REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || true)
  if [[ "${REMOTE_URL}" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    GITHUB_REPO="${BASH_REMATCH[1]}"
  else
    GITHUB_REPO="danmikita/lightwell-renovate-quarkus"
  fi
fi
echo "[INFO] Target GitHub Repository: ${GITHUB_REPO}"

# 5. Configure Renovate Credentials Secret & GitHub Webhook if GITHUB_TOKEN is provided
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo ""
  echo "[ACTION REQUIRED] To enable automatic PR creation and GitHub Webhook registration,"
  echo "re-run with your GitHub Personal Access Token (needs 'repo' and 'admin:repo_hook' scopes):"
  echo ""
  echo "  GITHUB_TOKEN=ghp_xxx ./setup-sandbox.sh"
  echo ""
  echo "Or manually add this Webhook URL in GitHub (${GITHUB_REPO} -> Settings -> Webhooks):"
  echo "  Payload URL : ${WEBHOOK_URL}"
  echo "  Content type: application/json"
  echo "  Events      : Just the push event"
  exit 0
fi

echo "[INFO] Creating/updating 'renovate-credentials' Secret in ${NAMESPACE}..."
oc create secret generic renovate-credentials \
  --from-literal=RENOVATE_PLATFORM=github \
  --from-literal=RENOVATE_TOKEN="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -

echo "[INFO] Registering OpenShift Tekton EventListener Webhook on GitHub (${GITHUB_REPO})..."
EXISTING_HOOK_ID=$(curl -sSf -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/hooks" \
  | grep -B 2 -A 5 "${WEBHOOK_HOST}" | grep -m1 '"id":' | tr -dc '0-9' || true)

if [ -n "${EXISTING_HOOK_ID}" ]; then
  echo "[INFO] Webhook already registered on ${GITHUB_REPO} (Hook ID: ${EXISTING_HOOK_ID})."
else
  curl -sSf -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/hooks" \
    -d @- <<EOF >/dev/null
{
  "name": "web",
  "active": true,
  "events": ["push"],
  "config": {
    "url": "${WEBHOOK_URL}",
    "content_type": "json",
    "insecure_ssl": "0"
  }
}
EOF
  echo "[INFO] Successfully registered GitHub Webhook -> ${WEBHOOK_URL}"
fi

echo "=================================================================="
echo " Setup Complete!"
echo " - Any 'git push' to 'main' on ${GITHUB_REPO} will now automatically"
echo "   trigger the Tekton Renovate PipelineRun in ${NAMESPACE}"
echo "   and open a remediation Pull Request!"
echo "=================================================================="
