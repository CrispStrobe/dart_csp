// The host clocks the complete callable boundary separately from solver work.
// Playwright transport, record parsing, and event-loop yields are outside both.
const target = new URL(location.href).searchParams.get('target');
const loadStarted = performance.now();

function script(src) {
  return new Promise((resolve, reject) => {
    const element = document.createElement('script');
    element.src = src;
    element.onload = resolve;
    element.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(element);
  });
}

function timerResolution() {
  let previous = performance.now(), minimum = Infinity;
  for (let i = 0; i < 2000; i++) {
    const next = performance.now();
    if (next > previous) minimum = Math.min(minimum, next - previous);
    previous = next;
  }
  return Number.isFinite(minimum) ? minimum : null;
}

try {
  if (target === 'dart2js') {
    await script('./build/dart_adapter.js');
  } else if (target === 'dart2wasm') {
    const runtime = await import('./build/dart_adapter.mjs');
    const module = await runtime.compileStreaming(fetch('./build/dart_adapter.wasm'));
    const instance = await module.instantiate();
    instance.invokeMain();
  } else if (target === 'solvent_wasm') {
    const { installSolvent } = await import('./solvent.mjs');
    await installSolvent('./build/solvent.wasm');
  } else {
    throw new Error(`Unknown target ${target}`);
  }
  if (typeof globalThis.comparisonStep !== 'function') {
    throw new Error('The compiled adapter did not register its entry points.');
  }
  const loadMs = performance.now() - loadStarted;
  const info = {
    target,
    user_agent: navigator.userAgent,
    platform: navigator.platform,
    hardware_concurrency: navigator.hardwareConcurrency,
    cross_origin_isolated: globalThis.crossOriginIsolated,
    timer_min_observed_step_ms: timerResolution(),
    module_load_ms: loadMs,
    timing_resolution_note: 'Nanosecond field units do not imply nanosecond browser timer resolution.',
  };
  globalThis.comparisonHost = {
    info,
    async run(request, emit) {
      const start = performance.now();
      const meta = JSON.parse(globalThis.comparisonBegin(JSON.stringify(request)));
      meta.browser_begin_ns = Math.round((performance.now() - start) * 1e6);
      meta.browser = info;
      await emit(meta);
      try {
        for (let i = -request.warmups; i < request.samples; i++) {
          const before = performance.now();
          const encoded = globalThis.comparisonStep(i);
          const boundaryNs = Math.round((performance.now() - before) * 1e6);
          const record = JSON.parse(encoded);
          record.browser_boundary_ns = boundaryNs;
          record.browser_target = target;
          await emit(record);
          // A browser job remains cancellable between operations. Yield time is
          // never part of a solve or public-boundary measurement.
          await new Promise(resolve => setTimeout(resolve, 0));
        }
      } finally {
        globalThis.comparisonDispose?.();
      }
    },
  };
  document.querySelector('#status').textContent = `Ready: ${target}`;
} catch (error) {
  globalThis.comparisonLoadError = String(error?.stack ?? error);
  document.querySelector('#status').textContent = globalThis.comparisonLoadError;
}
