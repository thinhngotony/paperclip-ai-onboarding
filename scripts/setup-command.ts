// Interactive all-in-one native setup command

import { execSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "../../../../..");
const VENDOR_DIR = process.env.VENDOR_DIR || "/opt/paperclip-ai-onboarding/vendor/paperclip";
const SVC_HOME = "/var/lib/paperclip";
const SVC_INSTANCE = "default";
const CONFIG_PATH = `${SVC_HOME}/instances/${SVC_INSTANCE}/config.json`;
const API_BASE = "http://127.0.0.1:3100";

// ── Resolve DB URL dynamically ─────────────────────────────────────
function resolveDbUrl(): string {
  try {
    const envContent = readFileSync("/etc/paperclip/.env", "utf8");
    const m = envContent.match(/^DATABASE_URL=(.+)$/m);
    if (m) return m[1].trim();
  } catch {}
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  // Auto-detect the actual PostgreSQL port before checking config (config may be stale)
  let port = "5432";
  try {
    const out = execSync("sudo -u postgres psql -tAc \"SHOW port;\" 2>/dev/null", { encoding: "utf8" });
    const m = out.match(/(\d+)/);
    if (m) port = m[1];
  } catch {}
  try {
    if (existsSync(CONFIG_PATH)) {
      const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
      if (config?.database?.mode === "embedded-postgres") {
        const ep = config.database.embeddedPostgresPort ?? 54329;
        return `postgres://paperclip:paperclip@127.0.0.1:${ep}/paperclip`;
      }
    }
  } catch {}
  return `postgres://paperclip:paperclip@localhost:${port}/paperclip`;
}

const DB_URL = resolveDbUrl();

// ── Helpers ──────────────────────────────────────────────────────────

function sh(cmd: string, opts?: { silent?: boolean; ignoreError?: boolean }): string {
  try {
    return execSync(cmd, { encoding: "utf8", stdio: opts?.silent ? "pipe" : "inherit" });
  } catch (e: any) {
    if (opts?.ignoreError) return "";
    console.error(e.stderr || e.message);
    throw e;
  }
}

function shQ(cmd: string): string {
  try { return execSync(cmd, { encoding: "utf8", stdio: "pipe" }).trim(); } catch { return ""; }
}

function pgSh(cmd: string): string {
  return sh(`sudo -u postgres ${cmd}`, { silent: true });
}
function pgShQ(cmd: string): string {
  try { return execSync(`sudo -u postgres ${cmd}`, { encoding: "utf8", stdio: "pipe" }).trim(); } catch { return ""; }
}

function detectPublicIp(): string {
  for (const url of ["https://api.ipify.org", "https://checkip.amazonaws.com", "https://ifconfig.me/ip"]) {
    try {
      const out = execSync(`curl -4fsS --max-time 6 "${url}" 2>/dev/null`, { encoding: "utf8", timeout: 8000 }).trim();
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(out)) return out;
    } catch {}
  }
  return "";
}

function spinnerMsg(msg: string) {
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let i = 0;
  const timer = setInterval(() => { process.stderr.write(`\r  ${frames[i++ % frames.length]} ${msg}`); }, 80);
  return () => { clearInterval(timer); process.stderr.write(`\r  ✔ ${msg}\n`); };
}

// ── 9Router detection & configuration ───────────────────────────────

interface RouterModel {
  id: string;
  owned_by?: string;
  display_name?: string;
}

async function detect9Router(): Promise<{ found: boolean; port: number; baseUrl: string }> {
  const port = parseInt(process.env.NINEROUTER_PORT || "20128");
  const bind = process.env.NINEROUTER_BIND_HOST || "127.0.0.1";
  const url = `http://${bind}:${port}/v1/models`;
  try {
    execSync(`curl -sfS --max-time 4 "${url}" >/dev/null 2>&1`, { encoding: "utf8" });
    return { found: true, port, baseUrl: `http://${bind}:${port}` };
  } catch {}
  return { found: false, port, baseUrl: "" };
}

