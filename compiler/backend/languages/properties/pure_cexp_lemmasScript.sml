
open HolKernel Parse boolLib bossLib term_tactic BasicProvers;
open arithmeticTheory listTheory stringTheory alistTheory
     optionTheory pairTheory pred_setTheory finite_mapTheory;
open pure_miscTheory pure_cexpTheory pureLangTheory
     pure_expTheory pure_exp_lemmasTheory;

val _ = new_theory "pure_cexp_lemmas";

Theorem silly_cong_lemma[local]:
  ((∀a b. MEM (a,b) l2 ⇒ P a b) ⇔ (∀p. MEM p l2 ⇒ P (FST p) (SND p))) ∧
  ((∀a b c. MEM (a,b,c) l3 ⇒ Q a b c) ⇔
     (∀t. MEM t l3 ⇒ Q (FST t) (FST (SND t)) (SND (SND t))))
Proof
  simp[FORALL_PROD]
QED

Theorem freevars_cexp_equiv:
  ∀ce. freevars_cexp ce = set (freevars_cexp_l ce)
Proof
  recInduct freevars_cexp_ind >>
  rw[] >>
  gvs[LIST_TO_SET_FLAT, MAP_MAP_o, combinTheory.o_DEF, Cong MAP_CONG,
      LIST_TO_SET_FILTER, UNCURRY, silly_cong_lemma] >>
  simp[Once EXTENSION, MEM_MAP, PULL_EXISTS, cepat_vars_l_correct] >>
  metis_tac[]
QED

Theorem freevars_lets_for:
  ∀c v l b. freevars (lets_for c v l b) =
    case l of
      [] => freevars b DIFF set (MAP SND l)
    | _ => v INSERT (freevars b DIFF set (MAP SND l))
Proof
  recInduct lets_for_ind >> rw[lets_for_def] >>
  CASE_TAC >> gvs[] >> simp[EXTENSION] >> metis_tac[]
QED

Theorem freevars_rows_of:
  ∀v l. freevars (rows_of v l) =
    case l of
      [] => {}
    | _ => v INSERT BIGUNION (set (MAP (λ(cn,vs,b). freevars b DIFF set vs) l))
Proof
  recInduct rows_of_ind >> rw[rows_of_def] >> simp[freevars_lets_for] >>
  Cases_on `rest` >> gvs[combinTheory.o_DEF] >>
  CASE_TAC >> gvs[EXTENSION] >> metis_tac[]
QED

Theorem set_MAPK[local]:
  set (MAP (λx. y) ps) = case ps of [] => ∅ | _ => {y}
Proof
   Induct_on ‘ps’ >> simp[] >> Cases_on ‘ps’ >> simp[]
QED

Theorem freevars_patguards:
  ∀eps gd binds.
    patguards eps = (gd, binds) ⇒
    freevars gd ⊆ BIGUNION (set (MAP (freevars o FST) eps)) ∧
    BIGUNION (set (MAP (freevars o SND) binds)) ⊆
    BIGUNION (set (MAP (freevars o FST) eps))
Proof
  recInduct patguards_ind >>
  simp[patguards_def, AllCaseEqs(), PULL_EXISTS] >> rpt strip_tac >>
  gvs[] >>~-
  ([‘MAPi’],
   pairarg_tac >> gvs[] >> gvs[combinTheory.o_DEF, set_MAPK] >>
   Cases_on ‘ps’ >> gvs[] >> gvs[SUBSET_DEF]) >>
  Cases_on ‘patguards eps’ >> gvs[] >> rw[] >> gvs[SUBSET_DEF]
QED

Theorem freevars_FOLDR_LetUB:
  (∀v b. MEM (v,b) binds ⇒ freevars b = B)
  ⇒
  freevars (FOLDR (λ(v,e) A. Let v e A) base binds) ⊆
  (freevars base DIFF set (MAP FST binds)) ∪ B
Proof
  Induct_on ‘binds’ >> simp[FORALL_PROD] >> rw[] >>
  gvs[DISJ_IMP_THM, FORALL_AND_THM] >>
  first_x_assum $ drule_at Any >>
  simp[SUBSET_DEF]
