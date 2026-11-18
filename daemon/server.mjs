import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { exec, execFile, execSync } from 'node:child_process';

const PORT = Number(process.env.DUMPLING_PORT || 47821);
const HOST = '127.0.0.1';
const HOME = os.homedir();
const COLORS = ['blue', 'pink', 'orange', 'purple', 'green'];

/** @type {Map<string, any>} */
const sessions = new Map();
/** @type {Set<http.ServerResponse>} */
const sseClients = new Set();
/** @type {Map<string, { resolve: (val: any) => void, timer: NodeJS.Timeout }>} */
const pendingHooks = new Map();
/** @type {Map<string, number>} */
const fileMtimes = new Map();

function pickColor(id) {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  }
  return COLORS[hash % COLORS.length];
}

function getRunningProcesses() {
  try {
    const out = execSync('ps -eo comm=', { encoding: 'utf8', timeout: 1000 });
    return out
      .toLowerCase()
      .split('\n')
      .filter((line) => !line.includes('claude.app'))
      .join('\n');
  } catch {
    return '';
  }
}

function buildAgentStatuses(visibleSessions) {
  const procs = getRunningProcesses();
  const defs = [
    {
      id: 'claude',
      name: 'Claude Code',
      processMatch: /\bclaude\b/,
    },
    {
      id: 'antigravity',
      name: 'Antigravity',
      processMatch: /antigravity|language_server/,
    },
    {
      id: 'opencode',
      name: 'OpenCode',
      processMatch: /\bopencode\b/,
    },
  ];

  return defs.map((def) => {
    const matching = visibleSessions.filter((s) => s.source === def.id);
    const working = matching.filter((s) => s.isWorking);
    const errored = matching.filter((s) => s.status === 'error');
    const needsInput = matching.filter((s) => s.pendingRequest != null);
    const procRunning = def.processMatch.test(procs);

    let status = 'not_working';
    let detail = procRunning ? 'Idle · No active task' : 'Not running';

    if (needsInput.length > 0) {
      status = 'needs_input';
      detail = `${needsInput.length} waiting for your input`;
    } else if (working.length > 0) {
      status = 'working';
      detail = working[0].subtitle || `${working.length} active`;
    } else if (errored.length > 0) {
      status = 'error';
      detail = errored[0].errorMessage || 'Last run failed';
    } else if (matching.length > 0) {
      status = 'not_working';
      detail = matching[0].subtitle || 'Idle';
    }

    return {
      id: def.id,
      name: def.name,
      status,
      isWorking: status === 'working' || status === 'needs_input',
      detail,
      activeCount: working.length + needsInput.length,
    };
  });
}

function getVisibleSessions() {
  const now = Date.now();
  const list = [];
  for (const s of sessions.values()) {
    if (s.dismissed) continue;
    // Hide stale read-only watched sessions older than 2 hours unless pending
    if (!s.pendingRequest && now - s.updatedAt > 2 * 60 * 60 * 1000) {
      continue;
    }
    list.push(s);
  }
  // Sort: needs_permission / asking_question first, then running, then error, then idle/done
  const rank = {
    needs_permission: 0,
    asking_question: 1,
    running: 2,
    error: 3,
    idle: 4,
    done: 5,
  };
  list.sort((a, b) => (rank[a.status] ?? 9) - (rank[b.status] ?? 9) || b.updatedAt - a.updatedAt);
  return list;
}

function getPayload() {
  const visible = getVisibleSessions();
  return {
    sessions: visible,
    agents: buildAgentStatuses(visible),
  };
}

function broadcast() {
  const payload = `data: ${JSON.stringify(getPayload())}\n\n`;
  for (const res of sseClients) {
    try {
      res.write(payload);
    } catch {
      sseClients.delete(res);
    }
  }
}

function upsertSession(id, patch) {
  const existing = sessions.get(id) || {
    id,
    source: 'claude',
    title: id.slice(0, 16),
    subtitle: 'Working...',
    color: pickColor(id),
    status: 'running',
    isWorking: true,
    statusLabel: 'Working',
    errorMessage: null,
    model: null,
    activeTool: null,
    progress: { completed: 0, total: 0, label: 'Steps' },
    steps: [],
    terminalCommand: '',
    terminalTail: [],
    pendingRequest: null,
    cwd: '',
    ide: 'vscode',
    updatedAt: Date.now(),
    dismissed: false,
  };
  const next = { ...existing, ...patch, updatedAt: patch.updatedAt ?? Date.now() };
  sessions.set(id, next);
  broadcast();
  return next;
}

