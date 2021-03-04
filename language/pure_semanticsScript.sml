
open HolKernel Parse boolLib bossLib term_tactic;
open arithmeticTheory listTheory stringTheory alistTheory optionTheory
     ltreeTheory llistTheory pure_evalTheory io_treeTheory;

val _ = new_theory "pure_semantics";

(*

TODO:
 - add Alloc[len,init], Update[loc,i,v], Deref[loc,i], Length[loc]

*)


(* definitions *)

Datatype:
  result = SilentDivergence
         | Termination
         | Error
End

Datatype:
  cont = Done        (* nothing left to do *)
       | BC exp cont (* RHS of Bind, rest *)
       | HC exp cont (* RHS of Handle, rest *)
End

Datatype:
  next_res = Act 'e cont | Ret | Div | Err
End

Definition with_atom_def:
  with_atom e f =
    case eval_wh e of
    | wh_Diverge => Div
    | wh_Atom a => f a
    | _ => Err
End

Definition get_atoms_def:
  get_atoms [] = SOME [] ∧
  get_atoms (wh_Atom a :: xs) = OPTION_MAP (λas. a::as) (get_atoms xs) ∧
  get_atoms _ = NONE
End

Definition with_atoms_def:
  with_atoms es f =
    let vs = MAP eval_wh es in
      if MEM wh_Error vs then Err else
      if MEM wh_Diverge vs then Div else
        case get_atoms vs of
        | SOME as => f as
        | NONE => Err
End

Definition with_atom_def:
  with_atom es f = with_atoms es (λvs. f (HD vs))
End

Definition with_atom2_def:
  with_atom2 es f = with_atoms es (λvs. f (EL 0 vs) (EL 1 vs))
End

Definition next_def:
  next (k:num) v stack =
    case v of
    | wh_Constructor s es =>
       (if s = "Ret" ∧ LENGTH es = 1 then
          (case stack of
           | Done => Ret
           | BC f fs =>
              (if eval_wh f = wh_Diverge then Div else
                 case dest_wh_Closure (eval_wh f) of
                 | NONE => Err
                 | SOME (n,e) => if k = 0 then Div else
                                   next (k-1) (eval_wh (bind n (HD es) e)) fs)
           | HC f fs => if k = 0 then Div else next (k-1) v fs)
        else if s = "Raise" ∧ LENGTH es = 1 then
          (case stack of
           | Done => Ret
           | BC f fs => if k = 0 then Div else next (k-1) v fs
           | HC f fs =>
              (if eval_wh f = wh_Diverge then Div else
                 case dest_wh_Closure (eval_wh f) of
                 | NONE => Err
                 | SOME (n,e) => if k = 0 then Div else
                                   next (k-1) (eval_wh (bind n (HD es) e)) fs))
        else if s = "Act" ∧ LENGTH es = 1 then
          (with_atom es (λa.
             case a of
             | Msg channel content => Act (channel, content) stack
             | _ => Err))
        else if s = "Bind" ∧ LENGTH es = 2 then
          (let m = EL 0 es in
           let f = EL 1 es in
             if k = 0 then Div else next (k-1) (eval_wh m) (BC f stack))
        else if s = "Handle" ∧ LENGTH es = 2 then
          (let m = EL 0 es in
           let f = EL 1 es in
             if k = 0 then Div else next (k-1) (eval_wh m) (HC f stack))
        else Err)
    | wh_Diverge => Div
    | _ => Err
End

Definition next_action_def:
  next_action wh stack =
    case some k. next k wh stack ≠ Div of
    | NONE => Div
    | SOME k => next k wh stack
End

