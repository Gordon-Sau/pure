(*
   This file defines expressions for typeclass_lang as the type system sees them.
*)
open HolKernel Parse boolLib bossLib BasicProvers dep_rewrite;
open arithmeticTheory listTheory rich_listTheory alistTheory stringTheory
     optionTheory pairTheory pred_setTheory mlmapTheory;
open pure_cexpTheory;
open typeclass_typesTheory typeclass_kindCheckTheory;
val _ = new_theory "typeclass_texp";

(* We associate a poly-type to variable.
* This is needed for type elaboration.
* It can be provided by the user as well. *)
Type annot_cvname = ``:(cvname # (num # PredType) option)``;
Type class_constr = ``:(cvname # type)``;

Datatype:
  (* The first argument for each constructor is the type of the whole expression *)
  (* So the user can do something like ``show ((read x)::Int)`` *)
  texp = Var (class_constr list) cvname                    (* variable                 *)
        | Prim cop (texp list)                        (* primitive operations     *)
        | App texp (texp list)                       (* function application     *)
        | Lam ((cvname # (type option)) list) texp    (* lambda                   *)
        | Let annot_cvname texp texp                 (* let                      *)
        | Letrec ((annot_cvname # texp) list) texp   (* mutually recursive exps  *)
        | UserAnnot type texp                         (* user type annotation     *)
        | NestedCase texp cvname cepat texp
            ((cepat # texp) list)                     (* case of                  *)
End

(* top level declarations *)
Datatype:
  tcdecl = FuncDecl PredType texp (* enforce top level declarations *)
End

Definition freevars_texp_def[simp]:
  freevars_texp ((Var c v): texp) = {v} /\
  freevars_texp (Prim op es) = BIGUNION (set (MAP (λa. freevars_texp a) es)) /\
  freevars_texp (App e es) =
    freevars_texp e ∪ BIGUNION (set (MAP freevars_texp es)) ∧
  freevars_texp (Lam vs e) = freevars_texp e DIFF set (MAP FST vs) ∧
  freevars_texp (Let v e1 e2) =
    freevars_texp e1 ∪ (freevars_texp e2 DELETE (FST v)) ∧
  freevars_texp (Letrec fns e) =
    freevars_texp e ∪ BIGUNION (set (MAP (λ(v,e). freevars_texp e) fns))
      DIFF set (MAP (FST o FST) fns) ∧
  freevars_texp (NestedCase g gv p e pes) =
    freevars_texp g ∪
    (((freevars_texp e DIFF cepat_vars p) ∪
      BIGUNION (set (MAP (λ(p,e). freevars_texp e DIFF cepat_vars p) pes)))
    DELETE gv) ∧
  freevars_texp (UserAnnot t e) = freevars_texp e
Termination
  WF_REL_TAC `measure texp_size` >> rw []
End

Definition texp_wf_def[nocompute]:
  texp_wf (Var _ v) = T ∧
  texp_wf (Prim op es) = (
    num_args_ok op (LENGTH es) ∧ EVERY texp_wf es ∧
    (∀l. op = AtomOp (Lit l) ⇒ isInt l ∨ isStr l) ∧
    (∀m. op = AtomOp (Message m) ⇒ m ≠ "")) ∧
  texp_wf (App e es) = (texp_wf e ∧ EVERY texp_wf es ∧ es ≠ []) ∧
  texp_wf (Lam vs e) = (texp_wf e ∧ vs ≠ []) ∧
  texp_wf (Let v e1 e2) = (texp_wf e1 ∧ texp_wf e2) ∧
  texp_wf (Letrec fns e) = (EVERY texp_wf $ MAP (λx. SND x) fns ∧
    texp_wf e ∧ fns ≠ []) ∧
  texp_wf (NestedCase g gv p e pes) = (
    texp_wf g ∧ texp_wf e ∧ EVERY texp_wf $ MAP SND pes ∧
    ¬ MEM gv (FLAT $ MAP (cepat_vars_l o FST) ((p,e) :: pes))) ∧
  texp_wf (UserAnnot _ e) = texp_wf e
Termination
  WF_REL_TAC `measure texp_size` >> rw[fetch "-" "texp_size_def"] >>
  gvs[MEM_MAP, EXISTS_PROD] >>
  rename1 `MEM _ es` >> Induct_on `es` >> rw[] >> gvs[fetch "-" "texp_size_def"]
End

val texp_size_eq = fetch "-" "texp_size_eq";

Theorem texp_size_lemma:
  (∀xs v e. MEM (v,e) xs ⇒ texp_size e < texp1_size xs) ∧
  (∀xs p e. MEM (p,e) xs ⇒ texp_size e < texp3_size xs) ∧
  (∀xs a. MEM a xs ⇒ texp_size a < texp5_size xs)
Proof
  rpt conj_tac
  \\ Induct \\ rw [] \\ fs [fetch "-" "texp_size_def"] \\ res_tac \\ fs []
QED

Theorem better_texp_induction =
        TypeBase.induction_of “:texp”
          |> Q.SPECL [‘P’,
                      ‘λxs. ∀v e. MEM (v,e) xs ⇒ P e’,
                      ‘λ(v,e). P e’,
                      ‘λlbs. ∀pat e. MEM (pat, e) lbs ⇒ P e’,
                      ‘λ(nm,e). P e’,
                      ‘λes. ∀e. MEM e es ⇒ P e’]
          |> CONV_RULE (LAND_CONV (SCONV [DISJ_IMP_THM, FORALL_AND_THM,
                                          pairTheory.FORALL_PROD,
                                          DECIDE “(p ∧ q ⇒ q) ⇔ T”]))
          |> UNDISCH |> CONJUNCTS |> hd |> DISCH_ALL

val _ = TypeBase.update_induction better_texp_induction

Definition every_texp_def[simp]:
  every_texp (p:texp -> bool) (Var cs v) = p (Var cs v) ∧
  every_texp p (Prim x es) =
    (p (Prim x es) ∧ EVERY (every_texp p) es) ∧
  every_texp p (App e es) =
    (p (App e es) ∧ every_texp p e ∧ EVERY (every_texp p) es) ∧
  every_texp p (Lam vs e) =
    (p (Lam vs e) ∧ every_texp p e) ∧
  every_texp p (Let v e1 e2) =
    (p (Let v e1 e2) ∧ every_texp p e1 ∧ every_texp p e2) ∧
  every_texp p (Letrec fns e) =
    (p (Letrec fns e) ∧
     every_texp p e ∧ EVERY (every_texp p) $ MAP (λx. SND x) fns) ∧
  every_texp p (NestedCase e1 v pat e2 rows) =
    (p (NestedCase e1 v pat e2 rows) ∧
     every_texp p e1 ∧ every_texp p e2 ∧
     EVERY (every_texp p) $ MAP SND rows) ∧
  every_texp p (UserAnnot t e) = (p (UserAnnot t e) ∧ every_texp p e)
Termination
  WF_REL_TAC ‘measure $ texp_size o SND’ >>
  simp[texp_size_eq, MEM_MAP, PULL_EXISTS, FORALL_PROD] >> rw[] >>
  rename [‘MEM _ list’] >> Induct_on ‘list’ >>
  simp[FORALL_PROD, listTheory.list_size_def, basicSizeTheory.pair_size_def] >>
  rw[] >> gs[]
End

val _ = export_theory();
