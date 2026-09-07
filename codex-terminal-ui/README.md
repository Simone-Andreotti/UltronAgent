# Codex Terminal UI

Local visual shell for the existing Codex Ultron launchers. It does not alter profiles, prompts, agents, or orchestration.

```powershell
npm install
npm start
```

Open `http://127.0.0.1:4317`, then choose the terminal workspace in the browser. No workspace is selected from the server's launch directory. Favorite folders are kept in the browser for one-click selection later.

The server binds to loopback, keeps one Codex PTY alive across browser refreshes, and reads Codex's local session JSONL for usage and subagent activity. Usage loads at startup and refreshes from Codex account data every 60 seconds.
