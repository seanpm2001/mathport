/-
Copyright (c) 2021 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Daniel Selsam

Based off <lean4>/src/Lean/Meta/Coe.lean
-/
import Lean
import Mathport.Bridge.Rename

namespace Mathport.Binary

open Lean Lean.Meta
open Mathport.Rename (resolveIdent?)

structure CoeInfo where
  instPos      : Nat
  indName      : Name
  projPos      : Nat

def isCoeApp? (env : Environment) (e : Expr) : Option CoeInfo := do
  let nArgs := e.getAppNumArgs

  match resolveIdent? env `coe with
  | some coe => if e.isAppOf coe && nArgs ≥ 3 then return some ⟨2, `HasLiftT, 0⟩
  | _ => pure ()

  match resolveIdent? env `coe_sort with
  | some coeSort => if e.isAppOf coeSort && nArgs ≥ 2 then return some ⟨1, `HasCoeToSort, 1⟩
  | _ => pure ()

  match resolveIdent? env `coe_fn with
  | some coeFn => if e.isAppOf coeFn && nArgs ≥ 2 then return some ⟨1, `HasCoeToFun, 1⟩
  | _ => pure ()

  return none

/-
This gem appears as a subterm in `int.mul_pos:
@(λ [_inst_1 : has_lift_t.{1 1} nat int] (ᾰ ᾰ_1 : nat)
                                          (e_2 : @eq.{1} nat ᾰ ᾰ_1),
                                            @congr_arg.{1 1} nat int ᾰ ᾰ_1 (@coe.{1 1} nat int _inst_1) e_2)
    (@coe_to_lift.{1 1} nat int (@coe_base.{1 1} nat int int.has_coe))
-/
partial def betaReduceCoesLifts (e : Expr) (declName : Name) : MetaM Expr := do
  Meta.transform e (post := core)
where
  core e := do
    let f := e.getAppFn
    let args := e.getAppArgs
    match f with
    | Expr.lam _ d b .. =>
      -- TODO: fun/sort? Not sure if it comes up.
      if (d.isAppOfArity `HasLiftT 2 || d.isAppOfArity `HasLift 2 || d.isAppOfArity `HasCoe 2 || d.isAppOfArity `HasCoeT 2) && args.size ≥ 1 then
        let e' := e.headBeta
        return TransformStep.visit e'
    | _ => pure ()
    return TransformStep.done e

partial def expandCoes (e : Expr) (declName : Name) : MetaM Expr := do
  let e ← betaReduceCoesLifts e declName
  withReducibleAndInstances do
    try
      withTransparency TransparencyMode.all do
        withCurrHeartbeats <| withTheReader Core.Context (fun ctx => { ctx with maxHeartbeats := 15000000 }) $
          Meta.transform e (post := step (shouldReduce := True))
    catch _ =>
      println! "[expand.coe] {declName} failed REDUCE-ALL"
      withCurrHeartbeats <| withTheReader Core.Context (fun ctx => { ctx with maxHeartbeats := 15000000 }) $
        Meta.transform e (post := step (shouldReduce := True))
    catch _ =>
      println! "[expand.coe] {declName} failed REDUCE-INSTANCES"
      withCurrHeartbeats <| withTheReader Core.Context (fun ctx => { ctx with maxHeartbeats := 15000000 }) $
        Meta.transform e (post := step (shouldReduce := False))
    catch _ =>
      println! "[expand.coe] {declName} failed WHNF"
      pure e
where
  step (e : Expr) (shouldReduce : Bool) : MetaM TransformStep := do
    match isCoeApp? (← getEnv) e with
    | none => TransformStep.done e
    | some ⟨instPos, indName, projPos⟩ => do
      let args := e.getAppArgs
      let fn := mkProj indName projPos args[instPos]
      -- TODO: reset heartbeats here?
      -- Note: if we only WHNF, we still end up with instances, e.g. `SetLike.toHasCoeToFun`
      let newFn ← if shouldReduce then reduce fn else whnf fn

      let mut newArgs := #[]
      for i in [instPos+1:args.size] do newArgs := newArgs.push args[i]
      let e' := (mkAppN newFn newArgs).headBeta
      -- Note: the reduction may have exposed more coeFns!
      TransformStep.visit e'

-- We need to traverse `type` and `val` simultaneously because we are
-- moving information from the val to the type.
partial def translateCoes (declName3 : Name) (type val : Expr) : MetaM (Option (Expr × Expr)) := do
  lambdaLetTelescope val fun xs b => do
    if ← xs.anyM (fun x => do let xType ← inferType x
                              xType.isAppOfArity `HasCoe 2 || xType.isAppOfArity `HasCoeT 2
                              || xType.isAppOfArity `HasCoeToFun 1 || xType.isAppOfArity `HasCoeToSort 1) then
       -- Only translate normal instances
       return none
    b.withApp fun f args => do
      if (f.isConstOf `HasCoe.mk || f.isConstOf `HasCoeT.mk) && args.size == 3 then
        let t' := mkAppN (mkConst `Coe f.constLevels!) args[:2]
        let b' := mkAppN (mkConst `Coe.mk f.constLevels!) args
        return some (← mkForallFVars xs t', ← mkLambdaFVars xs b')
      else if f.isConstOf `HasCoeToFun.mk && args.size == 3 then
        let t' := mkAppN (mkConst `CoeFun f.constLevels!) args[:2]
        let b' := mkAppN (mkConst `CoeFun.mk f.constLevels!) args
        return some (← mkForallFVars xs t', ← mkLambdaFVars xs b')
      else if f.isConstOf `HasCoeToSort.mk && args.size == 3 then
        let t' := mkAppN (mkConst `CoeSort f.constLevels!) args[:2]
        let b' := mkAppN (mkConst `CoeSort.mk f.constLevels!) args
        return some (← mkForallFVars xs t', ← mkLambdaFVars xs b')
      return none


end Mathport.Binary