async function fetch9RouterModels(): Promise<RouterModel[]> {
  const port = parseInt(process.env.NINEROUTER_PORT || "20128");
  const bind = process.env.NINEROUTER_BIND_HOST || "127.0.0.1";
  const url = `http://${bind}:${port}/v1/models`;
  try {
    const raw = execSync(`curl -sfS --max-time 5 "${url}"`, { encoding: "utf8" });
    const data = JSON.parse(raw);
    const items = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : [];
    return items.filter((m: any) => typeof m?.id === "string");
  } catch {}
  return [];
}

// Test which Claude models work through 9Router
async function probeWorkingClaudeModels(routerBase: string): Promise<string[]> {
  const candidates = await fetch9RouterModels();
  const working: string[] = [];

  // Quick test: send a minimal prompt with each model candidate
  for (const m of candidates) {
    // Only test models that look like Claude-compatible ones
    const id = m.id.toLowerCase();
    if (id === "command-code" || id === "free" || id === "super") {
      working.push(m.id);
      continue; // these always work
    }
    // Test kr/ and kc/ Claude models with a quick ping
    if (id.startsWith("kr/claude") || id.startsWith("kc/anthropic/claude") || id.startsWith("cu/claude")) {
      try {
        const result = execSync(
          `ANTHROPIC_BASE_URL="${routerBase}" ANTHROPIC_API_KEY=9router-local timeout 20 claude --model "${m.id}" --print "OK" 2>&1`,
          { encoding: "utf8", timeout: 25000 }
        );
        if (result.includes("OK")) working.push(m.id);
      } catch {
        // model doesn't work, skip
      }
    }
  }
  return working;
}

async function configure9Router(): Promise<boolean> {
  const router = await detect9Router();
  if (!router.found) {
    console.log("\n  9Router not detected — skipping LLM auto-config.");
    console.log("  You can set ANTHROPIC_API_KEY + ANTHROPIC_BASE_URL manually later.\n");
    return false;
  }

  console.log(`\n  9Router detected on http://127.0.0.1:${router.port}`);
  console.log("  Probing available Claude models...");

  const models = await fetch9RouterModels();
  const claudeModels = models.filter(m =>
    m.id === "command-code" ||
    m.id.startsWith("kr/claude") ||
    m.id.startsWith("kc/anthropic/claude") ||
    m.id.startsWith("cu/claude")
  );

  if (claudeModels.length === 0) {
    console.log("  No Claude-compatible models found in 9Router.");
    console.log("  Setting basic 9Router env vars anyway.");
  } else {
    console.log("  Available Claude models in 9Router:");
    for (const m of claudeModels) {
      console.log(`    • ${m.id}`);
    }
  }

  // Ask user if they want auto-config
  console.log("");
  const { createInterface } = await import("node:readline");
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise<string>((r) =>
    rl.question("  Auto-configure 9Router for Claude Code? [Y/n] ", (a) => { rl.close(); r(a.trim().toLowerCase()); })
  );
  if (answer === "n" || answer === "no") {
    console.log("  Skipping — you can configure later in /etc/paperclip/.env\n");
    return false;
  }

  // Write env vars
  const envPath = "/etc/paperclip/.env";
  const env = readFileSync(envPath, "utf8");
  const lines = env.split("\n").filter(l =>
    !l.startsWith("ANTHROPIC_BASE_URL=") &&
    !l.startsWith("ANTHROPIC_API_KEY=") &&
    !l.startsWith("OPENAI_BASE_URL=") &&
    !l.startsWith("OPENAI_API_KEY=") &&
    !l.startsWith("NINEROUTER_PORT=")
  ).filter(l => l.trim() !== "");

  lines.push(
    `NINEROUTER_PORT=${router.port}`,
    `OPENAI_BASE_URL=http://127.0.0.1:${router.port}/v1`,
    `OPENAI_API_KEY=9router-local`,
    `ANTHROPIC_BASE_URL=http://127.0.0.1:${router.port}`,
    `ANTHROPIC_API_KEY=9router-local`,
    ``
  );
  writeFileSync(envPath, lines.join("\n"));
  console.log("  9Router config written to /etc/paperclip/.env");

  // Update the Claude Local adapter model list with 9Router models
  updateClaudeLocalModels(claudeModels);

  // Restart service to pick up new env
  console.log("  Restarting Paperclip to apply new config...");
  sh("systemctl restart paperclip", { silent: true });
  // Wait for it to come back
  for (let i = 0; i < 60; i++) {
    if (shQ(`curl -sfS --max-time 2 "${API_BASE}/api/health" 2>/dev/null; echo $?`).includes("0")) {
      console.log("  Paperclip restarted with 9Router.");
      break;
    }
    execSync("sleep 2");
  }
  return true;
}

