# Lightwell + Renovate Quarkus Vulnerability Remediation Demo

[![Open in Red Hat OpenShift DevSpaces](https://img.shields.io/badge/Open%20in-OpenShift%20DevSpaces-EE0000?style=for-the-badge&logo=redhat&logoColor=white)](https://workspaces.openshift.com#https://github.com/danmikita/lightwell-renovate-quarkus)

A minimal, turnkey **Quarkus 3.x (Java 21)** application designed for the **Red Hat Developer Sandbox** (`developer.redhat.com`) that demonstrates automated CVE remediation using **Renovate CLI** pointed at the **Red Hat Lightwell Network - Remediated** Maven repository (`https://packages.redhat.com/lightwell/java/remediated/`).

---

## How the End-to-End Flow Works

1. **Workspace Startup (`devfile.yaml` `postStart` hook):**
   - Automatically installs the `renovate` CLI into a persistent volume (`/home/user/.npm-global`).
   - Automatically runs `oc apply` for [`tekton/tekton-renovate-task.yaml`](./tekton/tekton-renovate-task.yaml) and [`tekton/tekton-triggers.yaml`](./tekton/tekton-triggers.yaml) into your OpenShift Developer Sandbox namespace.
2. **Automatic Tekton Webhook (`tekton/tekton-triggers.yaml`):**
   - Deploys a Tekton `EventListener`, `TriggerBinding`, `TriggerTemplate`, and public HTTPS OpenShift `Route` (`el-renovate-listener`).
   - Includes a CEL interceptor that listens for `push` events to `refs/heads/main` (while ignoring commits authored by Renovate `chore(deps):` to prevent infinite loops).
3. **Commit -> Tekton -> Automatic PR:**
   - Whenever a commit is pushed to `main`, GitHub sends a webhook to the OpenShift `EventListener` Route.
   - Tekton automatically launches a `renovate-on-commit-xxxxx` `PipelineRun`.
   - Renovate scans `pom.xml`, detects vulnerable `org.apache.commons:commons-compress:1.9`, looks up the patched release from `https://packages.redhat.com/lightwell/java/remediated/`, and automatically opens a remediation Pull Request on GitHub.

---

## 1-Click Setup in Red Hat Developer Sandbox

### Step 1: Launch in OpenShift DevSpaces
Click the button below (or replace the GitHub URL after `workspaces.openshift.com#` with your repository URL):

[![Open in Red Hat OpenShift DevSpaces](https://img.shields.io/badge/Open%20in-OpenShift%20DevSpaces-EE0000?style=for-the-badge&logo=redhat&logoColor=white)](https://workspaces.openshift.com#https://github.com/danmikita/lightwell-renovate-quarkus)

As soon as DevSpaces opens, the Tekton `Task`, `EventListener`, and `Route` are **already deployed** in your namespace automatically by the `postStart` hook.

---

### Step 2: Run the One-Click Tasks in DevSpaces

Open the **Terminal -> Run Task... -> devfile** menu in OpenShift DevSpaces (or run the commands in the terminal):

#### Task 1: `1. Start Quarkus Live Coding (/archive endpoint)`
Starts Quarkus in dev mode and opens `/archive`:
```text
Apache Commons Compress (TarArchiveInputStream) version: 1.9
```

#### Task 2: `2. Run Renovate Local Scan (Lightwell Repo Dry-Run)`
Runs `./run-demo-local.sh` (prompting once for your Lightwell Service Account username & token to configure `~/.m2/settings.xml` and `RENOVATE_HOST_RULES`) and runs `renovate` in `--platform=local --dry-run=lookup` mode to verify `org.apache.commons:commons-compress:1.9` remediation against `https://packages.redhat.com/lightwell/java/remediated/`.

#### Task 3: `3. Deploy App to OpenShift Sandbox (S2I Binary Build)`
Compiles the app and streams it into an OpenShift S2I binary build pushed directly to the internal OpenShift `ImageStream` (no external container registry required), creating the `Deployment`, `Service`, and HTTPS `Route`:
```bash
mvn clean package -DskipTests -Dquarkus.kubernetes.deploy=true
```

#### Task 4: `4. Configure Lightwell & GitHub Credentials + Auto-Register Webhook`
Prompts for your Lightwell Service Account credentials and GitHub Personal Access Token (`repo` + `admin:repo_hook` scopes) and runs [`./setup-sandbox.sh`](./setup-sandbox.sh), which:
1. Writes `~/.m2/settings.xml` with the `lightwell-remediated` profile and server credentials.
2. Creates the `renovate-credentials` Kubernetes Secret in your namespace (including `RENOVATE_HOST_RULES` for Lightwell authentication).
3. Queries the public URL of the `el-renovate-listener` OpenShift Route.
4. Calls the GitHub REST API to automatically register that Route URL as a push webhook on your repository.

*(Now any `git commit && git push` to `main` will automatically trigger Tekton in OpenShift and open a Renovate PR!)*

#### Task 5: `5. Manually Trigger Tekton Renovate PipelineRun Now`
If you want to trigger the Tekton `PipelineRun` on-demand without pushing a commit or configuring a webhook:
```bash
oc create -f tekton/tekton-pipeline-run.yaml
tkn pipelinerun logs --last -f
```

---

## Project Structure

```text
lightwell-renovate-quarkus/
├── README.md
├── devfile.yaml
├── pom.xml
├── renovate.json
├── run-demo-local.sh
├── setup-sandbox.sh
├── src/
│   └── main/
│       ├── java/
│       │   └── com/
│       │       └── redhat/
│       │           └── demo/
│       │               └── ArchiveResource.java
│       └── resources/
│           └── application.properties
└── tekton/
    ├── tekton-pipeline-run.yaml
    ├── tekton-renovate-task.yaml
    └── tekton-triggers.yaml
```
