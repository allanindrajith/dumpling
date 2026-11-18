import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const settingsPath = path.join(os.homedir(), '.claude', 'settings.json');
const hookScript = path.resolve(import.meta.dirname, '..', 'hooks', 'claude-hook.mjs');
const command = `node "${hookScript}"`;

let settings = {};
if (fs.existsSync(settingsPath)) {
  const backupPath = `${settingsPath}.dumpling-backup-${Date.now()}`;
  fs.copyFileSync(settingsPath, backupPath);
  console.log(`Backed up ${settingsPath} -> ${backupPath}`);
  settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
}

settings.hooks = settings.hooks || {};

for (const eventName of ['PreToolUse', 'PostToolUse', 'PermissionRequest', 'Stop']) {
  const list = Array.isArray(settings.hooks[eventName]) ? settings.hooks[eventName] : [];
  const already = list.some((entry) =>
    entry.hooks?.some((h) => typeof h.command === 'string' && h.command.includes('claude-hook.mjs'))
  );
  if (!already) {
    list.push({
      hooks: [{ type: 'command', command }],
    });
  }
  settings.hooks[eventName] = list;
}

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
console.log(`Installed Dumpling hooks into ${settingsPath}`);
