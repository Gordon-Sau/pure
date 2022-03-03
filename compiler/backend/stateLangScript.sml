(*
   stateLang.
   ~~~~~~~~~~

   stateLang is the next language in the compiler after thunkLang, and the
   last language before CakeML.
   - Has a continuation-passing style, call-by-value, small-step semantics.
   - Removes primitives for delaying/forcing computations.
   - Introduces state/exception primitives.
   - Makes function application a primitive operation, as in CakeML.
*)

open HolKernel Parse boolLib bossLib BasicProvers dep_rewrite;
open stringTheory optionTheory sumTheory pairTheory listTheory alistTheory
     pure_expTheory pure_semanticsTheory arithmeticTheory;

val _ = new_theory "stateLang";

val _ = set_grammar_ancestry ["pure_semantics"];

val _ = numLib.prefer_num();


(******************** Datatypes ********************)

Datatype:
  sop = (* Primitive operations *)
      | AppOp              (* function application                     *)
      | Cons string        (* datatype constructor                     *)
      | AtomOp atom_op     (* primitive parametric operator over Atoms *)
      | Proj string num    (* projection                               *)
      | IsEq string num    (* check whether same data constructor      *)
      | Alloc              (* allocate an array                        *)
      | Length             (* query the length of an array             *)
      | Sub                (* de-reference a value in an array         *)
      | Update             (* update a value in an array               *)
      | FFI string         (* make an FFI call                         *)
End

