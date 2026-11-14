#!/usr/bin/env node
// Sequential portability host for the exact browser-targeted build artifacts.
// This runs in Node, not Chromium, and must never be called a browser result.
import { readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';

async function emit(value) {
  if (!process.stdout.write(JSON.stringify(value) + '\n')) {
    await once(process.stdout, 'drain');
  }
}

async function main() {
  const [target, requestFile] = process.argv.slice(2);
  const artifactNames = {
    dart2js: ['dart_adapter.js'],
    dart2wasm: ['dart_adapter.wasm', 'dart_adapter.mjs'],
    solvent_wasm: ['solvent.wasm'],
  };
  if (!artifactNames[target] || !requestFile) {
    throw new Error('Usage: node node_host.mjs dart2js|dart2wasm|solvent_wasm REQUEST.json');
  }
  const request = JSON.parse(await readFile(requestFile, 'utf8'));
  const artifacts = [];
  for (const name of artifactNames[target]) {
    const path = new URL(`./build/${name}`, import.meta.url);
    artifacts.push({
      file: name, bytes: (await stat(path)).size,
      sha256: createHash('sha256').update(await readFile(path)).digest('hex'),
    });
  }
  const started = process.hrtime.bigint();
  if (target === 'dart2js') {
    await import('./build/dart_adapter.js');
  } else if (target === 'dart2wasm') {
    const runtime = await import('./build/dart_adapter.mjs');
    const module = await runtime.compile(await readFile(new URL('./build/dart_adapter.wasm', import.meta.url)));
    const instance = await module.instantiate();
    instance.invokeMain();
  } else {
    const { installSolvent } = await import('./solvent.mjs');
    const response = new Response(await readFile(new URL('./build/solvent.wasm', import.meta.url)),
                                  { headers: { 'Content-Type': 'application/wasm' } });
    await installSolvent(response);
  }
  const moduleLoadNs = Number(process.hrtime.bigint() - started);
  if (typeof globalThis.comparisonStep !== 'function') {
    throw new Error('The module did not register its protocol entry point.');
  }
  const beginStarted = process.hrtime.bigint();
  const metadata = JSON.parse(globalThis.comparisonBegin(JSON.stringify(request)));
  metadata.node_begin_ns = Number(process.hrtime.bigint() - beginStarted);
  metadata.host = {
    runtime: 'Node.js', target, node_version: process.version, v8_version: process.versions.v8,
    platform: process.platform, architecture: process.arch,
    module_load_ns: moduleLoadNs, artifacts,
    host_path: fileURLToPath(import.meta.url),
    browser: false,
    purpose: request.run_purpose ?? 'unspecified',
    boundary_clock: 'process.hrtime.bigint; complete synchronous protocol call; excludes host JSON parse and stdout',
  };
  await emit(metadata);
  try {
    for (let index = -request.warmups; index < request.samples; index++) {
      const before = process.hrtime.bigint();
      const encoded = globalThis.comparisonStep(index);
      const boundaryNs = Number(process.hrtime.bigint() - before);
      const record = JSON.parse(encoded);
      record.node_boundary_ns = boundaryNs;
      record.node_target = target;
      await emit(record);
    }
  } finally {
    globalThis.comparisonDispose?.();
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(String(error?.stack ?? error) + '\n');
  process.exitCode = 1;
}