function tailLines(filePath, maxBytes = 65536) {
  try {
    const stat = fs.statSync(filePath);
    const start = Math.max(0, stat.size - maxBytes);
    const fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(stat.size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    fs.closeSync(fd);
    const text = buf.toString('utf8');
    const lines = text.split('\n').filter(Boolean);
    if (start > 0 && lines.length > 0) lines.shift();
    return lines;
  } catch {
    return [];
  }
}

function unquoteArg(val) {
  if (typeof val !== 'string') return val;
  const trimmed = val.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return trimmed.slice(1, -1);
    }
  }
  return trimmed;
}

function formatToolStep(name, input) {
  if (!input || typeof input !== 'object') return name;
  const filePath = unquoteArg(input.file_path || input.Path || input.TargetFile);
  if (filePath) return `${name}: ${path.basename(filePath)}`;
  const cmd = unquoteArg(input.command || input.CommandLine);
  if (input.command && cmd) return `Bash: ${String(cmd).split('\n')[0].slice(0, 40)}`;
  if (input.CommandLine && cmd) return `Run: ${String(cmd).split('\n')[0].slice(0, 40)}`;
  if (input.pattern) return `${name}: ${String(unquoteArg(input.pattern)).slice(0, 30)}`;
  if (input.query) return `${name}: ${String(unquoteArg(input.query)).slice(0, 30)}`;
  return name;
}

