#!/usr/bin/env node --import tsx
/**
 * paperclip-setup — single interactive CLI that handles the complete
 * Paperclip native onboarding flow.
 *
 * Usage:  node --import tsx scripts/cli.ts
 *
 * What it does:
 *   1. Checks / installs system deps (Node, pnpm, PostgreSQL)
 *   2. Clones/builds Paperclip
 *   3. Sets up PostgreSQL database
 *   4. Runs onboard (creates config), patches to authenticated mode
 *   5. Runs migrations, installs systemd service, starts server
 *   6. Creates bootstrap CEO invite (force if needed)
 *   7. Waits for you to claim the invite in your browser
 *   8. Auto‑creates a default company so you never see "No company access"
 */

import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

// ── Resolve paths ──────────────────────────────────────────────────
const ROOT = path.resolve(__dirname, "..");
const VENDOR_DIR = process.env.VENDOR_DIR || "/opt/paperclip-ai-onboarding/vendor/paperclip";
const SVC_HOME = "/var/lib/paperclip";
const SVC_INSTANCE = "default";
const CONFIG_PATH = `${SVC_HOME}/instances/${SVC_INSTANCE}/config.json`;
const DB_URL = "postgres://paperclip:paperclip@localhost:5432/paperclip";
const API_BASE = "http://127.0.0.1:3100";

// Detect public IP
function detectPublicIp(): string {
  try {
    for (const url of ["https://api.ipify.org", "https://checkip.amazonaws.com", "https://ifconfig.me/ip"]) {
      const out = execSync(`curl -4fsS --max-time 6 "${url}" 2>/dev/null`, { encoding: "utf8", timeout: 8000 }).trim();
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(out)) return out;
    }
  } catch { /* ignore */ }
  return "";
}

// ── CLI helpers ─────────────────────────────────────────────────────
function sh(cmd: string, opts?: { silent?: boolean; ignoreError?: boolean }): string {
  try {
    const out = execSync(cmd, { encoding: "utf8", stdio: opts?.silent ? "pipe" : "inherit" });
    return out;
  } catch (e: any) {
    if (opts?.ignoreError) return "";
    console.error(`\n  Command failed: ${cmd}`);
    console.error(`  ${e.stderr || e.message}`);
    throw e;
  }
}

function shQuiet(cmd: string): string {
  return sh(cmd, { silent: true, ignoreError: true });
}

function spinner(msg: string): { stop: (ok?: boolean) => void } {
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let i = 0;
  const timer = setInterval(() => {
    process.stderr.write(`\r  ${frames[i++ % frames.length]} ${msg}`);
  }, 80);
  return {
    stop(ok = true) {
      clearInterval(timer);
      const sym = ok ? "✔" : "✖";
      process.stderr.write(`\r  ${sym} ${msg}\n`);
    },
  };
}

// ── Step functions ──────────────────────────────────────────────────

async function step_install_deps(): Promise<void> {
  console.log("\n  Installing system dependencies...\n");
  sh("apt-get update -qq", { silent: true });
  sh("apt-get install -y --no-install-recommends curl git openssl postgresql postgresql-contrib");
  // Node.js >= 20
  const nodeVer = shQuiet("node -v 2>/dev/null | sed 's/v//' | cut -d. -f1");
  if (!nodeVer || parseInt(nodeVer) < 20) {
    sh("curl -fsSL https://deb.nodesource.com/setup_20.x | bash -", { silent: true });
    sh("apt-get install -y --no-install-recommends nodejs");
  }
  if (shQuiet("pnpm -v 2>/dev/null") === "") {
    sh("npm install -g pnpm");
  }
}

