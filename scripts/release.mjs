#!/usr/bin/env node
/**
 * DSH 伴侣（dsh-companion）一键发布助手。
 *
 * 流程：workflow_dispatch(build.yml, release_tag) -> 轮询 run 状态 -> 成功后
 *       gh release download 到 dist/ -> 打印 APK 体积 / SHA256 / ABI 校验结果。
 *
 * 为什么不用 git push：本机 github.com:443 不可达，一切 GitHub 交互都走
 * `gh`（api.github.com），详见 docs/dev-environment.md。
 *
 * 用法（node 不在 PATH，用绝对路径调用）：
 *   node scripts/release.mjs v0.1.0                # 触发构建、等待、下载 APK
 *   node scripts/release.mjs v0.1.0 --download-only # 不触发，只下载已有 Release（验收入口）
 *   node scripts/release.mjs --status              # 查看最近 10 次 run
 *   node scripts/release.mjs v0.1.0 --timeout 60 --ref main --out-dir dist
 *
 * 退出码：0 成功；1 失败（CI 失败会打印失败步骤与日志尾部）。
 */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const OWNER = "youzhaiZhi";
const REPO = "dsh-companion";
const REPO_SLUG = `${OWNER}/${REPO}`;
const WORKFLOW = "build.yml";
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// ---------------------------------------------------------------- arguments
const HELP = `DSH 伴侣发布助手

用法:
  node scripts/release.mjs <tag> [选项]

参数:
  <tag>               发布标签，必须以 v 开头（如 v0.1.0）

选项:
  --download-only     不触发 workflow，只下载已有 Release 的 APK
  --status            只列出最近 10 次 CI run，然后退出
  --ref <branch>      workflow_dispatch 的分支，默认 main
  --timeout <分钟>    等待 CI 的超时，默认 40
  --out-dir <目录>    APK 下载目录，默认 <repo>/dist
  -h, --help          显示本帮助

示例:
  node scripts/release.mjs v0.1.0
  node scripts/release.mjs v0.1.0 --download-only
  node scripts/release.mjs --status
`;

let tag = "";
let ref = "main";
let timeoutMin = 40;
let downloadOnly = false;
let statusOnly = false;
let outDir = join(REPO_ROOT, "dist");

const rawArgs = process.argv.slice(2);
for (let i = 0; i < rawArgs.length; i += 1) {
  const arg = rawArgs[i];
  if (arg === "-h" || arg === "--help") {
    console.log(HELP);
    process.exit(0);
  } else if (arg === "--download-only") {
    downloadOnly = true;
  } else if (arg === "--status") {
    statusOnly = true;
  } else if (arg === "--ref") {
    ref = rawArgs[++i] || "";
  } else if (arg === "--timeout") {
    timeoutMin = Number(rawArgs[++i]);
  } else if (arg === "--out-dir") {
    outDir = resolve(REPO_ROOT, rawArgs[++i] || "dist");
  } else if (arg.startsWith("-")) {
    fail(`未知参数：${arg}\n\n${HELP}`);
  } else if (!tag) {
    tag = arg;
  } else {
    fail(`多余的参数：${arg}\n\n${HELP}`);
  }
}
if (statusOnly) {
  // 允许不带 tag
} else if (!tag) {
  fail(`缺少发布标签，例如：node scripts/release.mjs v0.1.0\n\n${HELP}`);
} else if (!/^v\d+\.\d+\.\d+([-.+].*)?$/.test(tag)) {
  fail(`发布标签必须以 v 开头且形如 v0.1.0，当前：${tag}`);
}

// ---------------------------------------------------------------- helpers
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function fail(message) {
  console.error(`❌ ${message}`);
  process.exit(1);
}

// api.github.com 在本机偶发 TLS 握手超时，所以所有 gh 调用都带超时，只读调用带重试。
const NET_TIMEOUT_MS = 120_000;

