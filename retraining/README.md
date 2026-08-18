# Retraining the struggle model

The shipped model reads 11 Zoom engagement features. This directory retrains it
on 16 — the same 11 plus 5 from Google Classroom — so academic signals become
part of the prediction instead of a rule bolted on top of it.

## Why it matters that this happens

Until a 16-feature model exists, `AcademicEscalation` adds academic risk with
hand-written rules. Those rules are visible to the teacher and bounded at +0.20,
but they are judgement, not learning. Retraining replaces them: once the loaded
model declares the academic columns,
`StruggleDetectionService.usesAcademicFeatures` returns true and the escalation
switches itself off automatically. No Swift change is needed.

## 1. Collect labelled data

During a class, **Settings → Class history → Export Training Data…** writes one
row per student with all 16 features, Anchor's own score, and an empty
`struggle` column.

Fill that column in afterwards — `1` for students who were genuinely
struggling, `0` for those who weren't. This is the part that cannot be
automated. The label has to be the teacher's judgement; deriving it from
Anchor's own prediction would just train the next model to agree with this one.

Concatenate exports from several classes into one CSV. Keep the header row once.

### How much is enough

| Rows | What you can honestly say |
|---|---|
| < 200 | Nothing. Treat the output as a smoke test. |
| 200–1000 | Whether the model beats the majority-class baseline. |
| 1000+ | A cautious accuracy comparison, with a confidence interval. |

The script warns you when you are below these lines. The scarce resource is
labelled *struggling* students, not rows — a class of 28 with two struggling
students contributes two useful positive examples.

## 2. Train

**Use `.venv/bin/python`, not `python3`.** The system interpreter has none of
the dependencies and fails at the first import; the checked-in venv already has
pandas, scikit-learn and coremltools.

**Use `train_production_model.py`, not `train_struggle_model.py`.** The older
script pairs with `generate_corrected_data.py`, which emits only 13 columns —
the 11 engagement ones plus `missing_assignments` and `grade_trend`. The other
three academic columns `FeatureCalculator` produces are simply absent from that
data, so a model trained on it can never declare them.

```bash
.venv/bin/python train_production_model.py \
    --data labelled_sessions.csv --out StudentStruggleModel_16.mlmodel
```

Useful flags:

- `--engagement-only` — train on the 11 Zoom features alone. This is how the
  no-LMS model is built; see "Two models" below.
- `--iterations N` — size of the hyperparameter search. The default of 220 takes
  roughly 13 minutes on 50k rows, so this is not a thing to run casually while
  waiting for it.

### Generating synthetic rows

`generate_messy_data.py` is the current generator and takes `--rows`, not `--n`:

```bash
.venv/bin/python generate_messy_data.py --rows 50000 --out training_50k.csv
```

It emits all 16 features at production ranges, including the uncapped ones
(`missing_assignments` and `late_submissions` are raw counts summed across a
student's courses, so clipping them to 0..4 puts real students outside anything
the model has seen). `generate_corrected_data.py` is the superseded 13-column
version — it is kept for provenance and should not be used for new runs.

Synthetic rows are for smoke-testing the pipeline. They cannot tell you anything
about real accuracy: every number they produce is a property of the generator,
so a figure from them must never be quoted as a validation result.

## Two models: with and without an LMS

Anchor ships **two** models, not one, and not three.

| Model | Features | Loaded when |
|---|---|---|
| `StudentStruggleModel_16` | 11 engagement + 5 academic | the student was matched in Classroom or Canvas |
| `StudentStruggleModel_11` | 11 engagement | no LMS connected, or this student did not match |

### Why not three

Because Canvas and Google Classroom produce the *same five columns*. Both land in
`AcademicSnapshot` and are mapped by `FeatureCalculator.extractClassroomFeatures`,
so the model never learns which LMS the numbers came from. A Canvas connector is
a data source swap behind `ClassroomDataProviding`, not a second academic
feature set — so there is no Canvas-specific model to train.

### Why not one

Because the academic columns have benign defaults, and a 16-feature model cannot
tell a default from a measurement. A student who did not match the roster carries
`grade_average = 80` and `grade_trend = 100` — the values of a student in good
standing, invented because there was nothing to read. Scoring them with the
16-feature model reads those inventions as evidence on the columns that carry
most of its weight, and quietly reports a struggling student as fine.

This is the same "zero versus unknown" distinction `ObservedSignals` exists to
preserve everywhere else in the pipeline, reappearing at the model boundary.

### The selection is per student, not per launch

Not "is Classroom connected" — **`features.observed.contains(.academic)`**, which
is per student, per poll. In one class with Classroom connected, some students
match the roster and some do not (matching runs on normalised display names since
the `classroom.profile.emails` scope was dropped). Both models therefore have to
be resident at once, and the choice made inside the prediction call.

## 3. Read the output honestly

The script prints an **always-'coping' baseline** next to the model's accuracy.
Compare against it, always. Struggling students are the minority class, so a
model that answers "coping" every time can score 85%+ and be worthless.

It also splits **by student** rather than by row when an `identity_key` column
is present. Twelve rows from the same student are not twelve independent
samples; splitting them randomly leaks information across the split and inflates
the score. Expect the honest number to be lower than the leaky one.

The number to watch is **recall on `struggling`**. A missed struggling student
is the failure this product exists to prevent. A false alarm costs a teacher one
question.

## 4. Did Classroom data actually help?

Run the script twice on the same CSV:

```bash
.venv/bin/python train_production_model.py --data labelled.csv --engagement-only --out /dev/null
.venv/bin/python train_production_model.py --data labelled.csv                   --out /dev/null
```

The difference between those two runs is the only evidence that supports a claim
about what Classroom data added. Do not quote a figure like "97% → 98.5%"
without it — and not without a test set big enough that the difference exceeds
the margin of error, which at 120 test rows is roughly ±10 points.

## 5. Install the model

Drag the `.mlmodel` into the Anchor target in Xcode ("Copy items if needed").
`StruggleDetectionService` finds it by name or by feature match, so nothing else
needs to change. Confirm on next launch that the log line under subsystem
`com.anchor.coreml` reports 16 declared inputs, 5 academic.

## Note on macOS warnings

numpy 2.0 built against Accelerate emits spurious `encountered in matmul`
warnings from valid matrix products. The script filters that exact message and
nothing else. If you see other numerical warnings, they are real.