function updateClaudeLocalModels(_9routerModels: RouterModel[]) {
  // Rebuild the adapter index with 9Router models
  const indexPath = `${VENDOR_DIR}/packages/adapters/claude-local/src/index.ts`;
  if (!existsSync(indexPath)) return;

  const extra = _9routerModels
    .map(m => `  { id: "${m.id}", label: "${m.display_name || m.id} (9Router)" },`)
    .join("\n");

  const newContent = `import type { AdapterModelProfileDefinition } from "@paperclipai/adapter-utils";

export const type = "claude_local";
export const label = "Claude Code (local)";

export const SANDBOX_INSTALL_COMMAND = "npm install -g @anthropic-ai/claude-code";

export const models = [
  { id: "command-code", label: "Command Code (Claude Code)" },
${extra}
  { id: "claude-opus-4-8", label: "Claude Opus 4.8" },
  { id: "claude-opus-4-7", label: "Claude Opus 4.7" },
  { id: "claude-opus-4-6", label: "Claude Opus 4.6" },
  { id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6" },
  { id: "claude-haiku-4-6", label: "Claude Haiku 4.6" },
  { id: "claude-sonnet-4-5-20250929", label: "Claude Sonnet 4.5" },
  { id: "claude-haiku-4-5-20251001", label: "Claude Haiku 4.5" },
];

export const modelProfiles: AdapterModelProfileDefinition[] = [
  {
    key: "cheap",
    label: "Cheap",
    description: "Use Claude Sonnet as the lower-cost Claude Code lane while preserving the agent's primary model.",
    adapterConfig: {
      model: "claude-sonnet-4-6",
      effort: "low",
    },
    source: "adapter_default",
  },
];

export const agentConfigurationDoc = \`# claude_local agent configuration

Adapter: claude_local

Core fields:
- cwd (string, optional): default absolute working directory fallback for the agent process (created if missing when possible)
- instructionsFilePath (string, optional): absolute path to a markdown instructions file injected at runtime
- model (string, optional): Claude model id
- effort (string, optional): reasoning effort passed via --effort (low|medium|high)
- chrome (boolean, optional): pass --chrome when running Claude
- promptTemplate (string, optional): run prompt template
- maxTurnsPerRun (number, optional): max turns for one run
- dangerouslySkipPermissions (boolean, optional, default true): pass --dangerously-skip-permissions to claude; defaults to true because Paperclip runs Claude in headless --print mode where interactive permission prompts cannot be answered
- command (string, optional): defaults to "claude"
- extraArgs (string[], optional): additional CLI args
- env (object, optional): KEY=VALUE environment variables
- workspaceStrategy (object, optional): execution workspace strategy; currently supports { type: "git_worktree", baseRef?, branchTemplate?, worktreeParentDir? }
- workspaceRuntime (object, optional): reserved for workspace runtime metadata; workspace runtime services are manually controlled from the workspace UI and are not auto-started by heartbeats

Operational fields:
- timeoutSec (number, optional): run timeout in seconds
- graceSec (number, optional): SIGTERM grace period in seconds

Notes:
- When Paperclip realizes a workspace/runtime for a run, it injects PAPERCLIP_WORKSPACE_* and PAPERCLIP_RUNTIME_* env vars for agent-side tooling.
\`;
`;
  writeFileSync(indexPath, newContent);
}

