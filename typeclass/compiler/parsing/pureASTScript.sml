open HolKernel Parse boolLib bossLib;

local open stringTheory integerTheory pure_configTheory in end
val _ = new_theory "pureAST";

val _ = set_grammar_ancestry ["string", "integer", "pure_config"]

(* by convention tyOps will be capitalised alpha-idents, or "->",
   and tyVars will be lower-case alpha-idents.

   The tyTup constructor should never be applied to a singleton list
*)
Datatype:
  tyAST = tyOp string (tyAST list)
        | tyVarOp string (tyAST list)
        | tyVar string
        (* should we remove tyVar as it can represent as tyVarOp string [] *)
        | tyTup (tyAST list)
End

Datatype:
  PredtyAST = Predty ((string # string) list) tyAST
End

Overload boolTy = “tyOp "Bool" []”;
Overload intTy = “tyOp "Integer" []”
Overload listTy = “λty. tyOp "[]" [ty]”
Overload funTy = “λd r. tyOp "Fun" [d; r]”

Datatype:
  litAST = litInt int | litString string
End

Datatype:
  patAST = patVar string
         | patApp string (patAST list)
         | patTup (patAST list)
         | patLit litAST
         | patUScore
End

Datatype:
  expAST = expVar string
         | expCon string (expAST list)
         | expOp pure_config$atom_op (expAST list)
         | expTup (expAST list)
         | expApp expAST expAST
         | expAbs patAST expAST
         | expIf expAST expAST expAST
         | expLit litAST
         | expLet (expdecAST list) expAST
         | expDo (expdostmtAST list) expAST
         | expCase expAST ((patAST # expAST) list);
  expdecAST = expdecTysig string PredtyAST
            | expdecPatbind patAST expAST
            | expdecFunbind string (patAST list) expAST ;
  expdostmtAST = expdostmtExp expAST
               | expdostmtBind patAST expAST
               | expdostmtLet (expdecAST list)
End

Theorem better_expAST_induction =
        TypeBase.induction_of “:expAST”
          |> Q.SPECL [‘eP’, ‘dP’, ‘doP’,
                      ‘λpes. ∀p e. MEM (p,e) pes ⇒ eP e’,
                      ‘λpe. eP (SND pe)’,
                      ‘λdds. ∀ds. MEM ds dds ⇒ doP ds’,
                      ‘λes. ∀e. MEM e es ⇒ eP e’,
                      ‘λds. ∀d. MEM d ds ⇒ dP d’]
          |> SRULE [DISJ_IMP_THM, FORALL_AND_THM, pairTheory.FORALL_PROD,
                    DECIDE “p ∧ q ⇒ q ⇔ T”]
          |> UNDISCH
          |> SRULE [Cong (DECIDE “p = p' ∧ (p' ⇒ q = q') ⇒ (p ∧ q ⇔ p' ∧ q')”)]
          |> DISCH_ALL
          |> Q.GENL [‘eP’, ‘dP’, ‘doP’]

val _ = add_strliteral_form {ldelim = "‹", inj = “expVar”}
Overload pNIL = “expCon "[]" []”
Overload pCONS = “λe1 e2. expCon "::" [e1;e2]”
val _ = set_mapped_fixity {fixity = Infixr 490,term_name = "pCONS",tok = "::ₚ"}

val _ = set_fixity "⬝" (Infixl 600)
Overload "⬝" = “expApp”

Definition strip_comb_def:
  strip_comb (expApp f x) = (I ## (λl. l ++ [x])) (strip_comb f) ∧
  strip_comb e = (e, [])
End

Definition dest_expVar_def:
  dest_expVar (expVar s) = SOME s ∧
  dest_expVar _ = NONE
End

Definition dest_expLet_def:
  dest_expLet (expLet ads e) = SOME (ads,e) ∧
  dest_expLet _ = NONE
End

val _ = add_rule {term_name = "expAbs", fixity = Prefix 1,
                  block_style = (AroundEachPhrase, (PP.CONSISTENT, 0)),
                  pp_elements = [TOK "𝝺", TM, TOK "．", BreakSpace(1,2)],
                  paren_style = OnlyIfNecessary}

Type classname = ``:string``;

Type minImplAST = ``:(string list) list``; (* DNF *)

(* for declClass:
*  we only allow something like class Functor a => Monad a,
*  where there is only one type variable and
*  it cannot used as Functor [a] *)
(* only classname list is needed is for now *)

(* for declInst:
* we only allow the constraints to be
* ``instance (Cl1 a,Cl2 b,...) => Cl ty``,
* where ty can be any type that uses a, b...
* We need to ensure ty is not smaller or equal to a,b...for termination.
* In our case, we only need to ensure there is not a tyVar
*)

Datatype:
  declAST = declTysig string PredtyAST
          | declData string (string list)
                     ((string # tyAST list) list)
          | declFunbind string (patAST list) expAST
          | declPatbind patAST expAST
          | declClass (classname list) classname minImplAST (expdecAST list)
          | declInst ((classname # string) list) classname tyAst (expdecAST list)
End


val _ = export_theory();
