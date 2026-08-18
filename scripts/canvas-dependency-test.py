#!/usr/bin/env python3
#
# canvas-dependency-test.py — can Canvas supply what Anchor's academic half needs?
#
# This is the live half of the Canvas dependency test. The desk half — mapping
# every method and field to a documented Canvas endpoint — is written up in
# CANVAS_SPIKE.md and is already done; the docs say yes to everything. What the
# docs cannot tell you is what a *particular* institution's Canvas actually
# returns, because the two fields Anchor's identity matching depends on are
# permission-gated and are configured per install.
#
# So this script exists to be run once, against the partner's own instance,
# with a token issued by an account that has the access a real deployment would
# have. It answers one question per feature and prints a verdict. It writes
# nothing, changes nothing, and touches only GET endpoints.
#
# WHY A SCRIPT RATHER THAN A SWIFT TEST
#
# It needs a network, a token and somebody else's data, so it can never run in
# `xcodebuild test` alongside the 193 tests that do. Keeping it out of the suite
# keeps the suite hermetic. Keeping it in the repo means the spike is a command
# rather than a day's work rediscovering which endpoints matter.
#
# USAGE
#
#   export CANVAS_BASE_URL="https://school.instructure.com"
#   export CANVAS_TOKEN="…"                 # Account → Settings → New Access Token
#   ./scripts/canvas-dependency-test.py [--course-id 1234]
#
# With no --course-id it picks the first active course the token can see.
#
# EXIT CODES
#   0  every required feature is available
#   1  at least one required feature is missing — the connector would ship broken
#   2  could not run at all (no token, no course, network refused)
#

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone

TIMEOUT = 30

# Anchor needs at least four graded assignments before it will report a trend:
# with two or three, one bad test reads as a collapsing trend. Mirrors
# GoogleClassroomService.trend(of:).
MINIMUM_GRADED_FOR_TREND = 4


class Outcome:
    """One question, its answer, and whether shipping without it is survivable."""

    def __init__(self, name, required=True):
        self.name = name
        self.required = required
        self.ok = False
        self.detail = ""

    def pas(self, detail):
        self.ok, self.detail = True, detail
        return self

    def fail(self, detail):
        self.ok, self.detail = False, detail
        return self


def canvas_get(base, token, path, params=None):
    """One paginated GET. Follows Link rel="next" — Canvas pages everything, and
    a connector that reads only page one silently loses the second half of a
    class."""
    url = f"{base.rstrip('/')}/api/v1/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)

    out = []
    while url:
        request = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = json.loads(response.read().decode("utf-8"))
            out.extend(body if isinstance(body, list) else [body])

            # Canvas returns pagination in a Link header, not the payload.
            url = None
            for part in (response.headers.get("Link") or "").split(","):
                bits = part.split(";")
                if len(bits) >= 2 and 'rel="next"' in bits[1]:
                    url = bits[0].strip().strip("<>")
                    break
    return out


def iso(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--course-id", help="Course to probe. Default: first active course.")
    args = parser.parse_args()

    base = os.environ.get("CANVAS_BASE_URL", "").strip()
    token = os.environ.get("CANVAS_TOKEN", "").strip()
    if not base or not token:
        print("CANVAS_BASE_URL and CANVAS_TOKEN must both be set.", file=sys.stderr)
        print("This test only means anything against a real instance — see the header.", file=sys.stderr)
        return 2

    try:
        return run(base, token, args.course_id)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:400]
        print(f"\nHTTP {error.code} from Canvas: {detail}", file=sys.stderr)
        if error.code in (401, 403):
            print("The token was rejected or lacks access. That is itself a finding:", file=sys.stderr)
            print("a teacher-scoped token may not see what a connector needs.", file=sys.stderr)
        return 2
    except urllib.error.URLError as error:
        print(f"\nCould not reach {base}: {error.reason}", file=sys.stderr)
        return 2


