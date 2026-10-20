#!/usr/bin/env node
// Turns a `claude -p --output-format stream-json --verbose` run into the
// markdown transcript an audit carries (docs/design/agent-mcp.md, "Trying it"):
// what the agent said, each tool call with its arguments, and the start of
// each answer. Pictures are noted, not inlined.
//
//   Scripts/agent-transcript.mjs <run.jsonl> [--title "..."] > transcript.md
//
// Ends with the run's own totals (turns, time, tool calls by name).
import { readFileSync } from "node:fs";

const [file, ...rest] = process.argv.slice(2);
if (!file) {
  console.error("usage: Scripts/agent-transcript.mjs <run.jsonl> [--title \"...\"]");
  process.exit(1);
}
const titleAt = rest.indexOf("--title");
const title = titleAt >= 0 ? rest[titleAt + 1] : null;
const longest = 400;

const clip = (text) => (text.length > longest ? text.slice(0, longest) + " …" : text);
const bare = (name) => name.replace(/^mcp__[^_]+(?:_[^_]+)*?__/, "");

const out = [];
if (title) out.push(`## ${title}`, "");
const calls = new Map();
let result;
for (const line of readFileSync(file, "utf8").split("\n")) {
  if (!line.trim()) continue;
  let event;
  try { event = JSON.parse(line); } catch { continue; }
  if (event.type === "assistant") {
    for (const part of event.message?.content ?? []) {
      if (part.type === "text" && part.text.trim()) {
        out.push(part.text.trim().split("\n").map((l) => `> ${l}`).join("\n"), "");
      } else if (part.type === "tool_use") {
        const name = bare(part.name);
        calls.set(name, (calls.get(name) ?? 0) + 1);
        out.push(`**Tool call** \`${name}\` \`${clip(JSON.stringify(part.input))}\``, "");
      }
    }
  } else if (event.type === "user") {
    for (const part of event.message?.content ?? []) {
      if (part.type !== "tool_result") continue;
      const pieces = Array.isArray(part.content) ? part.content : [{ type: "text", text: String(part.content ?? "") }];
      const words = pieces.map((p) => (p.type === "image" ? "(picture)" : (p.text ?? ""))).join(" ").replace(/\s+/g, " ").trim();
      out.push(`Result${part.is_error ? " (refused)" : ""}: \`${clip(words)}\``, "");
    }
  } else if (event.type === "result") {
    result = event;
  }
}
if (result) {
  const minutes = Math.floor((result.duration_ms ?? 0) / 60000);
  const seconds = Math.round(((result.duration_ms ?? 0) % 60000) / 1000);
  const byName = [...calls.entries()].sort((a, b) => b[1] - a[1]).map(([n, c]) => `${n} ${c}`).join(", ");
  out.push("---", "",
    `Run: ${result.num_turns} turns, ${minutes}m${String(seconds).padStart(2, "0")}s, ${result.is_error ? "ended in error" : "finished"}.`,
    `Tool calls: ${byName}.`, "");
}
process.stdout.write(out.join("\n"));
