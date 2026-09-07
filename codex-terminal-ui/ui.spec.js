const path = require("node:path");
const { expect, test } = require("@playwright/test");

test("renders telemetry, unlocks Ultron, and opens a subagent log", async ({ page }) => {
  const errors = [];
  const failedRequests = [];
  const workspace = path.resolve(__dirname);
  const workspaceRoot = path.parse(workspace).root;
  const historyRequests = [];
  page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("requestfailed", (request) => failedRequests.push(`${request.method()} ${request.url()}`));
  page.on("request", (request) => { if (request.url().includes("/api/history")) historyRequests.push(request.url()); });
  await page.route("**/api/folders**", async (route) => {
    const requested = new URL(route.request().url()).searchParams.get("path");
    if (!requested) {
      await route.fulfill({ json: { path: null, parent: null, roots: [workspaceRoot], directories: [] } });
      return;
    }
    if (requested === workspace || requested === workspaceRoot) {
      await route.fulfill({ json: { path: requested, parent: requested === workspaceRoot ? null : workspaceRoot, roots: [workspaceRoot], directories: [] } });
      return;
    }
    await route.fulfill({ status: 400, json: { error: "Workspace is unavailable" } });
  });
  await page.route("**/api/history**", (route) => route.fulfill({ json: [] }));
  await page.addInitScript(() => {
    const nativeSetInterval = window.setInterval;
    window.__refreshIntervals = [];
    window.setInterval = (callback, delay, ...args) => {
      window.__refreshIntervals.push(delay);
      return nativeSetInterval(callback, delay, ...args);
    };
    window.__fakeSocketMessages = [];
    class FakeSocket extends EventTarget {
      static OPEN = 1;
      readyState = FakeSocket.OPEN;
      constructor() {
        super();
        queueMicrotask(() => {
          this.dispatchEvent(new Event("open"));
          this.emit({
            type: "snapshot",
            running: false,
            workspace: null,
            output: "",
            status: {
              plan: "plus",
              primary: { available: 72, resetsAt: Date.now() + 3600000 },
              secondary: { available: 91, resetsAt: Date.now() + 86400000 },
              resetsAvailable: 3,
              resetsExpireAt: Date.now() + 7200000,
              updatedAt: Date.now()
            },
            subagents: [{ id: "one", name: "Socrates", role: "luna_worker", status: "running", startedAt: Date.now(), log: "Inspecting rendered state" }]
          });
        });
      }
      emit(value) { this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(value) })); }
      send(raw) {
        const message = JSON.parse(raw);
        window.__fakeSocketMessages.push(message);
        if (message.type === "start") this.emit({ type: "state", running: true, agent: message.agent });
      }
    }
    window.WebSocket = FakeSocket;
  });

  await page.goto("/");
  await expect(page.getByText("72%", { exact: true })).toBeVisible();
  await expect(page.locator("#resets-available")).toHaveText("3");
  await expect(page.locator("#resets-expiry")).toContainText(/reset credits expire/i);
  await expect(page.locator('[class~="topbar"]')).toHaveCount(0);
  await expect(page.locator(".terminal-context")).toContainText("ONLINE");
  await expect(page.locator("#workspace-label")).toHaveText("NO WORKSPACE");
  await expect(page.locator("#history-list")).toContainText("Choose a workspace");
  await expect.poll(() => page.evaluate(() => window.__fakeSocketMessages.filter(({ type }) => type === "refresh").length)).toBeGreaterThan(0);
  await expect.poll(() => page.evaluate(() => window.__refreshIntervals)).toContain(60000);
  await page.locator('[data-agent="edith"]').click();
  await expect(page.locator("#workspace-dialog")).toBeVisible();
  await page.locator("#workspace-path").fill(workspace);
  await page.locator("#workspace-browse").click();
  await expect(page.locator("#workspace-browser-path")).toHaveText(workspace);
  await expect(page.locator("#workspace-select")).toBeEnabled();
  await page.locator("#workspace-favorite-toggle").click();
  await expect(page.locator("#workspace-favorite-toggle")).toHaveAttribute("aria-pressed", "true");
  await page.locator("#workspace-select").click();
  await expect(page.locator("#workspace-dialog")).toBeHidden();
  await expect(page.locator("#workspace-label")).toHaveText(workspace);
  await expect.poll(() => historyRequests.length).toBeGreaterThan(0);
  expect(historyRequests.at(-1)).toContain(encodeURIComponent(workspace));
  await page.locator("#workspace-control").click();
  await expect(page.locator(".workspace-favorite-select")).toHaveText(workspace);
  await page.locator(".workspace-favorite-select").click();
  await expect(page.locator("#workspace-dialog")).toBeHidden();
  await page.reload();
  await page.locator("#workspace-control").click();
  await expect(page.locator(".workspace-favorite-select")).toHaveText(workspace);
  await page.getByRole("button", { name: `Remove favorite ${workspace}` }).click();
  await expect(page.locator(".workspace-favorite-select")).toHaveCount(0);
  await page.locator("#workspace-path").fill(workspace);
  await page.locator("#workspace-browse").click();
  await page.locator("#workspace-select").click();
  await page.locator('[data-agent="ultron"]').click();
  await expect(page.locator("#ultron-state")).toHaveText("ARMED 1/2");
  await page.locator('[data-agent="ultron"]').click();
  await expect(page.locator('[data-agent="ultron"]')).toHaveClass(/breaking/);
  await expect(page.locator("#running-badge")).toHaveText("LIVE");
  await expect.poll(() => page.evaluate(() => window.__fakeSocketMessages.find(({ type }) => type === "start"))).toMatchObject({ type: "start", workspace });
  await page.screenshot({ path: path.resolve("test-results", "codex-terminal-ui.png"), fullPage: true });
  await page.getByRole("button", { name: /Socrates/ }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page.locator("#dialog-log")).toContainText("Inspecting rendered state");
  await page.keyboard.press("Escape");
  for (const [width, height] of [[1440, 900], [1024, 768]]) {
    await page.setViewportSize({ width, height });
    const metrics = await page.evaluate(() => ({
      scrollHeight: document.documentElement.scrollHeight,
      clientHeight: document.documentElement.clientHeight
    }));
    expect(metrics.scrollHeight).toBeLessThanOrEqual(metrics.clientHeight);
  }
  await page.screenshot({ path: path.resolve("test-results", "codex-terminal-ui-desktop.png"), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  for (const selector of [".agents-section", ".history-section", ".terminal-column", ".usage-section", ".subagents-section"]) {
    const panel = page.locator(selector);
    await expect(panel).toBeVisible();
    await panel.scrollIntoViewIfNeeded();
    await expect(panel).toBeInViewport();
  }
  await page.screenshot({ path: path.resolve("test-results", "codex-terminal-ui-mobile.png"), fullPage: true });
  expect(failedRequests).toEqual([]);
  expect(errors).toEqual([]);
});
