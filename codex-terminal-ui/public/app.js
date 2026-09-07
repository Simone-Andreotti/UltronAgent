(() => {
  "use strict";

  const $ = (selector) => document.querySelector(selector);
  const agentNames = { edith: "Edith", jarvis: "Jarvis", ultron: "Ultron" };
  const favoritesKey = "codex-terminal-workspace-favorites";
  const state = {
    agent: null,
    running: false,
    starting: false,
    output: "",
    workspace: "",
    status: null,
    subagents: new Map(),
    selectedSubagent: null,
    history: [],
    favorites: []
  };

  const terminalNode = $("#terminal");
  const terminalEmpty = $("#terminal-empty");
  const terminalMessage = $("#terminal-message");
  const workspaceDialog = $("#workspace-dialog");
  const workspacePath = $("#workspace-path");
  const workspaceBrowserPath = $("#workspace-browser-path");
  const workspaceParent = $("#workspace-parent");
  const workspaceSelect = $("#workspace-select");
  const workspaceFavoriteToggle = $("#workspace-favorite-toggle");
  const workspacePickerStatus = $("#workspace-picker-status");
  const dialog = $("#subagent-dialog");
  const dialogLog = $("#dialog-log");
  let socket;
  let reconnectTimer;
  let reconnectAttempt = 0;
  let toastTimer;
  let ultronTimer;
  let pendingResumeId;
  let lastDialogFocus;
  let pickerData = { path: null, parent: null, roots: [], directories: [] };

  const terminal = window.Terminal ? new window.Terminal({
    allowTransparency: true,
    convertEol: true,
    cursorBlink: true,
    cursorStyle: "bar",
    fontFamily: '"Cascadia Code", "SFMono-Regular", Consolas, monospace',
    fontSize: 13,
    lineHeight: 1.25,
    scrollback: 10000,
    theme: {
      background: "#041016",
      foreground: "#c8fcff",
      cursor: "#64e6ed",
      cursorAccent: "#041016",
      selectionBackground: "rgba(100, 230, 237, .25)",
      black: "#061016",
      red: "#ff6ba9",
      green: "#8af6bf",
      yellow: "#ffd36b",
      blue: "#75b9ff",
      magenta: "#a98aff",
      cyan: "#64e6ed",
      white: "#e9fbff",
      brightBlack: "#52727f",
      brightRed: "#ff8bbd",
      brightGreen: "#b2ffd6",
      brightYellow: "#ffe59b",
      brightBlue: "#9dceff",
      brightMagenta: "#c0aaff",
      brightCyan: "#a9f8fc",
      brightWhite: "#ffffff"
    }
  }) : null;
  const fitAddon = terminal && window.FitAddon ? new window.FitAddon.FitAddon() : null;

  function send(message) {
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  }

  function showToast(message) {
    const toast = $("#toast");
    toast.textContent = message;
    toast.classList.add("visible");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove("visible"), 3200);
  }

  function setConnection(label, connected) {
    $("#connection-label").textContent = label;
    $("#connection-dot").classList.toggle("connected", connected);
  }

  function setTerminalMessage(message) {
    terminalMessage.textContent = message;
  }

  function readFavorites() {
    try {
      const values = JSON.parse(localStorage.getItem(favoritesKey) || "[]");
      return [...new Set(Array.isArray(values) ? values.filter((value) => typeof value === "string" && value.trim()) : [])];
    } catch { return []; }
  }

  function saveFavorites() {
    try { localStorage.setItem(favoritesKey, JSON.stringify(state.favorites)); } catch {}
  }

  function renderWorkspaceControl() {
    const label = $("#workspace-label");
    const value = state.workspace || "NO WORKSPACE";
    label.textContent = value;
    label.title = state.workspace || "Choose workspace";
    $("#workspace-control").title = state.workspace ? "Change workspace" : "Choose workspace";
    $("#workspace-control").setAttribute("aria-label", state.workspace ? `Workspace ${state.workspace}` : "Choose workspace");
  }

  function setWorkspace(value) {
    state.workspace = value || "";
    renderWorkspaceControl();
    loadHistory();
  }

  function setWorkspacePickerStatus(message, warning = false) {
    workspacePickerStatus.textContent = message;
    workspacePickerStatus.classList.toggle("warn", warning);
  }

  function joinWorkspacePath(parent, child) {
    if (!parent) return child;
    if (parent.endsWith("\\") || parent.endsWith("/")) return `${parent}${child}`;
    return `${parent}${parent.includes("\\") ? "\\" : "/"}${child}`;
  }

  function renderWorkspaceFavorites() {
    const list = $("#workspace-favorites");
    list.replaceChildren();
    if (!state.favorites.length) {
      const empty = document.createElement("p");
      empty.className = "workspace-empty";
      empty.textContent = "No saved folders yet.";
      list.append(empty);
      return;
    }
    state.favorites.forEach((favorite) => {
      const row = document.createElement("div");
      row.className = "workspace-favorite";
      const select = document.createElement("button");
      select.className = "workspace-favorite-select";
      select.type = "button";
      select.title = `Use ${favorite}`;
      select.textContent = favorite;
      select.addEventListener("click", () => selectWorkspace(favorite));
      const remove = document.createElement("button");
      remove.className = "workspace-favorite-remove";
      remove.type = "button";
      remove.setAttribute("aria-label", `Remove favorite ${favorite}`);
      remove.textContent = "×";
      remove.addEventListener("click", () => {
        state.favorites = state.favorites.filter((value) => value !== favorite);
        saveFavorites();
        renderWorkspaceFavorites();
        renderWorkspaceSelection();
      });
      row.append(select, remove);
      list.append(row);
    });
  }

  function renderWorkspaceSelection() {
    const current = pickerData.path;
    workspaceBrowserPath.textContent = current || "Choose a root or paste a path";
    workspacePath.value = current || "";
    workspaceParent.disabled = !pickerData.parent;
    workspaceSelect.disabled = !current;
    workspaceFavoriteToggle.disabled = !current;
    const favorite = Boolean(current && state.favorites.includes(current));
    workspaceFavoriteToggle.textContent = favorite ? "★ FAVORITED" : "☆ FAVORITE";
    workspaceFavoriteToggle.setAttribute("aria-pressed", String(favorite));
    workspaceFavoriteToggle.title = favorite ? "Remove favorite" : "Save favorite";
  }

  function renderWorkspaceOptions() {
    const roots = $("#workspace-roots");
    const directories = $("#workspace-directories");
    roots.replaceChildren();
    directories.replaceChildren();
    pickerData.roots.forEach((root) => {
      const button = document.createElement("button");
      button.className = "workspace-option";
      button.type = "button";
      button.title = root;
      const label = document.createElement("span");
      label.textContent = root;
      button.append(label);
      button.addEventListener("click", () => browseWorkspace(root));
      roots.append(button);
    });
    if (!pickerData.roots.length) {
      const empty = document.createElement("p");
      empty.className = "workspace-empty";
      empty.textContent = "No roots available.";
      roots.append(empty);
    }
    pickerData.directories.forEach((directory) => {
      const button = document.createElement("button");
      button.className = "workspace-option";
      button.type = "button";
      button.title = directory;
      const label = document.createElement("span");
      label.textContent = directory;
      button.append(label);
      button.addEventListener("click", () => browseWorkspace(joinWorkspacePath(pickerData.path, directory)));
      directories.append(button);
    });
    if (!pickerData.directories.length) {
      const empty = document.createElement("p");
      empty.className = "workspace-empty";
      empty.textContent = pickerData.path ? "No subfolders." : "Open a folder to browse.";
      directories.append(empty);
    }
    renderWorkspaceSelection();
  }

  async function browseWorkspace(value) {
    const pathValue = typeof value === "string" ? value.trim() : "";
    setWorkspacePickerStatus("Loading folders…");
    try {
      const query = pathValue ? `?path=${encodeURIComponent(pathValue)}` : "";
      const response = await fetch(`/api/folders${query}`, { cache: "no-store" });
      let payload;
      try { payload = await response.json(); } catch { payload = {}; }
      if (!response.ok) throw new Error(payload.error || "Folder unavailable");
      pickerData = {
        path: payload.path || null,
        parent: payload.parent || null,
        roots: Array.isArray(payload.roots) ? payload.roots : [],
        directories: Array.isArray(payload.directories) ? payload.directories : []
      };
      renderWorkspaceOptions();
      setWorkspacePickerStatus(pickerData.path ? "Select this folder or keep browsing." : "Choose a root or paste an absolute path.");
      return pickerData;
    } catch (error) {
      setWorkspacePickerStatus(error.message || "Folder unavailable", true);
      return null;
    }
  }

  async function selectWorkspace(value) {
    if (state.running || state.starting) {
      showToast("End the active terminal before changing workspace");
      return;
    }
    const candidate = String(value || workspacePath.value || pickerData.path || "").trim();
    if (!candidate) {
      setWorkspacePickerStatus("Choose or paste an absolute folder path.", true);
      workspacePath.focus();
      return;
    }
    const data = await browseWorkspace(candidate);
    if (!data?.path) return;
    setWorkspace(data.path);
    closeWorkspacePicker();
    setTerminalMessage("Workspace selected. Choose a profile to begin.");
    showToast(`Workspace selected: ${data.path}`);
  }

  function toggleWorkspaceFavorite() {
    const current = pickerData.path;
    if (!current) return;
    if (state.favorites.includes(current)) state.favorites = state.favorites.filter((value) => value !== current);
    else state.favorites = [current, ...state.favorites];
    saveFavorites();
    renderWorkspaceFavorites();
    renderWorkspaceSelection();
  }

  function openWorkspacePicker() {
    if (state.running || state.starting) {
      showToast("End the active terminal before changing workspace");
      return;
    }
    lastDialogFocus = document.activeElement;
    pickerData = { path: null, parent: null, roots: [], directories: [] };
    workspacePath.value = "";
    renderWorkspaceFavorites();
    renderWorkspaceOptions();
    setWorkspacePickerStatus("Loading folders…");
    if (typeof workspaceDialog.showModal === "function") workspaceDialog.showModal();
    else workspaceDialog.setAttribute("open", "");
    browseWorkspace();
  }

  function closeWorkspacePicker() {
    if (workspaceDialog.open && typeof workspaceDialog.close === "function") workspaceDialog.close();
    else workspaceDialog.removeAttribute("open");
    lastDialogFocus?.focus?.();
  }

  function requireWorkspace() {
    if (state.workspace) return true;
    openWorkspacePicker();
    setTerminalMessage("Choose a workspace before starting a terminal");
    return false;
  }

  function setActiveAgent(agent) {
    document.querySelectorAll(".agent-card").forEach((button) => {
      button.setAttribute("aria-selected", String(button.dataset.agent === agent));
    });
    $("#terminal-agent").textContent = agent ? agentNames[agent].toUpperCase() : "NO PROFILE SELECTED";
  }

  function renderTerminalState(exitCode) {
    const badge = $("#running-badge");
    const pulse = $(".pulse-icon");
    const live = state.running || state.starting;
    badge.classList.toggle("live", state.running);
    badge.classList.toggle("error", exitCode !== undefined && exitCode !== 0);
    badge.textContent = state.running ? "LIVE" : state.starting ? "BOOTING" : exitCode !== undefined ? "ENDED" : "STANDBY";
    pulse.classList.toggle("active", state.running);
    terminalEmpty.classList.toggle("hidden", live || Boolean(state.output));
    if (!live && !state.running && exitCode !== undefined) setTerminalMessage(`Process ended (${exitCode})`);
  }

  function fitTerminal() {
    if (!terminal || !fitAddon || !terminalNode.clientWidth) return;
    try {
      fitAddon.fit();
      $("#terminal-size").textContent = `${terminal.cols} × ${terminal.rows}`;
      send({ type: "resize", cols: terminal.cols, rows: terminal.rows });
    } catch {}
  }

  function startSession(agent, resumeId) {
    if (state.running || state.starting) {
      setTerminalMessage("A terminal is already active");
      showToast("Terminal already running");
      return;
    }
    if (!requireWorkspace()) return;
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      setTerminalMessage("Waiting for loopback connection");
      showToast("Loopback connection is offline");
      return;
    }
    state.agent = agent;
    state.starting = true;
    state.output = "";
    setActiveAgent(agent);
    terminal?.clear();
    renderTerminalState();
    setTerminalMessage(resumeId ? "Resuming local session…" : `Starting ${agentNames[agent]}…`);
    send({
      type: "start",
      agent,
      workspace: state.workspace,
      cols: terminal?.cols || 120,
      rows: terminal?.rows || 36,
      ...(resumeId ? { resumeId } : {})
    });
  }

  function resetUltron() {
    const card = document.querySelector('[data-agent="ultron"]');
    if (!card || card.classList.contains("breaking")) return;
    card.classList.remove("arming");
    $("#ultron-state").textContent = "LOCKED";
    $("#ultron-hint").textContent = "double activate to unlock";
  }

  function activateUltron(resumeId) {
    if (state.running || state.starting) {
      setTerminalMessage("A terminal is already active");
      showToast("Terminal already running");
      return;
    }
    if (!requireWorkspace()) return;
    const card = document.querySelector('[data-agent="ultron"]');
    if (resumeId) pendingResumeId = resumeId;
    if (card.classList.contains("arming")) {
      clearTimeout(ultronTimer);
      card.classList.remove("arming");
      card.classList.add("breaking");
      $("#ultron-state").textContent = "CHAIN OFF";
      $("#ultron-hint").textContent = "access granted";
      $("#activation-note").textContent = "Chain broken. Initializing Ultron…";
      $("#activation-note").className = "activation-note active";
      setActiveAgent("ultron");
      setTimeout(() => {
        card.classList.remove("breaking");
        const sessionId = pendingResumeId;
        pendingResumeId = undefined;
        startSession("ultron", sessionId);
      }, 650);
      return;
    }
    card.classList.add("arming");
    $("#ultron-state").textContent = "ARMED 1/2";
    $("#ultron-hint").textContent = "activate again to break chain";
    $("#activation-note").textContent = "Second deliberate activation required.";
    $("#activation-note").className = "activation-note warn";
    clearTimeout(ultronTimer);
    ultronTimer = setTimeout(resetUltron, 2800);
  }

  function chooseAgent(agent) {
    if (state.running || state.starting) {
      setTerminalMessage("A terminal is already active");
      showToast("Terminal already running");
      return;
    }
    if (!requireWorkspace()) return;
    if (agent === "ultron") {
      pendingResumeId = undefined;
      activateUltron();
      return;
    }
    pendingResumeId = undefined;
    resetUltron();
    $("#activation-note").textContent = `${agentNames[agent]} terminal selected.`;
    $("#activation-note").className = "activation-note active";
    startSession(agent);
  }

  function formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "unknown time";
    return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(date);
  }

  function renderHistory() {
    const list = $("#history-list");
    list.replaceChildren();
    if (!state.history.length) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "No recent local sessions.";
      list.append(empty);
      return;
    }
    state.history.forEach((item) => {
      const button = document.createElement("button");
      button.className = "history-item";
      button.type = "button";
      button.title = `Resume ${item.label || "session"}`;
      const label = document.createElement("strong");
      label.textContent = item.label || "Untitled session";
      const stamp = document.createElement("small");
      stamp.textContent = formatDate(item.timestamp);
      button.append(label, stamp);
      button.addEventListener("click", () => {
        if (state.running || state.starting) {
          showToast("End the active terminal before resuming");
          return;
        }
        const agent = state.agent || "edith";
        if (agent === "ultron") activateUltron(item.id);
        else startSession(agent, item.id);
      });
      list.append(button);
    });
  }

  async function loadHistory() {
    if (!state.workspace) {
      const list = $("#history-list");
      list.replaceChildren();
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "Choose a workspace to view local sessions.";
      list.append(empty);
      return;
    }
    try {
      const response = await fetch(`/api/history?workspace=${encodeURIComponent(state.workspace)}`, { cache: "no-store" });
      if (!response.ok) throw new Error("History unavailable");
      const rows = await response.json();
      state.history = Array.isArray(rows) ? rows : [];
      renderHistory();
    } catch {
      const list = $("#history-list");
      list.replaceChildren();
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "Local history unavailable.";
      list.append(empty);
    }
  }

  function resetLabel(value) {
    if (value === null || value === undefined || value === "") return "reset —";
    const numeric = Number(value);
    const date = Number.isFinite(numeric) ? new Date(numeric < 1e12 ? numeric * 1000 : numeric) : new Date(value);
    if (Number.isNaN(date.getTime())) return "reset —";
    return `reset ${new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(date)}`;
  }

  function updateLimit(prefix, limit) {
    const available = Number(limit?.available);
    const value = Number.isFinite(available) ? Math.max(0, Math.min(100, Math.round(available))) : null;
    $(`#${prefix}-available`).textContent = value === null ? "—" : `${value}%`;
    $(`#${prefix}-bar`).style.width = `${value || 0}%`;
    $(`#${prefix}-reset`).textContent = resetLabel(limit?.resetsAt);
  }

  function renderStatus(status) {
    state.status = status || null;
    const expiry = $("#resets-expiry");
    const expiryLabel = resetLabel(status?.resetsExpireAt);
    expiry.textContent = expiryLabel === "reset —" ? "" : expiryLabel.replace(/^reset /, "reset credits expire ");
    expiry.hidden = !expiry.textContent;
    updateLimit("primary", status?.primary);
    updateLimit("secondary", status?.secondary);
    $("#resets-available").textContent = Number.isFinite(Number(status?.resetsAvailable)) ? String(status.resetsAvailable) : "—";
    $("#plan-label").textContent = status?.plan ? `PLAN ${String(status.plan).toUpperCase()}` : "PLAN —";
    $("#usage-updated").textContent = status?.updatedAt ? `SYNCED ${formatDate(status.updatedAt)}` : "NOT SYNCED";
  }

  function statusClass(status) {
    return status === "complete" || status === "error" ? status : "running";
  }

  function renderSubagents() {
    const list = $("#subagent-list");
    const agents = [...state.subagents.values()].sort((a, b) => (Date.parse(a.startedAt) || 0) - (Date.parse(b.startedAt) || 0));
    $("#subagent-count").textContent = String(agents.length);
    list.replaceChildren();
    if (!agents.length) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "No live subagents.";
      list.append(empty);
      return;
    }
    agents.forEach((agent) => {
      const card = document.createElement("button");
      card.className = "subagent-card";
      card.type = "button";
      card.dataset.id = agent.id || agent.name;
      const head = document.createElement("span");
      head.className = "subagent-card-head";
      const name = document.createElement("strong");
      name.textContent = agent.name || "Subagent";
      const status = document.createElement("span");
      status.className = `subagent-status ${statusClass(agent.status)}`;
      status.textContent = agent.status || "running";
      head.append(name, status);
      const preview = document.createElement("span");
      preview.className = "subagent-preview";
      preview.textContent = (agent.log || "Waiting for log output…").slice(-180);
      const foot = document.createElement("span");
      foot.className = "subagent-card-foot";
      const role = document.createElement("small");
      role.textContent = agent.role || "subagent";
      const open = document.createElement("small");
      open.textContent = "OPEN ↗";
      foot.append(role, open);
      card.append(head, preview, foot);
      card.addEventListener("click", () => openSubagent(agent.id || agent.name));
      list.append(card);
    });
    if (state.selectedSubagent) renderDialog();
  }

  function renderDialog() {
    const agent = state.subagents.get(state.selectedSubagent);
    if (!agent) return;
    $("#dialog-title").textContent = agent.name || "Subagent";
    $("#dialog-meta").replaceChildren();
    [agent.role || "subagent", agent.status || "running", agent.startedAt ? formatDate(agent.startedAt) : "live"].forEach((value) => {
      const item = document.createElement("span");
      item.textContent = value;
      $("#dialog-meta").append(item);
    });
    dialogLog.textContent = agent.log || "No log output yet.";
    dialogLog.scrollTop = dialogLog.scrollHeight;
  }

  function openSubagent(id) {
    if (!state.subagents.has(id)) return;
    state.selectedSubagent = id;
    lastDialogFocus = document.activeElement;
    renderDialog();
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
    $("#dialog-close").focus();
  }

  function closeDialog() {
    if (dialog.open && typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
    lastDialogFocus?.focus?.();
  }

  function updateState(message) {
    state.running = Boolean(message.running);
    state.starting = false;
    if (message.agent) state.agent = message.agent;
    setActiveAgent(state.agent);
    renderTerminalState(message.exitCode);
    if (state.running) setTerminalMessage(`${agentNames[state.agent] || "Codex"} terminal connected`);
  }

  function handleMessage(message) {
    if (!message || typeof message !== "object") return;
    if (message.type === "snapshot") {
      state.output = message.output || "";
      state.agent = message.agent || state.agent;
      state.running = Boolean(message.running);
      state.starting = false;
      if (message.workspace) state.workspace = message.workspace;
      renderWorkspaceControl();
      setActiveAgent(state.agent);
      renderStatus(message.status);
      state.subagents = new Map((message.subagents || []).map((agent) => [agent.id || agent.name, agent]));
      renderSubagents();
      loadHistory();
      terminal?.clear();
      if (state.output) terminal?.write(state.output);
      renderTerminalState();
      setTerminalMessage(state.running ? `${agentNames[state.agent] || "Codex"} terminal restored` : "Awaiting profile");
      return;
    }
    if (message.type === "output") {
      state.output = `${state.output || ""}${message.data || ""}`.slice(-1000000);
      terminal?.write(message.data || "");
      terminalEmpty.classList.add("hidden");
      return;
    }
    if (message.type === "state") {
      updateState(message);
      return;
    }
    if (message.type === "status") {
      renderStatus(message.status);
      return;
    }
    if (message.type === "subagents") {
      state.subagents = new Map((message.subagents || []).map((agent) => [agent.id || agent.name, agent]));
      renderSubagents();
      return;
    }
    if (message.type === "subagent") {
      const id = message.subagent?.id || message.subagent?.name;
      if (id) state.subagents.set(id, { ...state.subagents.get(id), ...message.subagent });
      renderSubagents();
      return;
    }
    if (message.type === "error") {
      state.starting = false;
      renderTerminalState();
      setTerminalMessage(message.message || "Terminal error");
      showToast(message.message || "Terminal error");
    }
  }

  function connect() {
    clearTimeout(reconnectTimer);
    setConnection("CONNECTING", false);
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    socket = new WebSocket(`${protocol}//${location.host}`);
    socket.addEventListener("open", () => {
      reconnectAttempt = 0;
      setConnection("ONLINE", true);
      send({ type: "refresh" });
    });
    socket.addEventListener("message", (event) => {
      try { handleMessage(JSON.parse(event.data)); } catch { showToast("Invalid terminal message"); }
    });
    socket.addEventListener("error", () => setConnection("LINK ERROR", false));
    socket.addEventListener("close", () => {
      setConnection("RETRYING", false);
      state.starting = false;
      reconnectAttempt += 1;
      reconnectTimer = setTimeout(connect, Math.min(10000, 700 * 2 ** Math.min(reconnectAttempt, 4)));
    });
  }

  document.querySelectorAll(".agent-card").forEach((button) => button.addEventListener("click", () => chooseAgent(button.dataset.agent)));
  $("#workspace-control").addEventListener("click", openWorkspacePicker);
  $("#workspace-dialog-close").addEventListener("click", closeWorkspacePicker);
  $("#workspace-browse").addEventListener("click", () => browseWorkspace(workspacePath.value));
  workspacePath.addEventListener("keydown", (event) => {
    if (event.key === "Enter") { event.preventDefault(); browseWorkspace(workspacePath.value); }
  });
  workspaceParent.addEventListener("click", () => browseWorkspace(pickerData.parent));
  workspaceSelect.addEventListener("click", () => selectWorkspace());
  workspaceFavoriteToggle.addEventListener("click", toggleWorkspaceFavorite);
  workspaceDialog.addEventListener("click", (event) => { if (event.target === workspaceDialog) closeWorkspacePicker(); });
  workspaceDialog.addEventListener("close", () => lastDialogFocus?.focus?.());
  $("#history-refresh").addEventListener("click", loadHistory);
  $("#fit-terminal").addEventListener("click", fitTerminal);
  $("#dialog-close").addEventListener("click", closeDialog);
  dialog.addEventListener("cancel", () => { state.selectedSubagent = null; });
  dialog.addEventListener("close", () => lastDialogFocus?.focus?.());
  dialog.addEventListener("click", (event) => { if (event.target === dialog) closeDialog(); });

  if (terminal && terminalNode) {
    if (fitAddon) terminal.loadAddon(fitAddon);
    terminal.open(terminalNode);
    terminal.onData((data) => send({ type: "input", data }));
    terminal.onResize(({ cols, rows }) => send({ type: "resize", cols, rows }));
    terminal.attachCustomKeyEventHandler((event) => {
      if (event.type === "keydown" && event.ctrlKey && event.key.toLowerCase() === "l") {
        terminal.clear();
        return false;
      }
      return true;
    });
    const observer = new ResizeObserver(() => requestAnimationFrame(fitTerminal));
    observer.observe(terminalNode.parentElement);
    window.addEventListener("resize", fitTerminal);
    requestAnimationFrame(fitTerminal);
  } else {
    setTerminalMessage("xterm assets unavailable");
  }

  state.favorites = readFavorites();
  renderWorkspaceControl();
  renderWorkspaceFavorites();
  renderWorkspaceOptions();
  renderStatus(null);
  renderTerminalState();
  loadHistory();
  connect();
  setInterval(() => send({ type: "refresh" }), 60000);
})();