QED

Theorem freevars_FOLDR_LetLB:
  (∀v b. MEM (v,b) binds ⇒ freevars b = B) ⇒
  freevars base DIFF set (MAP FST binds) ⊆
  freevars (FOLDR (λ(v,e) A. Let v e A) base binds)
Proof
  Induct_on ‘binds’ >> simp[FORALL_PROD, DISJ_IMP_THM, FORALL_AND_THM] >>
  rpt strip_tac >> first_x_assum drule >> simp[SUBSET_DEF]
QED

Theorem patguards_binds_pvars:
  ∀eps gd binds.
    patguards eps = (gd, binds) ⇒
    set (MAP FST binds) = BIGUNION (set (MAP (cepat_vars o SND) eps))
Proof
  recInduct patguards_ind >>
  simp[combinTheory.o_DEF, patguards_def, AllCaseEqs(), PULL_EXISTS,
       FORALL_PROD] >> rpt strip_tac >> gvs[] >~
  [‘(_ ## _)’]
  >- (Cases_on ‘patguards eps’ >> gvs[] >> simp[INSERT_UNION_EQ]) >>
  pairarg_tac >> gvs[SF ETA_ss]
QED

Theorem patguards_onebound_preserved:
  ∀eps gd binds.
    patguards eps = (gd, binds) ∧ (∀e p. MEM (e,p) eps ⇒ freevars e = B) ⇒
    (∀v e. MEM (v,e) binds ⇒ freevars e = B)
Proof
  recInduct patguards_ind >>
  simp[combinTheory.o_DEF, patguards_def, AllCaseEqs(), PULL_EXISTS,
       FORALL_PROD] >> rpt strip_tac >> gvs[] >~
  [‘( _ ## _) (patguards eps)’]
  >- (Cases_on ‘patguards eps’ >> gvs[DISJ_IMP_THM, FORALL_AND_THM] >>
      metis_tac[]) >~
  [‘(UNCURRY _) _ = (gd, binds)’]
  >- (pairarg_tac >>
      gvs[DISJ_IMP_THM, FORALL_AND_THM, indexedListsTheory.MEM_MAPi,
          PULL_EXISTS] >> metis_tac[]) >>
  metis_tac[]
QED

Theorem freevars_nested_rows_UB:
  freevars (nested_rows e pes) ⊆
  if pes = [] then ∅
  else
    freevars e ∪
    BIGUNION (set (MAP (λ(p,e). freevars e DIFF cepat_vars p) pes))
Proof
  Induct_on ‘pes’ >> simp[FORALL_PROD] >> qx_genl_tac [‘p’, ‘e0’] >>
  pairarg_tac >> simp[] >> rpt strip_tac
  >- (drule $ cj 1 freevars_patguards >> simp[] >>
      simp[SUBSET_DEF])
  >- (drule patguards_onebound_preserved >> simp[] >> strip_tac >>
      drule_then (qspec_then ‘e0’ mp_tac) freevars_FOLDR_LetUB >>
      simp[SUBSET_DEF, MEM_MAP, PULL_EXISTS, EXISTS_PROD, FORALL_PROD] >>
      rpt strip_tac >> first_x_assum drule >> strip_tac >> simp[] >>
      drule patguards_binds_pvars >> simp[] >>
      simp[EXTENSION, MEM_MAP, EXISTS_PROD] >> metis_tac[]) >>
  Cases_on ‘pes = []’ >> gs[] >>
  gs[SUBSET_DEF, MEM_MAP, PULL_EXISTS, EXISTS_PROD] >> metis_tac[]
QED

Theorem freevars_nested_rows_LB:
  BIGUNION (set (MAP (λ(p,e). freevars e DIFF cepat_vars p) pes)) ⊆
  freevars (nested_rows e pes)
Proof
  Induct_on ‘pes’ >> simp[FORALL_PROD] >> rpt strip_tac >>
  pairarg_tac >> simp[]
  >- (drule patguards_onebound_preserved >> simp[] >> strip_tac >>
      rename [‘freevars base DIFF cepat_vars pat ⊆ _’] >>
      drule_then (qspec_then ‘base’ mp_tac) freevars_FOLDR_LetLB >>
      drule_then assume_tac patguards_binds_pvars >> simp[] >>
      simp[SUBSET_DEF]) >>
  gs[SUBSET_DEF]
QED

Theorem freevars_exp_of:
  ∀ce. freevars (exp_of ce) = freevars_cexp ce
Proof
  recInduct freevars_cexp_ind >> rw[exp_of_def] >>
  gvs[MAP_MAP_o, combinTheory.o_DEF, Cong MAP_CONG, UNCURRY,
      silly_cong_lemma, freevars_rows_of]>>
  simp[SF ETA_ss] >>
  simp[Once EXTENSION, PULL_EXISTS, MEM_MAP]
  >- metis_tac[]
  >- (Cases_on ‘css’ >> simp[MEM_MAP, EXISTS_PROD, PULL_EXISTS] >>
      PairCases_on ‘h’ >> simp[]>> metis_tac[])
  >- (Cases_on ‘css’ >> simp[MEM_MAP, EXISTS_PROD, PULL_EXISTS] >>
      PairCases_on ‘h’ >> simp[]>> metis_tac[])
  >- (qx_gen_tac ‘vnm’ >> eq_tac >> strip_tac >> simp[]
      >- (Cases_on ‘pes = []’ >> gs[] >>
          drule (SRULE [SUBSET_DEF] freevars_nested_rows_UB) >>
          simp[MEM_MAP, PULL_EXISTS, SF CONJ_ss] >> metis_tac[])
      >- (disj1_tac >>
          irule (SRULE [SUBSET_DEF] freevars_nested_rows_LB) >>
          simp[MEM_MAP, PULL_EXISTS, SF CONJ_ss] >> metis_tac[]))
  >- (qx_gen_tac ‘vnm’ >> eq_tac >> strip_tac >> simp[]
      >- (Cases_on ‘pes = []’ >> gs[] >>
          drule (SRULE [SUBSET_DEF] freevars_nested_rows_UB) >>
          simp[MEM_MAP, PULL_EXISTS, SF CONJ_ss] >> metis_tac[])
      >- (disj1_tac >>
          irule (SRULE [SUBSET_DEF] freevars_nested_rows_LB) >>
          simp[MEM_MAP, PULL_EXISTS, SF CONJ_ss] >> metis_tac[]))
QED

Theorem subst_lets_for:
  ∀cn v l e f.  v ∉ FDOM f ⇒
    subst f (lets_for cn v l e) =
    lets_for cn v l (subst (FDIFF f (set (MAP SND l))) e)
Proof
  recInduct lets_for_ind >> rw[lets_for_def, subst_def] >>
  simp[FLOOKUP_DEF, FDIFF_FDOMSUB_INSERT]
QED

Theorem subst_rows_of:
  ∀v l f.  v ∉ FDOM f ⇒
    subst f (rows_of v l) =
    rows_of v (MAP (λ(a,b,c). (a,b, subst (FDIFF f (set b)) c)) l)
Proof
  recInduct rows_of_ind >> rw[rows_of_def, subst_def]
  >- simp[FLOOKUP_DEF] >>
  simp[subst_lets_for, combinTheory.o_DEF]
QED

Theorem subst_FOLDR_Let:
  ∀f B. FDOM f ∩ B = ∅ ∧ (∀v e. MEM (v,e) l ⇒ freevars e ⊆ B) ⇒
        subst f (FOLDR (λ(u,e) A. Let u e A) base l) =
        FOLDR (λ(u,e) A. Let u e A) (subst (FDIFF f (set (MAP FST l))) base) l
Proof
  Induct_on ‘l’ >>
  simp[FORALL_PROD, DISJ_IMP_THM, FORALL_AND_THM, subst_def] >>
  rpt strip_tac
  >- (rename [‘subst (f \\ vnm) (FOLDR _ _ _)’] >>
      ‘FDOM (f \\ vnm) ∩ B = ∅’ by simp[DELETE_INTER] >>
      first_x_assum drule_all >> simp[] >> disch_then kall_tac >>
      simp[FDIFF_FDOMSUB_INSERT]) >>
  irule subst_ignore >> irule SUBSET_DISJOINT >>
  irule_at (Pat ‘FDOM f ⊆ _’) SUBSET_REFL >>
  metis_tac[DISJOINT_DEF, INTER_COMM]
QED

Theorem subst_nested_rows:
  FDOM f ∩ freevars e = ∅ ⇒
  subst f (nested_rows e pes) =
  nested_rows e (MAP (λ(p,e). (p, subst (FDIFF f (cepat_vars p)) e)) pes)
Proof
  strip_tac >> Induct_on ‘pes’ >> simp[FORALL_PROD] >>
  qx_genl_tac [‘p’, ‘e0’] >> pairarg_tac >> simp[subst_def] >> conj_tac
  >- (irule subst_ignore >> simp[DISJOINT_DEF] >>
      drule freevars_patguards >> simp[] >> rpt strip_tac >>
      map_every (fn q => qpat_x_assum q mp_tac)
                [‘FDOM _ ∩ _ = ∅’, ‘freevars _ ⊆ freevars _’] >>
      simp[SUBSET_DEF, EXTENSION] >> metis_tac[]) >>
  drule_then (assume_tac o SYM) patguards_binds_pvars >> gs[] >>
  irule subst_FOLDR_Let >> first_assum $ irule_at Any >>
  rpt strip_tac >> rename [‘freevars e0 ⊆ freevars e’] >>
  ‘freevars e0 = freevars e’ suffices_by simp[] >>
  irule patguards_onebound_preserved >> rpt (first_assum $ irule_at Any) >>
  simp[]
QED

Theorem subst_exp_of:
  ∀f ce.
    exp_of (substc f ce) =
    subst (FMAP_MAP2 (λ(k,v). exp_of v) f) (exp_of ce)
Proof
  recInduct substc_ind >> rw[subst_def, substc_def, exp_of_def] >>
  gvs[MAP_MAP_o, combinTheory.o_DEF, LAMBDA_PROD, GSYM FST_THM]
  >- (simp[FLOOKUP_FMAP_MAP2] >> CASE_TAC >> gvs[exp_of_def])
  >- simp[Cong MAP_CONG]
  >- (simp[subst_Apps, Cong MAP_CONG, MAP_MAP_o])
  >- (simp[subst_Lams, Cong MAP_CONG, FDIFF_FMAP_MAP2])
  >- simp[DOMSUB_FMAP_MAP2]
  >- (
    rw[MAP_EQ_f] >> pairarg_tac >> rw[] >>
    first_x_assum drule >> rw[FDIFF_FMAP_MAP2]
    )
  >- simp[FDIFF_FMAP_MAP2] >>~-
  ([‘rows_of’],
   simp[subst_rows_of, MAP_MAP_o, combinTheory.o_DEF, LAMBDA_PROD] >>
   AP_TERM_TAC >> rw[MAP_EQ_f] >> pairarg_tac >> rw[] >>
   first_x_assum drule >> rw[] >>
   simp[FDIFF_FDOMSUB_INSERT, FDIFF_FMAP_MAP2]) >>
  gs[silly_cong_lemma, UNCURRY, Cong MAP_CONG] >>
  ‘∀f. (FDOM (f : string |-> exp) DELETE v) ∩ {v} = ∅’
    by simp[EXTENSION] >>
  simp[subst_nested_rows, MAP_MAP_o, FDIFF_FMAP_MAP2, combinTheory.o_DEF,
       FDIFF_FDOMSUB_INSERT]
QED

Theorem lets_for_APPEND:
  ∀ws1 ws2 cn ar v n w b.
    lets_for cn v (ws1 ++ ws2) b =
      lets_for cn v ws1 (lets_for cn v ws2 b)
Proof
  Induct >> rw[lets_for_def] >>
  PairCases_on `h` >> simp[lets_for_def]
QED


val _ = export_theory();