async function step_setup_postgres(): Promise<void> {
  console.log("\n  Setting up PostgreSQL...\n");
  sh("systemctl start postgresql || true", { ignoreError: true });
  sh("systemctl enable postgresql || true", { ignoreError: true });
  // Wait until PG is up
  for (let i = 0; i < 30; i++) {
    if (shQuiet('sudo -u postgres psql -c "\\q" 2>/dev/null; echo $?').trim() === "0") break;
    execSync("sleep 1");
  }
  const roleExists = shQuiet("sudo -u postgres psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='paperclip'\" 2>/dev/null");
  if (!roleExists.includes("1")) {
    sh('sudo -u postgres psql -c "CREATE USER paperclip WITH PASSWORD \'paperclip\' CREATEDB;"');
  }
  const dbExists = shQuiet("sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='paperclip'\" 2>/dev/null");
  if (!dbExists.includes("1")) {
    sh('sudo -u postgres psql -c "CREATE DATABASE paperclip OWNER paperclip;"');
  }
}

async function step_clone_build(): Promise<void> {
  console.log("\n  Preparing Paperclip source...\n");
  if (existsSync(`${VENDOR_DIR}/.git`)) {
    sh(`git -C "${VENDOR_DIR}" fetch --depth 1 origin master`, { ignoreError: true });
    sh(`git -C "${VENDOR_DIR}" reset --hard origin/master`, { ignoreError: true });
  } else {
    const parent = path.dirname(VENDOR_DIR);
    sh(`mkdir -p "${parent}"`);
    sh(`rm -rf "${VENDOR_DIR}"`);
    sh(`git clone --depth 1 https://github.com/paperclipai/paperclip.git "${VENDOR_DIR}"`);
  }
  console.log("\n  Building Paperclip...\n");
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  sh("pnpm install --frozen-lockfile || pnpm install", { silent: true });
  sh("pnpm --filter @paperclipai/shared build", { silent: true });
  sh("pnpm --filter @paperclipai/plugin-sdk build", { silent: true });
  sh("pnpm --filter @paperclipai/ui build", { silent: true });
  sh("pnpm --filter @paperclipai/server build", { silent: true });
  process.chdir(cwd);
}

async function step_run_onboard(): Promise<void> {
  console.log("\n  Initialising Paperclip instance...\n");
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  // Create .env
  const envPath = `${ROOT}/.env`;
  const auth = shQuiet("openssl rand -hex 32").trim();
  const agent = shQuiet("openssl rand -hex 32").trim();
  const fs = await import("node:fs");
  fs.writeFileSync(envPath, [
    `PAPERCLIP_PORT=3100`,
    `PAPERCLIP_DEPLOYMENT_MODE=authenticated`,
    `PAPERCLIP_DEPLOYMENT_EXPOSURE=private`,
    `BETTER_AUTH_SECRET=${auth}`,
    `PAPERCLIP_AGENT_JWT_SECRET=${agent}`,
    `DATABASE_URL=${DB_URL}`,
    `NINEROUTER_PORT=20128`,
    ``,
  ].join("\n"));

  // Run onboard -y
  sh(
    `PAPERCLIP_HOME="${SVC_HOME}" PAPERCLIP_CONFIG="${CONFIG_PATH}" DATABASE_URL="${DB_URL}" timeout --signal=SIGKILL 90s pnpm paperclipai onboard -y 2>&1 || true`,
    { silent: true }
  );
  sh("pkill -f 'paperclipai run' 2>/dev/null || true", { ignoreError: true });
  sh("pkill -f 'paperclipai onboard' 2>/dev/null || true", { ignoreError: true });

  // Copy config if needed
  if (existsSync(`${SVC_HOME}/.paperclip/instances/${SVC_INSTANCE}/config.json`) && !existsSync(CONFIG_PATH)) {
    sh(`mkdir -p "$(dirname "${CONFIG_PATH}")"`);
    sh(`cp "${SVC_HOME}/.paperclip/instances/${SVC_INSTANCE}/config.json" "${CONFIG_PATH}"`);
  }

  // Patch config to authenticated mode
  if (existsSync(CONFIG_PATH)) {
    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
    config.server.deploymentMode = "authenticated";
    config.server.bind = "lan";
    config.database = { mode: "postgres", connectionString: DB_URL };
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
    sh(`chown -R paperclip:paperclip "$(dirname "${CONFIG_PATH}")" 2>/dev/null || true`, { ignoreError: true });
  }

  process.chdir(cwd);
}

