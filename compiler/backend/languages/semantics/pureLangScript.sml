(*
  Conversion of ``:cexp`` from pure_cexpTheory to ``:exp``
*)
open HolKernel Parse boolLib bossLib;
open pairTheory listTheory pure_expTheory pure_cexpTheory;

val _ = new_theory "pureLang";

Definition lets_for_def:
  lets_for cn v [] b = b ∧
  lets_for cn v ((n,w)::ws) b = Let w (Proj cn n (Var v)) (lets_for cn v ws b)
End

Definition rows_of_def:
  rows_of v [] = Fail ∧
  rows_of v ((cn,vs,b)::rest) =
    If (IsEq cn (LENGTH vs) T (Var v))
      (lets_for cn v (MAPi (λi v. (i,v)) vs) b) (rows_of v rest)
End

Definition patguards_def:
  patguards [] = (Prim (Cons "True") [], []) ∧
  patguards (ep::eps) =
  case ep of
  | (e, cepatVar v) => (I ## CONS (v,e)) (patguards eps)
  | (e, cepatUScore) => patguards eps
  | (e, cepatCons cnm ps) =>
      let (gd, binds) = patguards (MAPi (λi p. (Proj cnm i e, p)) ps ++ eps)
      in
        (If (IsEq cnm (LENGTH ps) T e) gd (Prim (Cons "False") []),
         binds)
Termination
  WF_REL_TAC ‘measure (list_size cepat_size o MAP SND)’ >>
  simp[listTheory.list_size_def, cepat_size_def, combinTheory.o_DEF,
       listTheory.list_size_append, cepat_size_eq]
End

Definition nested_rows_def[simp]:
  nested_rows v [] = Fail ∧
  nested_rows v (pe :: pes) =
  let (gd, binds) = patguards [(v,FST pe)]
  in
    If gd (FOLDR (λ(u,e) A. Let u e A) (SND pe) binds) (nested_rows v pes)
End

Definition exp_of_def:
  exp_of (Var d n)       = ((Var n):exp) ∧
  exp_of (Prim d p xs)   = Prim (op_of p) (MAP exp_of xs) ∧
  exp_of (Let d v x y)   = Let v (exp_of x) (exp_of y) ∧
  exp_of (App _ f xs)    = Apps (exp_of f) (MAP exp_of xs) ∧
  exp_of (Lam d vs x)    = Lams vs (exp_of x) ∧
  exp_of (Letrec d rs x) = Letrec (MAP (λ(n,x). (n,exp_of x)) rs) (exp_of x) ∧
  exp_of (Case d x v rs) =
    (let caseexp =
       Let v (exp_of x) (rows_of v (MAP (λ(c,vs,x). (c,vs,exp_of x)) rs))
     in if MEM v (FLAT (MAP (FST o SND) rs)) then
       Seq Fail caseexp
     else
       caseexp) ∧
  exp_of (NestedCase d e v pes) =
  Let v (exp_of e) (nested_rows (Var v) (MAP (λ(p,e). (p, exp_of e)) pes))
Termination
  WF_REL_TAC ‘measure (cexp_size (K 0))’ \\ rw []
End

val _ = export_theory();