function scanClaudeSessions() {
  const claudeProjectsDir = path.join(HOME, '.claude', 'projects');
  if (!fs.existsSync(claudeProjectsDir)) return;

  const now = Date.now();
  let projectDirs = [];
  try {
    projectDirs = fs.readdirSync(claudeProjectsDir);
  } catch {
    return;
  }

  for (const proj of projectDirs) {
    const projPath = path.join(claudeProjectsDir, proj);
    let files = [];
    try {
      files = fs.readdirSync(projPath).filter((f) => f.endsWith('.jsonl'));
    } catch {
      continue;
    }

    for (const file of files) {
      const fullPath = path.join(projPath, file);
      let stat;
      try {
        stat = fs.statSync(fullPath);
      } catch {
        continue;
      }
      if (now - stat.mtimeMs > 30 * 60 * 1000) continue;

      const sessionId = `claude-${file.replace('.jsonl', '')}`;
      const existing = sessions.get(sessionId);
      if (existing?.pendingRequest) continue;

      // Re-evaluate staleness even if mtime hasn't changed
      const ageMs = now - stat.mtimeMs;
      if (fileMtimes.get(fullPath) === stat.mtimeMs) {
        if (existing && existing.status === 'running' && ageMs > 90 * 1000) {
          upsertSession(sessionId, {
            status: 'idle',
            isWorking: false,
            statusLabel: 'Not Working',
            subtitle: 'Idle · No recent activity',
            updatedAt: stat.mtimeMs,
          });
        }
        continue;
      }
      fileMtimes.set(fullPath, stat.mtimeMs);

      const lines = tailLines(fullPath);
      if (lines.length === 0) continue;

      let cwd = '';
      let title = proj.replace(/^-Users-[^-]+-/, '').replace(/-/g, '/') || 'Claude Code';
      let subtitle = 'Thinking...';
      let todoSteps = [];
      let recentTools = [];
      let terminalCommand = '';
      let terminalTail = [];
      let isDone = false;
      let hasError = false;
      let errorMessage = null;
      let model = null;
      let activeTool = null;

      for (const raw of lines) {
        try {
          const entry = JSON.parse(raw);
          if (entry.cwd) cwd = entry.cwd;
          if (entry.message?.model) model = entry.message.model;

          if (entry.isApiErrorMessage) {
            hasError = true;
            errorMessage =
              typeof entry.message?.content === 'string'
                ? entry.message.content.slice(0, 120)
                : 'API error';
            subtitle = `Error: ${errorMessage}`;
          }

          if (entry.type === 'user' && typeof entry.message?.content === 'string') {
            const clean = entry.message.content.trim().split('\n')[0];
            if (clean && !clean.startsWith('<')) {
              title = clean.slice(0, 34);
              isDone = false;
              hasError = false;
              errorMessage = null;
            }
          }

          const content = entry.message?.content;
          if (Array.isArray(content)) {
            for (const block of content) {
              if (block.type === 'tool_use') {
                isDone = false;
                hasError = false;
                errorMessage = null;
                activeTool = block.name || 'Tool';

                if (block.name === 'TodoWrite' && Array.isArray(block.input?.todos)) {
                  todoSteps = block.input.todos.map((t, idx) => ({
                    id: String(idx),
                    text: t.content || t.activeForm || 'Step',
                    status:
                      t.status === 'completed'
                        ? 'done'
                        : t.status === 'in_progress'
                        ? 'active'
                        : 'pending',
                  }));
                  const active = block.input.todos.find((t) => t.status === 'in_progress');
                  if (active) subtitle = active.activeForm || active.content;
                } else {
                  const label = formatToolStep(block.name, block.input);
                  recentTools.push(label);
                  if (recentTools.length > 5) recentTools.shift();

                  if (block.name === 'Bash') {
                    terminalCommand = block.input?.command || '';
                    subtitle = `Running ${terminalCommand.split(' ')[0] || 'command'}`;
                  } else {
                    subtitle = label;
                  }
                }
              } else if (block.type === 'tool_result') {
                if (block.is_error) {
                  hasError = true;
                  const errText =
                    typeof block.content === 'string'
                      ? block.content
                      : JSON.stringify(block.content || '');
                  errorMessage = errText.trim().split('\n')[0].slice(0, 100);
                }
                if (typeof block.content === 'string') {
                  const outLines = block.content.trim().split('\n').filter(Boolean).slice(-4);
                  if (outLines.length > 0) terminalTail = outLines;
                }
              }
            }
          }

          if (entry.type === 'assistant' && entry.message?.stop_reason === 'end_turn') {
            isDone = true;
            activeTool = null;
          }
        } catch {
          // ignore malformed line
        }
      }

      const steps =
        todoSteps.length > 0
          ? todoSteps
          : recentTools.map((txt, idx, arr) => ({
              id: String(idx),
              text: txt,
              status:
                idx === arr.length - 1 && !isDone && !hasError
                  ? 'active'
                  : idx === arr.length - 1 && hasError
                  ? 'error'
                  : 'done',
            }));

      const doneCount = steps.filter((s) => s.status === 'done').length;
      const stalled = !isDone && !hasError && ageMs > 90 * 1000;
      const status = hasError ? 'error' : isDone || stalled ? 'idle' : 'running';
      const isWorking = status === 'running';
      const statusLabel =
        status === 'error' ? 'Error' : status === 'idle' ? 'Not Working' : 'Working';

      upsertSession(sessionId, {
        source: 'claude',
        title: cwd ? path.basename(cwd) : title,
        subtitle:
          status === 'error'
            ? errorMessage || 'Tool or API error'
            : status === 'idle'
            ? stalled
              ? 'Idle · No recent activity'
              : 'Idle · Waiting for input'
            : subtitle,
        status,
        isWorking,
        statusLabel,
        errorMessage,
        model,
        activeTool,
        steps,
        progress: {
          completed: doneCount,
          total: steps.length,
          label: todoSteps.length > 0 ? 'Steps' : 'Actions',
        },
        terminalCommand,
        terminalTail,
        cwd,
        ide: 'vscode',
        updatedAt: stat.mtimeMs,
      });
    }
  }
}

