//! Native benchmark adapters for the exact pinned upstream solver revisions.
//! Common acceptance checks run outside each timed build/solve/extract interval.

use std::env;
use std::error::Error;
use std::fs;
use std::io::{self, BufWriter, Write};
use std::time::Instant;

use serde::{Deserialize, Serialize};

const EZPZ_REVISION: &str = "915882cc731da31042ce494c89b10334ee57837a";
const NEOSCAD_REVISION: &str = "87ad5bab1d89c1723c1ba4566f27555209a6fe4a";

#[derive(Debug, Deserialize)]
struct Request {
    schema_version: u32,
    engine: Engine,
    mode: Mode,
    warmups: usize,
    samples: usize,
    tolerance: f64,
    fixture: Fixture,
    #[serde(default)]
    edits: Vec<Edit>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
enum Engine {
    Ezpz,
    #[serde(rename = "ezpz_analysis")]
    EzpzAnalysis,
    Neoscad,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
enum Mode {
    Cold,
    Warm,
}

#[derive(Debug, Deserialize)]
struct Fixture {
    id: String,
    points: Vec<[f64; 2]>,
    fixed: Vec<usize>,
    constraints: Vec<Constraint>,
    #[serde(default)]
    orientations: Vec<(usize, usize, usize, f64)>,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Kind {
    Distance,
    Horizontal,
    Vertical,
    Coincident,
}

#[derive(Debug, Deserialize)]
struct Constraint {
    kind: Kind,
    a: usize,
    b: usize,
    value: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct Edit {
    values: Vec<f64>,
}

#[derive(Debug, Serialize)]
struct Sample<'a> {
    schema_version: u32,
    engine: Engine,
    mode: Mode,
    fixture_id: &'a str,
    index: i64,
    warmup: bool,
    build_ns: u128,
    solve_ns: u128,
    elapsed_ns: u128,
    coordinates: Vec<[f64; 2]>,
    reported_success: bool,
    status: String,
    adapter_error: Option<String>,
    accepted: bool,
    iterations: Option<usize>,
    model_reused: bool,
    active_coordinates: usize,
    equations: usize,
    // Additional observations make native status and shared acceptance auditable.
    geometric_free_coordinates: usize,
    engine_converged: bool,
    engine_satisfied: bool,
    engine_tolerance: Option<f64>,
    engine_degenerate: bool,
    engine_flips: Option<usize>,
    engine_rank: Option<usize>,
    engine_dof: Option<usize>,
    engine_underconstrained_coordinates: Option<usize>,
    physical_max_error: Option<f64>,
    orientation_mismatches: usize,
}

struct NativeResult {
    valid_output: bool,
    build_ns: u128,
    solve_ns: u128,
    elapsed_ns: u128,
    coordinates: Vec<[f64; 2]>,
    reported_success: bool,
    status: String,
    iterations: Option<usize>,
    active_coordinates: usize,
    equations: usize,
    converged: bool,
    satisfied: bool,
    tolerance: Option<f64>,
    degenerate: bool,
    flips: Option<usize>,
    rank: Option<usize>,
    dof: Option<usize>,
    underconstrained_coordinates: Option<usize>,
}

fn equation_count(fixture: &Fixture) -> usize {
    2 * fixture.fixed.len()
        + fixture
            .constraints
            .iter()
            .map(|c| {
                if matches!(c.kind, Kind::Coincident) {
                    2
                } else {
                    1
                }
            })
            .sum::<usize>()
}

fn validate_request(request: &Request) -> Result<(), String> {
    if request.schema_version != 1 {
        return Err("Only schema_version=1 is supported".into());
    }
    if !request.tolerance.is_finite() || request.tolerance <= 0.0 {
        return Err("tolerance must be finite and positive".into());
    }
    if request.warmups > i64::MAX as usize || request.samples > i64::MAX as usize {
        return Err("warmups and samples must fit a signed 64-bit index".into());
    }
    let f = &request.fixture;
    if f.points.is_empty() || !f.points.iter().flatten().all(|v| v.is_finite()) {
        return Err("points must be nonempty and finite".into());
    }
    if f.points.len() > (u32::MAX / 2) as usize {
        return Err("Too many points for upstream scalar identifiers".into());
    }
    let mut fixed = std::collections::BTreeSet::new();
    for &index in &f.fixed {
        if index >= f.points.len() || !fixed.insert(index) {
            return Err("fixed must contain distinct valid point indices".into());
        }
    }
    for c in &f.constraints {
        if c.a >= f.points.len() || c.b >= f.points.len() || c.a == c.b {
            return Err("constraints must refer to distinct valid point indices".into());
        }
        if matches!(c.kind, Kind::Distance) && !c.value.is_some_and(|v| v.is_finite() && v >= 0.0) {
            return Err("distance constraints require a finite nonnegative value".into());
        }
    }
    for &(a, b, c, sign) in &f.orientations {
        if a >= f.points.len()
            || b >= f.points.len()
            || c >= f.points.len()
            || !sign.is_finite()
            || sign == 0.0
        {
            return Err("orientations require valid indices and a nonzero finite sign".into());
        }
    }
    for edit in &request.edits {
        if edit.values.len() != f.constraints.len() || !edit.values.iter().all(|v| v.is_finite()) {
            return Err("each edit must have one finite value per constraint".into());
        }
        if f.constraints
            .iter()
            .zip(&edit.values)
            .any(|(c, &v)| matches!(c.kind, Kind::Distance) && v < 0.0)
        {
            return Err("edited distances must be nonnegative".into());
        }
    }
    Ok(())
}

fn solve_ezpz(request: &Request, seed: &[[f64; 2]], values: &[f64]) -> NativeResult {
    use ezpz::datatypes::inputs::{DatumLineSegment, DatumPoint};
    use ezpz::{Config, Constraint as C, ConstraintRequest, IdGenerator, WarningContent};

    let start = Instant::now();
    let mut ids = IdGenerator::default();
    let points: Vec<_> = seed.iter().map(|_| DatumPoint::new(&mut ids)).collect();
    let mut constraints = Vec::with_capacity(request.fixture.fixed.len() * 2 + values.len());
    for &p in &request.fixture.fixed {
        let target = request.fixture.points[p];
        constraints.push(ConstraintRequest::highest_priority(C::Fixed(
            points[p].id_x(),
            target[0],
        )));
        constraints.push(ConstraintRequest::highest_priority(C::Fixed(
            points[p].id_y(),
            target[1],
        )));
    }
    for (c, &value) in request.fixture.constraints.iter().zip(values) {
        let a = points[c.a];
        let b = points[c.b];
        let relation = match c.kind {
            Kind::Distance => C::Distance(a, b, value),
            Kind::Horizontal => C::Horizontal(DatumLineSegment::new(a, b)),
            Kind::Vertical => C::Vertical(DatumLineSegment::new(a, b)),
            Kind::Coincident => C::PointsCoincident(a, b),
        };
        constraints.push(ConstraintRequest::highest_priority(relation));
    }
    let mut guesses = Vec::with_capacity(seed.len() * 2);
    for (point, xy) in points.iter().zip(seed) {
        guesses.push((point.id_x(), xy[0]));
        guesses.push((point.id_y(), xy[1]));
    }
    // Componentwise constraints must also meet the common Euclidean tolerance.
    let tolerance = request.tolerance / std::f64::consts::SQRT_2;
    let config = Config::default().with_convergence_tolerance(tolerance);
    let built = Instant::now();
    let result = if matches!(request.engine, Engine::EzpzAnalysis) {
        ezpz::solve_analysis(&constraints, guesses, config)
            .map(|r| (r.outcome, Some(r.analysis.underconstrained().len())))
    } else {
        ezpz::solve(&constraints, guesses, config).map(|r| (r, None))
    };
    let solved = Instant::now();
    let (
        coordinates,
        reported_success,
        status,
        iterations,
        converged,
        satisfied,
        degenerate,
        valid_output,
        underconstrained_coordinates,
    ) = match result {
        Ok((outcome, underconstrained)) => {
            let coordinates = points
                .iter()
                .map(|point| {
                    let p = outcome.final_value_point(point);
                    [p.x, p.y]
                })
                .collect();
            let converged = outcome.converged();
            let satisfied = outcome.is_satisfied();
            let degenerate = outcome
                .warnings()
                .iter()
                .any(|w| matches!(w.content, WarningContent::Degenerate));
            (
                coordinates,
                converged && satisfied,
                if converged && satisfied {
                    "converged_satisfied"
                } else if converged {
                    "converged_unsatisfied"
                } else if satisfied {
                    "not_converged_satisfied"
                } else {
                    "not_converged_unsatisfied"
                }
                .to_string(),
                Some(outcome.iterations()),
                converged,
                satisfied,
                degenerate,
                true,
                underconstrained,
            )
        }
        Err(error) => (
            seed.to_vec(),
            false,
            format!("error: {}", error.error),
            None,
            false,
            false,
            false,
            false,
            None,
        ),
    };
    let finished = Instant::now();
    NativeResult {
        valid_output,
        build_ns: built.duration_since(start).as_nanos(),
        solve_ns: solved.duration_since(built).as_nanos(),
        elapsed_ns: finished.duration_since(start).as_nanos(),
        coordinates,
        reported_success,
        status,
        iterations,
        active_coordinates: seed.len() * 2,
        equations: equation_count(&request.fixture),
        converged,
        satisfied,
        tolerance: Some(tolerance),
        degenerate,
        flips: None,
        rank: None,
        dof: None,
        underconstrained_coordinates,
    }
}

fn solve_neoscad(request: &Request, seed: &[[f64; 2]], values: &[f64]) -> NativeResult {
    use sketch_solver::{Along, Constraint as C, Pair, Sketch, SolveOptions, Status};

    let start = Instant::now();
    let model = (|| -> Result<_, sketch_solver::ModelError> {
        let mut sketch = Sketch::new();
        let mut points = Vec::with_capacity(seed.len());
        for &xy in seed {
            points.push(sketch.point(Some(xy))?);
        }
        for &p in &request.fixture.fixed {
            sketch.add(C::Fix {
                entity: points[p],
                at: Some(request.fixture.points[p]),
            })?;
        }
        for (c, &value) in request.fixture.constraints.iter().zip(values) {
            let a = points[c.a];
            let b = points[c.b];
            let constraint = match c.kind {
                Kind::Distance => C::Distance {
                    a,
                    b,
                    value,
                    along: Along::Direct,
                },
                Kind::Horizontal => C::Horizontal(Pair::Points(a, b)),
                Kind::Vertical => C::Vertical(Pair::Points(a, b)),
                Kind::Coincident => C::Coincident(a, b),
            };
            sketch.add(constraint)?;
        }
        Ok((sketch, points))
    })();
    let built = Instant::now();
    let mut output = NativeResult {
        valid_output: false,
        build_ns: built.duration_since(start).as_nanos(),
        solve_ns: 0,
        elapsed_ns: 0,
        coordinates: Vec::new(),
        reported_success: false,
        status: String::new(),
        iterations: None,
        active_coordinates: seed.len() * 2,
        equations: equation_count(&request.fixture),
        converged: false,
        satisfied: false,
        tolerance: None,
        degenerate: false,
        flips: None,
        rank: None,
        dof: None,
        underconstrained_coordinates: None,
    };
    match model {
        Ok((sketch, points)) => {
            let solve_start = Instant::now();
            let result = sketch.solve_with(&SolveOptions::default());
            let solved = Instant::now();
            output.solve_ns = solved.duration_since(solve_start).as_nanos();
            match result {
                Ok(solution) => {
                    output.valid_output = true;
                    output.coordinates = points
                        .iter()
                        .map(|&point| solution.point(point).unwrap_or([f64::NAN, f64::NAN]))
                        .collect();
                    output.reported_success = solution.status == Status::Solved;
                    output.status = format!("{:?}", solution.status);
                    output.iterations = Some(solution.iterations as usize);
                    output.active_coordinates = solution.unknowns;
                    output.equations = solution.equations;
                    output.converged = output.reported_success;
                    output.satisfied = output.reported_success;
                    output.tolerance = Some(solution.tolerance);
                    output.flips = Some(solution.flipped.len());
                    output.rank = Some(solution.rank);
                    output.dof = Some(solution.dof);
                }
                Err(error) => {
                    output.coordinates = seed.to_vec();
                    output.status = format!("error: {error}");
                }
            }
        }
        Err(error) => {
            output.coordinates = seed.to_vec();
            output.status = format!("model_error: {error}");
        }
    }
    output.elapsed_ns = start.elapsed().as_nanos();
    output
}

/// Uses the physical meanings of the protocol, independently of native residuals.
/// Zero cross products do not meet either required branch sign.
fn acceptance(
    fixture: &Fixture,
    values: &[f64],
    points: &[[f64; 2]],
    tolerance: f64,
) -> (bool, Option<f64>, usize) {
    if points.len() != fixture.points.len() || !points.iter().flatten().all(|v| v.is_finite()) {
        return (false, None, fixture.orientations.len());
    }
    let mut max_error: f64 = 0.0;
    for &p in &fixture.fixed {
        let target = fixture.points[p];
        max_error = max_error.max((points[p][0] - target[0]).hypot(points[p][1] - target[1]));
    }
    for (c, &value) in fixture.constraints.iter().zip(values) {
        let dx = points[c.b][0] - points[c.a][0];
        let dy = points[c.b][1] - points[c.a][1];
        let error = match c.kind {
            Kind::Distance => (dx.hypot(dy) - value).abs(),
            Kind::Horizontal => dy.abs(),
            Kind::Vertical => dx.abs(),
            Kind::Coincident => dx.hypot(dy),
        };
        if !error.is_finite() {
            return (false, None, fixture.orientations.len());
        }
        max_error = max_error.max(error);
    }
    let mismatches = fixture
        .orientations
        .iter()
        .filter(|&&(a, b, c, sign)| {
            let ab = [points[b][0] - points[a][0], points[b][1] - points[a][1]];
            let ac = [points[c][0] - points[a][0], points[c][1] - points[a][1]];
            // Normalize before taking the cross product to avoid overflow/underflow.
            let scale = ab
                .iter()
                .chain(ac.iter())
                .map(|v| v.abs())
                .fold(0.0, f64::max);
            if scale == 0.0 || !scale.is_finite() {
                return true;
            }
            let cross = (ab[0] / scale) * (ac[1] / scale) - (ab[1] / scale) * (ac[0] / scale);
            cross == 0.0
                || !cross.is_finite()
                || cross.is_sign_positive() != sign.is_sign_positive()
        })
        .count();
    (
        max_error <= tolerance && mismatches == 0,
        Some(max_error),
        mismatches,
    )
}

fn run() -> Result<(), Box<dyn Error>> {
    let mut args = env::args();
    let _program = args.next();
    let path = args
        .next()
        .ok_or("usage: geometry-rust-adapter REQUEST.json")?;
    if args.next().is_some() {
        return Err("usage: geometry-rust-adapter REQUEST.json".into());
    }
    let request: Request = serde_json::from_slice(&fs::read(path)?)?;
    validate_request(&request)?;
    let mut output = BufWriter::new(io::stdout().lock());
    serde_json::to_writer(
        &mut output,
        &serde_json::json!({
            "record": "metadata", "schema_version": 1, "engine": request.engine,
            "revision": match request.engine { Engine::Ezpz | Engine::EzpzAnalysis => EZPZ_REVISION, Engine::Neoscad => NEOSCAD_REVISION },
            "adapter": "geometry-comparison-rust-adapter/0.1.0",
            "lifecycle": "rebuild_native_model_each_operation; warm_reuses_only_accepted_coordinates",
            "acceptance": "independent_physical_tolerance_and_orientation; native_status_recorded_separately",
            "diagnostics": match request.engine { Engine::Ezpz => "solve_without_freedom_analysis", Engine::EzpzAnalysis => "solve_with_dense_QR_freedom_analysis", Engine::Neoscad => "native_solve_includes_rank_and_conflict_diagnosis" },
            "native_iteration_limit": match request.engine { Engine::Ezpz | Engine::EzpzAnalysis => 35, Engine::Neoscad => 100 },
            "tolerance_policy": match request.engine { Engine::Ezpz | Engine::EzpzAnalysis => "configured_residual_tolerance=request/sqrt(2); native_satisfaction_epsilon=1e-4", Engine::Neoscad => "upstream_relative_tolerance_1e-10_times_size_is_not_configurable" },
            "active_coordinates_definition": "number_of_native_numerical_unknowns_including_fixed_point_equations",
            "timing": "native_monotonic_clock; build_update_and_solve_and_coordinate_extraction; excludes_JSON_and_common_validation"
        }),
    )?;
    writeln!(output)?;
    output.flush()?;
    let default_values: Vec<_> = request
        .fixture
        .constraints
        .iter()
        .map(|c| c.value.unwrap_or(0.0))
        .collect();
    let mut committed = request.fixture.points.clone();
    for index in -(request.warmups as i64)..request.samples as i64 {
        let operation = (index + request.warmups as i64) as usize;
        let values = if request.edits.is_empty() {
            &default_values
        } else {
            &request.edits[operation % request.edits.len()].values
        };
        let seed = match request.mode {
            Mode::Cold => &request.fixture.points,
            Mode::Warm => &committed,
        };
        let operation_start = Instant::now();
        let attempted = std::panic::catch_unwind(|| match request.engine {
            Engine::Ezpz | Engine::EzpzAnalysis => solve_ezpz(&request, seed, values),
            Engine::Neoscad => solve_neoscad(&request, seed, values),
        });
        let native = match attempted {
            Ok(native) => native,
            Err(payload) => {
                let message = payload
                    .downcast_ref::<String>()
                    .map(String::as_str)
                    .or_else(|| payload.downcast_ref::<&str>().copied())
                    .unwrap_or("non-string panic");
                NativeResult {
                    valid_output: false,
                    build_ns: 0,
                    solve_ns: 0,
                    elapsed_ns: operation_start.elapsed().as_nanos(),
                    coordinates: seed.to_vec(),
                    reported_success: false,
                    status: format!("panic: {message}"),
                    iterations: None,
                    active_coordinates: seed.len() * 2,
                    equations: equation_count(&request.fixture),
                    converged: false,
                    satisfied: false,
                    tolerance: None,
                    degenerate: false,
                    flips: None,
                    rank: None,
                    dof: None,
                    underconstrained_coordinates: None,
                }
            }
        };
        let (physically_valid, physical_max_error, orientation_mismatches) = acceptance(
            &request.fixture,
            values,
            &native.coordinates,
            request.tolerance,
        );
        let accepted = native.valid_output && physically_valid;
        if accepted && matches!(request.mode, Mode::Warm) {
            committed.clone_from(&native.coordinates);
        }
        let sample = Sample {
            schema_version: 1,
            engine: request.engine,
            mode: request.mode,
            fixture_id: &request.fixture.id,
            index,
            warmup: index < 0,
            build_ns: native.build_ns,
            solve_ns: native.solve_ns,
            elapsed_ns: native.elapsed_ns,
            coordinates: native.coordinates,
            reported_success: native.reported_success,
            adapter_error: if native.valid_output {
                None
            } else {
                Some(native.status.clone())
            },
            status: native.status,
            accepted,
            iterations: native.iterations,
            model_reused: false,
            active_coordinates: native.active_coordinates,
            equations: native.equations,
            geometric_free_coordinates: (request.fixture.points.len()
                - request.fixture.fixed.len())
                * 2,
            engine_converged: native.converged,
            engine_satisfied: native.satisfied,
            engine_tolerance: native.tolerance,
            engine_degenerate: native.degenerate,
            engine_flips: native.flips,
            engine_rank: native.rank,
            engine_dof: native.dof,
            engine_underconstrained_coordinates: native.underconstrained_coordinates,
            physical_max_error,
            orientation_mismatches,
        };
        serde_json::to_writer(&mut output, &sample)?;
        writeln!(output)?;
        output.flush()?;
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("geometry-rust-adapter: {error}");
        std::process::exit(2);
    }
}
