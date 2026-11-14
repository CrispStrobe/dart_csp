//! Process-isolated adapter for the pinned Solvent implementation.
//! Parsing, JSON output, and the common physical acceptance gate are not timed.
use std::io::{self, Write};
use std::time::Instant;

use gcs_solve::constraints::{Arg, CKind, Constraint};
use gcs_solve::decompose::PlanSolver;
use gcs_solve::json::{object, parse, Json};
use gcs_solve::model::{EntRef, Sketch};
use gcs_solve::newton::Method;
use gcs_solve::solve::SolveOpts;
use gcs_solve::system::System;

const REVISION: &str = "64bad08b2f126f6be495f6647c180ae703e0963e";

#[derive(Clone)]
struct Row { kind: String, a: usize, b: usize, value: f64 }
struct Fixture {
    id: String,
    points: Vec<[f64; 2]>,
    fixed: Vec<usize>,
    constraints: Vec<Row>,
    orientations: Vec<(usize, usize, usize, f64)>,
}

fn member<'a>(value: &'a Json, key: &str) -> Result<&'a Json, String> {
    value.get(key).ok_or_else(|| format!("missing {key}"))
}
fn number(value: &Json) -> Result<f64, String> {
    match value {
        Json::Num(n) if n.is_finite() => Ok(*n),
        Json::Int(n) => Ok(*n as f64),
        _ => Err("expected finite number".into()),
    }
}
fn index(value: &Json) -> Result<usize, String> {
    let n = number(value)?;
    if n >= 0.0 && n.fract() == 0.0 { Ok(n as usize) } else { Err("expected index".into()) }
}
fn points(value: &Json) -> Result<Vec<[f64; 2]>, String> {
    value.arr().iter().map(|p| {
        if p.arr().len() != 2 { return Err("point must have two coordinates".into()); }
        Ok([number(&p.arr()[0])?, number(&p.arr()[1])?])
    }).collect()
}
fn fixture(value: &Json) -> Result<Fixture, String> {
    let pts = points(member(value, "points")?)?;
    let fixed = member(value, "fixed")?.arr().iter().map(index).collect::<Result<Vec<_>,_>>()?;
    let rows = member(value, "constraints")?.arr().iter().map(|r| {
        let kind = member(r, "kind")?.as_str().to_string();
        if !["distance", "horizontal", "vertical", "coincident"].contains(&kind.as_str()) {
            return Err(format!("unsupported constraint {kind}"));
        }
        Ok(Row {
            kind,
            a: index(member(r, "a")?)?, b: index(member(r, "b")?)?,
            value: r.get("value").map(number).transpose()?.unwrap_or(0.0),
        })
    }).collect::<Result<Vec<_>, String>>()?;
    let orientations = value.get("orientations").map(Json::arr).unwrap_or(&[]).iter().map(|r| {
        let a = r.arr();
        if a.len() != 4 { return Err("orientation must have [a,b,c,sign]".into()); }
        Ok((index(&a[0])?, index(&a[1])?, index(&a[2])?, number(&a[3])?))
    }).collect::<Result<Vec<_>, String>>()?;
    if fixed.iter().any(|&i| i >= pts.len()) || rows.iter().any(|r| r.a >= pts.len() || r.b >= pts.len())
        || orientations.iter().any(|&(a,b,c,_)| [a,b,c].iter().any(|&i| i >= pts.len())) {
        return Err("point index outside fixture".into());
    }
    Ok(Fixture { id: member(value, "id")?.as_str().into(), points: pts, fixed, constraints: rows, orientations })
}

