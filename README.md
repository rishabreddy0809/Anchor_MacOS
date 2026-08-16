# Anchor

**See what your students aren't saying.**

Anchor is a macOS menu bar app that detects struggling students in real time
during Zoom classes — while the teacher can still do something about it.

In an online class, the student who is lost is the one who goes quiet. They
don't unmute, they don't raise a hand, they don't type in chat. The signal that
they need help is an *absence* of signals, which is exactly what a teacher
managing thirty tiles cannot see. Anchor watches for that absence and surfaces
it, with a specific question to ask the specific student.

---

## How it works

### Two signal sources, one score

**Live Zoom behavior.** Anchor connects through teacher OAuth and, where
permitted, a meeting bot, then polls participant state: mute status, cumulative
unmuted time, speaking duration, camera on/off, hand raises, chat message
length, hesitation markers, and whether the student has asked a question.

Zoom reports only *current* state, so the accumulator-type features
(`time_unmuted`, `hand_raise_count`) are integrated across polls by
`StruggleSignalHistory` rather than read instantaneously.

**Google Classroom.** Missing assignments, grade average, grade trend, days
since last submission, late submissions.

Those become a 16-feature vector, scored on-device by a Core ML random forest
(600 trees). The output is a struggle probability mapped to three levels:

| Level | Threshold | Meaning |
|---|---|---|
| Engaged | < 0.40 | No action needed |
| Watch | ≥ 0.40 | Worth checking on |
| Needs attention | ≥ 0.70 | Intervene now |

A sensitivity slider shifts both cut-offs by up to ±0.15.

### It tells you what to do, not just who

`RecommendationGenerator` turns *"this student is disengaged"* into *"ask this
student this question."* Three inputs, combined in a deliberate order:

- **The engagement score** decides *whether* a student is worth naming, and how
  urgently. It is the only input that can put someone on the list.
- **The live lesson topic**, pulled from transcript capture, decides what to ask
  about.
- **The student's historical weakness on that topic** decides what to say about
  why — and breaks ties between two equally disengaged students.

Topic weakness deliberately never changes the *urgency*. A card reading "high"
beside a student row reading "watch" would be two verdicts about one child.

Apple's Foundation Models write the phrasing. When the model is unavailable,
refuses, or times out, a deterministic fallback states the same facts in
Anchor's own voice — the feature degrades in phrasing quality, never in
correctness.

### It shows its work

Every score comes with a **Why this score** panel that attributes the
probability to individual features by measuring each one's actual contribution
against the loaded model, rather than asserting a hand-written rule:

```
Camera off              (medium weight)
Hasn't spoken in 18m    (high weight)
3 missing assignments   (medium weight)
```

Derived features are excluded from attribution on purpose. Telling a teacher
"the score is high because the confidence number is low" only restates the
score.

---

## Model performance

Held-out test set, 2,000 rows unseen during fit and hyperparameter search:

| Metric | Value |
|---|---|
| Majority-class baseline | 67.90% |
| **Accuracy** | **75.40%** |
| ROC AUC | 0.8044 |
| Precision (struggling) | 65.50% |
| Recall (struggling) | 49.38% |
| Brier score | 0.1626 |
| Estimated Bayes ceiling | 79.50% |

The baseline column matters more than the accuracy column. Struggling students
are the minority class, so a model that answers "coping" every time scores 67.9%
and is worthless. The Bayes ceiling is exact — it comes from the data
generator's latent probability — so the real headroom left is 4.1 points, not
24.6.

### Why the default threshold favors recall

| Threshold | Precision | Recall | Flagged |
|---|---|---|---|
| 0.25 — Watch, max sensitivity | 51.5% | 84.9% | 52.9% |
| **0.40 — Watch (default)** | **61.8%** | **64.5%** | **33.5%** |
| 0.70 — Needs attention (default) | 78.5% | 17.6% | 7.2% |
| 0.85 — Needs attention, min sensitivity | 95.2% | 3.1% | 1.1% |

