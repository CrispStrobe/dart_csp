// Run a pure-Dart dart2js or dart2wasm artifact under Node, forwarding main args.
// Usage: node tool/run_dart_node.cjs path/to/program.js [Dart arguments...]
//        node tool/run_dart_node.cjs path/to/program.wasm [Dart arguments...]
const { readFile } = require('node:fs/promises');
const { resolve } = require('node:path');
const { pathToFileURL } = require('node:url');

async function main() {
  const [artifact, ...args] = process.argv.slice(2);
  if (!artifact || !/\.(js|wasm)$/.test(artifact)) {
    throw new Error('Expected a generated .js or .wasm artifact path.');
  }
  const filename = resolve(artifact);
  if (filename.endsWith('.wasm')) {
    const loader = filename.replace(/\.wasm$/, '.mjs');
    const runtime = await import(pathToFileURL(loader).href);
    const compiled = await runtime.compile(await readFile(filename));
    const app = await compiled.instantiate();
    app.invokeMain(...args);
  } else {
    globalThis.self = globalThis;
    globalThis.dartMainRunner = (dartMain) => dartMain(args);
    require(filename);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