// ── Steps ────────────────────────────────────────────────────────────

async function stepDeps(): Promise<void> {
  process.stdout.write("  Checking system dependencies...\n");
  sh("apt-get update -qq 2>/dev/null", { silent: true, ignoreError: true });
  const missing: string[] = [];
  for (const pkg of ["curl", "git", "openssl", "postgresql", "postgresql-contrib"]) {
    if (!shQ(`dpkg -s ${pkg} 2>/dev/null | grep -q 'ok installed' && echo OK`).includes("OK")) {
      missing.push(pkg);
    }
  }
  if (missing.length > 0) {
    sh(`apt-get install -y --no-install-recommends ${missing.join(" ")}`, { silent: true });
  }

  const nv = shQ("node -v 2>/dev/null | sed 's/v//' | cut -d. -f1");
  if (!nv || parseInt(nv) < 20) {
    sh("curl -fsSL https://deb.nodesource.com/setup_20.x | bash -", { silent: true });
    sh("apt-get install -y --no-install-recommends nodejs", { silent: true });
  }
  if (!shQ("pnpm -v 2>/dev/null")) sh("npm install -g pnpm", { silent: true });
  process.stdout.write("  Dependencies ready.\n");
}

async function stepPostgres(): Promise<void> {
  process.stdout.write("  Setting up PostgreSQL...\n");
  sh("systemctl start postgresql 2>/dev/null || true", { ignoreError: true });
  sh("systemctl enable postgresql 2>/dev/null || true", { ignoreError: true });
  for (let i = 0; i < 30; i++) {
    if (pgShQ('psql -c "\\q" 2>/dev/null && echo OK').includes("OK")) break;
    execSync("sleep 1");
  }
  if (!pgShQ("psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='paperclip'\" 2>/dev/null").includes("1")) {
    pgSh("psql -c \"CREATE USER paperclip WITH PASSWORD 'paperclip' CREATEDB;\"");
  }
  if (!pgShQ("psql -tAc \"SELECT 1 FROM pg_database WHERE datname='paperclip'\" 2>/dev/null").includes("1")) {
    pgSh("psql -c 'CREATE DATABASE paperclip OWNER paperclip;'");
  }
  process.stdout.write("  PostgreSQL ready.\n");
}

async function stepCloneBuild(): Promise<void> {
  const done = spinnerMsg("Cloning / building Paperclip...");
  if (existsSync(`${VENDOR_DIR}/.git`)) {
    sh(`git -C "${VENDOR_DIR}" fetch --depth 1 origin master`, { silent: true, ignoreError: true });
    sh(`git -C "${VENDOR_DIR}" reset --hard origin/master`, { silent: true, ignoreError: true });
  } else {
    const parent = path.dirname(VENDOR_DIR);
    sh(`mkdir -p "${parent}"`);
    sh(`rm -rf "${VENDOR_DIR}"`);
    sh(`git clone --depth 1 https://github.com/paperclipai/paperclip.git "${VENDOR_DIR}"`, { silent: true });
  }
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  sh("find packages/plugins -name 'plugin-sdk' -type l -path '*/node_modules/*' -delete 2>/dev/null; pnpm install --ignore-scripts 2>&1", { silent: true });
  sh("pnpm install 2>&1 || true", { silent: true });
  sh("pnpm --filter @paperclipai/shared build", { silent: true });
  sh("pnpm --filter @paperclipai/plugin-sdk build", { silent: true });
  sh("pnpm --filter @paperclipai/ui build", { silent: true });
  sh("pnpm --filter @paperclipai/server build", { silent: true });
  process.chdir(cwd);

  // Copy patched CLI files from our repo into the cloned Paperclip monorepo
  const srcSetup = path.resolve(ROOT, "scripts/setup-command.ts");
  const srcIndex = path.resolve(ROOT, "scripts/index-command.ts");
  const dstSetup = path.resolve(VENDOR_DIR, "cli/src/commands/setup.ts");
  const dstIndex = path.resolve(VENDOR_DIR, "cli/src/index.ts");
  if (existsSync(srcSetup)) sh(`cp "${srcSetup}" "${dstSetup}"`, { silent: true });
  if (existsSync(srcIndex)) sh(`cp "${srcIndex}" "${dstIndex}"`, { silent: true });

  done();
}