function gh(args, { timeout = NET_TIMEOUT_MS } = {}) {
  try {
    return execFileSync("gh", args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 64 * 1024 * 1024,
      windowsHide: true,
      timeout,
    });
  } catch (error) {
    const stderr = error.stderr ? String(error.stderr).trim() : "";
    const stdout = error.stdout ? String(error.stdout).trim() : "";
    if (error.killed || error.signal) {
      throw new Error(
        `gh ${args.join(" ")} 超时（${Math.round(timeout / 1000)}s），api.github.com 大概率网络抖动`,
      );
    }
    throw new Error(`gh ${args.join(" ")} 失败（exit ${error.status}）\n${stderr || stdout || error.message}`);
  }
}

function ghJson(args, options = {}) {
  const out = gh(args, options).trim();
  return out ? JSON.parse(out) : null;
}

/** 只读调用：网络抖动 / 5xx 时自动重试。 */
async function ghJsonRetry(args, { tries = 4, delayMs = 5_000, timeout } = {}) {
  let lastError = null;
  for (let attempt = 1; attempt <= tries; attempt += 1) {
    try {
      return ghJson(args, timeout ? { timeout } : {});
    } catch (error) {
      lastError = error;
      if (attempt < tries) {
        console.warn(`  (重试 ${attempt}/${tries - 1}) ${error.message.split("\n")[0]}`);
        await sleep(delayMs);
      }
    }
  }
  throw lastError;
}

function ghBuffer(args, { timeout = 300_000 } = {}) {
  return execFileSync("gh", args, {
    maxBuffer: 512 * 1024 * 1024,
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
    timeout,
  });
}

function humanSize(bytes) {
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(2)} ${units[unit]}`;
}

function runUrl(id) {
  return `https://github.com/${REPO_SLUG}/actions/runs/${id}`;
}

function ensureGhAuth() {
  try {
    gh(["auth", "status"], { timeout: 60_000 });
  } catch (error) {
    fail(
      `gh 未登录、无权限，或 api.github.com 当前不通：${error.message.split("\n")[0]}\n`
      + "请先运行 'gh auth status' 检查（需要 repo/workflow 权限）。",
    );
  }
}

// ---------------------------------------------------------------- status
async function printStatus() {
  ensureGhAuth();
  const runs = await ghJsonRetry([
    "run", "list",
    "--repo", REPO_SLUG,
    "--limit", "10",
    "--json", "databaseId,workflowName,displayTitle,event,status,conclusion,headBranch,createdAt,url",
  ]);
  if (!runs || runs.length === 0) {
    console.log("最近没有 CI run。");
    return;
  }
  console.log(`最近 ${runs.length} 次 run（${REPO_SLUG}）：\n`);
  for (const run of runs) {
    const state = run.status === "completed" ? run.conclusion : run.status;
    const icon = run.status === "completed"
      ? (run.conclusion === "success" ? "✅" : "❌")
      : "⏳";
    const when = new Date(run.createdAt).toLocaleString("zh-CN", { hour12: false });
    console.log(
      `${icon} #${run.databaseId} [${run.event}] ${run.headBranch} ${state} — ${run.displayTitle} (${when})`,
    );
    console.log(`   ${run.url}`);
  }
}

// ---------------------------------------------------------------- trigger
async function waitForNewRun(dispatchedAt) {
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    let runs = [];
    try {
      runs = await ghJsonRetry([
        "run", "list",
        "--repo", REPO_SLUG,
        "--workflow", WORKFLOW,
        "--event", "workflow_dispatch",
        "--limit", "10",
        "--json", "databaseId,status,conclusion,event,headBranch,createdAt,url,displayTitle",
      ], { tries: 2 });
    } catch (error) {
      console.warn(`  查询 run 列表失败，继续等待：${error.message.split("\n")[0]}`);
    }
    const fresh = (runs || []).filter(
      (run) => new Date(run.createdAt).getTime() >= dispatchedAt - 120_000,
    );
    if (fresh.length > 0) {
      return fresh[0];
    }
    await sleep(5_000);
  }
  throw new Error("120 秒内没有等到新的 workflow_dispatch run，请到 Actions 页面确认是否触发成功。");
}

