// A small client for the Photonz MCP bridge (Scripts/photonz-mcp.sh), the way
// an agent's MCP client talks to it: one JSON line per message, both ways.
// The eval reads and photographs what a run made through it, so it measures
// the document the app holds, not what any engine says it did.
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

export function connect({ app = "probe" } = {}) {
  const bridge = spawn(path.join(repo, "Scripts/photonz-mcp.sh"), [], {
    env: { ...process.env, PHOTONZ_APP: app },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderr = "";
  bridge.stderr.on("data", (chunk) => { stderr += chunk; });
  let buffered = "";
  const waiting = new Map();
  let nextID = 1;
  bridge.stdout.on("data", (chunk) => {
    buffered += chunk;
    let newline;
    while ((newline = buffered.indexOf("\n")) >= 0) {
      const line = buffered.slice(0, newline);
      buffered = buffered.slice(newline + 1);
      if (!line.trim()) continue;
      let message;
      try { message = JSON.parse(line); } catch { continue; }
      waiting.get(message.id)?.(message);
      waiting.delete(message.id);
    }
  });

  function rpc(method, params, patience = 60_000) {
    const id = nextID++;
    bridge.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        waiting.delete(id);
        reject(new Error(`${method} ${params?.name ?? ""} timed out${stderr ? `: ${stderr.trim().split("\n").pop()}` : ""}`));
      }, patience);
      waiting.set(id, (message) => { clearTimeout(timer); resolve(message); });
    });
  }

  async function tool(name, args = {}, patience) {
    const answer = await rpc("tools/call", { name, arguments: args }, patience);
    if (answer.error) throw new Error(`${name}: ${answer.error.message}`);
    const content = answer.result?.content ?? [];
    const text = content.find((part) => part.type === "text")?.text ?? "";
    const image = content.find((part) => part.type === "image")?.data;
    if (answer.result?.isError) throw new Error(`${name}: ${text}`);
    let json;
    try { json = JSON.parse(text); } catch { json = undefined; }
    return { text, json, image };
  }

  return {
    async start() {
      await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "ask-eval", version: "1" } }, 120_000);
      bridge.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    },
    tool,
    close() { bridge.stdin.end(); bridge.kill(); },
  };
}