async function stepOnboard(): Promise<void> {
  const done = spinnerMsg("Configuring instance (onboard)...");

  const rootEnv = path.resolve(ROOT, ".env");
  const auth = shQ("openssl rand -hex 32");
  const agent = shQ("openssl rand -hex 32");
  writeFileSync(rootEnv, [
    `PAPERCLIP_PORT=3100`,
    `PAPERCLIP_DEPLOYMENT_MODE=authenticated`,
    `PAPERCLIP_DEPLOYMENT_EXPOSURE=private`,
    `BETTER_AUTH_SECRET=${auth}`,
    `PAPERCLIP_AGENT_JWT_SECRET=${agent}`,
    `DATABASE_URL=${DB_URL}`,
    `NINEROUTER_PORT=20128`,
    ``,
  ].join("\n"));

  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  sh(
    `PAPERCLIP_HOME="${SVC_HOME}" PAPERCLIP_CONFIG="${CONFIG_PATH}" DATABASE_URL="${DB_URL}" timeout --signal=SIGKILL 90s pnpm paperclipai onboard -y 2>&1 || true`,
    { silent: true, ignoreError: true }
  );
  sh("pkill -f 'paperclipai run' 2>/dev/null || true", { ignoreError: true });
  sh("pkill -f 'paperclipai onboard' 2>/dev/null || true", { ignoreError: true });

  const altConfig = `${SVC_HOME}/.paperclip/instances/${SVC_INSTANCE}/config.json`;
  if (existsSync(altConfig) && !existsSync(CONFIG_PATH)) {
    const destDir = path.dirname(CONFIG_PATH);
    sh(`mkdir -p "${destDir}"`);
    sh(`cp "${altConfig}" "${CONFIG_PATH}"`);
    const altDir = path.dirname(altConfig);
    for (const sub of ["secrets", "data"]) {
      if (existsSync(`${altDir}/${sub}`)) sh(`cp -a "${altDir}/${sub}" "${destDir}/"`);
    }
  }

  if (existsSync(CONFIG_PATH)) {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
    config.server.deploymentMode = "authenticated";
    config.server.bind = "lan";
    config.database = { mode: "postgres", connectionString: DB_URL };
    writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
    sh(`chown -R paperclip:paperclip "$(dirname "${CONFIG_PATH}")" 2>/dev/null || true`, { ignoreError: true });
  }
  process.chdir(cwd);
  done();
}

async function stepRunMigrations(): Promise<void> {
  const done = spinnerMsg("Running database migrations...");
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  execSync(`DATABASE_URL="${DB_URL}" pnpm --filter @paperclipai/db migrate`, { encoding: "utf8", stdio: "pipe" });
  process.chdir(cwd);
  done();
}