async function step_install_service(): Promise<void> {
  console.log("\n  Installing systemd service...\n");
  // Create service user
  shQuiet('id -u paperclip >/dev/null 2>&1 || useradd -r -s /bin/false -d "/var/lib/paperclip" paperclip');
  sh(`mkdir -p "${SVC_HOME}"`);
  sh(`chown paperclip:paperclip "${SVC_HOME}"`);
  sh(`mkdir -p /etc/paperclip`);
  sh(`cp "${ROOT}/.env" /etc/paperclip/.env`);
  sh(`chown paperclip:paperclip /etc/paperclip/.env`);

  // Render unit from template
  const template = path.join(ROOT, "scripts/systemd/paperclip.service.template");
  const fs = await import("node:fs");
  let unit = fs.readFileSync(template, "utf8");
  unit = unit
    .replace(/%%VENDOR_DIR%%/g, VENDOR_DIR)
    .replace(/%%SVC_HOME%%/g, SVC_HOME)
    .replace(/%%SVC_USER%%/g, "paperclip")
    .replace(/%%SVC_INSTANCE%%/g, SVC_INSTANCE);
  fs.writeFileSync("/etc/systemd/system/paperclip.service", unit);
  sh("chown root:root /etc/systemd/system/paperclip.service");
  sh("chmod 644 /etc/systemd/system/paperclip.service");
  sh("systemctl daemon-reload");
  sh("systemctl enable paperclip");
}

async function step_start_service(): Promise<void> {
  console.log("\n  Starting Paperclip...\n");
  sh("systemctl stop paperclip 2>/dev/null || true", { ignoreError: true });
  sh("systemctl start paperclip");
  for (let i = 0; i < 90; i++) {
    const ok = shQuiet(`curl -sfS --max-time 2 "${API_BASE}/api/health" >/dev/null 2>&1; echo $?`).trim();
    if (ok === "0") {
      console.log("  Paperclip is healthy.");
      return;
    }
    execSync("sleep 2");
  }
  throw new Error("Paperclip server did not become healthy within 3 minutes");
}

async function step_bootstrap_ceo(): Promise<string> {
  console.log("\n  Creating bootstrap CEO invite...\n");
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  const out = sh(`PAPERCLIP_HOME="${SVC_HOME}" PAPERCLIP_CONFIG="${CONFIG_PATH}" DATABASE_URL="${DB_URL}" pnpm paperclipai auth bootstrap-ceo --force 2>&1`, { silent: true });
  process.chdir(cwd);
  // Parse invite URL from output
  const match = out.match(/(https?:\/\/[^\s]+\/invite\/pcp_bootstrap_[a-fA-F0-9]+)/);
  return match ? match[1] : "";
}

async function step_wait_for_claim(): Promise<void> {
  console.log("\n  Waiting for you to claim the invite...\n");
  process.stdout.write("  Open the invite URL in your browser and sign in.\n");
  process.stdout.write("  ");
  while (true) {
    const health = shQuiet(`curl -sfS --max-time 5 "${API_BASE}/api/health" 2>/dev/null`);
    if (health.includes('"bootstrapStatus":"ready"')) {
      console.log("\n\n  Admin claimed!");
      return;
    }
    process.stdout.write(".");
    execSync("sleep 3");
  }
}

async function step_create_company(): Promise<string> {
  console.log("\n  Creating default company...\n");
  const exists = shQuiet(`sudo -u postgres psql "${DB_URL}" -tAc "SELECT 1 FROM companies LIMIT 1" 2>/dev/null`);
  if (exists.includes("1")) {
    console.log("  Company already present — skipping.");
    return "";
  }
  const cwd = process.cwd();
  process.chdir(VENDOR_DIR);
  const out = sh(`PAPERCLIP_HOME="${SVC_HOME}" PAPERCLIP_CONFIG="${CONFIG_PATH}" DATABASE_URL="${DB_URL}" pnpm paperclipai company create --payload-json '{"name":"My Company"}' 2>&1 | tail -20`, { silent: true });
  process.chdir(cwd);
  return out;
}

// ── Main ────────────────────────────────────────────────────────────