function scanAntigravitySessions() {
  const brainDir = path.join(HOME, '.gemini', 'antigravity', 'brain');
  if (!fs.existsSync(brainDir)) return;

  const now = Date.now();
  let convs = [];
  try {
    convs = fs.readdirSync(brainDir);
  } catch {
    return;
  }

  for (const convId of convs) {
    const transcriptPath = path.join(
      brainDir,
      convId,
      '.system_generated',
      'logs',
      'transcript.jsonl'
    );
    if (!fs.existsSync(transcriptPath)) continue;

    let stat;
    try {
      stat = fs.statSync(transcriptPath);
    } catch {
      continue;
    }
    if (now - stat.mtimeMs > 30 * 60 * 1000) continue;

    const sessionId = `agy-${convId}`;
    const existing = sessions.get(sessionId);
    const ageMs = now - stat.mtimeMs;

    if (fileMtimes.get(transcriptPath) === stat.mtimeMs) {
      if (existing && existing.status === 'running' && ageMs > 90 * 1000) {
        upsertSession(sessionId, {
          status: 'idle',
          isWorking: false,
          statusLabel: 'Not Working',
          subtitle: 'Idle · Waiting for prompt',
          updatedAt: stat.mtimeMs,
        });
      }
      continue;
    }
    fileMtimes.set(transcriptPath, stat.mtimeMs);

    const lines = tailLines(transcriptPath);
    if (lines.length === 0) continue;

    let title = `Antigravity · ${convId.slice(0, 6)}`;
    let subtitle = 'Active session';
    let recentTools = [];
    let terminalCommand = '';
    let terminalTail = [];
    let cwd = existing?.cwd || '';
    let targetFile = existing?.targetFile || '';
    let model = null;
    let activeTool = null;
    let lastType = '';
    let lastStatus = '';
    let lastHasTools = false;
    let errorMessage = null;

    for (const raw of lines) {
      try {
        const entry = JSON.parse(raw);
        lastType = entry.type || '';
        lastStatus = entry.status || '';
        if (entry.model) model = entry.model;

        if (entry.type === 'USER_INPUT' && entry.content) {
          const firstLine = String(entry.content)
            .replace(/<[^>]+>/g, '')
            .trim()
            .split('\n')[0];
          if (firstLine) title = `AGY · ${firstLine.slice(0, 28)}`;
          errorMessage = null;
        }

        if (entry.type === 'PLANNER_RESPONSE') {
          if (entry.status === 'ERROR') {
            errorMessage =
              typeof entry.content === 'string' && entry.content.trim()
                ? entry.content.trim().slice(0, 100)
                : 'Planner error';
          }
          if (Array.isArray(entry.tool_calls) && entry.tool_calls.length > 0) {
            lastHasTools = true;
            for (const tc of entry.tool_calls) {
              const tcArgs = tc.args || tc.arguments;
              const summary = unquoteArg(tcArgs?.toolSummary) || formatToolStep(tc.name || 'Tool', tcArgs);
              recentTools.push(summary);
              if (recentTools.length > 5) recentTools.shift();
              activeTool = tc.name || 'Tool';
              subtitle = summary;
              if (tcArgs?.CommandLine) {
                terminalCommand = unquoteArg(tcArgs.CommandLine);
              }
              const rawPath = unquoteArg(
                tcArgs?.Path ||
                tcArgs?.AbsolutePath ||
                tcArgs?.TargetFile ||
                tcArgs?.DirectoryPath ||
                tcArgs?.SearchPath ||
                tcArgs?.Cwd
              );
              if (rawPath && typeof rawPath === 'string' && !rawPath.startsWith(path.join(HOME, '.gemini'))) {
                const resolved = resolveProjectTarget(rawPath);
                if (resolved.cwd) cwd = resolved.cwd;
                if (resolved.targetFile) targetFile = resolved.targetFile;
              }
            }
          } else {
            lastHasTools = false;
            activeTool = null;
          }
        }

        if (entry.type === 'GENERIC' && typeof entry.content === 'string') {
          const cleanLines = entry.content
            .split('\n')
            .map((l) => l.trim())
            .filter(
              (l) =>
                l &&
                !l.startsWith('Created At:') &&
                !l.startsWith('Completed At:') &&
                !l.startsWith('Command exited')
            );
          if (cleanLines.length > 0) {
            terminalTail = cleanLines.slice(-3);
          }
        }
      } catch {
        // ignore malformed line
      }
    }

    const isError = lastStatus === 'ERROR' || errorMessage != null;
    const isFinishedTurn = lastType === 'PLANNER_RESPONSE' && lastStatus === 'DONE' && !lastHasTools;
    const stalled = !isError && !isFinishedTurn && ageMs > 90 * 1000;

    const status = isError ? 'error' : isFinishedTurn || stalled ? 'idle' : 'running';
    const isWorking = status === 'running';
    const statusLabel =
      status === 'error' ? 'Error' : status === 'idle' ? 'Not Working' : 'Working';

    const steps = recentTools.map((txt, i, arr) => ({
      id: String(i),
      text: txt,
      status:
        i === arr.length - 1 && isWorking
          ? 'active'
          : i === arr.length - 1 && isError
          ? 'error'
          : 'done',
    }));

    const doneCount = steps.filter((s) => s.status === 'done').length;

    upsertSession(sessionId, {
      source: 'antigravity',
      title,
      subtitle: isError
        ? errorMessage || 'Agent error'
        : status === 'idle'
        ? 'Idle · Ready for prompt'
        : subtitle,
      status,
      isWorking,
      statusLabel,
      errorMessage,
      model,
      activeTool,
      steps,
      progress: { completed: doneCount, total: steps.length, label: 'Actions' },
      terminalCommand,
      terminalTail,
      cwd,
      targetFile,
      ide: 'antigravity',
      updatedAt: stat.mtimeMs,
    });
  }
}

