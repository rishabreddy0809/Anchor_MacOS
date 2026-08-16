#!/usr/bin/env python3
"""
train_struggle_model.py — retrain Anchor's struggle model on 16 features.

Takes labelled rows exported from Anchor (11 Zoom features + 5 Google Classroom
features + a teacher label) and produces a Core ML .mlmodel that
StruggleDetectionService can load without any Swift changes.

    python3 train_struggle_model.py --data labelled_sessions.csv --out StudentStruggleModel.mlmodel

WHAT THIS WILL AND WON'T TELL YOU
---------------------------------
The script reports accuracy on a held-out test split and a baseline to compare
against. Read both. An accuracy number on its own is close to meaningless here:

  * Struggling students are the minority class. If 12% of your rows are labelled
    struggling, a model that answers "coping" every single time scores 88% and is
    useless. The majority-class baseline is printed for exactly this reason — if
    the model doesn't clearly beat it, it has learned nothing.
  * Rows from the same student are correlated. Splitting them randomly across
    train and test leaks information and inflates the score. This script splits
    by *student* when an identity column is present, which usually lowers the
    reported number and makes it real.
  * Recall on the struggling class is the metric that matters. A missed
    struggling student is the failure the product exists to prevent; a false
    alarm costs a teacher one question.

Do not quote an accuracy improvement to teachers or in a README without a test
set large enough to support it. With a handful of sessions the confidence
interval is wider than any improvement you'll see.

REQUIREMENTS
    pip install pandas scikit-learn coremltools
"""

from __future__ import annotations

import argparse
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

# numpy 2.0 built against macOS Accelerate emits spurious "divide by zero /
# overflow / invalid value encountered in matmul" warnings from perfectly
# well-formed matrix products — reproducible with a plain `random(200,16) @
# random(16)`, with no inf or nan anywhere in the inputs or outputs. They are a
# BLAS-backend artefact, not a signal about your data, and they bury the actual
# evaluation output.
#
# Scoped to this exact message so any *other* numerical warning still surfaces.
warnings.filterwarnings("ignore", message=".*encountered in matmul.*", category=RuntimeWarning)
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    roc_auc_score,
)
from sklearn.model_selection import GroupShuffleSplit, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

# Must match StruggleFeature.rawValue in FeatureCalculator.swift exactly.
ENGAGEMENT_FEATURES = [
    "is_muted",
    "time_unmuted",
    "is_speaking",
    "speaking_duration",
    "camera_on",
    "hand_raised",
    "hand_raise_count",
    "message_length",
    "hesitation_count",
    "has_question",
    "confidence_level",
]

ACADEMIC_FEATURES = [
    "missing_assignments",
    "grade_average",
    "grade_trend",          # offset by +100; 100 == no change
    "days_since_submission",
    "late_submissions",
]

ALL_FEATURES = ENGAGEMENT_FEATURES + ACADEMIC_FEATURES

LABEL_COLUMN = "struggle"      # 0 = coping, 1 = struggling
GROUP_COLUMN = "identity_key"  # optional; used to split by student


def load(path: Path, require_academic: bool) -> pd.DataFrame:
    if not path.exists():
        sys.exit(f"No such file: {path}")

    frame = pd.read_csv(path)

    if LABEL_COLUMN not in frame.columns:
        sys.exit(f"Missing label column '{LABEL_COLUMN}'. Columns present: {list(frame.columns)}")

    wanted = ALL_FEATURES if require_academic else ENGAGEMENT_FEATURES
    missing = [c for c in wanted if c not in frame.columns]
    if missing:
        sys.exit(
            f"Missing feature columns: {missing}\n"
            "Export from Anchor writes every column; if you built this CSV by "
            "hand, the names must match StruggleFeature.rawValue exactly."
        )

    # Rows with no label are unlabelled samples, not negatives. Dropping them is
    # the only honest option — treating them as "coping" would train the model to
    # reproduce whatever the teacher didn't get round to reviewing.
    before = len(frame)
    frame = frame.dropna(subset=[LABEL_COLUMN])
    dropped = before - len(frame)
    if dropped:
        print(f"Dropped {dropped} unlabelled row(s).")

    frame[LABEL_COLUMN] = frame[LABEL_COLUMN].astype(int)
    for column in wanted:
        frame[column] = pd.to_numeric(frame[column], errors="coerce").fillna(0).astype(int)

    return frame


