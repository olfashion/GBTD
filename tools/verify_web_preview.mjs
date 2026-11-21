#!/usr/bin/env node
// Exercise the real fetch adapter against a local HTTP server; no browser UI.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { createReadStream, readFileSync, statSync } from 'node:fs';
import { resolve, join, basename } from 'node:path';
import vm from 'node:vm';

const directory = resolve(process.argv[2] || '');
if (!process.argv[2]) throw new Error('Usage: node tools/verify_web_preview.mjs /path/to/prepared/dist');
const manifest = JSON.parse(readFileSync(join(directory, 'web-preview-manifest.json'), 'utf8'));
const adapter = readFileSync(join(directory, 'wasm-chunk-loader.js'), 'utf8');
const nativeFetch = globalThis.fetch;
let failPart = '';
const errors = [];

const server = createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/passthrough') {
    let body = '';
    request.on('data', (chunk) => { body += chunk; });
    request.on('end', () => {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ method: request.method, body, header: request.headers['x-test'] }));
    });
    return;
  }
  const name = basename(pathname);
  if (name === 'index.wasm' || name === failPart || !manifest.parts.some((p) => p.file === name)) {
    response.writeHead(404);
    response.end('Missing');
    return;
  }
  const path = join(directory, name);
  response.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': statSync(path).size });
  const file = createReadStream(path);
  response.on('close', () => file.destroy());
  file.pipe(response);
});

await new Promise((resolveListening) => server.listen(0, '127.0.0.1', resolveListening));
const origin = `http://127.0.0.1:${server.address().port}`;
globalThis.document = { baseURI: `${origin}/` };
globalThis.location = { origin };
globalThis.dispatchEvent = (event) => { errors.push(event.detail); };
globalThis.fetch = async function recordedFetch(input, init) {
  const url = new URL(input instanceof Request ? input.url : input);
  if (url.origin === 'https://other.invalid') return new Response('cross-origin unchanged');
  return nativeFetch(input, init);
};

try {
  new vm.Script(adapter, { filename: 'wasm-chunk-loader.js' }).runInThisContext();
  const result = await fetch(`${origin}/index.wasm?cache-bust=1`);
  assert.equal(result.headers.get('content-type'), 'application/wasm');
  assert.equal(Number(result.headers.get('content-length')), manifest.bytes);
  const bytes = new Uint8Array(await result.arrayBuffer());
  assert.equal(bytes.length, manifest.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), manifest.sha256);
  assert.ok(WebAssembly.validate(bytes), 'Reassembled bytes form a valid WASM module');
  console.log('PASS: streamed WASM has original bytes, SHA256, MIME type, and length');

  const passthrough = await fetch(`${origin}/passthrough`, {
    method: 'POST', headers: { 'X-Test': 'preserved' }, body: 'untouched body',
  });
  assert.deepEqual(await passthrough.json(), { method: 'POST', body: 'untouched body', header: 'preserved' });
  const crossOrigin = await fetch('https://other.invalid/index.wasm');
  assert.equal(await crossOrigin.text(), 'cross-origin unchanged');
  const range = await fetch(`${origin}/index.wasm`, { headers: { Range: 'bytes=0-7' } });
  assert.equal(range.status, 404, 'Range requests pass through rather than receiving a false full response');
  console.log('PASS: unrelated requests, POST bodies/headers, other origins, and range requests pass through');

  const abort = new AbortController();
  abort.abort();
  await assert.rejects(fetch(`${origin}/index.wasm`, { signal: abort.signal }), { name: 'AbortError' });
  console.log('PASS: caller cancellation aborts the chunk request');

  failPart = manifest.parts[Math.min(1, manifest.parts.length - 1)].file;
  const originalError = console.error;
  console.error = () => {}; // This test deliberately generates a failed download.
  try {
    await assert.rejects(async () => {
      const missing = await fetch(`${origin}/index.wasm`);
      await missing.arrayBuffer();
    }, /returned HTTP 404/);
  } finally {
    console.error = originalError;
  }
  assert.ok(errors.some((event) => event.message.includes('interrupted')));
  console.log('PASS: missing part rejects loading and emits the visible retry error');
} finally {
  globalThis.fetch = nativeFetch;
  server.closeAllConnections();
  await new Promise((resolveClose) => server.close(resolveClose));
}