function describeJobs(run) {
  return (run.jobs || [])
    .map((job) => {
      const state = job.status === "completed" ? job.conclusion : job.status;
      return `${job.name}=${state}`;
    })
    .join(" | ");
}

function printFailedLog(id) {
  console.log("\n----- 失败日志（gh run view --log-failed，尾部 200 行）-----");
  try {
    const log = gh(["run", "view", String(id), "--repo", REPO_SLUG, "--log-failed"]);
    const lines = log.split(/\r?\n/);
    console.log(lines.slice(-200).join("\n"));
  } catch (error) {
    console.log(`（拿不到失败日志：${error.message.split("\n")[0]}）`);
  }
  console.log("----- 日志结束 -----\n");
}

async function waitForRun(id) {
  const deadline = Date.now() + timeoutMin * 60_000;
  let lastSummary = "";
  let lastStatus = "";
  while (Date.now() < deadline) {
    let run = null;
    try {
      run = await ghJsonRetry([
        "run", "view", String(id),
        "--repo", REPO_SLUG,
        "--json", "status,conclusion,jobs,url,displayTitle",
      ], { tries: 2, timeout: 90_000 });
    } catch (error) {
      console.warn(`  查询 run 状态失败，继续等待：${error.message.split("\n")[0]}`);
      await sleep(10_000);
      continue;
    }
    const now = new Date().toLocaleTimeString("zh-CN", { hour12: false });
    const summary = describeJobs(run);
    if (summary !== lastSummary || run.status !== lastStatus) {
      console.log(`[${now}] run #${id} ${run.status}${run.conclusion ? ` (${run.conclusion})` : ""} — ${summary}`);
      lastSummary = summary;
      lastStatus = run.status;
    }
    if (run.status === "completed") {
      return run;
    }
    await sleep(10_000);
  }
  throw new Error(`等待 CI 超时（${timeoutMin} 分钟）：${runUrl(id)}`);
}

// ---------------------------------------------------------------- download
async function downloadApk(expectedTag) {
  mkdirSync(outDir, { recursive: true });
  console.log(`\n下载 Release ${expectedTag} 的 APK 到 ${outDir} ...`);
  let downloaded = false;
  try {
    gh(["release", "download", expectedTag, "--repo", REPO_SLUG, "--pattern", "*.apk", "--dir", outDir, "--clobber"], { timeout: 300_000 });
    downloaded = true;
  } catch (error) {
    console.warn(`gh release download 失败：${error.message.split("\n")[0]}`);
    console.warn("改用 api.github.com asset API 重试 ...");
  }

  if (!downloaded) {
    const release = await ghJsonRetry(["api", `repos/${REPO_SLUG}/releases/tags/${expectedTag}`]);
    const asset = (release.assets || []).find((a) => /\.apk$/i.test(a.name));
    if (!asset) {
      throw new Error(`Release ${expectedTag} 中找不到 .apk asset`);
    }
    const buffer = ghBuffer([
      "api", "-H", "Accept: application/octet-stream",
      `repos/${REPO_SLUG}/releases/assets/${asset.id}`,
    ]);
    writeFileSync(join(outDir, asset.name), buffer);
  }

  const apks = readdirSync(outDir)
    .filter((name) => /\.apk$/i.test(name))
    .map((name) => join(outDir, name))
    .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  if (apks.length === 0) {
    throw new Error(`下载完成但 ${outDir} 里没有 .apk 文件`);
  }
  return apks[0];
}

function inspectApk(apkPath) {
  const buffer = readFileSync(apkPath);
  const sha256 = createHash("sha256").update(buffer).digest("hex");
  const knownAbis = ["arm64-v8a", "armeabi-v7a", "x86", "x86_64"];
  const abis = knownAbis.filter((abi) => buffer.includes(Buffer.from(`lib/${abi}/`)));
  return {
    path: apkPath,
    bytes: buffer.length,
    size: humanSize(buffer.length),
    sha256,
    abis,
  };
}