fn make_sketch(f: &Fixture, seed: &[[f64; 2]], values: &[f64]) -> Sketch {
    let mut sk = Sketch::new();
    for (i, p) in seed.iter().enumerate() {
        sk.point(p[0], p[1], f.fixed.contains(&i), "");
    }
    for (i, r) in f.constraints.iter().enumerate() {
        let a = EntRef::point(r.a);
        let b = EntRef::point(r.b);
        let c = match r.kind.as_str() {
            "distance" => Constraint::distance(a, b, values[i]),
            "coincident" => Constraint::coincident(a, b),
            "horizontal" | "vertical" => {
                let line = sk.line(r.a, r.b);
                Constraint::one_line(if r.kind == "horizontal" { CKind::Horizontal } else { CKind::Vertical }, EntRef::line(line))
            },
            _ => unreachable!(),
        };
        sk.add(c);
    }
    sk
}
fn restore(sk: &mut Sketch, pts: &[[f64; 2]]) {
    for (i, p) in pts.iter().enumerate() {
        let params = sk.point_params(i);
        sk.params[params[0] as usize].value = p[0];
        sk.params[params[1] as usize].value = p[1];
    }
}
fn update(sk: &mut Sketch, f: &Fixture, values: &[f64]) {
    for (i, r) in f.constraints.iter().enumerate() {
        if r.kind == "distance" { sk.constraints[i].args[2] = Arg::Num(values[i]); }
    }
}
fn coordinates(sk: &Sketch) -> Vec<[f64; 2]> {
    (0..sk.points.len()).map(|i| { let p=sk.point_xy(i); [p.0,p.1] }).collect()
}
fn acceptance(f: &Fixture, p: &[[f64; 2]], v: &[f64], tol: f64) -> (bool, f64, bool) {
    if p.len() != f.points.len() || p.iter().flatten().any(|x| !x.is_finite()) {
        return (false, f64::INFINITY, false);
    }
    let mut worst = 0.0_f64;
    for (i, r) in f.constraints.iter().enumerate() {
        let dx = p[r.a][0] - p[r.b][0]; let dy = p[r.a][1] - p[r.b][1];
        let e = match r.kind.as_str() {
            "distance" => (dx.hypot(dy) - v[i]).abs(),
            "horizontal" => dy.abs(), "vertical" => dx.abs(),
            "coincident" => dx.hypot(dy), _ => f64::INFINITY,
        };
        worst = worst.max(e);
    }
    for &i in &f.fixed { worst = worst.max((p[i][0]-f.points[i][0]).hypot(p[i][1]-f.points[i][1])); }
    let branch = f.orientations.iter().all(|&(a,b,c,sign)| {
        let cross = (p[b][0]-p[a][0])*(p[c][1]-p[a][1]) - (p[b][1]-p[a][1])*(p[c][0]-p[a][0]);
        cross * sign > 0.0
    });
    (worst <= tol && branch, worst, branch)
}
fn finite(n: f64) -> Json { if n.is_finite() { Json::Num(n) } else { Json::Null } }
fn coords_json(p: &[[f64; 2]]) -> Json {
    Json::Arr(p.iter().map(|q| Json::Arr(q.iter().map(|&n| finite(n)).collect())).collect())
}
enum Backend { Numeric(System), Replay(PlanSolver) }
impl Backend {
    fn new(sk: &Sketch, replay: bool) -> Self {
        if replay { Self::Replay(PlanSolver::new(sk, true)) } else { Self::Numeric(System::new(sk)) }
    }
    fn refresh(&mut self, sk: &Sketch) {
        match self { Self::Numeric(s)=>s.refresh_consts(sk), Self::Replay(s)=>s.system.refresh_consts(sk) }
    }
    fn sizes(&self) -> (usize,usize) {
        let s = match self { Self::Numeric(s)=>s, Self::Replay(s)=>&s.system };
        (s.n_free, s.n_res)
    }
}