function resolveProjectTarget(rawPath) {
  try {
    if (!fs.existsSync(rawPath)) return { cwd: '', targetFile: '' };
    const st = fs.statSync(rawPath);
    const targetFile = st.isFile() ? rawPath : '';
    let dir = st.isDirectory() ? rawPath : path.dirname(rawPath);
    let cur = dir;
    while (cur && cur !== path.dirname(cur)) {
      if (fs.existsSync(path.join(cur, '.git'))) {
        return { cwd: cur, targetFile };
      }
      cur = path.dirname(cur);
    }
    return { cwd: dir, targetFile };
  } catch {
    return { cwd: '', targetFile: '' };
  }
}

function pollWatchers() {
  scanClaudeSessions();
  scanAntigravitySessions();
}

function focusApp(ide, targetPath) {
  const appMap = {
    vscode: 'Visual Studio Code',
    cursor: 'Cursor',
    antigravity: 'Antigravity',
    terminal: 'Terminal',
  };
  const appName = appMap[ide] || 'Visual Studio Code';
  const args = ['-a', appName];
  if (targetPath && typeof targetPath === 'string' && fs.existsSync(targetPath)) {
    args.push(targetPath);
  }
  execFile('open', args, (err) => {
    if (err) execFile('open', ['-a', 'Terminal']);
  });
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (chunk) => (data += chunk));
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        resolve({});
      }
    });
  });
}