async function stepInstallService(): Promise<void> {
  const done = spinnerMsg("Installing systemd service...");
  execSync('id -u paperclip >/dev/null 2>&1 || useradd -r -s /bin/false -d "/var/lib/paperclip" paperclip');
  sh(`mkdir -p "${SVC_HOME}"`);
  sh(`chown paperclip:paperclip "${SVC_HOME}"`);
  sh("mkdir -p /etc/paperclip");
  sh(`cp "${path.resolve(ROOT, '.env')}" /etc/paperclip/.env`);
  sh("chown paperclip:paperclip /etc/paperclip/.env");

  const templatePath = path.resolve(ROOT, "scripts/systemd/paperclip.service.template");
  const template = readFileSync(templatePath, "utf8");
  const unit = template
    .replace(/%%VENDOR_DIR%%/g, VENDOR_DIR)
    .replace(/%%SVC_HOME%%/g, SVC_HOME)
    .replace(/%%SVC_USER%%/g, "paperclip")
    .replace(/%%SVC_INSTANCE%%/g, SVC_INSTANCE);

  writeFileSync("/etc/systemd/system/paperclip.service", unit);
  sh("chown root:root /etc/systemd/system/paperclip.service");
  sh("chmod 644 /etc/systemd/system/paperclip.service");
  sh("systemctl daemon-reload");
  sh("systemctl enable paperclip");
  done();
}

async function stepStartService(): Promise<void> {
  const done = spinnerMsg("Starting Paperclip service...");
  sh("systemctl stop paperclip 2>/dev/null || true", { ignoreError: true });
  sh("systemctl start paperclip");
  for (let i = 0; i < 90; i++) {
    if (shQ(`curl -sfS --max-time 2 "${API_BASE}/api/health" >/dev/null 2>&1; echo $?`) === "0") {
      done();
      return;
    }
    execSync("sleep 2");
  }
  throw new Error("Paperclip server did not become healthy within 3 minutes");
}

async function stepBootstrapCeo(): Promise<string> {
  console.log("  Generating admin invite...\n");
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  const out = execSync(
    `PAPERCLIP_HOME="${SVC_HOME}" PAPERCLIP_CONFIG="${CONFIG_PATH}" DATABASE_URL="${DB_URL}" pnpm paperclipai auth bootstrap-ceo --force 2>&1`,
    { encoding: "utf8" }
  );
  process.chdir(cwd);
  const match = out.match(/(https?:\/\/[^\s]+\/invite\/pcp_bootstrap_[a-fA-F0-9]+)/);
  return match ? match[1] : "";
}

async function stepWaitForClaim(): Promise<void> {
  process.stdout.write("  Open the invite link in your browser and sign in.\n  ");
  while (true) {
    if (shQ(`curl -sfS --max-time 5 "${API_BASE}/api/health" 2>/dev/null`).includes('"bootstrapStatus":"ready"')) {
      console.log("\n\n  Admin claimed!");
      return;
    }
    process.stdout.write(".");
    execSync("sleep 3");
  }
}

async function stepCreateCompany(): Promise<void> {
  const done = spinnerMsg("Creating default company 'My Company'...");
  if (pgShQ(`psql "${DB_URL}" -tAc "SELECT 1 FROM companies LIMIT 1" 2>/dev/null`).includes("1")) {
    done();
    return;
  }
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  execSync(
    `PAPERCLIP_HOME="${SVC_HOME}" PAPERCLIP_CONFIG="${CONFIG_PATH}" DATABASE_URL="${DB_URL}" pnpm paperclipai company create --payload-json '{"name":"My Company"}' 2>&1 | tail -20`,
    { encoding: "utf8" }
  );
  process.chdir(cwd);
  done();
}

// ── Main ────────────────────────────────────────────────────────────

