# Canvas dependency test

**Question:** can Canvas supply the five academic features Anchor's model reads,
and can it tie them to a person in a Zoom call?

**Desk half: answered, 2026-08-17. Yes on every count, on paper.**
**Live half: not run.** It needs a real instance and there is no partner yet.
`scripts/canvas-dependency-test.py` runs it in one command when there is.

This is a spike, not a connector. Nothing here builds anything; the point is to
turn "we'd have to write a Canvas connector" from a guess into a decision. There
is still **no Canvas code in this repo** and there should not be until the live
half runs.

---

## 1. The seam a Canvas service has to fit

`ClassroomDataProviding` (`Anchor/Services/GoogleClassroomService.swift:40`) is
the whole contract. Five methods, and every one maps to a documented endpoint:

| `ClassroomDataProviding` | Canvas endpoint |
|---|---|
| `courses()` | `GET /api/v1/courses` |
| `students(courseID:)` | `GET /api/v1/courses/:id/users?enrollment_type[]=student` |
| `assignments(courseID:)` | `GET /api/v1/courses/:id/assignments` |
| `submissions(courseID:assignmentID:)` | `GET /api/v1/courses/:id/assignments/:aid/submissions` |
| `submissions(courseID:assignmentIDs:)` | `GET /api/v1/courses/:id/students/submissions` |

The last row is the one that matters for cost. That bulk endpoint is documented
as "a paginated list of all existing submissions for a given set of students and
assignments" — so Canvas, like Google, serves a whole class in one paged call
rather than N sequential round trips. The comment on the bulk method explaining
why it exists separately applies unchanged to Canvas.

## 2. The five features

| Feature | Canvas source | Note |
|---|---|---|
| `missing_assignments` | Submission `missing` (bool) | **First-class flag.** |
| `grade_average` | Submission `score` ÷ Assignment `points_possible` | |
| `grade_trend` | Same, split across ≥4 graded items | Needs `graded_at` or due order |
| `days_since_submission` | Submission `submitted_at` | |
| `late_submissions` | Submission `late` (bool) | **First-class flag.** |

Two of these are *better* on Canvas than on Google Classroom. Canvas states
`late` and `missing` directly on the submission; Classroom exposes neither, so
`GoogleClassroomService` derives both by comparing `submitted_at` against
`due_at` itself. A Canvas connector would read a fact where the Google one
infers one.

`points_possible` is the denominator everything grade-shaped rests on. It is
optional per assignment in Canvas (ungraded work has none), which is fine —
`ClassroomSubmission.fraction(maxPoints:)` already returns nil when there is no
denominator and clamps to `0...1` when there is.

## 3. Identity — the actual pass/fail criterion

**A record Anchor cannot attach to a participant in the call is worth nothing,
however complete it looks.** This is where the spike either succeeds or fails,
and it is the part the docs cannot settle.

What the User object documents:

- `login_id` — "The unique login id for the user." Always present.
- `email` — "**Optional:** This field can be requested with certain API calls."
- `sis_user_id` — "only included if the user came from a SIS import **and has
  permissions to view SIS information**."
- `name`, `short_name`, `sortable_name` — always present.

So two of the three strong keys are permission-gated and configured per
institution. That is exactly why the live half exists, and why it has to run
against **the partner's own instance** rather than a free sandbox that happens
to have permissive defaults. A token issued to a teacher may see less than one
issued to an admin; if it does, that is a finding about deployment, not a bug.

### The part that changes the calculus

Anchor's Google Classroom path has **no email at all** any more. The
`classroom.profile.emails` scope was dropped on 2026-08-17, and
`AcademicSnapshot.email` says so: *"On a normal install this is now always
nil."* Classroom matching is therefore name-based today, through
`ClassroomNameKey` and `ManualRosterLinks`.

Canvas's `login_id` is documented as always present. If it survives contact with
a real install, **Canvas identity matching would be strictly stronger than the
Google path Anchor already ships** — a stable per-user key instead of a
normalised display name. That inverts the usual assumption that the incumbent
integration is the better one, and it is worth knowing before anyone budgets
three weeks on the basis that Canvas is the compromise.

Caveat worth holding: `login_id` is a Canvas login, not necessarily an email,
and not necessarily anything a Zoom display name resembles. It is a stable key
for *joining Canvas to itself*; whether it joins Canvas to **Zoom** depends on
the institution using the same identifier in both. The script reports which keys
are present; it cannot tell you they match Zoom. That comparison needs one real
roster next to one real participant list, which is a partner-call task.

## 4. What would still be unknown after a green run

- **Whether `login_id` or `email` actually matches the Zoom display name or
  email** for the same human. See above — the script cannot answer this.
- **Rate limits.** Canvas throttles per token with a leaky bucket and returns
  `403` with `X-Rate-Limit-Remaining`. Anchor's Zoom path already has a backoff
  ladder and `PollSchedule` to hang this off, but no Canvas-specific budget has
  been measured.
- **Pagination volume at real class size.** The script follows `Link rel="next"`
  and counts, so a green run at 25 students tells you the shape; it does not
  tell you the cost at 200.
- **Whether the partner's Canvas is self-hosted.** Endpoint paths are the same;
  auth and available features may not be.

## 5. Running it

```sh
export CANVAS_BASE_URL="https://school.instructure.com"
export CANVAS_TOKEN="…"          # Account → Settings → New Access Token
./scripts/canvas-dependency-test.py            # or --course-id 1234
```

Exit `0` every required feature available · `1` something required is missing ·
`2` could not run at all.

It is read-only — GETs only, writes nothing, changes nothing — so it is safe to
run against a live course during a setup call.

**When it runs, record the answer here.** Which identity key carried it is the
single fact the connector decision turns on, and it should not live in someone's
memory of a call.
