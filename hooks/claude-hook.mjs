#!/usr/bin/env node
import http from 'node:http';

const PORT = Number(process.env.DUMPLING_PORT || 47821);

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => (raw += chunk));
process.stdin.on('end', () => {
  if (!raw.trim()) process.exit(0);

  const req = http.request(
    {
      hostname: '127.0.0.1',
      port: PORT,
      path: '/hook',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(raw),
      },
      timeout: 310000,
    },
    (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        if (body && body.trim() !== '{}') {
          process.stdout.write(body);
        }
        process.exit(0);
      });
    }
  );

  // Never block Claude Code if daemon is offline
  req.on('error', () => process.exit(0));
  req.on('timeout', () => {
    req.destroy();
    process.exit(0);
  });

  req.write(raw);
  req.end();
});