def describe(frame: pd.DataFrame) -> None:
    total = len(frame)
    positives = int(frame[LABEL_COLUMN].sum())
    rate = positives / total if total else 0.0

    print(f"\nRows: {total}")
    print(f"Struggling: {positives} ({rate:.1%})   Coping: {total - positives}")

    if GROUP_COLUMN in frame.columns:
        print(f"Distinct students: {frame[GROUP_COLUMN].nunique()}")

    if total < 200:
        print(
            "\n  WARNING: fewer than 200 rows. Any accuracy figure from this is "
            "\n  dominated by noise. Treat the model as a smoke test, not a result."
        )
    if positives < 20:
        print(
            "\n  WARNING: fewer than 20 struggling examples. The model has very "
            "\n  little to learn the positive class from and will likely under-flag."
        )


def split(frame: pd.DataFrame, features: list[str], seed: int):
    """Split by student where possible, so the same person can't appear in both
    train and test — the most common way this kind of evaluation flatters
    itself."""
    X = frame[features]
    y = frame[LABEL_COLUMN]

    if GROUP_COLUMN in frame.columns and frame[GROUP_COLUMN].nunique() >= 4:
        splitter = GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=seed)
        train_idx, test_idx = next(splitter.split(X, y, groups=frame[GROUP_COLUMN]))
        print("\nSplit: by student (no student appears in both sets).")
        return X.iloc[train_idx], X.iloc[test_idx], y.iloc[train_idx], y.iloc[test_idx]

    print(
        "\nSplit: random rows. No usable "
        f"'{GROUP_COLUMN}' column, so the reported score may be optimistic — "
        "rows from one student can land on both sides."
    )
    stratify = y if y.nunique() > 1 and y.value_counts().min() >= 2 else None
    return train_test_split(X, y, test_size=0.25, random_state=seed, stratify=stratify)


def build(kind: str) -> Pipeline:
    if kind == "logistic":
        # Mirrors the original model: a scaled linear classifier, which stays
        # interpretable and keeps per-feature attribution meaningful.
        return Pipeline([
            ("scale", StandardScaler()),
            ("clf", LogisticRegression(
                max_iter=2000,
                class_weight="balanced",   # the minority class is the one that matters
            )),
        ])

    return Pipeline([
        ("clf", GradientBoostingClassifier(random_state=0)),
    ])


def evaluate(model: Pipeline, X_train, X_test, y_train, y_test) -> None:
    baseline = DummyClassifier(strategy="most_frequent").fit(X_train, y_train)
    baseline_accuracy = accuracy_score(y_test, baseline.predict(X_test))

    predictions = model.predict(X_test)
    accuracy = accuracy_score(y_test, predictions)

    print("\n" + "=" * 62)
    print("EVALUATION (held-out test set)")
    print("=" * 62)
    print(f"Test rows:                 {len(y_test)}")
    print(f"Always-'coping' baseline:  {baseline_accuracy:.1%}")
    print(f"Model accuracy:            {accuracy:.1%}")

    delta = accuracy - baseline_accuracy
    if delta <= 0.01:
        print(
            "\n  The model does not meaningfully beat guessing the majority class."
            "\n  Do not ship it. Collect more labelled data, especially more"
            "\n  struggling examples."
        )

    if y_test.nunique() > 1:
        try:
            probabilities = model.predict_proba(X_test)[:, 1]
            print(f"ROC AUC:                   {roc_auc_score(y_test, probabilities):.3f}")
        except Exception:
            pass

    print("\nPer-class detail (recall on 'struggling' is the number that matters):")
    print(classification_report(
        y_test, predictions, target_names=["coping", "struggling"], zero_division=0
    ))

    print("Confusion matrix (rows = actual, cols = predicted):")
    print(confusion_matrix(y_test, predictions))

    if len(y_test) < 50:
        print(
            "\n  NOTE: with fewer than 50 test rows, every figure above carries a"
            "\n  margin of error of roughly ±10 points. Do not quote an"
            "\n  improvement to anyone on this basis."
        )


