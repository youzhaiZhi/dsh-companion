#!/usr/bin/env node
/**
 * Push the current working tree to GitHub through the Git Data REST API.
 *
 * Why not `git push`: on this machine github.com:443 is unreachable (git-over-HTTPS
 * times out), while api.github.com works through the authenticated `gh` CLI.
 * This script mirrors the working tree into one commit (full-tree snapshot, so
 * deleted files are deleted) and fast-forwards the branch ref.
 *
 * Usage:
 *   node scripts/push_github.mjs "commit message"
 *
 * Requires: `gh` on PATH and authenticated (`gh auth status`).
 */
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const OWNER = "youzhaiZhi";
const REPO = "dsh-companion";
const BRANCH = "main";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Directories/files never pushed. */
const EXCLUDE_DIRS = new Set([
  ".git",
  ".dart_tool",
  "build",
  "dist",
  "node_modules",
  ".idea",
  ".vscode",
  "android/.gradle",
  "android/local.properties",
]);
const EXCLUDE_PATTERNS = [
  /^\.flutter-plugins(-dependencies)?$/,
  /^\.packages$/,
  /^android\/local\.properties$/,
  /\.apk$/i,
  /\.aab$/i,
  /\.jks$/i,
  /\.keystore$/i,
  /^test\/.*\.golden\.png$/i,
];
const BINARY_EXT = new Set([
  ".apk", ".aab", ".jar", ".png", ".jpg", ".jpeg", ".webp", ".ico",
  ".ttf", ".otf", ".woff", ".woff2", ".zip", ".gz", ".gif", ".pdf",
]);
const MAX_BLOB_BYTES = 45 * 1024 * 1024;

const token = execFileSync("gh", ["auth", "token"], { encoding: "utf8" }).trim();
if (!token) {
  console.error("gh auth token is empty; run `gh auth login` first.");
  process.exit(1);
}

const message = process.argv.slice(2).join(" ").trim() || "chore: update from local workspace";

async function api(method, path, body) {
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "dsh-companion-push",
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${path} -> ${res.status}\n${text}`);
  }
  return text ? JSON.parse(text) : undefined;
}

/** Collect workspace files (relative, forward-slash paths). */
function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const abs = join(dir, name);
    const rel = relative(ROOT, abs).split("\\").join("/");
    const st = statSync(abs);
    if (st.isDirectory()) {
      if (EXCLUDE_DIRS.has(rel) || EXCLUDE_DIRS.has(name)) continue;
      walk(abs, out);
      continue;
    }
    if (EXCLUDE_DIRS.has(rel)) continue;
    if (EXCLUDE_PATTERNS.some((re) => re.test(rel))) continue;
    if (st.size > MAX_BLOB_BYTES) {
      console.warn(`skip oversized file (${st.size} B): ${rel}`);
      continue;
    }
    out.push({ path: rel, abs, size: st.size });
  }
  return out;
}

function isBinary(buf, rel) {
  const ext = rel.slice(rel.lastIndexOf(".")).toLowerCase();
  if (BINARY_EXT.has(ext)) return true;
  const probe = buf.subarray(0, Math.min(buf.length, 8000));
  return probe.includes(0);
}

async function main() {
  const files = walk(ROOT).sort((a, b) => a.path.localeCompare(b.path));
  console.log(`files: ${files.length} (${files.reduce((n, f) => n + f.size, 0)} bytes)`);

  // Resolve current branch head, if any.
  let parentSha = null;
  let baseTree = null;
  try {
    const ref = await api("GET", `/repos/${OWNER}/${REPO}/git/ref/heads/${BRANCH}`);
    parentSha = ref.object.sha;
    const commit = await api("GET", `/repos/${OWNER}/${REPO}/git/commits/${parentSha}`);
    baseTree = commit.tree.sha;
  } catch (error) {
    // An empty repository answers 409 "Git Repository is empty"; a missing
    // branch/ref answers 404. Both mean: create the first commit.
    const text = String(error.message);
    if (!text.includes("404") && !text.includes("409")) throw error;
    console.log("repository branch is empty; creating an initial commit via the contents API");
    // GitHub's Git Data API cannot create a tree in a repository that has no
    // commits at all (409). Seed one small commit, then snapshot on top of it.
    await api("PUT", `/repos/${OWNER}/${REPO}/contents/.gitkeep`, {
      message: "chore: initialize repository",
      content: Buffer.from("").toString("base64"),
    });
    const ref = await api("GET", `/repos/${OWNER}/${REPO}/git/ref/heads/${BRANCH}`);
    parentSha = ref.object.sha;
    const commit = await api("GET", `/repos/${OWNER}/${REPO}/git/commits/${parentSha}`);
    baseTree = commit.tree.sha;
  }

  const tree = [];
  let binaryCount = 0;
  for (const file of files) {
    const buf = readFileSync(file.abs);
    if (isBinary(buf, file.path)) {
      const blob = await api("POST", `/repos/${OWNER}/${REPO}/git/blobs`, {
        content: buf.toString("base64"),
        encoding: "base64",
      });
      tree.push({ path: file.path, mode: "100644", type: "blob", sha: blob.sha });
      binaryCount += 1;
    } else {
      tree.push({ path: file.path, mode: "100644", type: "blob", content: buf.toString("utf8") });
    }
  }
  console.log(`binary blobs: ${binaryCount}`);

  // Full-tree snapshot (no base_tree): the commit matches the workspace exactly.
  const newTree = await api("POST", `/repos/${OWNER}/${REPO}/git/trees`, { tree });
  const commit = await api("POST", `/repos/${OWNER}/${REPO}/git/commits`, {
    message,
    tree: newTree.sha,
    parents: parentSha ? [parentSha] : [],
  });

  if (parentSha) {
    await api("PATCH", `/repos/${OWNER}/${REPO}/git/refs/heads/${BRANCH}`, {
      sha: commit.sha,
      force: false,
    });
  } else {
    await api("POST", `/repos/${OWNER}/${REPO}/git/refs`, {
      ref: `refs/heads/${BRANCH}`,
      sha: commit.sha,
    });
  }

  console.log(`pushed ${commit.sha.slice(0, 10)} -> ${OWNER}/${REPO}#${BRANCH}`);
  console.log(`https://github.com/${OWNER}/${REPO}/commit/${commit.sha}`);
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exit(1);
});