A missed struggling student is the failure this product exists to prevent. A
false alarm costs a teacher one question. The default operating point is the
recall-favoring one for that reason.

### Feature importance

```
grade_trend              0.3277  ← academic
grade_average            0.2117  ← academic
confidence_level         0.0854
time_unmuted             0.0721
missing_assignments      0.0572  ← academic
message_length           0.0470
late_submissions         0.0404  ← academic
speaking_duration        0.0386
days_since_submission    0.0354  ← academic
hesitation_count         0.0257
```

The academic signals carry the model — together they account for roughly 54% of
importance. Live Zoom behavior contributes meaningfully but is not the dominant
term, which is worth knowing before trusting a score from a class where
Classroom isn't connected.

### Training data

The model is trained on **10,000 synthetic rows** from `retraining/generate_messy_data.py`.
No real classroom has labeled a dataset for this. The generator is built to make
that synthetic origin as harmless as possible:

- Each student has an unobserved engagement/academic state. Features are *noisy
  observations* of it, and the label is drawn from the state — so irreducible
  error arises the way it does in reality, instead of being sprinkled on
  afterwards via label flipping.
- Feature ranges are validated against `FeatureCalculator.swift` at training
  time, including the genuinely unbounded ones (`missing_assignments` and
  `late_submissions` are summed across a student's courses and are not clipped).
- `confidence_level` is a line-by-line port of the Swift `confidenceLevel()`
  function, not an independent draw, so the column means the same thing in
  training and production.
- Every row draws its own observation regime — a REST-only Zoom connection
  reports almost nothing, a student joining at minute 40 has small accumulators
  without being disengaged — so the model learns to read partial data rather
  than treating "unobserved" as "zero".

`retraining/` contains the full pipeline for retraining on real labeled sessions
once they exist. Anchor exports labelable rows via
**Settings → Class history → Export Training Data…**; the `struggle` column has
to be filled in by the teacher, because deriving it from Anchor's own prediction
would just train the next model to agree with this one.

---

## Privacy

- **On-device inference.** Scores are computed locally by Core ML. No
  engagement data leaves the teacher's Mac.
- **No facial recognition.** The model never receives video. It reads Zoom's
  participant metadata only.
- **No student install.** Everything runs from the teacher's machine.
- **Credentials live only in the macOS Keychain.** No secret is stored in this
  repository, and `.gitignore` enforces it. Refresh tokens rotate on every use.

## Requirements

- macOS 26.5 or later
- A Zoom account, and a Zoom Marketplace app (setup in [`ZOOM_INTEGRATION.md`](ZOOM_INTEGRATION.md))
- Google Classroom, optional — Anchor runs on Zoom signals alone, with reduced
  accuracy

> **Zoom authorization is currently limited.** The Marketplace app is
> unpublished, so only the developer's own Zoom account can authorize it. See
> [`ZOOM_INTEGRATION.md`](ZOOM_INTEGRATION.md) §2a for the school-account route
> that lifts this for a pilot.

## Layout

```
Anchor/
  App/            Menu bar shell — status item, popover routing, app delegate
  Models/         Domain types: Student, Classroom, RiskLevel, StruggleFactor
  Services/       Zoom, Google Classroom, transcript capture, scoring, ML
    OAuth/        PKCE, loopback redirect listener, URL scheme handling
  Views/          SwiftUI — popover, main window, onboarding, settings
  DesignSystem/   Theme tokens
  Data/           Local persistence: engagement history, session archive
  Utils/          Keychain, constants, diagnostics
retraining/       Data generation, training, and evaluation pipeline
Web/              OAuth redirect bounce page
website/landing/  Marketing site
scripts/          Dev and provisioning helpers
```

## Documentation

- [`ZOOM_INTEGRATION.md`](ZOOM_INTEGRATION.md) — what Anchor can and cannot see
  through Zoom, and full Marketplace app setup
- [`retraining/README.md`](retraining/README.md) — retraining on real labeled
  sessions, and how to read the output honestly

---

Built by Rishab Reddy Paili.