Definition interp'_def:
  interp' =
    io_unfold
      (λ(v,stack). case next_action v stack of
                   | Ret => Ret' Termination
                   | Err => Ret' Error
                   | Div => Ret' SilentDivergence
                   | Act a new_stack =>
                       Vis' a (λy. (wh_Constructor "Ret" [Lit (Str y)], new_stack)))
End

Definition interp:
  interp v stack = interp' (v, stack)
End

Theorem interp_def:
  interp wh stack =
    case next_action wh stack of
    | Ret => Ret Termination
    | Div => Ret SilentDivergence
    | Err => Ret Error
    | Act a new_stack =>
        Vis a (λy. interp (wh_Constructor "Ret" [Lit (Str y)]) new_stack)
Proof
  fs [Once interp,interp'_def]
  \\ once_rewrite_tac [io_unfold] \\ fs []
  \\ Cases_on ‘next_action wh stack’ \\ fs []
  \\ fs [combinTheory.o_DEF,FUN_EQ_THM] \\ rw []
  \\ once_rewrite_tac [EQ_SYM_EQ]
  \\ fs [interp,interp'_def]
  \\ simp [Once io_unfold] \\ fs []
QED

Definition semantics_def:
  semantics e binds = interp (eval_wh e) binds
End


(* basic lemmas *)

Theorem next_less_eq:
  ∀k1 x fs. next k1 x fs ≠ Div ⇒ ∀k2. k1 ≤ k2 ⇒ next k1 x fs = next k2 x fs
Proof
  ho_match_mp_tac next_ind \\ rw []
  \\ pop_assum mp_tac
  \\ pop_assum mp_tac
  \\ once_rewrite_tac [next_def]
  \\ Cases_on ‘x’ \\ fs []
  \\ Cases_on ‘s = "Bind"’ THEN1 (fs [] \\ rw [])
  \\ Cases_on ‘s = "Act"’ THEN1 (fs [] \\ rw [])
  \\ Cases_on ‘s = "Raise"’
  THEN1
   (fs [] \\ rw [] \\ Cases_on ‘fs’ \\ fs []
    \\ Cases_on ‘dest_wh_Closure (eval_wh e)’ \\ fs []
    \\ rw [] \\ fs [] \\ PairCases_on ‘x’ \\ gvs [] \\ rw [] \\ fs [])
  \\ Cases_on ‘s = "Ret"’
  THEN1
   (fs [] \\ rw [] \\ Cases_on ‘fs’ \\ fs []
    \\ Cases_on ‘dest_wh_Closure (eval_wh e)’ \\ fs []
    \\ rw [] \\ fs [] \\ PairCases_on ‘x’ \\ gvs [] \\ rw [] \\ fs [])
  \\ rw [] \\ fs []
QED

Theorem next_next:
  next k1 x fs ≠ Div ∧ next k2 x fs ≠ Div ⇒
  next k1 x fs = next k2 x fs
Proof
  metis_tac [LESS_EQ_CASES, next_less_eq]
QED

(* descriptive lemmas *)

Overload Ret = “λx. Cons "Ret" [x]”
Overload Raise = “λx. Cons "Raise" [x]”
Overload Act = “λx. Cons "Act" [x]”
Overload Bind = “λx y. Cons "Bind" [x;y]”
Overload Handle = “λx y. Cons "Handle" [x;y]”

Theorem semantics_Ret:
  semantics (Ret x) Done = Ret Termination
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ simp [Once interp_def]
  \\ fs [next_action_def]
  \\ simp [Once next_def]
  \\ simp [Once next_def]
  \\ DEEP_INTRO_TAC some_intro \\ fs []
QED

Theorem semantics_Raise:
  semantics (Raise x) Done = Ret Termination
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ simp [Once interp_def]
  \\ fs [next_action_def]
  \\ simp [Once next_def]
  \\ simp [Once next_def]
  \\ DEEP_INTRO_TAC some_intro \\ fs []
QED

Theorem semantics_Ret_HC:
  semantics (Ret x) (HC f fs) = semantics (Ret x) fs
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ once_rewrite_tac [interp_def]
  \\ ntac 4 AP_THM_TAC \\ AP_TERM_TAC
  \\ simp [Once next_action_def]
  \\ once_rewrite_tac [next_def] \\ fs []
  \\ simp [Once next_action_def]
  \\ DEEP_INTRO_TAC some_intro \\ fs []
  \\ DEEP_INTRO_TAC some_intro \\ fs []
  \\ rw [] \\ rw [] \\ fs []
  \\ imp_res_tac next_next
  \\ qexists_tac ‘x'+1’ \\ fs []
QED

Theorem semantics_Raise_BC:
  semantics (Raise x) (BC f fs) = semantics (Raise x) fs
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ once_rewrite_tac [interp_def]
  \\ ntac 4 AP_THM_TAC \\ AP_TERM_TAC
  \\ simp [Once next_action_def]
  \\ once_rewrite_tac [next_def] \\ fs []
  \\ simp [Once next_action_def]
  \\ DEEP_INTRO_TAC some_intro \\ fs []
  \\ DEEP_INTRO_TAC some_intro \\ fs []
  \\ rw [] \\ rw [] \\ fs []
  \\ imp_res_tac next_next
  \\ qexists_tac ‘x'+1’ \\ fs []
QED

Theorem semantics_Ret_BC:
  semantics (Ret x) (BC f fs) = semantics (App f x) fs
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ once_rewrite_tac [interp_def]
  \\ rpt AP_THM_TAC \\ rpt AP_TERM_TAC
  \\ fs [next_action_def]
  \\ CONV_TAC (RATOR_CONV (ONCE_REWRITE_CONV [next_def])) \\ fs []
  \\ Cases_on ‘eval_wh f = wh_Diverge’ \\ fs [eval_wh_thm]
  THEN1 (simp [Once next_def])
  \\ Cases_on ‘dest_wh_Closure (eval_wh f)’ \\ fs []
  THEN1
   (simp [Once next_def]
    \\ DEEP_INTRO_TAC some_intro \\ fs []
    \\ simp [Once next_def])
  \\ rename [‘_ = SOME xx’] \\ PairCases_on ‘xx’ \\ fs []
  \\ rpt (DEEP_INTRO_TAC some_intro \\ fs [])
  \\ reverse (rw [] \\ fs [AllCaseEqs()])
  THEN1 (qexists_tac ‘x'+1’ \\ fs [])
  \\ match_mp_tac next_next \\ gvs []
QED

Theorem semantics_Bottom:
  semantics Bottom xs = Ret SilentDivergence
Proof
  fs [semantics_def,eval_wh_thm]
  \\ simp [Once interp_def]
  \\ fs [next_action_def]
  \\ simp [Once next_def]
QED

Theorem semantics_Bind:
  semantics (Bind x f) fs = semantics x (BC f fs)
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ simp [Once interp_def]
  \\ qsuff_tac ‘next_action (wh_Constructor "Bind" [x; f]) fs =
                next_action (eval_wh x) (BC f fs)’
  THEN1 (rw [] \\ once_rewrite_tac [EQ_SYM_EQ] \\ simp [Once interp_def])
  \\ fs [next_action_def]
  \\ CONV_TAC (RATOR_CONV (ONCE_REWRITE_CONV [next_def])) \\ fs []
  \\ rpt (DEEP_INTRO_TAC some_intro \\ fs [])
  \\ rw [] \\ fs [AllCaseEqs()]
  THEN1 (match_mp_tac next_next \\ gvs [])
  \\ qexists_tac ‘x'+1’ \\ gvs []
QED

Theorem semantics_Handle:
  semantics (Handle x f) fs = semantics x (HC f fs)
Proof
  fs [semantics_def,eval_wh_Cons]
  \\ simp [Once interp_def]
  \\ qsuff_tac ‘next_action (wh_Constructor "Handle" [x; f]) fs =
                next_action (eval_wh x) (HC f fs)’
  THEN1 (rw [] \\ once_rewrite_tac [EQ_SYM_EQ] \\ simp [Once interp_def])
  \\ fs [next_action_def]
  \\ CONV_TAC (RATOR_CONV (ONCE_REWRITE_CONV [next_def])) \\ fs []
  \\ rpt (DEEP_INTRO_TAC some_intro \\ fs [])
  \\ rw [] \\ fs [AllCaseEqs()]
  THEN1 (match_mp_tac next_next \\ gvs [])
  \\ qexists_tac ‘x'+1’ \\ gvs []
QED

Theorem semantics_Act:
  eval_wh x = wh_Atom (Msg c s) ⇒
  semantics (Act x) fs = Vis (c,s) (λy. semantics (Ret (Lit (Str y))) fs)
Proof
  strip_tac
  \\ fs [semantics_def,eval_wh_Cons]
  \\ simp [Once interp_def]
  \\ fs [next_action_def]
  \\ simp [Once next_def,CaseEq"wh",with_atom_def,with_atoms_def,get_atoms_def]
  \\ DEEP_INTRO_TAC some_intro \\ fs []
  \\ simp [Once next_def,CaseEq"wh",with_atom_def,with_atoms_def,get_atoms_def]
QED

val _ = export_theory();
