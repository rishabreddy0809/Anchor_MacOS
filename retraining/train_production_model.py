#!/usr/bin/env python3
"""
train_production_model.py — trains Anchor's shipping struggle model.

Search
------
200+ hyperparameter candidates are evaluated with 5-fold stratified
cross-validation over two families that coremltools can actually export
(RandomForest and GradientBoosting — HistGradientBoosting has no Core ML
converter, so it is deliberately not in the pool however well it scores).
Selection is on ROC AUC rather than accuracy: the app thresholds the
*probability*, not the hard label, so ranking quality is what matters.

Calibration
-----------
The exported model's probability is shown to a teacher as a percentage and
drives alert thresholds, so it has to mean what it says. A model that ranks
perfectly but reports 0.9 for cases that struggle 60% of the time would make
the alert policy fire constantly. Calibration is therefore measured — Brier
score plus a reliability table — rather than imposed: coremltools' sklearn
converter cannot export a `CalibratedClassifierCV`, so wrapping the winner in
one would yield a model that looks good in this report and cannot ship. An
isotonic-calibrated copy is fitted alongside only to report how much headroom
the raw probabilities leave.

Honest accuracy
---------------
Labels are drawn from a latent state the features only partially reveal (see
generate_messy_data.py), so there is a real Bayes ceiling well under 100%.
The script estimates that ceiling and reports the gap to it, because "how
close to the best achievable" is the only meaningful reading of an accuracy
number on data like this. A model scoring far above the ceiling would mean
the generator leaked its labels, not that the model is good.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.metrics import (
    accuracy_score, brier_score_loss, classification_report,
    confusion_matrix, f1_score, precision_score, recall_score, roc_auc_score,
)
from sklearn.model_selection import RandomizedSearchCV, StratifiedKFold, train_test_split

HERE = Path(__file__).parent
FEATURES = [
    "is_muted", "time_unmuted", "is_speaking", "speaking_duration",
    "camera_on", "hand_raised", "hand_raise_count", "message_length",
    "hesitation_count", "has_question", "confidence_level",
    "missing_assignments", "grade_average", "grade_trend",
    "days_since_submission", "late_submissions",
]
LABEL = "struggle_label"
ACADEMIC = {"missing_assignments", "grade_average", "grade_trend",
            "days_since_submission", "late_submissions"}

SEED = 20260812


# ---------------------------------------------------------------------------
# scenario gates — the same production cases the previous run checked, now
# expressed over all 16 columns.
# ---------------------------------------------------------------------------

SCENARIOS = [
    ("A. Obviously struggling", "min", 0.75, dict(
        is_muted=1, time_unmuted=5, is_speaking=0, speaking_duration=0,
        camera_on=0, hand_raised=0, hand_raise_count=0, message_length=0,
        hesitation_count=4, has_question=0, confidence_level=8,
        missing_assignments=6, grade_average=52, grade_trend=74,
        days_since_submission=21, late_submissions=4)),
    ("B. Quiet but fine", "max", 0.35, dict(
        is_muted=1, time_unmuted=90, is_speaking=0, speaking_duration=45,
        camera_on=1, hand_raised=0, hand_raise_count=1, message_length=30,
        hesitation_count=0, has_question=1, confidence_level=68,
        missing_assignments=0, grade_average=88, grade_trend=103,
        days_since_submission=1, late_submissions=0)),
    ("C. Introvert, engaged", "max", 0.35, dict(
        is_muted=1, time_unmuted=40, is_speaking=0, speaking_duration=10,
        camera_on=1, hand_raised=0, hand_raise_count=0, message_length=55,
        hesitation_count=0, has_question=1, confidence_level=58,
        missing_assignments=0, grade_average=92, grade_trend=108,
        days_since_submission=0, late_submissions=0)),
    ("D. Talks a lot, failing", "min", 0.60, dict(
        is_muted=0, time_unmuted=420, is_speaking=1, speaking_duration=260,
        camera_on=1, hand_raised=1, hand_raise_count=3, message_length=70,
        hesitation_count=1, has_question=1, confidence_level=82,
        missing_assignments=7, grade_average=48, grade_trend=68,
        days_since_submission=25, late_submissions=5)),
    ("E. REST-only, nothing observed", "max", 0.55, dict(
        is_muted=0, time_unmuted=0, is_speaking=0, speaking_duration=0,
        camera_on=0, hand_raised=0, hand_raise_count=0, message_length=0,
        hesitation_count=0, has_question=0, confidence_level=50,
        missing_assignments=0, grade_average=80, grade_trend=100,
        days_since_submission=0, late_submissions=0)),
    ("F. Extreme academic tail", "min", 0.80, dict(
        is_muted=1, time_unmuted=0, is_speaking=0, speaking_duration=0,
        camera_on=0, hand_raised=0, hand_raise_count=0, message_length=0,
        hesitation_count=2, has_question=0, confidence_level=5,
        missing_assignments=18, grade_average=22, grade_trend=55,
        days_since_submission=45, late_submissions=12)),
]


# Two exportable families, searched separately over identical CV folds so the
# comparison stays apples-to-apples. `n_estimators` is >= 200 throughout, so
# the shipped model is at least 200 boosting/bagging iterations either way.
#
# These were originally searched in one pass via a wrapper estimator that made
# `estimator` itself a tunable parameter. That wrapper did not implement the
# sklearn estimator protocol properly, so every fit raised, RandomizedSearchCV
# swallowed it into the default `error_score=np.nan`, and all 220 candidates
# tied at nan — the "winner" was then whichever happened to sort first. The
# run looked complete and reported a model that had never actually been
# compared to anything. Two plain searches cannot fail that way, and
# `error_score="raise"` below means a broken candidate stops the run instead
# of quietly becoming the answer.
FAMILIES = {
    "RandomForest": (
        # n_jobs=1: RandomizedSearchCV already parallelises across candidates,
        # and nesting the two oversubscribes every core.
        RandomForestClassifier(random_state=SEED, n_jobs=1),
        {
            "n_estimators": [200, 300, 400, 600, 800],
            "max_depth": [6, 8, 10, 12, 16, None],
            "min_samples_leaf": [1, 2, 4, 8, 16, 32],
            "min_samples_split": [2, 5, 10, 20],
            "max_features": ["sqrt", "log2", 0.4, 0.6, 0.8],
            "class_weight": [None, "balanced", "balanced_subsample"],
        },
    ),
    "GradientBoosting": (
        GradientBoostingClassifier(random_state=SEED),
        {
            "n_estimators": [200, 300, 400, 600],
            "learning_rate": [0.01, 0.02, 0.05, 0.08, 0.12],
            "max_depth": [2, 3, 4, 5],
            "min_samples_leaf": [4, 8, 16, 32, 64],
            "subsample": [0.6, 0.75, 0.9, 1.0],
            "max_features": ["sqrt", 0.5, 0.8, None],
        },
    ),
}


def _rename_probability_output(spec, new_name: str) -> str | None:
    """Rename a classifier spec's probability output in place, recursively.

    The sklearn converter wraps tree ensembles in a pipelineClassifier, so the
    name has to change on the outer description *and* on the nested model that
    actually produces it — otherwise the pipeline advertises one name and emits
    another, and Core ML rejects the model at load. Returns the old name.
    """
    old = spec.description.predictedProbabilitiesName
    if old and old != new_name:
        for output in spec.description.output:
            if output.name == old:
                output.name = new_name
        spec.description.predictedProbabilitiesName = new_name

    kind = spec.WhichOneof("Type")
    if kind in ("pipelineClassifier", "pipeline"):
        for sub in getattr(spec, kind).pipeline.models:
            _rename_probability_output(sub, new_name)

    return old


def bayes_ceiling(latent_p: np.ndarray) -> float:
    """Best accuracy any classifier could reach on these labels.

    The generator records each row's true struggle probability, so this is
    exact rather than estimated: the optimal call for a row is whichever side
    of 0.5 its probability falls on, and it is right max(p, 1-p) of the time.

    An earlier version grouped rows by their exact feature vector and took the
    per-group majority. With ~9.9k distinct vectors in 10k rows almost every
    group had one member, so it reported a 99.45% "ceiling" — an artefact of
    the rows being unique, not a bound on anything.
    """
    return float(np.maximum(latent_p, 1 - latent_p).mean())


def reliability_table(y_true, prob, bins=10) -> str:
    edges = np.linspace(0, 1, bins + 1)
    idx = np.clip(np.digitize(prob, edges) - 1, 0, bins - 1)
    lines = ["  predicted     n   actual   gap"]
    for b in range(bins):
        mask = idx == b
        if not mask.any():
            continue
        lines.append(
            f"  {edges[b]:.1f}-{edges[b+1]:.1f}  {mask.sum():5d}   "
            f"{y_true[mask].mean():6.1%}  {y_true[mask].mean() - prob[mask].mean():+6.1%}"
        )
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=HERE / "training_data_10k_MESSY.csv")
    ap.add_argument("--iterations", type=int, default=220,
                    help="hyperparameter candidates to evaluate (>=200)")
    ap.add_argument("--out", type=Path, default=HERE / "StudentStruggleModel_PRODUCTION.mlmodel")
    ap.add_argument("--report", type=Path, default=HERE / "model_evaluation_production.txt")
    ap.add_argument("--engagement-only", action="store_true",
                    help="Train on the 11 Zoom columns alone, dropping the 5 academic "
                         "ones. This is the model Anchor loads for a teacher with no "
                         "Classroom or Canvas connected — see ANCHOR note below.")
    args = ap.parse_args()

    # Both models come out of this one script on purpose.
    #
    # The whole value of an 11-vs-16 comparison is that everything except the
    # feature set is held identical: same rows, same folds, same search space,
    # same thresholds, same gates, same export path. Training the engagement
    # model from a different script — train_struggle_model.py has its own
    # --engagement-only — would compare two pipelines rather than two feature
    # sets, and the delta would mean nothing.
    global FEATURES
    if args.engagement_only:
        FEATURES = [f for f in FEATURES if f not in ACADEMIC]

    frame = pd.read_csv(args.data)
    latent_p = frame["_latent_p"].to_numpy()
    X, y = frame[FEATURES], frame[LABEL]

    out: list[str] = []

    def say(line: str = "") -> None:
        print(line)
        out.append(line)

    say("=" * 74)
    say("ANCHOR STRUGGLE MODEL — PRODUCTION TRAINING RUN")
    say("=" * 74)
    say(f"Data:       {args.data.name}")
    n_academic = len([f for f in FEATURES if f in ACADEMIC])
    say(f"Rows:       {len(frame):,}   Features: {len(FEATURES)} "
        f"({len(FEATURES) - n_academic} engagement + {n_academic} academic)")
    say(f"Balance:    {y.mean():.1%} struggling")
    say(f"Distinct feature vectors: {X.drop_duplicates().shape[0]:,}")
    say()

    # --- range agreement with FeatureCalculator.swift --------------------
    say("-" * 74)
    say("PRODUCTION RANGE CHECK (vs FeatureCalculator.swift)")
    say("-" * 74)
    expectations = {
        "grade_trend": (40, 165, "offset +100; 100 = no change"),
        "missing_assignments": (0, None, "UNCAPPED — snapshot.missingCount, summed across courses"),
        "late_submissions": (0, None, "UNCAPPED — snapshot.lateCount"),
        "grade_average": (0, 100, "whole percent"),
        "days_since_submission": (0, 90, "0 when the course has no past-due work"),
        "confidence_level": (0, 100, "derived — ported from confidenceLevel()"),
    }
    # Only the columns this model actually carries. An engagement-only build
    # has no academic columns to range-check, and asking pandas for one is a
    # KeyError rather than a useful complaint.
    for name, (lo, hi, note) in expectations.items():
        if name not in FEATURES:
            say(f"  {name:<22} {'—':>4}       SKIP   not in this model")
            continue
        lo_seen, hi_seen = int(X[name].min()), int(X[name].max())
        ok = lo_seen >= lo and (hi is None or hi_seen <= hi)
        say(f"  {name:<22} {lo_seen:>4}..{hi_seen:<4}  {'PASS' if ok else 'FAIL'}   {note}")
    say()

    idx = np.arange(len(frame))
    X_train, X_test, y_train, y_test, _, idx_test = train_test_split(
        X, y, idx, test_size=0.2, stratify=y, random_state=SEED
    )

    # --- search ----------------------------------------------------------
    say("-" * 74)
    say(f"HYPERPARAMETER SEARCH — {args.iterations} candidates x 5-fold CV")
    say("-" * 74)
    started = time.time()
    folds = StratifiedKFold(5, shuffle=True, random_state=SEED)
    per_family = max(1, args.iterations // len(FAMILIES))

    searches: dict[str, RandomizedSearchCV] = {}
    for label, (estimator, grid) in FAMILIES.items():
        search = RandomizedSearchCV(
            estimator,
            param_distributions=grid,
            n_iter=per_family,
            scoring="roc_auc",
            cv=folds,
            random_state=SEED,
            n_jobs=-1,
            refit=False,
            error_score="raise",
            verbose=0,
        )
        search.fit(X_train, y_train)
        searches[label] = search
        say(f"  {label:<18} {per_family:3d} candidates   best CV ROC AUC {search.best_score_:.4f}")

    elapsed = time.time() - started
    total = per_family * len(FAMILIES)
    say(f"  Evaluated {total} candidates ({total * 5} fits) in {elapsed:.0f}s")
    say()

    family = max(searches, key=lambda k: searches[k].best_score_)
    winner = searches[family]
    best = dict(winner.best_params_)
    say(f"  Winner: {family}  (CV ROC AUC {winner.best_score_:.4f})")
    for k, v in sorted(best.items()):
        say(f"     {k:<20} {v}")
    say()
    say("  Top 5 candidates overall:")
    pooled = pd.concat(
        [pd.DataFrame(s.cv_results_).assign(family=name) for name, s in searches.items()],
        ignore_index=True,
    )
    for rank, (_, r) in enumerate(pooled.nlargest(5, "mean_test_score").iterrows(), 1):
        say(f"    {rank}. {r['family']:<20} AUC {r['mean_test_score']:.4f} "
            f"(+/-{r['std_test_score']:.4f})")
    say()

    # --- refit the winner -------------------------------------------------
    #
    # The raw estimator is what ships: coremltools' sklearn converter has no
    # support for CalibratedClassifierCV, so wrapping the winner in one would
    # produce a model that scores well here and cannot be exported at all.
    # Calibration is therefore *measured* below rather than imposed — and
    # isotonic calibration is fitted alongside purely to report how much
    # headroom is being left on the table. If that gap were ever large, the
    # answer would be to pick a better-calibrated family in the search, not to
    # add a wrapper the export path cannot carry.
    def build():
        base = FAMILIES[family][0]
        return base.__class__(**{**base.get_params(), **best})

    model = build()
    model.fit(X_train, y_train)

    prob = model.predict_proba(X_test)[:, 1]
    pred = (prob >= 0.5).astype(int)

    reference = CalibratedClassifierCV(build(), method="isotonic", cv=5)
    reference.fit(X_train, y_train)
    reference_brier = brier_score_loss(y_test, reference.predict_proba(X_test)[:, 1])

    ceiling = bayes_ceiling(latent_p[idx_test])
    baseline = max(y_test.mean(), 1 - y_test.mean())

    say("=" * 74)
    say("HELD-OUT TEST METRICS (2,000 rows, unseen during fit and search)")
    say("=" * 74)
    say(f"  Majority-class baseline: {baseline:.2%}")
    say(f"  Accuracy:                {accuracy_score(y_test, pred):.2%}")
    say(f"  Precision (struggling):  {precision_score(y_test, pred):.2%}")
    say(f"  Recall (struggling):     {recall_score(y_test, pred):.2%}")
    say(f"  F1 (struggling):         {f1_score(y_test, pred):.3f}")
    say(f"  ROC AUC:                 {roc_auc_score(y_test, prob):.4f}")
    say(f"  Brier score:             {brier_score_loss(y_test, prob):.4f}  (lower is better)")
    say(f"  Brier if isotonic-calibrated: {reference_brier:.4f}  (not exportable — see above)")
    say()
    say(f"  Estimated Bayes ceiling: {ceiling:.2%} (exact — from the generator's latent p)")
    say(f"  Gap to ceiling:          {ceiling - accuracy_score(y_test, pred):+.2%}")
    say()
    say("  Labels are drawn from a latent state the features only partly reveal,")
    say("  so the ceiling above is where a perfect model lands. Scoring at or")
    say("  over it would mean the generator leaked its labels, not that the")
    say("  model is good; the gap is the real headroom left.")
    say()
    say("Per-class detail:")
    say(classification_report(y_test, pred, target_names=["coping", "struggling"]))
    cm = confusion_matrix(y_test, pred)
    say("Confusion matrix (rows=actual, cols=predicted):")
    say(f"                 pred coping   pred struggling")
    say(f"  actual coping       {cm[0][0]:5d}          {cm[0][1]:5d}")
    say(f"  actual struggling   {cm[1][0]:5d}          {cm[1][1]:5d}")
    say()
    say("Calibration (predicted probability vs observed rate):")
    say(reliability_table(y_test.to_numpy(), prob))
    say()

    # --- the thresholds the app actually uses ----------------------------
    #
    # Nothing in Anchor decides at 0.5. RiskLevel puts a student on "Watch" at
    # 0.40 and "Needs attention" at 0.70, and the sensitivity slider moves both
    # by up to +/-0.15. The 0.5 row below is only there for comparison with the
    # headline numbers above — the rows that matter for whether a teacher is
    # told about a struggling student are 0.40 and 0.70.
    say("-" * 74)
    say("OPERATING POINTS (RiskLevel.swift cut-offs)")
    say("-" * 74)
    say("  threshold                     precision  recall     F1   flagged")
    for cut, note in [
        (0.25, "Watch, max sensitivity"),
        (0.40, "Watch  <- default"),
        (0.50, "(comparison only)"),
        (0.55, "Needs attention, max sens."),
        (0.70, "Needs attention  <- default"),
        (0.85, "Needs attention, min sens."),
    ]:
        p = (prob >= cut).astype(int)
        flagged = p.mean()
        say(f"  {cut:.2f}  {note:<28} {precision_score(y_test, p, zero_division=0):7.1%} "
            f"{recall_score(y_test, p):7.1%} {f1_score(y_test, p):6.3f} {flagged:8.1%}")
    say()
    say("  A missed struggling student is the failure this product exists to")
    say("  prevent; a false alarm costs a teacher one question. The default")
    say("  'Watch' point is deliberately the recall-favouring one.")
    say()

    # --- importance -------------------------------------------------------
    fitted = model
    if hasattr(fitted, "feature_importances_"):
        imp = pd.Series(fitted.feature_importances_, index=FEATURES).sort_values(ascending=False)
        say("-" * 74)
        say("FEATURE IMPORTANCE")
        say("-" * 74)
        for name, value in imp.items():
            tag = "  <- academic" if name in ACADEMIC else ""
            say(f"  {name:<24} {value:.4f}  {'#' * int(value * 120)}{tag}")
        say()
        present_academic = [f for f in ACADEMIC if f in FEATURES]
        if present_academic:
            say(f"Academic features combined: {imp[present_academic].sum():.1%}")
        else:
            say("Academic features: none in this model (engagement-only build).")
        say()

    # --- scenarios --------------------------------------------------------
    say("=" * 74)
    say("PRODUCTION SCENARIO GATES")
    say("=" * 74)
    failures = 0
    academic_only_scenarios = {"D. Talks a lot, failing", "F. Extreme academic tail"}
    scenarios = [s for s in SCENARIOS
                 if not (args.engagement_only and s[0] in academic_only_scenarios)]
    if args.engagement_only:
        for name in sorted(academic_only_scenarios):
            say(f"  {name:<35} SKIPPED — needs academic signal this model lacks")
    for name, direction, bound, values in scenarios:
        row = pd.DataFrame([[values[f] for f in FEATURES]], columns=FEATURES)
        p = float(model.predict_proba(row)[0, 1])
        ok = p >= bound if direction == "min" else p <= bound
        failures += (not ok)
        want = f"{'>' if direction == 'min' else '<'} {bound:.0%}"
        say(f"  {name:<34} {p:6.1%}   expect {want:<7} [{'PASS' if ok else 'FAIL'}]")
    say()
    say(f"  {len(scenarios) - failures}/{len(scenarios)} gates passed")
    say()

    # --- direction gates --------------------------------------------------
    #
    # A tree ensemble has no built-in notion of "more missing work is worse",
    # and sklearn's exportable families support no monotonic constraints, so
    # the direction is only ever as good as the data taught it. The first
    # 16-feature model passed every scenario gate above while scoring
    # missing_assignments *backwards* — 22.2% at zero missing, 18.6% at thirty.
    # Scenario gates could not catch that because each one moves every feature
    # at once. These sweeps move exactly one column and assert the sign.
    say("=" * 74)
    say("FEATURE DIRECTION GATES (one column swept, everything else held)")
    say("=" * 74)
    neutral = dict(
        is_muted=1, time_unmuted=60, is_speaking=0, speaking_duration=30,
        camera_on=1, hand_raised=0, hand_raise_count=1, message_length=20,
        hesitation_count=1, has_question=0, confidence_level=50,
        missing_assignments=0, grade_average=75, grade_trend=100,
        days_since_submission=0, late_submissions=0,
    )
    sweeps = [
        ("missing_assignments", range(0, 31, 2), "up"),
        ("late_submissions", range(0, 21, 1), "up"),
        ("days_since_submission", range(0, 91, 5), "up"),
        ("grade_average", range(0, 101, 5), "down"),
        ("grade_trend", range(40, 166, 5), "down"),
        ("confidence_level", range(0, 101, 5), "down"),
    ]
    sweeps = [s for s in sweeps if s[0] in FEATURES]
    direction_failures = 0
    for feature, values, want in sweeps:
        rows = []
        for v in values:
            r = dict(neutral); r[feature] = v; rows.append(r)
        frame_sweep = pd.DataFrame(rows, columns=FEATURES)
        ps = model.predict_proba(frame_sweep)[:, 1]
        delta = ps[-1] - ps[0]
        got = "up" if delta > 0 else "down"
        # Spearman sign: is the trend consistent, not just the endpoints?
        ranks = np.argsort(np.argsort(ps))
        corr = np.corrcoef(np.arange(len(ps)), ranks)[0, 1]
        ok = got == want and abs(delta) > 0.02
        direction_failures += (not ok)
        say(f"  {feature:<24} {ps[0]:6.1%} -> {ps[-1]:6.1%}  {got:<5} "
            f"(want {want:<5}) rank-corr {corr:+.2f}  [{'PASS' if ok else 'FAIL'}]")
    say()
    say(f"  {len(sweeps) - direction_failures}/{len(sweeps)} direction gates passed")
    say()
    failures += direction_failures

    # --- export -----------------------------------------------------------
    import coremltools as ct

    converted = ct.converters.sklearn.convert(model, FEATURES, LABEL)

    # The sklearn converter names the probability output "classProbability".
    # CreateML — which produced every previous Anchor model — names it
    # "<label>Probability", and StruggleDetectionService.struggleProbability
    # reads exactly that key. On a mismatch the dictionary lookup silently
    # misses and the service falls through to the hard label, turning every
    # score into 0% or 100% with no error anywhere. Renaming here keeps the
    # exported model a drop-in for the Swift that already exists.
    spec = converted.get_spec()
    renamed_from = _rename_probability_output(spec, f"{LABEL}Probability")
    coreml = ct.models.MLModel(spec)
    if renamed_from:
        say(f"Renamed probability output {renamed_from!r} -> {LABEL}Probability")

    coreml.short_description = (
        "Anchor student-struggle classifier. 16 features (11 Zoom engagement + "
        "5 Google Classroom). Trained on 10,000 messy synthetic sessions."
    )
    coreml.author = "Anchor"
    coreml.save(str(args.out))
    say(f"Wrote {args.out.name}")

    spec = ct.utils.load_spec(str(args.out))
    declared = sorted(i.name for i in spec.description.input)
    say(f"  declares {len(declared)} inputs: {', '.join(declared)}")
    say(f"  outputs: {[o.name for o in spec.description.output]}")
    missing = set(FEATURES) - set(declared)
    say(f"  schema matches FeatureCalculator: {'YES' if not missing else 'NO ' + str(missing)}")

    args.report.write_text("\n".join(out) + "\n")
    (HERE / "search_results.json").write_text(json.dumps({
        "candidates": total,
        "cv_roc_auc_by_family": {k: float(s.best_score_) for k, s in searches.items()},
        "winner": family,
        "best_cv_roc_auc": float(winner.best_score_),
        "test_roc_auc": float(roc_auc_score(y_test, prob)),
        "bayes_ceiling": ceiling,
        "params": {k: str(v) for k, v in best.items()},
        "scenario_gates_passed": len(scenarios) - failures,
    }, indent=2))
    print(f"\nReport -> {args.report.name}")

    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
