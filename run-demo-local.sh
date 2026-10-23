#!/usr/bin/env bash
set -euo pipefail

LIGHTWELL_REPO_URL="https://packages.redhat.com/lightwell/java/remediated/"
M2_SETTINGS="${HOME}/.m2/settings.xml"

echo "=================================================================="
echo " Lightwell + Renovate Local Verification (OpenShift DevSpaces)"
echo "=================================================================="

# 1. Load or prompt for Lightwell Service Account credentials
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

# 2. Ensure ~/.m2/settings.xml is configured for Maven builds
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
echo "[INFO] Configured Maven settings in ${M2_SETTINGS}"

# 3. Verify available remediated versions in Lightwell for commons-compress
echo "[INFO] Versions of org.apache.commons:commons-compress in Lightwell Remediated (1.9*):"
curl -sSf -u "${LIGHTWELL_USERNAME}:${LIGHTWELL_TOKEN}" \
  "${LIGHTWELL_REPO_URL}org/apache/commons/commons-compress/maven-metadata.xml" \
  | sed -n 's/.*<version>\(.*\)<\/version>.*/  - \1/p' | grep "1\.9" || true
echo "------------------------------------------------------------------"

# 4. Ensure a local git repository exists so Renovate's local platform can scan the workspace
if [ ! -d ".git" ]; then
  echo "[INFO] Initializing temporary local git repository for Renovate scan..."
  git init -q
  git add .
  git -c user.name="Demo User" -c user.email="demo@redhat.com" commit -q -m "Initial commit"
fi

echo "[INFO] Running Renovate local lookup against Lightwell Remediated..."
echo "       Target package : org.apache.commons:commons-compress:1.9"
echo "       Lightwell repo : ${LIGHTWELL_REPO_URL}"
echo "------------------------------------------------------------------"

if command -v renovate >/dev/null 2>&1; then
  RENOVATE_CMD="renovate"
else
  RENOVATE_CMD="npx --yes renovate"
fi

export RENOVATE_HOST_RULES="[{\"matchHost\":\"${LIGHTWELL_REPO_URL}\",\"username\":\"${LIGHTWELL_USERNAME}\",\"password\":\"${LIGHTWELL_TOKEN}\"}]"
export RENOVATE_ONBOARDING="false"
export RENOVATE_REQUIRE_CONFIG="optional"

if [ "${VERBOSE:-false}" = "true" ]; then
  LOG_LEVEL=debug $RENOVATE_CMD --platform=local --dry-run=lookup
  exit 0
fi

LOG_FILE=$(mktemp /tmp/renovate-scan.XXXXXX.jsonl)
trap 'rm -f "${LOG_FILE}"' EXIT

LOG_FORMAT=json LOG_LEVEL=debug \
  $RENOVATE_CMD --platform=local --dry-run=lookup > "${LOG_FILE}"

node -e '
const fs = require("fs");
const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
let found = false;

for (const line of lines) {
  let entry;
  try { entry = JSON.parse(line); } catch { continue; }
  if (entry.msg === "packageFiles with updates" && entry.config && entry.config.maven) {
    for (const pkgFile of entry.config.maven) {
      for (const dep of (pkgFile.deps || [])) {
        if (dep.depName === "org.apache.commons:commons-compress") {
          found = true;
          console.log("✅ Renovate Scan Result (" + pkgFile.packageFile + "):");
          console.log("   Dependency      : " + dep.depName);
          console.log("   Current Version : " + dep.currentValue);
          console.log("   Source Registry : " + (dep.registryUrls || []).join(", "));
          if (dep.updates && dep.updates.length > 0) {
            console.log("   Available Remediation Updates:");
            for (const u of dep.updates) {
              console.log("     ➜ " + dep.currentValue + " -> " + u.newVersion + " (updateType: " + u.updateType + ", branch: " + u.branchName + ")");
            }
          } else {
            console.log("   No updates proposed (skipReason: " + (dep.skipReason || "none") + ")");
          }
        }
      }
    }
  }
}

if (!found) {
  console.log("⚠️ No matching dependency entry found in Renovate output. Re-run with VERBOSE=true ./run-demo-local.sh for full debug logs.");
}
' "${LOG_FILE}"
echo "=================================================================="