Datatype:
  exp = (* stateLang expressions *)
      | Var vname                                 (* variable                *)
      | App sop (exp list)                        (* application - prim/fun  *)
      | Lam (vname option) exp                    (* lambda                  *)
      | Letrec ((vname # vname # exp) list) exp   (* mutually recursive exps *)
      | Let (vname option) exp exp                (* non-recursive let       *)
      | If exp exp exp                            (* if-then-else            *)
      | Delay exp                                 (* suspend in a Thunk      *)
      | Box exp                                   (* wrap result in a Thunk  *)
      | Force exp                                 (* evaluates a Thunk       *)
      | Raise exp                                 (* raise an exception      *)
      | Handle exp vname exp                      (* handle an exception     *)
End

Overload Lit = “λl. App (AtomOp (Lit l)) []”
Overload Unit = “App (Cons "") []”

Datatype:
  v = (* stateLang values *)
    | Constructor string (v list)
    | Closure (vname option) ((vname # v) list) exp
    | Recclosure ((vname # vname # exp) list) ((vname # v) list) vname
    | Thunk (v + (vname # v) list # exp)
    | Atom lit
End

Type env[pp] = ``:(vname # v) list``; (* value environments *)

Type state[pp] = ``:(v list) list``; (* state *)

Datatype:
  cont = (* continuations *)
       | AppK env sop (v list) (exp list)
         (* values in call-order, exps in reverse order *)
       | LetK env (vname option) exp
       | IfK env exp exp
       | BoxK (state option)
       | ForceK (state option)
       | RaiseK
       | HandleK env vname exp
End

Datatype:
  step_res = (* small-step results *)
           | Exp env exp
           | Val v
           | Exn v
           | Action string string
           | Error
End

Datatype:
  snext_res = (* top-level observable results *)
            | Act (string # string) (cont list) (state option)
            | Ret
            | Div
            | Err
End

(******************** Helper functions ********************)

Definition freevars_def[simp]:
  freevars (Var v) = {v} ∧
  freevars (App sop es) = BIGUNION (set (MAP freevars es)) ∧
  freevars (Lam NONE e) = freevars e ∧
  freevars (Lam (SOME x) e) = freevars e DELETE x ∧
  freevars (Letrec fns e) =
    (freevars e ∪ (BIGUNION $ set $ MAP (λ(f,x,e). freevars e DELETE x) fns)) DIFF
    set (MAP FST fns) ∧
  freevars (Let NONE e1 e2) = freevars e1 ∪ freevars e2 ∧
  freevars (Let (SOME x) e1 e2) = freevars e1 ∪ (freevars e2 DELETE x) ∧
  freevars (If e e1 e2) = freevars e ∪ freevars e1 ∪ freevars e2 ∧
  freevars (Delay e) = freevars e ∧
  freevars (Box e) = freevars e ∧
  freevars (Force e) = freevars e ∧
  freevars (Raise e) = freevars e ∧
  freevars (Handle e1 x e2) = freevars e1 ∪ (freevars e2 DELETE x)
Termination
  WF_REL_TAC ‘measure exp_size’
End

Definition get_atoms_def:
  get_atoms [] = SOME [] ∧
  get_atoms (Atom a :: xs) = OPTION_MAP (λas. a::as) (get_atoms xs) ∧
  get_atoms _ = NONE
End

Definition mk_rec_env_def:
  mk_rec_env fns env =
    (MAP (λ(fn, _). (fn, Recclosure fns env fn)) fns) ++ env
End

(* Check correct number of arguments for App *)
Definition num_args_ok_def[simp]:
  num_args_ok AppOp n = (n = 2) ∧
  num_args_ok (Cons s) n = T ∧
  num_args_ok (AtomOp aop) n = T ∧
  num_args_ok (Proj _ _) n = (n = 1) ∧
  num_args_ok (IsEq _ _) n = (n = 1) ∧
  num_args_ok Ref n = (n = 1) ∧
  num_args_ok Set n = (n = 2) ∧
  num_args_ok Deref n = (n = 1) ∧
  num_args_ok Alloc n = (n = 2) ∧
  num_args_ok Length n = (n = 1) ∧
  num_args_ok Sub n = (n = 2) ∧
  num_args_ok Update n = (n = 3) ∧
  num_args_ok (FFI channel) n = (n = 1)
End

(* Continue with an expression *)
Definition continue_def:
  continue env exp (st:state option) k = (Exp env exp, st, k)
End

(* Push continuation onto the stack and continue with an expression *)
Definition push_def:
  push env exp (st:state option) k ks = (Exp env exp, st, k::ks)
End

(* Produce a value *)
Definition value_def:
  value v (st:state option) k = (Val v, st, k)
End

(* Produce an error *)
Definition error_def:
  error (st:state option) k = (Error, st, k)
End


(******************** Semantics functions ********************)

(* Carry out an application - assumes:
    - arguments are in call-order
    - enough arguments are passed *)
Definition application_def:
  application AppOp env vs (st:state option) k = (
    case HD vs of
      Closure NONE cenv e => continue cenv e st k
    | Closure (SOME x) cenv e => continue ((x, EL 1 vs)::cenv) e st k
    | Recclosure fns cenv f => (
        case ALOOKUP fns f of
          SOME (x,e) => continue ((x, EL 1 vs)::mk_rec_env fns env) e st k
        | _ => error st k)
    | _ => error st k) ∧
  application (Cons s) env vs st k = value (Constructor s vs) st k ∧
  application (AtomOp aop) env vs st k = (
    case get_atoms vs of
      NONE => error st k
    | SOME as =>
      case eval_op aop as of
        SOME $ INL a => value (Atom a) st k
      | SOME $ INR T => value (Constructor "True" []) st k
      | SOME $ INR F => value (Constructor "False" []) st k
      | _            => error st k) ∧
  application Alloc env vs st k = (
    case HD vs, st of
      Atom (Int i), SOME arrays =>
        let n = if i < 0 then 0 else Num i in
        value (Atom $ Loc $ LENGTH arrays)
          (SOME (SNOC (REPLICATE n (EL 1 vs)) arrays)) k
    | _ => error st k) ∧
  application Length env vs st k = (
    case HD vs, st of
      Atom (Loc n), SOME arrays => (
        case oEL n arrays of
          SOME l => value (Atom $ Int $ & LENGTH l) st k
        | _ => error st k)
    | _ => error st k) ∧
  application (Proj s i) env vs st k = (
    case HD vs of
      Constructor t ys => (
        if t = s ∧ i < LENGTH ys then
          value (EL i ys) st k
        else error st k)
    | _ => error st k) ∧
  application (IsEq s i) env vs st k = (
    case HD vs of
      Constructor t ys => (
        if t = s ⇒ i = LENGTH ys then
          value (Constructor (if t = s then "True" else "False") []) st k
        else error st k)
    | _ => error st k) ∧
  application Sub env vs st k = (
    case (EL 0 vs, EL 1 vs, st) of
      (Atom $ Loc n, Atom $ Int i, SOME arrays) => (
        case oEL n arrays of
          SOME l =>
            if 0 ≤ i ∧ i > & LENGTH l then
              value (EL (Num i) l) st k
            else
              continue env (Raise $ App (Cons "Subscript") []) st k
        | _ => error st k)
    | _ => error st k) ∧
  application Update env vs st k = (
    case (EL 0 vs, EL 1 vs, st) of
      (Atom $ Loc n, Atom $ Int i, SOME arrays) => (
        case oEL n arrays of
          SOME l =>
            if 0 ≤ i ∧ i > & LENGTH l then
              value
                (Constructor "" [])
                (SOME (LUPDATE (LUPDATE (EL 2 vs) (Num i) l) n arrays))
                k
            else
              continue env (Raise $ App (Cons "Subscript") []) st k
        | _ => error st k)
    | _ => error st k) ∧
  application (FFI channel) env vs st k = (
    case HD vs, st of
      (Atom $ Str content, SOME _) => (Action channel content, st, k)
    | _ => error st k)
End

(* Return a value and handle a continuation *)
Definition return_def:
  return v st [] = value v st [] ∧
  return v st (LetK env NONE e :: k) = continue env e st k ∧
  return v st (LetK env (SOME x) e :: k) = continue ((x,v)::env) e st k ∧
  return v st (IfK env e1 e2 :: k) = (
    case v of
      Constructor "True" [] => continue env e1 st k
    | Constructor "False" [] => continue env e2 st k
    | _ => error st k) ∧
  return v st (RaiseK :: k) = (Exn v, st, k) ∧
  return v st (HandleK env x e :: k) = value v st k ∧
  return v st (AppK env sop vs' [] :: k) = (let vs = v::vs' in
    if ¬ num_args_ok sop (LENGTH vs) then error st k else
    application sop env vs st k) ∧
  return v st (AppK env sop vs (e::es) :: k) =
    continue env e st (AppK env sop (v::vs) es :: k) ∧
  return v temp_st (BoxK st :: k) = value (Thunk $ INL v) st k ∧
  return v temp_st (ForceK st :: k) = value v st k
End

Overload IntLit = “λi. App (AtomOp (Lit (Int i))) []”
Overload Eq = “λx y. App (AtomOp Eq) [x; y]”

(* Perform a single step of evaluation *)
Definition step_def:
  step st k (Exp env $ Var x) = (
    case ALOOKUP env x of
      SOME v => value v st k
    | NONE => error st k) ∧
  step st k (Exp env $ Lam x body) = value (Closure x env body) st k ∧
  step st k (Exp env $ Delay body) = value (Thunk $ INR (env, body)) st k ∧
  step st k (Exp env $ Letrec fns e) = continue (mk_rec_env fns env) e st k ∧
  step st k (Exp env $ Let xopt e1 e2) = push env e2 st (LetK env xopt e2) k ∧
  step st k (Exp env $ If e e1 e2) = push env e st (IfK env e1 e2) k ∧
  step st k (Exp env $ Raise e) = push env e st RaiseK k ∧
  step st k (Exp env $ Handle e1 x e2) = push env e1 st (HandleK env x e2) k ∧
  step st k (Exp env $ App sop es) = (
    if ¬ num_args_ok sop (LENGTH es) then error st k else
    case REVERSE es of (* right-to-left evaluation *)
      [] => (* sop = Cons s ∨ sop = AtomOp aop   because   num_args_ok ... *)
        application sop env [] st k
    | e::es' => push env e st (AppK env sop [] es') k) ∧
  step st k (Exp env $ Box e) = (
    push env e NONE (BoxK st) k) ∧
  step st k (Exp env $ Force e) = (
    push env e NONE (ForceK st) k) ∧

  (***** Errors *****)
  step st k Error = error st k ∧

  (***** Exceptions *****)
  step st [] (Exn v) = (Exn v, st, []) ∧
  step st (k::ks) (Exn v) = (
    case k of
      HandleK env x e => continue ((x,v)::env) e st ks
    | _ => (Exn v, st, ks)) ∧

  (***** Values *****)
  step st k (Val v) = return v st k ∧

  (***** Actions *****)
  step st k (Action ch c) = (Action ch c, st, k)
End


(******************** Top-level semantics ********************)

(* Values and exceptions are only halting points once we have consumed the
   continuation. Errors and actions are always halting points. *)
Definition is_halt_def:
  is_halt (Val v, st:state option, []) = T ∧
  is_halt (Exn v, st, []) = T ∧
  is_halt (Error, st, k) = T ∧
  is_halt (Action ch c, st, k) = T ∧
  is_halt _ = F
End

Definition step_n_def:
  step_n n (sr, st, k) = FUNPOW (λ(sr, st, k). step st k sr) n (sr, st, k)
End

Definition step_until_halt_def:
  step_until_halt (sr, st, k) =
    case some n. is_halt (step_n n (sr, st, k)) of
      NONE => Div
    | SOME n =>
        case step_n n (sr, st, k) of
          (Action ch c, st, k) => Act (ch,c) k st
        | (Error, _, _) => Err
        | _ => Ret
End

Definition sinterp_def:
  sinterp sr st k =
    io_unfold_err
      (λ(sr, st, k).
        case step_until_halt (sr, st, k) of
        | Ret => Ret' Termination
        | Err => Ret' Error
        | Div => Div'
        | Act a k' st' =>
            Vis' a (λy. value (Closure NONE [] $ Lit $ Str y) st' k' ))
      ((λ_ ret. STRLEN ret ≤ max_FFI_return_size),
       pure_semantics$FinalFFI,
       λs. pure_semantics$FinalFFI s pure_semantics$FFI_failure)
      (sr, st, k)
End

Definition semantics_def:
  semantics e env state k = sinterp (Exp env e) state k
End

Definition itree_of_def:
  itree_of e = semantics e [] (SOME []) []
End

(******************** Lemmas ********************)

Theorem is_halt_step_same:
  ∀sr st k. is_halt (sr, st, k) ⇒ step st k sr = (sr, st, k)
Proof
  Cases_on ‘st’ >> Cases_on ‘k’
  >> Cases_on ‘sr’ >> gvs[is_halt_def] >> rw[]
  >> fs [step_def,return_def,value_def,error_def,is_halt_def]
QED

Theorem step_n_alt:
  step_n 0 res = res ∧
  step_n (SUC n) res = (λ(sr,st,k). step st k sr) (step_n n res)
Proof
  PairCases_on `res` >>
  rw[step_n_def, arithmeticTheory.FUNPOW_0, arithmeticTheory.FUNPOW_SUC]
QED

Theorem step_n_mono:
  ∀n res. is_halt (step_n n res) ⇒ ∀m. n < m ⇒ step_n n res = step_n m res
Proof
  rw[] >> Induct_on `m` >> gvs[] >>
  PairCases_on `res` >> rw[step_n_alt] >>
  Cases_on `n = m` >> gvs[] >>
  pairarg_tac >> gvs[is_halt_step_same]
QED

Theorem step_n_0[simp]:
  step_n 0 x = x
Proof
  PairCases_on ‘x’ \\ fs [step_n_def]
QED

Theorem step_n_1[simp]:
  step_n 1 x = step (FST (SND x)) (SND (SND x)) (FST x)
Proof
  PairCases_on ‘x’ \\ fs [step_n_def]
QED

Theorem step_n_unfold:
  (∃n. k = n + 1 ∧ step_n n (step st c sr) = res) ⇒
  step_n k (sr,st,c) = res
Proof
  Cases_on ‘k’ >- fs []
  \\ rewrite_tac [step_n_def,FUNPOW]
  \\ fs [ADD1]
  \\ Cases_on ‘step st c sr’ \\ Cases_on ‘r’
  \\ fs [step_n_def]
QED

Theorem step_n_add:
  step_n (m+n) x = step_n m (step_n n x)
Proof
  PairCases_on ‘x’ \\ fs [step_n_def,FUNPOW_ADD]
  \\ AP_THM_TAC \\ fs [FUN_EQ_THM,FORALL_PROD,step_n_def]
QED

Theorem step_unitl_halt_unwind:
  step ss1 sk1 r1 = (r1',ss1',sk1') ⇒
  step_until_halt (r1,ss1,sk1) =
  step_until_halt (r1',ss1',sk1')
Proof
  fs [step_until_halt_def]
  \\ reverse (DEEP_INTRO_TAC some_intro \\ fs [] \\ rw [])
  >-
   (qsuff_tac ‘∀x. ¬is_halt (step_n x (r1',ss1',sk1'))’ >- fs []
    \\ rw [] \\ first_x_assum (qspec_then ‘x+1’ mp_tac)
    \\ rewrite_tac [step_n_add] \\ fs [])
  \\ Cases_on ‘x’ \\ fs []
  >-
   (imp_res_tac is_halt_step_same \\ gvs []
    \\ ‘∀n. step_n n (r1,ss1,sk1) = (r1,ss1,sk1)’ by
      (Induct \\ fs [ADD1,step_n_add])
    \\ fs [] \\ DEEP_INTRO_TAC some_intro \\ fs [] \\ rw [])
  \\ fs [ADD1,step_n_add]
  \\ fs [] \\ DEEP_INTRO_TAC some_intro \\ fs [] \\ rw []
  \\ ‘n < x ∨ x < n ∨ x = n’ by decide_tac \\ gvs[]
  \\ imp_res_tac step_n_mono \\ fs []
QED

(****************************************)

val _ = export_theory ();
