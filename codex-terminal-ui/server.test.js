const assert = require("node:assert/strict");
const test = require("node:test");
const path = require("node:path");
const { clamp, eventLog, listDirectories, normalizeLiveStatus, normalizeStatus, safePublicPath, sessionLabel, sourceDetails, validateAgent, validateWorkspace } = require("./server");

test("validates the local control boundary", () => {
  assert.equal(validateAgent("jarvis"), "jarvis");
  assert.throws(() => validateAgent("shell"), /Unknown agent/);
  assert.equal(clamp("4", 40, 320, 120), 40);
  assert.equal(safePublicPath("/../../secret"), null);
  assert.equal(validateWorkspace(__dirname), __dirname);
  assert.throws(() => validateWorkspace("relative"), /absolute workspace/);
  assert.throws(() => validateWorkspace(__filename), /must be a folder/);
});

test("lists folders without selecting one implicitly", async () => {
  assert.deepEqual((await listDirectories()).directories, []);
  const result = await listDirectories(path.dirname(__dirname));
  assert.ok(result.directories.includes(path.basename(__dirname)));
});

test("normalizes live Codex usage", () => {
  const status = normalizeStatus({
    total_token_usage: { total_tokens: 321 },
    model_context_window: 1000,
    rate_limits: {
      plan_type: "plus",
      primary: { used_percent: 68, window_minutes: 300, resets_at: 42 },
      secondary: { used_percent: 11, window_minutes: 10080, resets_at: 84 }
    }
  });
  assert.deepEqual(status.primary, { used: 68, available: 32, windowMinutes: 300, resetsAt: 42 });
  assert.deepEqual(status.context, { used: 321, size: 1000 });
});

test("accepts current Codex token event shape", () => {
  const status = normalizeStatus({ model_context_window: 1000 }, { primary: { used_percent: 25 } });
  assert.equal(status.primary.available, 75);
});

test("normalizes authoritative app-server limits and reset expiry", () => {
  const status = normalizeLiveStatus({
    rateLimits: { planType: "plus", primary: { usedPercent: 11, windowDurationMins: 300, resetsAt: 42 }, secondary: { usedPercent: 17 } },
    rateLimitResetCredits: { availableCount: 2, credits: [{ status: "available", expiresAt: 84 }, { status: "redeemed", expiresAt: 21 }] }
  });
  assert.equal(status.primary.available, 89);
  assert.equal(status.secondary.available, 83);
  assert.equal(status.resetsAvailable, 2);
  assert.equal(status.resetsExpireAt, 84);
});

test("extracts compact subagent activity", () => {
  assert.deepEqual(sourceDetails({ subagent: { thread_spawn: { agent_nickname: "Socrates", agent_role: "luna_worker" } } }, "Agent 1"), { name: "Socrates", role: "luna_worker" });
  assert.equal(eventLog({ type: "response_item", payload: { type: "custom_tool_call", name: "exec" } }), "› exec");
});

test("keeps setup messages out of session labels", () => {
  assert.equal(sessionLabel("# AGENTS.md instructions <INSTRUCTIONS>"), "");
  assert.equal(sessionLabel("  Build   terminal UI  "), "Build terminal UI");
});
