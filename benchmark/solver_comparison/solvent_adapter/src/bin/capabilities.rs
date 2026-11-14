//! Executable feature probes. These are semantic observations, not timings.
use gcs_solve::cgraph::El;
use gcs_solve::constraints::{CKind, Constraint};
use gcs_solve::decompose::PlanSolver;
use gcs_solve::diagnose::{diagnose, DiagnoseOptions};
use gcs_solve::homotopy::{enumerate_step, EnumerateOptions};
use gcs_solve::json::{object, parse, Json};
use gcs_solve::model::{EntRef, Sketch};
use gcs_solve::newton::Method;
use gcs_solve::solve::{Drag, SolveOpts};
use gcs_solve::system::System;

fn triangle() -> Sketch {
    let mut s=Sketch::new();
    s.point(0.0,0.0,true,"a"); s.point(10.0,0.0,true,"b"); s.point(5.0,4.0,false,"c");
    s.add(Constraint::distance(EntRef::point(0),EntRef::point(2),6.0));
    s.add(Constraint::distance(EntRef::point(1),EntRef::point(2),6.0));
    s
}
fn distance(s:&Sketch,a:usize,b:usize)->f64 {
    let (ax,ay)=s.point_xy(a); let (bx,by)=s.point_xy(b); (ax-bx).hypot(ay-by)
}
fn point(s:&Sketch,i:usize)->Json {let (x,y)=s.point_xy(i);Json::from(vec![x,y])}
fn branch_probe()->Json {
    let mut sk=triangle();
    let mut ps=PlanSolver::new(&sk,true);
    let initial=ps.solve(&mut sk,1e-10,true,Method::DogLeg);
    let complete=ps.plan.fully_decomposed();
    let steps=ps.plan.steps.len();
    let el=El::p(ps.plan.graph.point_of[2]);
    let alternatives=if steps>0 {enumerate_step(&mut ps.plan,&mut sk,steps-1,EnumerateOptions {locate:Some(el),..Default::default()}).len()} else {0};
    let flipped=ps.flip(&mut sk,el);
    let result=ps.solve(&mut sk,1e-10,true,Method::DogLeg);
    let mut saved=Json::obj();
    for (k,&v) in &sk.branches {saved.set(k,v.into());}
    // A no-language host persists the actual branch map, then rebuilds entities with stable ids.
    let bytes=saved.dump(None); let restored=parse(&bytes).expect("valid branch JSON");
    let mut sk2=triangle();
    if let Json::Obj(items)=restored {for (k,v) in items {sk2.branches.insert(k,v.as_i64() as i32);}}
    let same_keys=sk.branches==sk2.branches;
    let mut ps2=PlanSolver::new(&sk2,true);
    let replay=ps2.solve(&mut sk2,1e-10,true,Method::DogLeg);
    let err=(distance(&sk2,0,2)-6.0).abs().max((distance(&sk2,1,2)-6.0).abs());
    let pass=initial.success && result.success && replay.success && flipped>0 && same_keys && sk2.point_xy(2).1<0.0 && err<1e-7;
    object([("probe","decomposition_branch_roundtrip".into()),("passed",pass.into()),
        ("fully_decomposed",complete.into()),("plan_steps",steps.into()),
        ("initial_fallback",initial.fell_back.into()),("flip_count",flipped.into()),
        ("homotopy_alternatives",alternatives.into()),("persisted_branch_count",sk.branches.len().into()),
        ("branch_keys_identical",same_keys.into()),("replay_fallback",replay.fell_back.into()),
        ("restored_point",point(&sk2,2)),("physical_max_error",err.into()),
        ("roundtrip_scope","branch map in JSON plus language-free entity rebuild".into())])
}
fn spline_probe()->Json {
    let mut sk=Sketch::new();
    let ctrl:Vec<usize>=[(0.0,0.0),(1.0,2.0),(2.0,2.0),(3.0,0.0)].iter().map(|&(x,y)|sk.point(x,y,true,"")).collect();
    let curve=sk.spline(&ctrl).expect("cubic spline");
    let p=sk.point(1.7,1.2,false,"contact");
    let anchor=sk.point(1.5,0.0,true,"x_anchor");
    sk.add(Constraint::point_on_spline(&sk,EntRef::point(p),EntRef::spline(curve)));
    let line=sk.line(anchor,p);sk.add(Constraint::one_line(CKind::Vertical,EntRef::line(line)));
    let mut sys=System::new(&sk);
    let r=sys.solve(&mut sk,SolveOpts{acceptance_tol:1e-10,..Default::default()});
    let (x,y)=sk.point_xy(p);let err=(x-1.5).hypot(y-1.5);
    object([("probe","cubic_spline_contact".into()),("passed",(r.success&&err<1e-7).into()),
        ("reported_success",r.success.into()),("point",point(&sk,p)),
        ("expected_point",Json::from(vec![1.5,1.5])),("physical_max_error",err.into()),
        ("active_coordinates",sys.n_free.into()),("equations",sys.n_res.into())])
}
fn held_drag_probe()->Json {
    let mut sk=triangle();let mut sys=System::new(&sk);sys.solve(&mut sk,Default::default());
    let (x,y)=sk.point_xy(2);let mut drag=Drag::new(&mut sk,2,x,y,Method::DogLeg,1.0,vec![(0,1,2)],0.05);
    let mut max_error=0.0_f64;let mut max_move=0.0_f64;let mut native_ok=true;
    for i in 0..32 {let t=std::f64::consts::TAU*i as f64/32.0;
        let r=drag.move_to(&mut sk,x+2.0*t.cos(),y+1.5*t.sin());native_ok&=r.success;
        max_error=max_error.max((distance(&sk,0,2)-6.0).abs()).max((distance(&sk,1,2)-6.0).abs());
        let (px,py)=sk.point_xy(2);max_move=max_move.max((px-x).hypot(py-y));
    }
    let flips=drag.flips.len();drag.end(&mut sk);
    object([("probe","fully_constrained_drag".into()),("passed",(native_ok&&max_error<1e-7&&max_move<1e-7&&flips==0).into()),
        ("frames",32.into()),("all_reported_success",native_ok.into()),("physical_max_error",max_error.into()),
        ("max_point_displacement",max_move.into()),("orientation_flips",flips.into())])
}
fn crossing_probe()->Json {
    let mut sk=Sketch::new();sk.point(0.0,0.0,true,"a");sk.point(10.0,0.0,true,"b");sk.point(5.0,11.0_f64.sqrt(),false,"c");
    sk.add(Constraint::distance(EntRef::point(0),EntRef::point(2),6.0));
    let (x,y)=sk.point_xy(2);let mut d=Drag::new(&mut sk,2,x,y,Method::DogLeg,1.0,vec![(0,1,2)],0.05);
    let mut err=0.0_f64;let mut successes=0;let mut messages=Vec::new();
    for i in 0..9 {let r=d.move_to(&mut sk,5.0,4.0-i as f64);successes+=usize::from(r.success);
        err=err.max((distance(&sk,0,2)-6.0).abs());if r.message.contains("flip"){messages.push(r.message);}}
    let flips=d.flips.len();d.end(&mut sk);let below=sk.point_xy(2).1<0.0;
    object([("probe","guarded_drag_unavoidable_crossing".into()),
        ("passed",(err<1e-7&&below&&flips>0&&!messages.is_empty()).into()),
        ("frames",9.into()),("reported_successes",successes.into()),("physical_max_error",err.into()),
        ("positive_branch_preserved",(!below).into()),("orientation_flips",flips.into()),
        ("flip_messages",Json::from(messages)),("final_point",point(&sk,2)),
        ("interpretation","Unavoidable orientation crossing is accepted and flagged by the raw drag API".into())])
}
fn diagnostics_probe()->Json {
    let mut sk=triangle();let mut sys=System::new(&sk);sys.solve(&mut sk,Default::default());
    let d=diagnose(&mut sk,DiagnoseOptions{solid_claims:false,..Default::default()});
    sk.add(Constraint::distance(EntRef::point(0),EntRef::point(2),6.0));
    let redundant=diagnose(&mut sk,DiagnoseOptions{solid_claims:false,..Default::default()});
    sk.add(Constraint::distance(EntRef::point(0),EntRef::point(2),7.0));
    let mut sys=System::new(&sk);let bad=sys.solve(&mut sk,Default::default());
    let conflicting=diagnose(&mut sk,DiagnoseOptions{solid_claims:false,..Default::default()});
    let conflict_count=conflicting.conflicts.as_ref().map_or(0,Vec::len);
    object([("probe","redundancy_and_conflict_diagnosis".into()),
        ("passed",(d.dof==0&&conflict_count>0&&!bad.success).into()),
        ("base_dof",d.dof.into()),("base_numeric_rank",Json::from(d.numeric_rank)),
        ("redundant_status",redundant.status.as_str().into()),("redundant_over_count",redundant.over.len().into()),
        ("conflicting_status",conflicting.status.as_str().into()),("conflict_set_count",conflict_count.into()),
        ("conflict_solve_reported_success",bad.success.into())])
}
fn main() {
    let mut all_pass=true;
    for probe in [branch_probe as fn()->Json,spline_probe,held_drag_probe,crossing_probe,diagnostics_probe] {
        let row=std::panic::catch_unwind(probe).unwrap_or_else(|_|object([("probe","panic".into()),("passed",false.into())]));
        all_pass &= row.get("passed").map(Json::as_bool).unwrap_or(false);
        println!("{}",row.dump(None));
    }
    if !all_pass {std::process::exit(1);}
}