def report_weights(model: Pipeline, features: list[str]) -> None:
    step = model.named_steps["clf"]
    if not hasattr(step, "coef_"):
        return

    print("\nFeature weights (positive pushes toward 'struggling'):")
    pairs = sorted(zip(features, step.coef_[0]), key=lambda pair: abs(pair[1]), reverse=True)
    for name, weight in pairs:
        marker = "  <- academic" if name in ACADEMIC_FEATURES else ""
        print(f"  {name:<24} {weight:+.3f}{marker}")


def export(model: Pipeline, features: list[str], out: Path) -> None:
    try:
        import coremltools as ct
    except ImportError:
        sys.exit(
            "coremltools is not installed — the model was trained but not exported.\n"
            "    pip install coremltools"
        )

    # A bare string here silently falls back to coremltools' defaults
    # ("classLabel"/"classProbability") instead of erroring — StruggleDetectionService
    # reads the probability dictionary by the exact name "struggle_labelProbability",
    # so a name mismatch doesn't crash, it just makes every prediction fall
    # back to the hard 0/1 class label. Pass the 2-tuple form explicitly.
    coreml = ct.converters.sklearn.convert(
        model,
        input_features=features,
        output_feature_names=(LABEL_COLUMN, f"{LABEL_COLUMN}Probability"),
    )

    coreml.short_description = (
        "Anchor student struggle classifier. "
        f"{len(features)} features "
        f"({len(ENGAGEMENT_FEATURES)} Zoom engagement"
        f"{f', {len(ACADEMIC_FEATURES)} Google Classroom academic' if len(features) > 11 else ''})."
    )
    coreml.author = "Anchor"

    coreml.save(str(out))
    print(f"\nWrote {out}")
    print(
        "\nNext steps:"
        "\n  1. Drag the .mlmodel into the Anchor Xcode target (Copy items if needed)."
        "\n  2. StruggleDetectionService picks it up by name or by feature match —"
        "\n     no Swift changes needed."
        "\n  3. Once it declares the academic columns, AcademicEscalation switches"
        "\n     itself off automatically and the model's own weights take over."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", type=Path, required=True, help="labelled CSV")
    parser.add_argument("--out", type=Path, default=Path("StudentStruggleModel.mlmodel"))
    parser.add_argument(
        "--model",
        choices=["logistic", "boosted"],
        default="logistic",
        help="logistic (default, interpretable, matches the original) or boosted",
    )
    parser.add_argument(
        "--engagement-only",
        action="store_true",
        help="train on the 11 Zoom features only, for comparison against the 16-feature model",
    )
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    features = ENGAGEMENT_FEATURES if args.engagement_only else ALL_FEATURES
    frame = load(args.data, require_academic=not args.engagement_only)

    describe(frame)

    if frame[LABEL_COLUMN].nunique() < 2:
        sys.exit("\nThe label column has only one value — nothing to learn.")

    X_train, X_test, y_train, y_test = split(frame, features, args.seed)

    model = build(args.model)
    model.fit(X_train, y_train)

    evaluate(model, X_train, X_test, y_train, y_test)
    report_weights(model, features)
    export(model, features, args.out)

    print(
        "\nTo measure whether Classroom data actually helped, run this twice on"
        "\nthe same CSV and compare — once with --engagement-only and once without."
        "\nThat is the only comparison that supports a claim about the difference."
    )


if __name__ == "__main__":
    main()