export async function setup(opts?: { force?: boolean }) {
  console.log("\n╔══════════════════════════════════════════════╗");
  console.log("║     Paperclip Native Setup — One-Shot CLI     ║");
  console.log("╚══════════════════════════════════════════════╝");

  const isInstalled = existsSync(CONFIG_PATH);
  const pubIp = detectPublicIp();
  const pubUrl = pubIp ? `http://${pubIp}:3100` : "http://127.0.0.1:3100";

  console.log(`  Database: ${DB_URL}`);

  if (isInstalled && !opts?.force) {
    console.log("\n  Existing installation found.\n");
    console.log("  [1] Fresh reinstall (wipe & rebuild)");
    console.log("  [2] Quick bootstrap (invite + company only)");
    console.log("  [3] Create company only");
    console.log("  [4] Re-detect 9Router and reconfigure");
    console.log("  [q] Quit\n");

    const { createInterface } = await import("node:readline");
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const choice = await new Promise<string>((r) => rl.question("  > ", (a) => { rl.close(); r(a.trim().toLowerCase()); }));

    if (choice === "q") { console.log("  Bye.\n"); return; }
    if (choice === "3") { await stepCreateCompany(); return; }
    if (choice === "4") { await configure9Router(); return; }
    if (choice === "2") {
      const invite = await stepBootstrapCeo();
      if (!invite) { console.error("  Failed to create invite.\n"); process.exit(1); }
      console.log(`\n╔══════════════════════════════════════════════════════════════╗`);
      console.log(`║  Open this link in your browser to become the admin:          ║`);
      console.log(`║      ${invite}`);
      console.log(`╚══════════════════════════════════════════════════════════════╝\n`);
      await stepWaitForClaim();
      await stepCreateCompany();
      console.log(`\n  Done. Open ${pubUrl} to use Paperclip.\n`);
      return;
    }
    // Fresh reinstall — wipe old data
    console.log("  Wiping old instance data...");
    sh("systemctl stop paperclip 2>/dev/null || true", { ignoreError: true });
    pgShQ(`psql "${DB_URL}" -c "DELETE FROM company_memberships; DELETE FROM companies; DELETE FROM invites WHERE inviteType='bootstrap_ceo'; DELETE FROM instance_user_roles WHERE role='instance_admin';" 2>/dev/null`);
    sh("rm -rf /var/lib/paperclip /etc/paperclip 2>/dev/null || true", { ignoreError: true });
  }

  // ── Full pipeline ──
  console.log("\n  Step 1/10: System dependencies");
  await stepDeps();

  console.log("  Step 2/10: PostgreSQL");
  await stepPostgres();

  console.log("  Step 3/10: Clone & build Paperclip");
  await stepCloneBuild();

  console.log("  Step 4/10: Configure instance (onboard)");
  await stepOnboard();

  console.log("  Step 5/10: Run database migrations");
  await stepRunMigrations();

  console.log("  Step 6/10: Install systemd service");
  await stepInstallService();

  console.log("  Step 7/10: Start server");
  await stepStartService();

  console.log("\n  Step 8/10: Auto-detect 9Router");
  const routerConfigured = await configure9Router();

  console.log("\n  Step 9/10: Bootstrap admin invite");
  const invite = await stepBootstrapCeo();
  if (!invite) {
    console.error("\n  Could not create bootstrap invite. Check the logs.\n");
    process.exit(1);
  }

  console.log(`\n╔══════════════════════════════════════════════════════════════╗`);
  console.log(`║                                                              ║`);
  console.log(`║  Open this link in your browser to become the admin:           ║`);
  console.log(`║                                                              ║`);
  console.log(`║  ${invite}`);
  console.log(`║                                                              ║`);
  console.log(`╚══════════════════════════════════════════════════════════════╝`);

  console.log("\n  Step 10/10: Wait for admin claim + auto-create company");
  await stepWaitForClaim();
  await stepCreateCompany();

  const modelsTag = routerConfigured ? " + 9Router models configured" : "";

  console.log(`\n╔══════════════════════════════════════════════════════════════╗`);
  console.log(`║                                                              ║`);
  console.log(`║  Paperclip is ready!${modelsTag}                                          ║`);
  console.log(`║                                                              ║`);
  console.log(`║  Local:  http://127.0.0.1:3100`);
  if (pubIp) console.log(`║  Public: ${pubUrl}`);
  console.log(`║                                                              ║`);
  console.log(`║  Company 'My Company' created — you are the owner.            ║`);
  console.log(`║                                                              ║`);
  console.log(`╚══════════════════════════════════════════════════════════════╝\n`);
}
