// Integration qualification through Solvent's existing exported C ABI.
// No Solvent language document or alternate numerical implementation is used.
// The ABI cannot set SolveOpts.acceptance_tol (it remains the upstream 1e-6),
// so this is explicitly a separate lane from the native Rust adapter.
const revision = '64bad08b2f126f6be495f6647c180ae703e0963e';
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const copyPoints = points => points.map(point => [...point]);
const ns = milliseconds => Math.round(milliseconds * 1e6);

function physical(request, targets, points) {
  const fixture = request.fixture;
  if (points.length !== fixture.points.length ||
      points.some(point => point.length !== 2 || !point.every(Number.isFinite))) {
    return { accepted: false, maxError: null, mismatches: fixture.orientations.length };
  }
  let maxError = 0;
  for (const index of fixture.fixed) {
    maxError = Math.max(maxError, Math.hypot(
      points[index][0] - fixture.points[index][0],
      points[index][1] - fixture.points[index][1]));
  }
  for (let i = 0; i < fixture.constraints.length; i++) {
    const row = fixture.constraints[i];
    const dx = points[row.b][0] - points[row.a][0];
    const dy = points[row.b][1] - points[row.a][1];
    let error;
    switch (row.kind) {
      case 'distance': error = Math.abs(Math.hypot(dx, dy) - targets[i]); break;
      case 'horizontal': error = Math.abs(dy); break;
      case 'vertical': error = Math.abs(dx); break;
      case 'coincident': error = Math.hypot(dx, dy); break;
      default: throw new Error(`Unsupported constraint ${row.kind}`);
    }
    maxError = Math.max(maxError, error);
  }
  let mismatches = 0;
  for (const [a, b, c, sign] of fixture.orientations ?? []) {
    const bx = points[b][0] - points[a][0], by = points[b][1] - points[a][1];
    const cx = points[c][0] - points[a][0], cy = points[c][1] - points[a][1];
    const scale = Math.max(Math.abs(bx), Math.abs(by), Math.abs(cx), Math.abs(cy));
    const cross = scale === 0 ? 0 : (bx / scale) * (cy / scale) - (by / scale) * (cx / scale);
    if (!Number.isFinite(cross) || sign * cross <= 0) mismatches++;
  }
  return {
    accepted: Number.isFinite(maxError) && maxError <= request.tolerance && mismatches === 0,
    maxError: Number.isFinite(maxError) ? maxError : null,
    mismatches,
  };
}

