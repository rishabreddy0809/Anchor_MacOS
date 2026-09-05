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
correctness. Below macOS 26 the framework does not exist at all, so on most
Macs the fallback is the ordinary path rather than the exception. That is the
whole reason it has to carry the same facts and not a thinner set of them.

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
| Majority-class baseline | 67.70% |
| **Accuracy** | **81.10%** |
| ROC AUC | 0.8676 |
| Precision (struggling) | 74.19% |
| Recall (struggling) | 63.62% |
| F1 (struggling) | 0.685 |
| Brier score | 0.1343 |
| Estimated Bayes ceiling | 86.20% |

Gradient boosting, selected over random forest by a 220-candidate,
5-fold cross-validated search.

The baseline column matters more than the accuracy column. Struggling students
are the minority class, so a model that answers "coping" every time scores 67.7%
and is worthless. The Bayes ceiling is exact — it comes from the data
generator's latent probability — so the real headroom left is 5.1 points, not
18.9.

### Why the default threshold favors recall

| Threshold | Precision | Recall | Flagged |
|---|---|---|---|
| 0.25 — Watch, max sensitivity | 60.9% | 82.8% | 44.0% |
| **0.40 — Watch (default)** | **70.0%** | **71.1%** | **32.8%** |
| 0.70 — Needs attention (default) | 79.4% | 44.1% | 17.9% |
| 0.85 — Needs attention, min sensitivity | 89.5% | 22.4% | 8.1% |

A missed struggling student is the failure this product exists to prevent. A
false alarm costs a teacher one question. The default operating point is the
recall-favoring one for that reason.

### Feature importance

```
grade_trend              0.4478  ← academic
grade_average            0.1949  ← academic
confidence_level         0.0810
time_unmuted             0.0479
missing_assignments      0.0451  ← academic
message_length           0.0346
late_submissions         0.0282  ← academic
is_muted                 0.0274
hesitation_count         0.0259
days_since_submission    0.0230  ← academic
```

The academic signals carry the model — the five Classroom columns are about 74%
of total importance, and `grade_trend` alone is 45%. Live Zoom behavior
contributes meaningfully but is nowhere near the dominant term. That is worth
knowing before trusting a score from a class where Classroom isn't connected:
without it the model is running on roughly a quarter of the signal it was
trained to weigh.

### Training data

The model is trained on **10,000 synthetic rows** from `retraining/generate_messy_data.py`.
No real classroom has labeled a dataset for this.

> **On the 81.1% figure.** An earlier run of this model scored 75.4% against a
> 79.5% ceiling. The gain since is mostly *not* a better model — the generator
> gained a `--sharpness` dial that scales the latent logit before the label is
> drawn, which pushes each row's probability away from 0.5 and raises the
> ceiling to 86.2%. In plain terms it asserts that two students emitting the
> same feature vector rarely differ in outcome. Features are untouched: same
> seed, same rows, same observation regimes. So the task got easier by
> assumption, and the honest comparison is the *gap to ceiling* — 5.1 points,
> versus 4.1 before. Whether real classrooms are that separable is exactly the
> thing only real labelled data can answer.

The generator is built to make
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
- **Session history expires.** `SessionArchive` keeps one term (120 days) by
  default — one school year and "keep everything" are the alternatives, under
  **Settings → Data & Privacy**. It prunes on load, when a class ends, and
  immediately when the window is shortened, and Anchor's own leftover sidecars
  (`session-archive.corrupt-*`, `session-archive.backup-*`) age out on the same
  schedule rather than outliving the records they were copied from.

## Requirements

- macOS 14.0 or later
- A Zoom account, and a Zoom Marketplace app (setup in [`ZOOM_INTEGRATION.md`](ZOOM_INTEGRATION.md))
- Google Classroom, optional — Anchor runs on Zoom signals alone, with reduced
  accuracy

> **Why 14.0.** The deployment target was 26.5 until 2026-08-17, for exactly one
> reason: `FoundationModelAnalyzer` referenced FoundationModels unconditionally,
> so an optional phrasing feature set the floor for the entire app. It is now
> behind `@available(macOS 26.0, *)`, with `#available` checks at its three entry
> points, and the framework's own floor applies to the phrasing and nothing else.
> The vendored Zoom SDK asks only for 10.15. macOS 13 stays out of reach for a
> separate reason — a handful of SwiftUI APIs newer than it.
> `ContentUnavailableView`, `SettingsLink`, the two-argument `onChange`,
> `symbolEffect` and `variableColor` need 14.0; `scrollBounceBehavior` needs
> 13.3. Reaching 13.0 is a UI rewrite rather than a build setting, and nothing
> below 13.3 is reachable at all.

> **Live behavior needs the bot on most plans.** The two participant scopes are
> Dashboard/Report scopes, and Zoom only offers those to Business, Education and
> Enterprise accounts — on anything smaller they cannot be added to the
> Marketplace app at all, so the REST path never returns a participant list and
> the meeting bot is the only source of live engagement signal. See
> [`ZOOM_INTEGRATION.md`](ZOOM_INTEGRATION.md) §2a.

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
AnchorTests/      XCTest target — score shaping and the RiskLevel thresholds
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

Contributed to by Rishab Reddy Paili and Aariz Khan.