async function main() {
  console.log("\n╔══════════════════════════════════════════════╗");
  console.log("║   Paperclip Native Setup — Interactive CLI   ║");
  console.log("╚══════════════════════════════════════════════╝\n");

  // Check if already installed
  const isInstalled = existsSync(CONFIG_PATH);

  if (isInstalled) {
    console.log("  Existing Paperclip installation detected.");
    console.log("  [Enter] Re-run fresh  ·  [s] Skip to bootstrap  ·  [q] Quit\n");

    // Simple readline for menu
    const readline = await import("node:readline");
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const choice = await new Promise<string>((resolve) => {
      rl.question("  > ", (a) => { rl.close(); resolve(a.trim().toLowerCase()); });
    });
    if (choice === "q") { console.log("  Bye.\n"); return; }
    if (choice === "s") {
      // Skip ahead to bootstrap + company
      const invite = await step_bootstrap_ceo();
      if (!invite) {
        console.error("  Could not create bootstrap invite.\n");
        process.exit(1);
      }
      console.log(`\n  Invite: ${invite}\n`);
      await step_wait_for_claim();
      const result = await step_create_company();
      console.log(`\n  ${result}`);
      console.log("\n  All done. Open http://127.0.0.1:3100 to use Paperclip.\n");
      return;
    }
    // Default: re-run everything fresh
  }

  // --- Full install flow ---
  const pubIp = detectPublicIp();
  const pubUrl = pubIp ? `http://${pubIp}:3100` : "http://127.0.0.1:3100";

  console.log("  This will install Paperclip with:");
  console.log("    • Node.js 20 + pnpm");
  console.log("    • PostgreSQL (user: paperclip, db: paperclip)");
  console.log("    • Paperclip server as systemd service");
  console.log("    • Authenticated deployment mode");
  if (pubIp) console.log(`    • Public URL: ${pubUrl}`);
  console.log("");

  const readline = await import("node:readline");
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const confirm = await new Promise<string>((resolve) => {
    rl.question("  Proceed? [Y/n] ", (a) => { rl.close(); resolve(a.trim().toLowerCase()); });
  });
  if (confirm === "n" || confirm === "no") {
    console.log("  Aborted.\n");
    return;
  }

  console.log("\n── Step 1/8: System dependencies");
  await step_install_deps();

  console.log("\n── Step 2/8: PostgreSQL");
  await step_setup_postgres();

  console.log("\n── Step 3/8: Clone & build");
  await step_clone_build();

  console.log("\n── Step 4/8: Configure instance (onboard)");
  await step_run_onboard();

  console.log("\n── Step 5/8: Install systemd service");
  await step_install_service();

  console.log("\n── Step 6/8: Start server");
  await step_start_service();

  console.log("\n── Step 7/8: Bootstrap admin invite");
  const invite = await step_bootstrap_ceo();
  if (!invite) {
    console.error("  Could not create bootstrap invite.");
    process.exit(1);
  }

  console.log("\n╔═══════════════════════════════════════════════════════════════════╗");
  console.log("║                                                                   ║");
  console.log(`║   👤  Open this link in your browser to become the admin:           ║`);
  console.log(`║                                                                   ║`);
  console.log(`║   ${invite}`);
  console.log("║                                                                   ║");
  console.log("╚═══════════════════════════════════════════════════════════════════╝\n");

  console.log("── Step 8/8: Wait for admin claim + create company");
  await step_wait_for_claim();
  await step_create_company();

  console.log("\n╔═══════════════════════════════════════════════════════════════════╗");
  console.log("║                                                                   ║");
  console.log("║   ✅  Paperclip is ready!                                          ║");
  console.log("║                                                                   ║");
  console.log(`║   Local:  http://127.0.0.1:3100`);
  if (pubIp) {
    console.log(`║   Public: ${pubUrl}`);
  }
  console.log("║                                                                   ║");
  console.log("║   Company 'My Company' created — you are the owner.                ║");
  console.log("║                                                                   ║");
  console.log("╚═══════════════════════════════════════════════════════════════════╝\n");
}

main().catch((err) => {
  console.error(`\n  Fatal: ${err.message}\n`);
  process.exit(1);
});