export async function installSolvent(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Cannot load Solvent Wasm: ${response.status}`);
  const { instance } = await WebAssembly.instantiateStreaming(response, {});
  const abi = instance.exports;
  const doubles = (pointer, length) => new Float64Array(abi.memory.buffer, pointer, length);
  function allocate(bytes) {
    const pointer = abi.gcs_malloc(Math.max(bytes, 1));
    if (!pointer) throw new Error('Solvent Wasm allocation failed.');
    return pointer;
  }
  function takeString(handle) {
    if (!handle) return '';
    try {
      const pointer = abi.gcs_str_ptr(handle), length = abi.gcs_str_len(handle);
      return decoder.decode(new Uint8Array(abi.memory.buffer, pointer, length));
    } finally {
      abi.gcs_str_free(handle);
    }
  }
  function withString(text, fn) {
    const bytes = encoder.encode(text), pointer = allocate(bytes.length);
    try {
      new Uint8Array(abi.memory.buffer, pointer, bytes.length).set(bytes);
      return fn(pointer, bytes.length);
    } finally {
      abi.gcs_free(pointer, Math.max(bytes.length, 1));
    }
  }
  function failure(fallback) {
    return new Error(takeString(abi.gcs_last_error()) || fallback);
  }

  class Runner {
    constructor(request) {
      if (request.schema_version !== 1 || request.engine !== 'solvent_cabi_wasm' ||
          !['cold', 'warm'].includes(request.mode)) {
        throw new Error('Unsupported Solvent browser request.');
      }
      this.request = request;
      this.seed = copyPoints(request.fixture.points);
      this.sketch = 0;
      this.system = 0;
      this.resultBuffer = 0;
      this.coordinateBuffer = 0;
      this.constraintIds = [];
      this.rejected = false;
    }

    disposeModel() {
      if (this.system) abi.gcs_system_free(this.system);
      if (this.sketch) abi.gcs_sketch_free(this.sketch);
      if (this.resultBuffer) abi.gcs_free(this.resultBuffer, 9 * 8);
      if (this.coordinateBuffer) abi.gcs_free(this.coordinateBuffer, this.seed.length * 2 * 8);
      this.system = this.sketch = this.resultBuffer = this.coordinateBuffer = 0;
      this.constraintIds = [];
    }

    build(targets) {
      const fixture = this.request.fixture, fixed = new Set(fixture.fixed);
      const seed = this.request.mode === 'warm' ? this.seed : fixture.points;
      this.sketch = abi.gcs_sketch_new();
      if (!this.sketch) throw failure('Cannot create sketch.');
      for (let i = 0; i < fixture.points.length; i++) {
        const p = seed[i];
        const index = withString(`p${i}`, (name, length) =>
          abi.gcs_sketch_point(this.sketch, p[0], p[1], fixed.has(i) ? 1 : 0, name, length));
        if (index !== i) throw failure('Unexpected point indexing.');
      }
      for (let i = 0; i < fixture.constraints.length; i++) {
        const row = fixture.constraints[i];
        let record;
        if (row.kind === 'distance' || row.kind === 'coincident') {
          record = {
            type: row.kind === 'distance' ? 'Distance' : 'Coincident',
            args: [['point', row.a], ['point', row.b]],
          };
          if (row.kind === 'distance') record.args.push(targets[i]);
        } else if (row.kind === 'horizontal' || row.kind === 'vertical') {
          const line = abi.gcs_sketch_line(this.sketch, row.a, row.b);
          if (line < 0) throw failure('Cannot create line.');
          record = { type: row.kind === 'horizontal' ? 'Horizontal' : 'Vertical', args: [['line', line]] };
        } else {
          throw new Error(`Unsupported constraint ${row.kind}`);
        }
        const id = withString(JSON.stringify(record), (pointer, length) =>
          abi.gcs_constraint_add(this.sketch, pointer, length));
        if (id < 0) throw failure('Cannot add constraint.');
        this.constraintIds.push(id);
      }
      this.system = abi.gcs_system_new(this.sketch);
      if (!this.system) throw failure('Cannot compile system.');
      this.resultBuffer = allocate(9 * 8);
      this.coordinateBuffer = allocate(fixture.points.length * 2 * 8);
      this.activeCoordinates = abi.gcs_system_n_free(this.system);
      this.equations = abi.gcs_system_n_res(this.system);
      this.nonzeros = abi.gcs_system_nnz(this.system);
    }

    update(targets) {
      doubles(this.coordinateBuffer, this.seed.length * 2).set(this.seed.flat());
      if (abi.gcs_sketch_set_x(this.sketch, this.coordinateBuffer, this.seed.length * 2) < 0) {
        throw failure('Cannot restore the accepted coordinates.');
      }
      for (let i = 0; i < this.request.fixture.constraints.length; i++) {
        if (this.request.fixture.constraints[i].kind !== 'distance') continue;
        const status = withString('d', (pointer, length) =>
          abi.gcs_constraint_set_num(this.sketch, this.constraintIds[i], pointer, length, targets[i]));
        if (status < 0) throw failure('Cannot update distance.');
      }
      abi.gcs_system_refresh_consts(this.system, this.sketch);
    }

    metadata() {
      return {
        record: 'metadata', schema_version: 1, engine: this.request.engine,
        adapter: 'solvent_existing_c_abi_wasm/1', upstream_revision: revision,
        lifecycle: 'cold rebuilds; warm retains sketch and compiled System and restores the accepted coordinates',
        integration: 'JavaScript calls existing flat C ABI; no language document; Wasm memory copies are timed',
        native_max_iterations: 100, native_max_function_evaluations: 0,
        native_iteration_tolerance: 1e-14, native_acceptance_tolerance: 1e-6,
        tolerance_limit: 'The existing C ABI does not expose acceptance_tol. Native Rust lane config differs.',
        cold_teardown: 'Prior model disposal occurs before the next operation clock, matching the native Solvent adapter.',
        physical_tolerance: this.request.tolerance,
        diagnostics_included: false,
        timing: 'performance.now before build/update through coordinate extraction; excludes JSON and common physical acceptance',
      };
    }

    step(index) {
      const request = this.request, fixture = request.fixture;
      const targets = request.edits[(index + request.warmups) % request.edits.length].values;
      const reused = request.mode === 'warm' && this.system !== 0;
      const reset = reused && this.rejected;
      let buildMs = 0, solveMs = 0, result = null, status = 'adapter_error', error = null;
      let coordinates = copyPoints(request.mode === 'warm' ? this.seed : fixture.points);
      if (!reused) this.disposeModel();
      const started = performance.now();
      try {
        if (reused) this.update(targets); else this.build(targets);
        buildMs = performance.now() - started;
        const solveStarted = performance.now();
        const message = abi.gcs_system_solve(
          this.system, this.sketch, 0, 1e-14, 100, 0, -1, 1, this.resultBuffer);
        solveMs = performance.now() - solveStarted;
        if (!message) throw failure('Solvent solve returned no result.');
        status = takeString(message);
        result = Array.from(doubles(this.resultBuffer, 9));
        abi.gcs_sketch_get_x(this.sketch, this.coordinateBuffer);
        const values = doubles(this.coordinateBuffer, fixture.points.length * 2);
        coordinates = fixture.points.map((_, i) => [values[2 * i], values[2 * i + 1]]);
      } catch (exception) {
        error = String(exception?.stack ?? exception);
        if (buildMs === 0) buildMs = performance.now() - started;
        coordinates = copyPoints(request.mode === 'warm' ? this.seed : fixture.points);
      }
      const elapsedMs = performance.now() - started;
      // Never reuse a partially initialized or trapped model. A later warm
      // rebuild starts at the last common accepted coordinates.
      if (error !== null) this.disposeModel();
      const physicalResult = physical(request, targets, coordinates);
      const accepted = error === null && physicalResult.accepted;
      if (request.mode === 'warm') {
        if (accepted) this.seed = copyPoints(coordinates);
        this.rejected = !accepted;
      }
      return {
        schema_version: 1, engine: request.engine, mode: request.mode,
        fixture_id: fixture.id, index, warmup: index < 0,
        build_ns: ns(buildMs), solve_ns: ns(solveMs), elapsed_ns: ns(elapsedMs),
        coordinates, reported_success: result !== null && result[0] === 1,
        status, adapter_error: error, accepted, iterations: result?.[6] ?? null,
        model_reused: reused, session_reused: reused, coordinate_seed_reset: reset,
        coordinate_seed_restored: reused,
        active_coordinates: this.activeCoordinates ?? 0, equations: this.equations ?? 0,
        jacobian_nonzeros: this.nonzeros ?? null,
        geometric_free_coordinates: 2 * (fixture.points.length - fixture.fixed.length),
        native_status_code: result?.[1] ?? null, native_residual_norm: result?.[2] ?? null,
        native_max_residual: result?.[3] ?? null,
        residual_evaluations: result?.[4] ?? null, jacobian_evaluations: result?.[5] ?? null,
        numerical_rank: result !== null && result[7] >= 0 ? result[7] : null,
        physical_max_error: physicalResult.maxError,
        orientation_mismatches: physicalResult.mismatches,
      };
    }
  }

  let runner = null;
  globalThis.comparisonBegin = encoded => {
    runner?.disposeModel();
    runner = new Runner(JSON.parse(encoded));
    return JSON.stringify(runner.metadata());
  };
  globalThis.comparisonStep = index => {
    if (!runner) throw new Error('Call comparisonBegin first.');
    return JSON.stringify(runner.step(index));
  };
  globalThis.comparisonDispose = () => {
    runner?.disposeModel();
    runner = null;
  };
}
