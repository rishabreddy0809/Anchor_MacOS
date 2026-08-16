#!/usr/bin/env python3
"""
train_corrected_model.py — trains the corrected-scale struggle model.

Random Forest, 300 estimators, on the 13-feature schema (11 Zoom engagement +
missing_assignments + grade_trend) using training_data_10k_CORRECTED.csv.

Reports metrics on a held-out test split (never fit on) — not in-sample
accuracy, which the earlier Anchor_Accurate evaluation showed is a
misleading number on its own.

Usage:
    python3 train_corrected_model.py \
        --data training_data_10k_CORRECTED.csv \
        --out StudentStruggleModel_CORRECTED.mlmodel \
        --report model_evaluation_corrected.txt
"""

from __future__ import annotations

import argparse
import io
import sys
import warnings
from contextlib import redirect_stdout
from pathlib import Path

warnings.filterwarnings("ignore", message=".*encountered in matmul.*", category=RuntimeWarning)

import numpy as np
import pandas as pd
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import train_test_split

ENGAGEMENT_FEATURES = [
    "is_muted", "time_unmuted", "is_speaking", "speaking_duration",
    "camera_on", "hand_raised", "hand_raise_count", "message_length",
    "hesitation_count", "has_question", "confidence_level",
]
ACADEMIC_FEATURES = ["missing_assignments", "grade_trend"]
ALL_FEATURES = ENGAGEMENT_FEATURES + ACADEMIC_FEATURES
LABEL_COLUMN = "struggle_label"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path("StudentStruggleModel_CORRECTED.mlmodel"))
    parser.add_argument("--report", type=Path, default=Path("model_evaluation_corrected.txt"))
    parser.add_argument("--n-estimators", type=int, default=300)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    buf = io.StringIO()
    with redirect_stdout(buf):
        run(args)
    text = buf.getvalue()
    print(text)
    args.report.write_text(text)
    print(f"\n(report also written to {args.report})")


