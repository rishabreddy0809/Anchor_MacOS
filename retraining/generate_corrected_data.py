#!/usr/bin/env python3
"""
generate_corrected_data.py — regenerate Anchor's synthetic struggle-model
training data with feature scales that actually match production, and with
genuinely varied per-row scenarios rather than a handful of noisy templates.

Why this exists
----------------
The original training set (training_data_10k.csv, 7,000 rows) had two bugs,
found by evaluating Anchor_Accurate.mlmodel against FeatureCalculator.swift's
real conventions:

  1. missing_assignments was 0 for every single row — zero variance, so the
     model could not learn anything from that column despite declaring it.
  2. grade_trend was generated in a raw -2..19 range. Production
     (FeatureCalculator.swift) sends grade_trend offset by +100, so real
     values run ~70..130 with 100 == "no change". Every real prediction was
     therefore made on a value the model had never seen anything near.

A first corrected pass fixed both scales but used 8 fixed archetypes (4
struggling, 4 engaged) with Gaussian jitter around each — every row was a
noisy clone of one of 8 templates. This version replaces that with a
continuous latent-variable model: every row draws its own independent
engagement level, academic level, and situational modifiers (connectivity
trouble, chattiness, introversion), so no two of the 10,000 rows share a
template and the feature space is covered far more densely.

Columns (must match StruggleFeature.rawValue in FeatureCalculator.swift):
    is_muted, time_unmuted, is_speaking, speaking_duration, camera_on,
    hand_raised, hand_raise_count, message_length, hesitation_count,
    has_question, confidence_level, missing_assignments, grade_trend,
    struggle_label
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

import pandas as pd

COLUMNS = [
    "is_muted", "time_unmuted", "is_speaking", "speaking_duration",
    "camera_on", "hand_raised", "hand_raise_count", "message_length",
    "hesitation_count", "has_question", "confidence_level",
    "missing_assignments", "grade_trend", "struggle_label",
]


def clip(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def clip_int(value: float, lo: int, hi: int) -> int:
    return int(max(lo, min(hi, round(value))))


def bernoulli(rng: random.Random, p: float) -> int:
    return 1 if rng.random() < clip(p, 0.0, 1.0) else 0


def make_row(rng: random.Random) -> dict:
    """One fully independent synthetic scenario.

    Every row draws its own continuous engagement level (e) and academic
    level (a) in 0..1, plus three independent situational modifiers that can
    apply to *either* an engaged or a struggling student:

      - tech_trouble: camera/mic look bad for reasons unrelated to how the
        student is actually doing (Scenario B's "quiet but fine" family).
      - introvert: low voice/hand-raise activity, but chat and coursework can
        still be completely healthy (Scenario C's family).
      - verbose_but_behind: talks/chats a lot while academic signals slide —
        the case a Zoom-only signal set structurally cannot catch
        (Scenario D's family).

    Because e, a, and the modifiers are each drawn independently per row from
    continuous distributions (not picked from a small fixed set of
    templates), the 10,000 rows this produces are 10,000 distinct points in
    feature space rather than noisy copies of a handful of archetypes.
    """
    # Beta(2, 2) gives a smooth, mildly bell-shaped spread over 0..1 — more
    # rows in the middle than at the extremes, matching a real classroom
    # better than a uniform draw would.
    e = rng.betavariate(2, 2)   # engagement level: 0 = totally disengaged, 1 = fully engaged
    # Academic level is mostly independent of engagement — a light 15% pull
    # toward e keeps some realistic correlation without making "talks a lot
    # but failing" rare. That pattern is exactly what a Zoom-only signal set
    # cannot see, so it needs real density in training, not just a template.
    a = clip(0.15 * e + 0.85 * rng.betavariate(2, 2) + rng.gauss(0, 0.08), 0.0, 1.0)

    tech_trouble = bernoulli(rng, 0.16)
    introvert = bernoulli(rng, 0.16)
    verbose_but_behind = bernoulli(rng, 0.22)
    if verbose_but_behind:
        # Force the academic side down into a genuinely struggling band
        # regardless of how e came out — this is the "looks fine in the
        # room, actually behind" case. Capping (not just scaling) guarantees
        # real density in exactly this corner of feature space — moderate
        # confidence/engagement alongside missing work and falling grades —
        # rather than leaving it a rare, thinly-sampled combination that a
        # tree ensemble can memorize around instead of generalizing to.
        a = clip(min(a * 0.35, 0.30), 0.0, 1.0)

    # MARK: Engagement-side features, each a noisy function of e (and the
    # situational modifiers), never a lookup from a fixed template.

    mute_prob = 1 - e
    if tech_trouble:
        mute_prob = clip(mute_prob + 0.35, 0, 1)
    is_muted = bernoulli(rng, mute_prob)

    time_unmuted_mean = (1 - mute_prob) * 1400
    time_unmuted = clip_int(rng.gauss(time_unmuted_mean, 220 + 150 * (1 - e)), 0, 1800)

    speaking_prob = e * 0.55
    if introvert:
        speaking_prob *= 0.15
    is_speaking = bernoulli(rng, speaking_prob)

    speaking_mean = e * 320
    if introvert:
        speaking_mean *= 0.1
    if verbose_but_behind:
        speaking_mean = max(speaking_mean, 200 * rng.random())
    speaking_duration = clip_int(rng.gauss(speaking_mean, 60 + 40 * e), 0, 550)

    camera_prob = 0.25 + 0.65 * e
    if tech_trouble:
        camera_prob *= 0.35
    camera_on = bernoulli(rng, camera_prob)

    hand_prob = 0.08 + 0.35 * e
    if introvert:
        hand_prob *= 0.6
    hand_raised = bernoulli(rng, hand_prob)
    hand_raise_count = clip_int(rng.gauss(e * 3.2, 1.1), 0, 7)

    message_mean = e * 35
    if introvert:
        message_mean = max(message_mean, e * 22)   # chat replaces voice
    if verbose_but_behind:
        message_mean = max(message_mean, 20 + rng.random() * 40)
    message_length = clip_int(rng.gauss(message_mean, 12), 0, 95)

    hesitation_mean = (1 - e) * 4.2
    hesitation_count = clip_int(rng.gauss(hesitation_mean, 1.4), 0, 9)

    has_question = bernoulli(rng, 0.10 + 0.35 * e)

    confidence_mean = 8 + e * 88
    confidence_level = clip_int(rng.gauss(confidence_mean, 10), 0, 100)

    # MARK: Academic-side features, functions of a, on FeatureCalculator's
    # real production scale.

    missing_mean = (1 - a) * 4.3
    missing_assignments = clip_int(rng.gauss(missing_mean, 1.0), 0, 4)
    if verbose_but_behind:
        missing_assignments = max(missing_assignments, clip_int(rng.gauss(2.5, 0.8), 2, 4))

    # grade_trend is offset by +100 in production; 100 = no change,
    # 70 = down 30%, 130 = up 30%. Centered on `a` across that range.
    grade_trend = clip_int(70 + a * 60 + rng.gauss(0, 6), 70, 130)

    # struggle_label is assigned afterward in generate(), from a proxy score
    # computed over the whole batch (see the weighting note there) — a
    # placeholder here keeps the DataFrame column present until then.
    struggle_label = 0

    return dict(
        is_muted=is_muted, time_unmuted=time_unmuted, is_speaking=is_speaking,
        speaking_duration=speaking_duration, camera_on=camera_on,
        hand_raised=hand_raised, hand_raise_count=hand_raise_count,
        message_length=message_length, hesitation_count=hesitation_count,
        has_question=has_question, confidence_level=confidence_level,
        missing_assignments=missing_assignments, grade_trend=grade_trend,
        struggle_label=struggle_label,
    )


def jittered_variant(rng: random.Random, base: dict, spread: dict) -> dict:
    """A small, randomized neighborhood around one exact scenario — distinct
    rows, not literal duplicates, but concentrated where the model needs
    dense, unambiguous coverage of a pattern the broader continuous
    population under-represents."""
    row = dict(base)
    for key, (lo, hi, jitter) in spread.items():
        row[key] = clip_int(base[key] + rng.gauss(0, jitter), lo, hi)
    return row


# Anchor patterns: dense, jittered coverage around the two production
# scenarios the continuous population thinly samples — a confidently
# "obviously struggling" profile, and the "talks a lot but failing"
# contradiction a Zoom-only signal set structurally can't see. Both are
# labelled struggling directly rather than left to the proxy threshold,
# because they exist specifically to make sure the trained model is
# unambiguous in these corners, not just directionally correct.
ANCHOR_STRUGGLING = {
    "obviously_struggling": dict(
        base=dict(
            is_muted=1, time_unmuted=5, is_speaking=0, speaking_duration=0,
            camera_on=0, hand_raised=0, hand_raise_count=0, message_length=0,
            hesitation_count=2, has_question=0, confidence_level=15,
            grade_trend=75, missing_assignments=2,
        ),
        spread=dict(
            time_unmuted=(0, 60, 8), hesitation_count=(0, 9, 1.5),
            confidence_level=(0, 30, 8), grade_trend=(70, 90, 6),
            missing_assignments=(1, 4, 0.8),
        ),
        count=250,
    ),
    "contradictory": dict(
        base=dict(
            is_muted=0, time_unmuted=200, is_speaking=1, speaking_duration=150,
            camera_on=1, hand_raised=0, hand_raise_count=2, message_length=25,
            hesitation_count=0, has_question=0, confidence_level=70,
            grade_trend=70, missing_assignments=3,
        ),
        spread=dict(
            time_unmuted=(50, 400, 60), speaking_duration=(50, 300, 40),
            message_length=(10, 60, 12), confidence_level=(50, 90, 10),
            grade_trend=(70, 88, 6), missing_assignments=(2, 4, 0.7),
        ),
        count=250,
    ),
}


def generate(n: int, target_share: float, seed: int, label_noise: float = 0.12) -> pd.DataFrame:
    """Draws features per-row (continuous, non-templated — see `make_row`),
    then assigns struggle_label from a "how struggling does this look"
    proxy computed once over the whole batch, thresholded at the
    `target_share` quantile — then flips `label_noise` of ALL labels
    (base rows and anchors alike) at random.

    Weighted so academic standing (grade_trend, missing_assignments) matters
    more than the visible engagement proxies (confidence_level, camera_on) —
    deliberately, because the entire point of a 13-feature model over the
    original 11-feature one is to catch the student who *looks* engaged
    (talking, camera on, reasonably confident) but is quietly falling behind
    on coursework. A proxy that let a high confidence_level cancel out a
    rock-bottom grade_trend would train the model to miss exactly that case
    — which is what the first version of this rebalance did, caught by
    scenario-testing the exported model against Scenario D ("contradictory")
    rather than by its held-out accuracy number, which looked fine either
    way.

    The noise step matters as much as the weighting does. Without it, the
    label is a *deterministic* function of the same features being fed to
    the model — a threshold on a linear combination of four columns — and a
    300-tree forest will reconstruct a deterministic threshold on its own
    inputs almost perfectly. That produced 97-99% held-out accuracy the
    first time through, which was a symptom, not a result: real students
    with near-identical Zoom-and-Classroom signals genuinely do end up on
    both sides of "struggling" for reasons nothing in this feature set can
    see (motivation, what's happening outside class, a rough week vs. a
    pattern). Flipping a slice of labels at random — independent of how
    "struggling" the proxy says a row looks — puts a bound on how well any
    model, however well-trained, can score here, which is the honest
    version of this dataset. Expect held-out accuracy in the 85-92% range,
    not the high-90s, and do not chase the number back up by shrinking this.
    """
    anchor_total = sum(spec["count"] for spec in ANCHOR_STRUGGLING.values())
    base_n = n - anchor_total

    # Two corrections stack here: anchor rows start pre-noise at label=1, and
    # symmetric label noise pulls an imbalanced split toward 50/50 (flipping
    # r of a p0 share nets p0 + r(1-2p0)). Solve both backward so the
    # *post-noise* share lands on `target_share`, not the pre-noise one.
    r = label_noise
    anchor_expected_struggling = anchor_total * (1 - r)
    base_target_count = n * target_share - anchor_expected_struggling
    base_target_share = clip((base_target_count / base_n - r) / (1 - 2 * r), 0.0, 1.0)

    rng = random.Random(seed)
    rows = [make_row(rng) for _ in range(base_n)]
    frame = pd.DataFrame(rows, columns=COLUMNS)

    proxy = (
        (100 - frame["confidence_level"]) * 0.20
        + (130 - frame["grade_trend"]) * 1.1
        + frame["missing_assignments"] * 12
        + (1 - frame["camera_on"]) * 8
    )
    cutoff = proxy.quantile(1 - base_target_share)
    frame["struggle_label"] = (proxy >= cutoff).astype(int)

    anchor_rows: list[dict] = []
    for spec in ANCHOR_STRUGGLING.values():
        for _ in range(spec["count"]):
            row = jittered_variant(rng, spec["base"], spec["spread"])
            row["struggle_label"] = 1
            anchor_rows.append(row)

    frame = pd.concat([frame, pd.DataFrame(anchor_rows, columns=COLUMNS)], ignore_index=True)
    frame = frame.sample(frac=1, random_state=seed).reset_index(drop=True)

    # Irreducible label noise: a fixed fraction of rows get their label
    # flipped independent of the proxy, anchors included. This is what makes
    # the "obviously struggling" and "contradictory" clusters realistically
    # ambiguous rather than a guaranteed-correct lookup table — a handful of
    # rows in each will now carry a label that contradicts their own
    # features, exactly as a real classroom would.
    flip_mask = rng.sample(range(len(frame)), k=int(round(len(frame) * label_noise)))
    frame.loc[flip_mask, "struggle_label"] = 1 - frame.loc[flip_mask, "struggle_label"]

    return frame


def validate(frame: pd.DataFrame) -> None:
    print("=" * 62)
    print("FEATURE RANGE VALIDATION")
    print("=" * 62)

    problems = []
    for column in COLUMNS:
        if column == "struggle_label":
            continue
        lo, hi = frame[column].min(), frame[column].max()
        variance = frame[column].var()
        flag = ""
        if variance == 0:
            flag = "  <-- ZERO VARIANCE, model cannot learn from this"
            problems.append(column)
        print(f"  {column:<20} min={lo:<6} max={hi:<6} var={variance:.2f}{flag}")

    gt_min, gt_max = frame["grade_trend"].min(), frame["grade_trend"].max()
    if not (70 <= gt_min and gt_max <= 130):
        problems.append("grade_trend range outside 70-130")
    ma_min, ma_max = frame["missing_assignments"].min(), frame["missing_assignments"].max()
    if not (0 <= ma_min and ma_max <= 4):
        problems.append("missing_assignments range outside 0-4")

    print(f"\ngrade_trend range:         {gt_min}-{gt_max}  "
          f"({'OK, matches FeatureCalculator 70-130' if 70 <= gt_min and gt_max <= 130 else 'OUT OF SPEC'})")
    print(f"missing_assignments range: {ma_min}-{ma_max}  "
          f"({'OK, matches 0-4 spec' if 0 <= ma_min and ma_max <= 4 else 'OUT OF SPEC'})")

    positives = int(frame["struggle_label"].sum())
    print(f"\nRows: {len(frame)}   Struggling: {positives} ({positives / len(frame):.1%})   "
          f"Engaged: {len(frame) - positives} ({(len(frame) - positives) / len(frame):.1%})")

    duplicate_feature_rows = frame.drop(columns=["struggle_label"]).duplicated().sum()
    unique_rows = len(frame) - duplicate_feature_rows
    print(f"\nDistinct feature-vectors: {unique_rows} of {len(frame)} "
          f"({unique_rows / len(frame):.1%}) — continuous per-row generation, not fixed templates")

    if problems:
        print("\nFAILED VALIDATION:")
        for p in problems:
            print(f"  - {p}")
        raise SystemExit(1)

    print("\nAll checks passed: no zero-variance features, both academic "
          "columns match FeatureCalculator.swift's production ranges.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("training_data_10k_CORRECTED.csv"))
    parser.add_argument("--n", type=int, default=10000)
    parser.add_argument("--struggling-share", type=float, default=0.30)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--label-noise", type=float, default=0.12,
        help="Fraction of labels flipped independent of the proxy score, simulating "
             "real ambiguity a features-only signal can't resolve. Do not set to 0 — "
             "see generate()'s docstring."
    )
    args = parser.parse_args()

    frame = generate(args.n, args.struggling_share, args.seed, args.label_noise)
    print(f"Label noise: {args.label_noise:.0%} of rows have a randomly-flipped label "
          f"(irreducible ambiguity, not a bug)")
    validate(frame)

    frame.to_csv(args.out, index=False)
    print(f"\nWrote {len(frame)} rows to {args.out}")


if __name__ == "__main__":
    main()
