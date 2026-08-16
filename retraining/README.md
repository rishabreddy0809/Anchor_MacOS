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

```bash
pip install pandas scikit-learn coremltools
python3 train_struggle_model.py --data labelled_sessions.csv --out StudentStruggleModel.mlmodel
```

Useful flags:

- `--engagement-only` — train on the 11 Zoom features alone.
- `--model boosted` — gradient boosting instead of logistic regression. Usually
  scores a little higher and loses per-feature attribution, which is what powers
  the "Why this score" panel.

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
python3 train_struggle_model.py --data labelled.csv --engagement-only --out /dev/null
python3 train_struggle_model.py --data labelled.csv                   --out /dev/null
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