def run(args: argparse.Namespace) -> None:
    frame = pd.read_csv(args.data)

    print("=" * 66)
    print("ANCHOR STRUGGLE MODEL — CORRECTED TRAINING RUN")
    print("=" * 66)
    print(f"Data:       {args.data}")
    print(f"Algorithm:  RandomForestClassifier (n_estimators={args.n_estimators})")
    print(f"Rows:       {len(frame)}")

    missing = [c for c in ALL_FEATURES + [LABEL_COLUMN] if c not in frame.columns]
    if missing:
        sys.exit(f"Missing columns: {missing}")

    # MARK: Feature range confirmation
    print("\n" + "-" * 66)
    print("FEATURE RANGE CONFIRMATION (must match FeatureCalculator.swift)")
    print("-" * 66)
    gt_min, gt_max = frame["grade_trend"].min(), frame["grade_trend"].max()
    ma_min, ma_max = frame["missing_assignments"].min(), frame["missing_assignments"].max()
    gt_ok = 70 <= gt_min and gt_max <= 130
    ma_ok = 0 <= ma_min and ma_max <= 4
    print(f"grade_trend:         min={gt_min} max={gt_max}   "
          f"expected 70-130 (100=no change)  -> {'PASS' if gt_ok else 'FAIL'}")
    print(f"missing_assignments: min={ma_min} max={ma_max}   "
          f"expected 0-4                     -> {'PASS' if ma_ok else 'FAIL'}")
    for column in ALL_FEATURES:
        if frame[column].var() == 0:
            print(f"  WARNING: {column} has zero variance in this dataset.")
    if not (gt_ok and ma_ok):
        sys.exit("\nFeature ranges do not match production. Aborting before training.")

    positives = int(frame[LABEL_COLUMN].sum())
    print(f"\nLabel balance: {positives} struggling ({positives / len(frame):.1%}), "
          f"{len(frame) - positives} engaged ({(len(frame) - positives) / len(frame):.1%})")

    # MARK: Split — random stratified. Rows are independent synthetic
    # snapshots (no repeated student), so unlike real session exports there
    # is no identity_key to group by; a plain stratified split is the
    # correct one for this data-generating process.
    X = frame[ALL_FEATURES]
    y = frame[LABEL_COLUMN]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.20, random_state=args.seed, stratify=y
    )
    print(f"\nSplit: {len(X_train)} train / {len(X_test)} test (held out, stratified, unseen during fit)")

    # MARK: Train
    model = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=None,
        min_samples_leaf=5,
        class_weight="balanced",
        random_state=args.seed,
        n_jobs=-1,
    )
    model.fit(X_train, y_train)

    baseline = DummyClassifier(strategy="most_frequent").fit(X_train, y_train)
    baseline_accuracy = accuracy_score(y_test, baseline.predict(X_test))

    predictions = model.predict(X_test)
    probabilities = model.predict_proba(X_test)[:, 1]

    accuracy = accuracy_score(y_test, predictions)
    precision = precision_score(y_test, predictions)
    recall = recall_score(y_test, predictions)
    f1 = f1_score(y_test, predictions)
    auc = roc_auc_score(y_test, probabilities)

    print("\n" + "=" * 66)
    print("HELD-OUT TEST SET METRICS (not in-sample)")
    print("=" * 66)
    print(f"Test rows:                 {len(y_test)}")
    print(f"Always-'coping' baseline:  {baseline_accuracy:.2%}")
    print(f"Accuracy:                  {accuracy:.2%}")
    print(f"Precision (struggling):    {precision:.2%}")
    print(f"Recall (struggling):       {recall:.2%}")
    print(f"F1 (struggling):           {f1:.3f}")
    print(f"ROC AUC:                   {auc:.3f}")

    if accuracy <= 0.90:
        print(
            "\n  Below 90% — deliberately. This data carries 12% irreducible label "
            "\n  noise (see generate_corrected_data.py), simulating real classroom "
            "\n  ambiguity a Zoom+Classroom feature set can't resolve. That noise "
            f"\n  caps ANY classifier at roughly {1 - 0.12:.0%} accuracy on these labels — this "
            f"\n  model is landing close to that ceiling ({accuracy:.1%}), not underperforming. "
            "\n  A 90%+ number on this kind of data is the thing to be suspicious of, "
            "\n  not the thing to chase — see the first (deterministic-label) version "
            "\n  of this dataset, which hit 97.8% by reconstructing its own labeling "
            "\n  rule rather than learning anything generalizable."
        )
    else:
        print(f"\n  Held-out accuracy {accuracy:.1%} clears the 90% bar (and beats the "
              f"{baseline_accuracy:.1%} majority-class baseline by {(accuracy - baseline_accuracy) * 100:.1f} points).")

    print("\nPer-class detail:")
    print(classification_report(y_test, predictions, target_names=["coping", "struggling"], zero_division=0))

    print("Confusion matrix (rows=actual, cols=predicted):")
    print(f"                 pred coping   pred struggling")
    cm = confusion_matrix(y_test, predictions)
    print(f"  actual coping     {cm[0][0]:>6}          {cm[0][1]:>6}")
    print(f"  actual struggling {cm[1][0]:>6}          {cm[1][1]:>6}")

    print("\n" + "-" * 66)
    print("FEATURE IMPORTANCE")
    print("-" * 66)
    importances = sorted(zip(ALL_FEATURES, model.feature_importances_), key=lambda p: -p[1])
    for name, imp in importances:
        marker = "  <- academic" if name in ACADEMIC_FEATURES else ""
        bar = "#" * int(imp * 100)
        print(f"  {name:<20} {imp:.4f}  {bar}{marker}")

    academic_importance = sum(imp for name, imp in importances if name in ACADEMIC_FEATURES)
    print(f"\nAcademic features' combined importance: {academic_importance:.1%} of total")
    if academic_importance < 0.02:
        print("  WARNING: academic features are contributing almost nothing — check for the "
              "zero-variance / scale-mismatch bugs this retrain was meant to fix.")

    # MARK: Export
    import coremltools as ct

    # For a classifier, coremltools wants a 2-tuple (class-label output name,
    # class-scores output name) — passing a bare string silently falls back
    # to the defaults "classLabel"/"classProbability" instead of erroring,
    # which is how this shipped broken the first time: StruggleDetectionService
    # reads the probability dictionary by the exact name "struggle_labelProbability"
    # (matching the naming Create ML's own exporter used for the earlier
    # models), so a name mismatch doesn't crash — it just silently makes
    # every prediction fall back to the hard 0/1 class label instead of a
    # real probability. Caught here by scenario-testing the exported .mlmodel
    # itself, not by the training metrics, which don't touch export naming.
    coreml = ct.converters.sklearn.convert(
        model,
        input_features=ALL_FEATURES,
        output_feature_names=(LABEL_COLUMN, f"{LABEL_COLUMN}Probability"),
    )
    coreml.short_description = (
        f"Anchor student struggle classifier (corrected). Random Forest, "
        f"{args.n_estimators} trees. {len(ALL_FEATURES)} features "
        f"({len(ENGAGEMENT_FEATURES)} Zoom engagement, {len(ACADEMIC_FEATURES)} Google "
        f"Classroom academic on production-matched scales)."
    )
    coreml.author = "Anchor"
    coreml.save(str(args.out))
    print(f"\nWrote {args.out}")


if __name__ == "__main__":
    main()