function printApkSummary(tagName, apk, releaseUrl) {
  const onlyArm64 = apk.abis.length === 1 && apk.abis[0] === "arm64-v8a";
  console.log("\n================ 发布结果 ================");
  console.log(`标签   : ${tagName}`);
  console.log(`Release: ${releaseUrl}`);
  console.log(`APK    : ${apk.path}`);
  console.log(`大小   : ${apk.size} (${apk.bytes} bytes)`);
  console.log(`SHA256 : ${apk.sha256}`);
  console.log(`ABIs   : ${apk.abis.length > 0 ? apk.abis.join(", ") : "未识别到 lib/<abi>/ 目录"}`);
  console.log(`ABI 校验: ${onlyArm64 ? "通过（仅 arm64-v8a）✅" : "异常，请检查 APK ❌"}`);
  console.log("==========================================");
  if (!onlyArm64) {
    return false;
  }
  return true;
}

// ---------------------------------------------------------------- main
async function main() {
  ensureGhAuth();

  if (statusOnly) {
    await printStatus();
    return;
  }

  let releaseUrl = `https://github.com/${REPO_SLUG}/releases/tag/${tag}`;

  if (downloadOnly) {
    const release = await ghJsonRetry([
      "release", "view", tag,
      "--repo", REPO_SLUG,
      "--json", "tagName,url,assets,publishedAt,isDraft",
    ]);
    releaseUrl = release.url || releaseUrl;
    console.log(`Release ${release.tagName}（${release.publishedAt}）`);
    console.log(`  ${releaseUrl}`);
    for (const asset of release.assets || []) {
      console.log(`  asset: ${asset.name} (${humanSize(asset.size)})`);
    }
    const apkPath = await downloadApk(tag);
    const apk = inspectApk(apkPath);
    const ok = printApkSummary(tag, apk, releaseUrl);
    process.exitCode = ok ? 0 : 1;
    return;
  }

  // 1) 触发 workflow_dispatch
  console.log(`触发 ${WORKFLOW}（ref=${ref}, release_tag=${tag}）...`);
  const dispatchedAt = Date.now();
  try {
    gh(
      ["workflow", "run", WORKFLOW, "--repo", REPO_SLUG, "--ref", ref, "-f", `release_tag=${tag}`],
      { timeout: 90_000 },
    );
  } catch (error) {
    fail(
      `触发 workflow_dispatch 失败：${error.message}\n`
      + "如果是超时，请求可能已经生效——先运行 'node scripts/release.mjs --status' 确认，不要立刻重复触发。",
    );
  }
  console.log("已触发，等待 GitHub 创建 run ...");

  // 2) 找到并盯住新 run
  const queued = await waitForNewRun(dispatchedAt);
  console.log(`发现 run #${queued.databaseId}: ${runUrl(queued.databaseId)}`);
  const finished = await waitForRun(queued.databaseId);
  releaseUrl = releaseUrl || "";

  if (finished.conclusion !== "success") {
    const failed = (finished.jobs || []).filter((job) => job.conclusion === "failure");
    for (const job of failed) {
      const failedSteps = (job.steps || [])
        .filter((step) => step.conclusion === "failure")
        .map((step) => step.name);
      console.error(`\n❌ job「${job.name}」失败，失败步骤：${failedSteps.join(" -> ") || "(未知)"}`);
    }
    console.error(`\nrun: ${runUrl(queued.databaseId)}`);
    printFailedLog(queued.databaseId);
    process.exitCode = 1;
    return;
  }

  console.log(`\n✅ CI 成功：${runUrl(queued.databaseId)}`);

  // 3) 校验 Release 存在并下载 APK
  const release = await ghJsonRetry(["release", "view", tag, "--repo", REPO_SLUG, "--json", "tagName,url,assets"]);
  releaseUrl = release.url || releaseUrl;
  const apkPath = await downloadApk(tag);
  const apk = inspectApk(apkPath);
  const ok = printApkSummary(tag, apk, releaseUrl);
  process.exitCode = ok ? 0 : 1;
}

main().catch((error) => {
  console.error(`\n❌ ${error.stack || error.message || error}`);
  process.exit(1);
});