fn run() -> Result<(), String> {
    let file = std::env::args().nth(1).ok_or("usage: solvent-adapter REQUEST.json")?;
    let input = std::fs::read_to_string(file).map_err(|e|e.to_string())?;
    let req = parse(&input).map_err(|e|format!("JSON: {e:?}"))?;
    if member(&req,"schema_version")?.as_i64() != 1 { return Err("unsupported schema".into()); }
    let engine = member(&req,"engine")?.as_str();
    if engine != "solvent" && engine != "solvent_replay" { return Err("engine must be solvent or solvent_replay".into()); }
    let replay = engine == "solvent_replay";
    let mode = member(&req,"mode")?.as_str();
    if mode != "cold" && mode != "warm" { return Err("mode must be cold or warm".into()); }
    let warmups = index(member(&req,"warmups")?)?;
    let samples = index(member(&req,"samples")?)?;
    let tolerance = number(member(&req,"tolerance")?)?;
    if tolerance <= 0.0 { return Err("tolerance must be positive".into()); }
    let f = fixture(member(&req,"fixture")?)?;
    let default_values: Vec<f64> = f.constraints.iter().map(|r|r.value).collect();
    let mut edits = req.get("edits").map(Json::arr).unwrap_or(&[]).iter().map(|e| {
        let vals = member(e,"values")?.arr().iter().map(number).collect::<Result<Vec<_>,_>>()?;
        if vals.len()!=f.constraints.len() { return Err("edit value count differs from constraint count".into()); }
        Ok(vals)
    }).collect::<Result<Vec<Vec<f64>>,String>>()?;
    let mut accepted_values=default_values.clone();
    if edits.is_empty() { edits.push(default_values); }
    let mut session: Option<(Sketch,Backend)> = None;
    let mut seed = f.points.clone();
    let stdout = io::stdout(); let mut out = io::BufWriter::new(stdout.lock());
    for round in 0..warmups+samples {
        let values = &edits[round % edits.len()];
        // Teardown belongs after the preceding extraction, outside its timing window.
        if mode=="cold" { session=None; }
        let reused = mode=="warm" && session.is_some();
        let begin = Instant::now();
        if !reused {
            let sk=make_sketch(&f, if mode=="warm" {&seed} else {&f.points}, values);
            let backend=Backend::new(&sk,replay);
            session=Some((sk,backend));
        } else {
            let (sk,backend)=session.as_mut().unwrap();
            // This is part of the host edit/update cost. Seed is the last accepted pose.
            restore(sk,&seed); update(sk,&f,values); backend.refresh(sk);
        }
        // Save branch decisions as well as coordinates for transactional host rejection.
        let prior_branches=session.as_ref().unwrap().0.branches.clone();
        let prior_plan_branches=match &session.as_ref().unwrap().1 {
            Backend::Replay(p)=>Some(p.plan.branches()),Backend::Numeric(_)=>None,
        };
        let build_ns = begin.elapsed().as_nanos() as i64;
        let (sk,backend)=session.as_mut().unwrap();
        let solve_start=Instant::now();
        let outcome=std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match backend {
            Backend::Numeric(sys)=>{
                let r=sys.solve(sk,SolveOpts { tol:1e-14,acceptance_tol:tolerance,..SolveOpts::default() });
                (r.success,r.message,r.iterations,false,r.max_residual)
            },
            Backend::Replay(plan)=>{
                let r=plan.solve(sk,tolerance,true,Method::DogLeg);
                let status=if let Some(ref n)=r.numeric { format!("plan fallback: {}",n.message) } else { "plan replay".into() };
                let its=r.numeric.as_ref().map_or(0,|n|n.iterations);
                (r.success,status,its,r.fell_back,r.max_residual)
            },
        }));
        let (reported_success,status,iterations,fell_back,native_residual,adapter_error)=match outcome {
            Ok((ok,status,it,fb,res))=>(ok,status,it,fb,res,None),
            Err(payload)=>{
                let message=payload.downcast_ref::<String>().cloned()
                    .or_else(||payload.downcast_ref::<&str>().map(|x|x.to_string()))
                    .unwrap_or_else(||"upstream solver panicked".into());
                (false,format!("adapter error: {message}"),0,false,f64::NAN,Some(message))
            },
        };
        let solve_ns=solve_start.elapsed().as_nanos() as i64;
        let coords=coordinates(sk);
        let (active,equations)=backend.sizes();
        let elapsed_ns=begin.elapsed().as_nanos() as i64;
        // Physical validation, state acceptance/rollback, and JSON are outside timing.
        let (physically_valid,physical_error,branch_ok)=acceptance(&f,&coords,values,tolerance);
        let accepted=physically_valid && adapter_error.is_none();
        if accepted { seed=coords.clone(); accepted_values=values.clone(); } else {
            restore(sk,&seed); update(sk,&f,&accepted_values); sk.branches=prior_branches;
            if let (Backend::Replay(p),Some(branches))=(&mut *backend,prior_plan_branches) {
                p.plan.apply_branches(&branches);
            }
            backend.refresh(sk);
        }
        let panicked=adapter_error.is_some();
        let row=object([
            ("schema_version",1.into()),("engine",engine.into()),("mode",mode.into()),
            ("fixture_id",f.id.clone().into()),("index",((round as i64)-(warmups as i64)).into()),
            ("warmup",(round<warmups).into()),("build_ns",build_ns.into()),
            ("solve_ns",solve_ns.into()),("elapsed_ns",elapsed_ns.into()),
            ("coordinates",coords_json(&coords)),("reported_success",reported_success.into()),
            ("status",status.into()),("accepted",accepted.into()),("iterations",iterations.into()),
            ("model_reused",reused.into()),("active_coordinates",active.into()),("equations",equations.into()),
            ("plan_fell_back",fell_back.into()),("native_residual",finite(native_residual)),
            ("physical_max_error",finite(physical_error)),("orientation_ok",branch_ok.into()),
            ("upstream_revision",REVISION.into()),("native_iteration_tolerance",1e-14.into()),
            ("native_acceptance_tolerance",(if replay {1e-6} else {tolerance}).into()),
            ("replay_fallback_trigger_tolerance",Json::from(if replay {Some(tolerance)} else {None})),
            ("adapter_error",Json::from(adapter_error)),
        ]);
        writeln!(out,"{}",row.dump(None)).map_err(|e|e.to_string())?;
        out.flush().map_err(|e|e.to_string())?;
        if panicked {session=None;}
    }
    Ok(())
}
fn main() {
    if let Err(e)=run() { eprintln!("solvent-adapter: {e}"); std::process::exit(2); }
}
