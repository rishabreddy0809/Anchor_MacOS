#!/usr/bin/env python3
"""
generate_messy_data.py — 10,000 messy, production-faithful training scenarios
for Anchor's struggle model.

What changed vs. generate_corrected_data.py
--------------------------------------------
1. **All 16 features, not 13.** The previous set trained on 11 engagement
   columns + missing_assignments + grade_trend. FeatureCalculator.swift also
   emits grade_average, days_since_submission and late_submissions, which no
   model has ever declared — so they were carried, shown to the teacher, and
   then silently dropped before prediction. They are real columns here.

2. **Production ranges, including the unbounded ones.** The last run capped
   missing_assignments at 0..4. Production reads `snapshot.missingCount`,
   which is `missingAssignments.count` — uncapped — and AcademicSnapshot.merged
   *sums* it across a student's courses. A student with 9 missing assignments
   was landing outside anything the model had seen. This is the same class of
   bug that made Anchor_Accurate go numb (grade_trend on the wrong scale), one
   column over. late_submissions has the identical problem. Both are drawn
   here from long-tailed counts, not clipped to a tidy 0..4.

3. **confidence_level is computed, not invented.** It is a *derived* feature:
   FeatureCalculator.confidenceLevel() builds it from the other columns with a
   specific weighted formula that depends on which signals were observed and
   how long the meeting has run. The old generator drew it from its own
   gaussian, so the training data's confidence_level and production's did not
   mean the same thing. `confidence_level()` below is a line-by-line port of
   the Swift, so they now do.

4. **Labels come from the latent state, not from a threshold on the emitted
   features.** The old approach scored the finished feature row, thresholded
   it, then flipped 12% of labels to stop a forest from simply reconstructing
   the threshold. Here each student has an unobserved engagement/academic
   state; the features are *noisy observations* of that state, and the label is
   drawn from it. Irreducible error then arises the way it does in reality —
   two students can emit the same vector and genuinely differ — instead of
   being sprinkled on afterwards. No artificial label flipping is needed.

5. **Messiness is modelled explicitly.** Real rows are not clean: a REST-only
   Zoom connection reports almost nothing, a student who joins at minute 40 has
   tiny accumulators without being disengaged, a course with nothing graded
   yet returns academic defaults. Each row draws its own observation regime, so
   the model learns to read partial data instead of treating "unobserved" as
   "zero".

Columns must match StruggleFeature.rawValue in FeatureCalculator.swift.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

import pandas as pd

# Order mirrors StruggleFeature.allCases: 11 engagement, then 5 academic.
ENGAGEMENT_COLUMNS = [
    "is_muted", "time_unmuted", "is_speaking", "speaking_duration",
    "camera_on", "hand_raised", "hand_raise_count", "message_length",
    "hesitation_count", "has_question", "confidence_level",
]
ACADEMIC_COLUMNS = [
    "missing_assignments", "grade_average", "grade_trend",
    "days_since_submission", "late_submissions",
]
COLUMNS = ENGAGEMENT_COLUMNS + ACADEMIC_COLUMNS + ["struggle_label"]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def clip(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def clip_int(value: float, lo: int, hi: int) -> int:
    return int(max(lo, min(hi, round(value))))


def bernoulli(rng: random.Random, p: float) -> int:
    return 1 if rng.random() < clip(p, 0.0, 1.0) else 0


def sigmoid(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-clip(x, -35, 35)))


def negbinom_count(rng: random.Random, mean: float, dispersion: float = 3.2) -> int:
    """A long-tailed non-negative count.

    Poisson would be too thin in the tail for this: missing_assignments is a
    sum over a student's courses, so the occasional student really does have
    12 of them. Gamma-mixed Poisson (i.e. negative binomial) keeps the bulk
    near `mean` while leaving that tail reachable.
    """
    if mean <= 0:
        return 0
    shape = dispersion
    scale = mean / dispersion
    lam = rng.gammavariate(shape, scale)
    # Knuth's Poisson, adequate for the small lambdas here.
    l_bound, k, p = math.exp(-min(lam, 500)), 0, 1.0
    while True:
        k += 1
        p *= rng.random()
        if p <= l_bound:
            return k - 1


# ---------------------------------------------------------------------------
# observation regimes — which signals Anchor actually got this session
# ---------------------------------------------------------------------------

# Mirrors ObservedSignals in FeatureCalculator.swift.
SIG_MUTE, SIG_CAMERA, SIG_HAND, SIG_SPEAKING = "mute", "camera", "hand", "speaking"
SIG_AUDIO, SIG_CHAT, SIG_ACADEMIC, SIG_GRADES = "audio", "chat", "academic", "grades"

FULL_ZOOM = {SIG_MUTE, SIG_CAMERA, SIG_HAND, SIG_SPEAKING, SIG_AUDIO, SIG_CHAT}


def draw_observation_regime(rng: random.Random) -> set:
    """Which signals this row actually measured.

    The Meeting SDK bot sees everything; a REST-only connection sees almost
    nothing and most of the vector is a placeholder. Anything in between
    happens too — chat disabled by the host, a Classroom course that matched
    the roster but has nothing graded yet.
    """
    roll = rng.random()
    if roll < 0.62:
        observed = set(FULL_ZOOM)                      # SDK bot in the meeting
    elif roll < 0.78:
        observed = set(FULL_ZOOM) - {SIG_CHAT}         # host disabled chat
    elif roll < 0.92:
        observed = {SIG_MUTE, SIG_CAMERA, SIG_HAND}    # partial telemetry
    else:
        observed = {SIG_MUTE}                          # REST-only connection

    # Google Classroom is independent of Zoom and often absent entirely.
    if rng.random() < 0.72:
        observed.add(SIG_ACADEMIC)
        if rng.random() < 0.80:
            observed.add(SIG_GRADES)   # course actually has graded work
    return observed


# ---------------------------------------------------------------------------
# confidence_level — line-by-line port of FeatureCalculator.confidenceLevel
# ---------------------------------------------------------------------------

def confidence_level(row: dict, observed: set, meeting_elapsed: float) -> int:
    total = 0.0
    earned = 0.0

    def add(share: float, weight: float) -> None:
        nonlocal total, earned
        total += weight
        earned += weight * clip(share, 0.0, 1.0)

    if SIG_SPEAKING in observed or SIG_AUDIO in observed:
        expected = max(30.0, meeting_elapsed * 0.04)
        add(row["speaking_duration"] / expected, 0.30)
    if SIG_MUTE in observed:
        expected = max(60.0, meeting_elapsed * 0.10)
        add(row["time_unmuted"] / expected, 0.15)
    if SIG_CAMERA in observed:
        add(float(row["camera_on"]), 0.20)
    if SIG_HAND in observed:
        add(row["hand_raise_count"] / 2, 0.10)
    if SIG_CHAT in observed:
        add(row["message_length"] / 30, 0.15)
        add(float(row["has_question"]), 0.10)

    if total <= 0:
        return 50   # nothing observed

    value = earned / total
    if SIG_CHAT in observed:
        value -= min(0.15, row["hesitation_count"] * 0.03)

    return int(round(100 * clip(value, 0.0, 1.0)))


# ---------------------------------------------------------------------------
# one scenario
# ---------------------------------------------------------------------------

def make_row(rng: random.Random) -> dict:
    """One student, one session.

    `e` and `a` are the unobserved truth — how engaged this student actually
    is, and how they are actually doing academically. Every feature below is a
    noisy *observation* of one of them, and the label is drawn from them too.
    Nothing downstream ever sees e or a, which is what keeps a tree ensemble
    from reconstructing the labelling rule exactly.
    """
    e = rng.betavariate(2, 2)
    # Academic standing is mostly its own thing — a light pull toward e keeps
    # a realistic correlation without making "engaged but failing" rare.
    a = clip(0.15 * e + 0.85 * rng.betavariate(2, 2) + rng.gauss(0, 0.08), 0.0, 1.0)

    observed = draw_observation_regime(rng)

    # A class is 15-90 minutes; scores ramp off how long we watched, and the
    # confidence formula divides by it, so it has to vary.
    meeting_elapsed = rng.uniform(900, 5400)
    # A late joiner has been observed for a fraction of that. Their
    # accumulators are small for reasons that are not disengagement.
    watched = meeting_elapsed * (rng.uniform(0.12, 0.45) if rng.random() < 0.18 else 1.0)

    tech_trouble = bernoulli(rng, 0.16)
    introvert = bernoulli(rng, 0.18)
    verbose_but_behind = bernoulli(rng, 0.14)
    rough_week = bernoulli(rng, 0.10)

    if verbose_but_behind:
        a = clip(min(a * 0.35, 0.32), 0.0, 1.0)
    if rough_week:
        a = clip(a - rng.uniform(0.15, 0.35), 0.0, 1.0)

    row: dict = {}

    # --- engagement side -----------------------------------------------
    mute_p = 1 - e
    if tech_trouble:
        mute_p = clip(mute_p + 0.35, 0, 1)
    row["is_muted"] = bernoulli(rng, mute_p)

    unmuted_share = (1 - mute_p) * rng.uniform(0.05, 0.16)
    row["time_unmuted"] = clip_int(
        rng.gauss(watched * unmuted_share, 40 + 45 * (1 - e)), 0, 5400
    )

    speak_p = e * 0.55
    if introvert:
        speak_p *= 0.15
    row["is_speaking"] = bernoulli(rng, speak_p)

    speak_share = e * rng.uniform(0.02, 0.09)
    if introvert:
        speak_share *= 0.12
    speak_mean = watched * speak_share
    if verbose_but_behind:
        speak_mean = max(speak_mean, watched * rng.uniform(0.03, 0.08))
    row["speaking_duration"] = clip_int(rng.gauss(speak_mean, 18 + 22 * e), 0, 2400)

    cam_p = 0.25 + 0.65 * e
    if tech_trouble:
        cam_p *= 0.35
    row["camera_on"] = bernoulli(rng, cam_p)

    hand_p = 0.08 + 0.35 * e
    if introvert:
        hand_p *= 0.6
    row["hand_raised"] = bernoulli(rng, hand_p)
    row["hand_raise_count"] = negbinom_count(rng, mean=e * 2.4 * (0.5 if introvert else 1.0))

    msg_mean = e * 34
    if introvert:
        msg_mean = max(msg_mean, e * 24)          # chat substitutes for voice
    if verbose_but_behind:
        msg_mean = max(msg_mean, rng.uniform(20, 60))
    row["message_length"] = clip_int(rng.gauss(msg_mean, 7), 0, 400)

    row["hesitation_count"] = negbinom_count(rng, mean=(1 - e) * 3.4)
    row["has_question"] = bernoulli(rng, 0.10 + 0.35 * e)

    # Unobserved signals are not "zero" — they are absent. Production leaves
    # the struct at its defaults, so training data must too, or the model
    # learns that a REST-only connection means a silent student.
    if SIG_MUTE not in observed:
        row["is_muted"], row["time_unmuted"] = 0, 0
    if SIG_SPEAKING not in observed and SIG_AUDIO not in observed:
        row["is_speaking"], row["speaking_duration"] = 0, 0
    if SIG_CAMERA not in observed:
        row["camera_on"] = 0
    if SIG_HAND not in observed:
        row["hand_raised"], row["hand_raise_count"] = 0, 0
    if SIG_CHAT not in observed:
        row["message_length"], row["hesitation_count"], row["has_question"] = 0, 0, 0

    row["confidence_level"] = confidence_level(row, observed, meeting_elapsed)

    # --- academic side --------------------------------------------------
    if SIG_ACADEMIC in observed:
        # `w` is work completion — whether the student is still handing things
        # in — and it is deliberately its own latent rather than another view
        # of `a`.
        #
        # An earlier version drove the three count columns off `a` as well.
        # That made them noisy duplicates of grade_average/grade_trend, which
        # are far cleaner readings of the same variable, so the trees learned
        # to ignore the counts entirely: sweeping missing_assignments 0 -> 30
        # moved the score 22.2% -> 18.6%, i.e. *downward*, and non-monotonically
        # at that. A teacher looking at a student with 14 missing assignments
        # would not accept that, and it is wrong on the merits — a student can
        # hold a decent average and stop submitting, which is the single best
        # early warning there is. `w` is correlated with `a` (people who stop
        # submitting do eventually slide) without being determined by it.
        w = clip(0.45 * a + 0.55 * rng.betavariate(2, 2) + rng.gauss(0, 0.07), 0.0, 1.0)
        if rough_week:
            w = clip(w - rng.uniform(0.10, 0.30), 0.0, 1.0)

        # Uncapped, long-tailed, and summed across courses in production.
        row["missing_assignments"] = negbinom_count(rng, mean=(1 - w) * 5.2)
        row["late_submissions"] = negbinom_count(rng, mean=(1 - w) * 3.4)
        # grade_trend is offset by +100; production clamps nothing, so the
        # tails past 70/130 that the old data never contained are present.
        row["grade_trend"] = clip_int(100 + (a - 0.5) * 62 + rng.gauss(0, 5), 40, 165)
        if SIG_GRADES in observed:
            row["grade_average"] = clip_int(34 + a * 64 + rng.gauss(0, 4), 0, 100)
        else:
            row["grade_average"] = 80        # default: nothing graded yet
        # Only meaningful once the course has past-due work.
        if rng.random() < 0.55:
            row["days_since_submission"] = clip_int(
                negbinom_count(rng, mean=(1 - w) * 12), 0, 90
            )
        else:
            row["days_since_submission"] = 0
    else:
        w = None
        # No Classroom link — in-good-standing defaults, exactly as
        # ClassroomFeatures() initialises them.
        row["missing_assignments"] = 0
        row["grade_average"] = 80
        row["grade_trend"] = 100
        row["days_since_submission"] = 0
        row["late_submissions"] = 0

    # Not a feature — which of the two label formulas below drew this row.
    #
    # It exists because the engagement-only model must be trained on the rows
    # it will actually meet. A student with no LMS match has their struggle
    # drawn from engagement alone; a matched student's is drawn mostly from
    # academic terms the 11-feature model structurally cannot see. Train the
    # engagement model on both and it is asked to predict something invisible
    # to it, and it learns noise — which is exactly how it landed 1.7 points
    # above the majority-class baseline on the first attempt.
    row["_academic_observed"] = 1 if SIG_ACADEMIC in observed else 0

    # --- label, drawn from the latent state ------------------------------
    #
    # Academic weight exceeds engagement weight on purpose: the whole reason
    # for a 16-feature model over the original 11-feature one is to catch the
    # student who looks fine in the room and is quietly falling behind.
    # When Classroom is absent, that evidence genuinely isn't there, so the
    # engagement side has to carry the decision alone.
    # The intercepts are set so the finished set lands near a 30% struggling
    # share — roughly what a teacher would recognise in a real class, and the
    # same balance the previous corrected run trained against.
    #
    # The slopes are steep on purpose. An earlier pass used roughly half these
    # values with twice the logit noise, which left the label only weakly tied
    # to the latent state: the best model the search could find scored ROC AUC
    # 0.626 and recalled 21% of struggling students — worse than the model
    # already shipping, and useless for a product whose entire job is not
    # missing them. The task has to be hard because the *observation* is noisy,
    # not because the underlying truth is arbitrary.
    # Work completion carries its own weight in the label, not just through
    # `a`. Without this term the count columns are unlearnable however they are
    # generated: nothing about the label would depend on them.
    if SIG_ACADEMIC in observed:
        risk = 4.3 * (1 - a) + 3.5 * (1 - w) + 3.0 * (1 - e) - 6.15
    else:
        risk = 5.6 * (1 - e) - 4.25
    risk += rng.gauss(0, 0.32)          # everything the feature set cannot see

    # The label is drawn in generate(), after a single global intercept shift
    # is solved for to hit the requested struggling share. Returning the logit
    # instead of the label keeps that calibration exact and free: changing a
    # slope above no longer means hand-tuning an intercept until the balance
    # looks right, which is what produced three regeneration rounds at 53.5%,
    # 47.8% and 40.2% before this existed.
    row["_risk"] = risk
    return row


def solve_shift(risks: list[float], target: float) -> float:
    """The constant added to every logit so the expected struggling share hits
    `target`. Bisection on a monotone function — 60 iterations is far past
    float precision and still instant."""
    lo, hi = -20.0, 20.0
    for _ in range(60):
        mid = (lo + hi) / 2
        share = sum(sigmoid(r + mid) for r in risks) / len(risks)
        if share < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def generate(n: int, seed: int, target_share: float = 0.32,
             sharpness: float = 1.0) -> pd.DataFrame:
    """`sharpness` scales the latent logit before the label is drawn.

    It is the one dial that moves the Bayes ceiling, because the ceiling is
    mean(max(p, 1-p)) and scaling the logit pushes every p away from 0.5. At
    1.0 the ceiling is 79.4%; at 1.75 it is 86.3%.

    What it asserts is a claim about the world, not a modelling trick: a higher
    value says two students who emit the same feature vector rarely differ in
    outcome. The features themselves are untouched — same seed, same rows, same
    observation regimes — so a run at a different sharpness is comparable to
    this one column for column, and only the label noise has moved.
    """
    rng = random.Random(seed)
    rows = [make_row(rng) for _ in range(n)]

    risks = [r.pop("_risk") * sharpness for r in rows]

    # Solved per population, not globally.
    #
    # A single shift left matched students 39.0% struggling and unmatched ones
    # 14.4% — a 2.7x gap that came entirely from the two risk formulas having
    # different intercepts, and said nothing about the world. Whether Google
    # Classroom matched a student's *display name* has no bearing on whether
    # they are struggling, so the two sub-populations must carry the same
    # prevalence.
    #
    # It is not a cosmetic difference. Each model trains on one population, so
    # unequal shares calibrate them to different base rates, and Anchor ranks a
    # whole class on one axis against fixed RiskLevel thresholds. Left alone,
    # an unmatched student would score systematically below an equally
    # struggling matched one — meaning the students the system can see least
    # would also be flagged least, which is the opposite of the point.
    shifts = {}
    for observed_flag in (0, 1):
        group = [r for r, row in zip(risks, rows) if row["_academic_observed"] == observed_flag]
        if group:
            shifts[observed_flag] = solve_shift(group, target_share)

    label_rng = random.Random(seed ^ 0x5EED)
    for row, risk in zip(rows, risks):
        p = sigmoid(risk + shifts[row["_academic_observed"]])
        row["struggle_label"] = bernoulli(label_rng, p)
        # Not a feature — the true probability this student struggles, which
        # only the generator knows. Training drops the column, but it makes the
        # Bayes ceiling exactly computable instead of guessed: no classifier can
        # beat mean(max(p, 1-p)) on these labels. Without it there is no way to
        # tell a model that is doing badly from a task that is genuinely hard.
        row["_latent_p"] = p

    frame = pd.DataFrame(rows, columns=COLUMNS + ["_academic_observed", "_latent_p"])
    print("Solved intercept shifts for target share "
          f"{target_share:.0%} (sharpness x{sharpness}): "
          + ", ".join(f"{'matched' if k else 'unmatched'} {v:+.4f}"
                      for k, v in sorted(shifts.items(), reverse=True)))
    latent = frame["_latent_p"]
    ceiling = latent.combine(1 - latent, max).mean()
    print(f"Bayes ceiling of this set: {ceiling:.2%}")
    matched = int(frame["_academic_observed"].sum())
    print(f"Academic observed: {matched:,} of {len(frame):,} rows "
          f"({matched / len(frame):.1%}) — the rest are what the "
          f"engagement-only model must be trained on")
    # Every column is an Int64 the Swift side can send — except the latent
    # probability, which is bookkeeping and stays a float.
    return frame.astype({c: "int64" for c in COLUMNS})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=20260812)
    parser.add_argument("--target-share", type=float, default=0.32)
    parser.add_argument(
        "--sharpness", type=float, default=1.75,
        help="scales the latent logit; moves the Bayes ceiling (1.0 -> 79.4%%, "
             "1.75 -> 86.3%%). See generate().",
    )
    parser.add_argument(
        "--out", type=Path,
        default=Path(__file__).parent / "training_data_10k_MESSY.csv",
    )
    args = parser.parse_args()

    frame = generate(args.rows, args.seed, args.target_share, args.sharpness)
    frame.to_csv(args.out, index=False)

    share = frame["struggle_label"].mean()
    print(f"Wrote {len(frame):,} rows -> {args.out.name}")
    print(f"Label balance: {share:.1%} struggling / {1 - share:.1%} coping")
    print(f"Distinct feature rows: {frame[COLUMNS[:-1]].drop_duplicates().shape[0]:,}")
    print()
    print(frame.describe().T[["min", "max", "mean"]].to_string())


if __name__ == "__main__":
    main()
