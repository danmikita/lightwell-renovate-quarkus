#!/usr/bin/env bash
set -euo pipefail

LIGHTWELL_REPO_URL="https://packages.redhat.com/lightwell/java/remediated/"
M2_SETTINGS="${HOME}/.m2/settings.xml"

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

# 2. Load or prompt for Lightwell Service Account credentials
if [ -z "${LIGHTWELL_USERNAME:-}" ] || [ -z "${LIGHTWELL_TOKEN:-}" ]; then
  if [ -f "${M2_SETTINGS}" ] && grep -q "lightwell-remediated" "${M2_SETTINGS}" 2>/dev/null; then
    LIGHTWELL_USERNAME=$(sed -n 's/.*<username>\(.*\)<\/username>.*/\1/p' "${M2_SETTINGS}" | head -n1)
    LIGHTWELL_TOKEN=$(sed -n 's/.*<password>\(.*\)<\/password>.*/\1/p' "${M2_SETTINGS}" | head -n1)
  fi
fi

if [ -z "${LIGHTWELL_USERNAME:-}" ]; then
  read -rp "Enter Lightwell Service Account Username: " LIGHTWELL_USERNAME
fi
if [ -z "${LIGHTWELL_TOKEN:-}" ]; then
  read -rsp "Enter Lightwell Service Account Token: " LIGHTWELL_TOKEN
  echo ""
fi

# 3. Write ~/.m2/settings.xml for Maven builds
mkdir -p "${HOME}/.m2"
cat > "${M2_SETTINGS}" <<EOF
<settings>
  <profiles>
    <profile>
      <id>lightwell-remediated</id>
      <repositories>
        <repository>
          <id>lightwell-remediated</id>
          <name>Red Hat Lightwell Network - Remediated</name>
          <url>${LIGHTWELL_REPO_URL}</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </repository>
      </repositories>
    </profile>
  </profiles>
  <activeProfiles>
    <activeProfile>lightwell-remediated</activeProfile>
  </activeProfiles>
  <servers>
    <server>
      <id>lightwell-remediated</id>
      <username>${LIGHTWELL_USERNAME}</username>
      <password>${LIGHTWELL_TOKEN}</password>
    </server>
  </servers>
</settings>
EOF
chmod 600 "${M2_SETTINGS}"
echo "[INFO] Configured Lightwell Remediated Maven settings in ${M2_SETTINGS}"

# 4. Apply Tekton Task, EventListener, TriggerBinding, TriggerTemplate, and Route
echo "[INFO] Applying Tekton Task and Webhook EventListener in ${NAMESPACE}..."
oc apply -f tekton/tekton-renovate-task.yaml
oc apply -f tekton/tekton-triggers.yaml

# 5. Wait briefly for the Route host to be assigned
WEBHOOK_HOST=$(oc get route el-renovate-listener -o jsonpath='{.spec.host}' 2>/dev/null || true)
WEBHOOK_URL="https://${WEBHOOK_HOST}"
echo "[INFO] Tekton EventListener Webhook URL: ${WEBHOOK_URL}"

# 6. Detect GitHub Repo (owner/repo) from git remote if not set
if [ -z "${GITHUB_REPO:-}" ]; then
  REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || true)
  if [[ "${REMOTE_URL}" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    GITHUB_REPO="${BASH_REMATCH[1]}"
  else
    GITHUB_REPO="danmikita/lightwell-renovate-quarkus"
  fi
fi
echo "[INFO] Target GitHub Repository: ${GITHUB_REPO}"

# 7. Prompt for GitHub Personal Access Token if not provided
if [ -z "${GITHUB_TOKEN:-}" ]; then
  read -rsp "Enter your GitHub Personal Access Token (repo + admin:repo_hook scopes): " GITHUB_TOKEN
  echo ""
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[WARN] No GITHUB_TOKEN provided; skipping OpenShift Secret and GitHub Webhook creation."
  exit 0
fi

RENOVATE_HOST_RULES="[{\"matchHost\":\"${LIGHTWELL_REPO_URL}\",\"username\":\"${LIGHTWELL_USERNAME}\",\"password\":\"${LIGHTWELL_TOKEN}\"}]"

echo "[INFO] Creating/updating 'renovate-credentials' Secret in ${NAMESPACE}..."
oc create secret generic renovate-credentials \
  --from-literal=RENOVATE_PLATFORM=github \
  --from-literal=RENOVATE_TOKEN="${GITHUB_TOKEN}" \
  --from-literal=RENOVATE_HOST_RULES="${RENOVATE_HOST_RULES}" \
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
echo " - ~/.m2/settings.xml configured for Lightwell Java Remediated"
echo " - 'renovate-credentials' Secret updated with GitHub + Lightwell auth"
echo " - Any 'git push' to 'main' on ${GITHUB_REPO} will now automatically"
echo "   trigger the Tekton Renovate PipelineRun in ${NAMESPACE}"
echo "   and open a remediation Pull Request!"
echo "=================================================================="
