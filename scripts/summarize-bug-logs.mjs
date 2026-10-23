// Groups a fetch-bug-logs.ps1 export into distinct problems, so a week of
// logs can be read in one screen. Reads only the local JSON file.
//
// Usage (repo root):
//   node scripts/summarize-bug-logs.mjs                 # client-logs/prod-latest.json
//   node scripts/summarize-bug-logs.mjs emu --samples 3 # client-logs/emu-latest.json (test export)
//   node scripts/summarize-bug-logs.mjs client-logs/prod-20261022-120000.json
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Same problem = same type + source + error code + message with ids/numbers blanked. */
export const shape = (msg = "") =>
  String(msg)
    .split("\n")[0]
    .replace(/[A-Za-z0-9_-]{20,}/g, "<id>")
    .replace(/#?\d[\d.,:]*/g, "<n>")
    .slice(0, 140);

/** "iPhone Safari" / "Android Chrome" / "Windows Chrome" ... from a user-agent string. */
export function deviceClass(ua = "") {
  const s = String(ua);
  const os = /iPhone|iPad|iPod/i.test(s) ? "iPhone" : /Android/i.test(s) ? "Android"
    : /Windows/i.test(s) ? "Windows" : /Mac OS X|Macintosh/i.test(s) ? "Mac" : /Linux|CrOS/i.test(s) ? "Linux" : "?";
  const browser = /Edg\//i.test(s) ? "Edge" : /SamsungBrowser/i.test(s) ? "Samsung Browser"
    : /(Chrome|CriOS)\//i.test(s) ? "Chrome" : /Firefox|FxiOS/i.test(s) ? "Firefox"
    : /Safari\//i.test(s) ? "Safari" : "?";
  return `${os} ${browser}`;
}

const rank = { ERROR: 0, WARN: 1 };

/** Pure: logs[] -> distinct problems, most serious then most frequent first. */
export function summarize(logs) {
  const groups = new Map();
  for (const l of logs) {
    const key = [l.type, l.source, l.errorCode ?? "", shape(l.message)].join(" | ");
    let g = groups.get(key);
    if (!g) {
      g = { type: l.type, source: l.source, errorCode: l.errorCode ?? "", message: shape(l.message),
        count: 0, first: null, last: null, devices: new Set(), admins: 0, customers: 0, builds: new Set(), ids: [] };
      groups.set(key, g);
    }
    g.count++;
    const t = l.createdAtIst ?? "?";
    if (!g.first || t < g.first) g.first = t;
    if (!g.last || t > g.last) g.last = t;
    g.devices.add(deviceClass(l.userAgent));
    if (l.userId) g.admins++; else g.customers++;
    if (l.build) g.builds.add(l.build);
    g.ids.push(l.id);
  }
  return [...groups.values()].sort(
    (a, b) => (rank[a.type] ?? 9) - (rank[b.type] ?? 9) || b.count - a.count,
  );
}

function main() {
  const args = process.argv.slice(2);
  const target = args.find((a) => !a.startsWith("--")) ?? "prod";
  const samplesAt = args.indexOf("--samples");
  const samples = samplesAt >= 0 ? Number(args[samplesAt + 1]) || 2 : 2;
  const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
  const file = /\.json$/i.test(target) ? target : path.join(root, "client-logs", `${target}-latest.json`);
  if (!fs.existsSync(file)) {
    console.error(`No export at ${file}. Run: .\\scripts\\fetch-bug-logs.ps1`);
    process.exit(1);
  }
  const data = JSON.parse(fs.readFileSync(file, "utf8").replace(/^﻿/, ""));
  const logs = data.logs ?? [];
  const sorted = summarize(logs);

  console.log(`${data.project}${data.emulator ? " (LOCAL EMULATOR)" : ""} · fetched ${data.fetchedAt} · ${logs.length} logs · ${sorted.length} distinct problems`);
  console.log(`filters: ${JSON.stringify(data.filters)}`);
  console.log("");
  sorted.forEach((g, i) => {
    console.log(`#${i + 1}  ${g.type}  ${g.source}${g.errorCode ? `  [${g.errorCode}]` : ""}  ×${g.count}`);
    console.log(`    msg:     ${g.message}`);
    console.log(`    when:    ${g.first} → ${g.last}`);
    console.log(`    spread:  ${[...g.devices].join(", ")} · ${g.customers} customer / ${g.admins} admin · builds: ${[...g.builds].join(", ") || "-"}`);
    console.log(`    log ids: ${g.ids.slice(0, samples).join(", ")}${g.ids.length > samples ? ` (+${g.ids.length - samples})` : ""}`);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