function sendJson(res, code, obj) {
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(obj));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${HOST}:${PORT}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    return res.end();
  }

  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, { ok: true, sessions: getVisibleSessions().length });
  }

  if (req.method === 'GET' && url.pathname === '/sessions') {
    return sendJson(res, 200, getPayload());
  }

  if (req.method === 'GET' && url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
    res.write(`data: ${JSON.stringify(getPayload())}\n\n`);
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    return;
  }

  if (req.method === 'POST' && url.pathname === '/hook') {
    const body = await readBody(req);
    const event = body.hook_event_name || 'PreToolUse';
    const rawId = body.session_id || 'default';
    const sessionId = `claude-${rawId}`;
    const cwd = body.cwd || '';
    const title = cwd ? path.basename(cwd) : 'Claude Code';

    if (event === 'Stop' || event === 'SessionEnd') {
      upsertSession(sessionId, {
        source: 'claude',
        title,
        subtitle: 'Idle · Session finished',
        status: 'idle',
        isWorking: false,
        statusLabel: 'Not Working',
        activeTool: null,
        pendingRequest: null,
        cwd,
      });
      return sendJson(res, 200, {});
    }

    if (event === 'PermissionRequest') {
      const requestId = `req-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
      const tool = body.tool_name || 'Bash';
      const detail =
        body.tool_input?.command ||
        body.tool_input?.file_path ||
        JSON.stringify(body.tool_input || {}).slice(0, 80);

      upsertSession(sessionId, {
        source: 'claude',
        title,
        subtitle: `Needs permission: ${tool}`,
        status: 'needs_permission',
        isWorking: true,
        statusLabel: 'Needs Input',
        activeTool: tool,
        cwd,
        pendingRequest: {
          type: 'permission',
          requestId,
          tool: `${tool}: ${detail}`,
          detail,
        },
      });

      const decision = await new Promise((resolve) => {
        const timer = setTimeout(() => {
          pendingHooks.delete(requestId);
          resolve({ decision: 'open_ide' });
        }, 5 * 60 * 1000);
        pendingHooks.set(requestId, { resolve, timer });
      });

      if (decision.decision === 'allow') {
        upsertSession(sessionId, {
          status: 'running',
          isWorking: true,
          statusLabel: 'Working',
          subtitle: `Allowed ${tool}`,
          pendingRequest: null,
        });
        return sendJson(res, 200, {
          hookSpecificOutput: {
            hookEventName: 'PermissionRequest',
            decision: { behavior: 'allow' },
          },
        });
      }
      if (decision.decision === 'deny') {
        upsertSession(sessionId, {
          status: 'running',
          isWorking: true,
          statusLabel: 'Working',
          subtitle: `Denied ${tool}`,
          pendingRequest: null,
        });
        return sendJson(res, 200, {
          hookSpecificOutput: {
            hookEventName: 'PermissionRequest',
            decision: { behavior: 'deny', message: 'Denied from Dumpling' },
          },
        });
      }
      upsertSession(sessionId, {
        status: 'running',
        isWorking: true,
        statusLabel: 'Working',
        subtitle: 'Opened in IDE',
        pendingRequest: null,
      });
      focusApp('vscode');
      return sendJson(res, 200, {});
    }

    const tool = body.tool_name || 'Tool';
    const cmd = body.tool_input?.command || body.tool_input?.file_path || '';
    upsertSession(sessionId, {
      source: 'claude',
      title,
      subtitle: event === 'PostToolUse' ? `Completed ${tool}` : formatToolStep(tool, body.tool_input),
      status: 'running',
      isWorking: true,
      statusLabel: 'Working',
      activeTool: tool,
      terminalCommand: cmd || sessions.get(sessionId)?.terminalCommand || '',
      cwd,
    });
    return sendJson(res, 200, {});
  }

  const respondMatch = url.pathname.match(/^\/sessions\/([^/]+)\/respond$/);
  if (req.method === 'POST' && respondMatch) {
    const id = decodeURIComponent(respondMatch[1]);
    const body = await readBody(req);
    const session = sessions.get(id);
    if (!session) return sendJson(res, 404, { error: 'Session not found' });

    const reqId = session.pendingRequest?.requestId;
    if (reqId && pendingHooks.has(reqId)) {
      const pending = pendingHooks.get(reqId);
      clearTimeout(pending.timer);
      pendingHooks.delete(reqId);
      pending.resolve(body);
    } else {
      const label =
        body.decision === 'allow'
          ? 'Allowed'
          : body.decision === 'deny'
          ? 'Denied'
          : body.answer
          ? `Using "${body.answer}"`
          : 'Opened in IDE';
      if (body.decision === 'open_ide') {
        const target = session.ide === 'terminal' ? session.cwd : (session.targetFile || session.cwd);
        focusApp(session.ide, target);
      }
      upsertSession(id, {
        status: 'running',
        isWorking: true,
        statusLabel: 'Working',
        subtitle: label,
        pendingRequest: null,
      });
    }
    return sendJson(res, 200, { ok: true });
  }

  const focusMatch = url.pathname.match(/^\/sessions\/([^/]+)\/focus$/);
  if (req.method === 'POST' && focusMatch) {
    const id = decodeURIComponent(focusMatch[1]);
    const session = sessions.get(id);
    const ide = session?.ide || 'vscode';
    const target = ide === 'terminal' ? session?.cwd : (session?.targetFile || session?.cwd);
    focusApp(ide, target);
    return sendJson(res, 200, { ok: true });
  }

  const dismissMatch = url.pathname.match(/^\/sessions\/([^/]+)\/dismiss$/);
  if (req.method === 'POST' && dismissMatch) {
    const id = decodeURIComponent(dismissMatch[1]);
    const session = sessions.get(id);
    if (session) {
      session.dismissed = true;
      broadcast();
    }
    return sendJson(res, 200, { ok: true });
  }

  sendJson(res, 404, { error: 'Not found' });
});

setInterval(pollWatchers, 1500);
pollWatchers();

server.listen(PORT, HOST, () => {
  console.log(`Dumpling daemon listening on http://${HOST}:${PORT}`);
});