def run(base, token, course_id):
    results = []
    print(f"Canvas dependency test — {base}\n")

    # ---- ClassroomDataProviding.courses() -----------------------------------
    courses = canvas_get(base, token, "courses", {
        "enrollment_state": "active",
        "per_page": 100,
    })
    if not courses:
        print("No active courses visible to this token. Nothing to probe.", file=sys.stderr)
        return 2

    if course_id:
        course = next((c for c in courses if str(c.get("id")) == str(course_id)), None)
        if course is None:
            print(f"Course {course_id} is not visible to this token.", file=sys.stderr)
            return 2
    else:
        course = courses[0]

    cid = course["id"]
    print(f"Course: {course.get('name', '(unnamed)')}  (id {cid})\n")
    results.append(Outcome("courses()").pas(f"{len(courses)} active course(s)"))

    # ---- ClassroomDataProviding.students() ----------------------------------
    # `include[]=email` is requested deliberately: the docs mark email as
    # permission-gated, and whether *this* install returns it is the single most
    # important thing this script is here to find out.
    students = canvas_get(base, token, f"courses/{cid}/users", {
        "enrollment_type[]": "student",
        "include[]": ["email", "enrollments"],
        "per_page": 100,
    })
    students = [s for s in students if not s.get("id") is None]
    if not students:
        results.append(Outcome("students()").fail("no students enrolled"))
    else:
        results.append(Outcome("students()").pas(f"{len(students)} student(s)"))

    # ---- Identity matching — the pass/fail criterion ------------------------
    #
    # This is the one that decides the whole question. An academic record Anchor
    # cannot attach to a Zoom participant is worth nothing, however complete the
    # grade data behind it looks.
    with_email = sum(1 for s in students if (s.get("email") or "").strip())
    with_login = sum(1 for s in students if (s.get("login_id") or "").strip())
    with_sis = sum(1 for s in students if (s.get("sis_user_id") or "").strip())
    total = max(len(students), 1)

    identity = Outcome("identity: a stable key per student")
    if with_email == len(students) and students:
        identity.pas(f"email present for all {len(students)}")
    elif with_login == len(students) and students:
        identity.pas(f"login_id present for all {len(students)} (email hidden on this install)")
    elif with_login or with_email:
        identity.fail(
            f"partial — email {with_email}/{total}, login_id {with_login}/{total}, "
            f"sis_user_id {with_sis}/{total}; the remainder fall back to name matching"
        )
    else:
        identity.fail("no email, no login_id, no sis_user_id — name matching only")
    results.append(identity)

    # ---- ClassroomDataProviding.assignments() -------------------------------
    assignments = canvas_get(base, token, f"courses/{cid}/assignments", {"per_page": 100})
    scored = [a for a in assignments if a.get("points_possible")]
    dated = [a for a in assignments if a.get("due_at")]

    if not assignments:
        results.append(Outcome("assignments()").fail("course has no assignments"))
    else:
        results.append(Outcome("assignments()").pas(
            f"{len(assignments)} assignment(s), {len(dated)} with due_at, "
            f"{len(scored)} with points_possible"
        ))

    # points_possible is the denominator for the 0...1 fraction every grade
    # feature is built on. Without it there is no average and no trend.
    denominator = Outcome("points_possible (the grade denominator)")
    if scored:
        denominator.pas(f"{len(scored)}/{len(assignments)} assignments carry it")
    else:
        denominator.fail("no assignment exposes points_possible — grades cannot be normalised")
    results.append(denominator)

    # ---- ClassroomDataProviding.submissions(courseID:assignmentIDs:) --------
    #
    # The bulk form matters more than it looks. Fetched one assignment at a time
    # this is N sequential round trips per class; Canvas serves all N in one
    # paged call, exactly as Google does.
    submissions = canvas_get(base, token, f"courses/{cid}/students/submissions", {
        "student_ids[]": "all",
        "per_page": 100,
    })
    if submissions:
        results.append(Outcome("submissions() bulk").pas(
            f"{len(submissions)} submission(s) in one paged call"
        ))
    else:
        results.append(Outcome("submissions() bulk").fail(
            "returned nothing — a per-assignment fallback would be needed"
        ))

    # ---- The five academic features ----------------------------------------
    by_student = defaultdict(list)
    for s in submissions:
        by_student[s.get("user_id")].append(s)

    graded = [s for s in submissions if s.get("score") is not None]
    late_flagged = [s for s in submissions if s.get("late") is True]
    missing_flagged = [s for s in submissions if s.get("missing") is True]
    submitted_at = [s for s in submissions if s.get("submitted_at")]

    # missing_assignments — Canvas flags this directly, which Classroom does not.
    m = Outcome("feature: missing_assignments")
    if any("missing" in s for s in submissions):
        m.pas(f"`missing` flag present ({len(missing_flagged)} currently true)")
    elif dated:
        m.pas("no `missing` flag, but due_at + submitted_at can derive it")
    else:
        m.fail("no `missing` flag and no due dates to derive it from")
    results.append(m)

    # grade_average
    g = Outcome("feature: grade_average")
    if graded and scored:
        g.pas(f"{len(graded)} scored submission(s) against points_possible")
    else:
        g.fail("nothing graded, or no points_possible to divide by")
    results.append(g)

    # grade_trend — needs enough graded work per student to split in half.
    per_student_graded = [
        sum(1 for s in rows if s.get("score") is not None)
        for rows in by_student.values()
    ]
    eligible = [n for n in per_student_graded if n >= MINIMUM_GRADED_FOR_TREND]
    t = Outcome("feature: grade_trend")
    if eligible:
        t.pas(
            f"{len(eligible)}/{len(by_student)} student(s) have ≥{MINIMUM_GRADED_FOR_TREND} "
            "graded items, enough to split"
        )
    elif graded:
        t.fail(
            f"no student has ≥{MINIMUM_GRADED_FOR_TREND} graded items yet — the data shape "
            "is right but this course is too early to show a trend"
        )
    else:
        t.fail("nothing graded")
    results.append(t)

    # days_since_submission
    d = Outcome("feature: days_since_submission")
    if submitted_at:
        newest = max(filter(None, (iso(s["submitted_at"]) for s in submitted_at)), default=None)
        if newest:
            age = (datetime.now(timezone.utc) - newest).days
            d.pas(f"submitted_at present; most recent submission {age} day(s) ago")
        else:
            d.fail("submitted_at present but unparseable")
    else:
        d.fail("no submitted_at on any submission")
    results.append(d)

    # late_submissions — also a first-class Canvas flag.
    l = Outcome("feature: late_submissions")
    if any("late" in s for s in submissions):
        l.pas(f"`late` flag present ({len(late_flagged)} currently true)")
    elif dated and submitted_at:
        l.pas("no `late` flag, but due_at + submitted_at can derive it")
    else:
        l.fail("no `late` flag and nothing to derive it from")
    results.append(l)

    # ---- Verdict ------------------------------------------------------------
    print(f"{'':2}{'CHECK':<44}{'':2}RESULT")
    print("  " + "-" * 74)
    for r in results:
        mark = "PASS" if r.ok else ("FAIL" if r.required else "WARN")
        print(f"  {r.name:<44}  {mark}  {r.detail}")

    failed = [r for r in results if not r.ok and r.required]
    print()
    if failed:
        print(f"VERDICT: {len(failed)} required check(s) failed.")
        print("Canvas cannot supply Anchor's academic half on this instance as configured.")
        print("Read the failures above before deciding whether that is the institution")
        print("or Canvas itself — they need different answers.")
        return 1

    print("VERDICT: every required feature is available on this instance.")
    print("The connector is worth building. Record which identity key carried it —")
    print("that decision belongs in CANVAS_SPIKE.md, not in someone's memory.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
