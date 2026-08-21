# Anchor — the prospect list

`OUTREACH.md` has the two emails. This file has the people to send them to, and
the reasons each name is here, so the list survives being edited.

Built 2026-08-19 by research, not by contact. **Nothing here has been emailed.**
The Notion task *Contact 10–15 online K-12 academies and homeschool co-ops*
stays open; this is its unblocked half.

Everything below is either **quoted from the organisation's own site** or marked
as third-party. Where a fact could not be confirmed it says so rather than
guessing — a prospect list that quietly infers is worse than a short one,
because the first call is where the guess gets found.

---

## Four findings that change the plan

These came out of the research and matter more than the list itself. Three of
them contradict something the plan currently assumes.

### 1. This segment runs on Canvas, not Google Classroom

The LMS was publicly discoverable for six organisations. **None of them uses
Google Classroom.**

| Organisation | LMS | How it was found |
| --- | --- | --- |
| Excelsior Classes | Canvas | `excelsiorclasses.instructure.com` login link |
| Wilson Hill Academy | Canvas | `go2.wilsonhillacademy.com/canvas-login-2` |
| Aim Academy Online | Canvas | `aimacademy.instructure.com` |
| Blue Tent Online | Moodle | third-party profile, not their own site |
| True North Academy | Blackbaud / MySchoolApp | `truenorthhomeschoolacademy.myschoolapp.com` |
| Homeschool Connections | Caravel | named in their own Live Classes page |

**Why this matters more than it looks.** The README puts the five Google
Classroom features at **74% of total model importance**, `grade_trend` alone at
45%. The artifact's own reasoning for choosing this segment over bootcamps was
that it is "the segment where 100% of your model works on day one, with no
connector to build first." That reasoning assumed these organisations use
Google Classroom. On this evidence the named online academies mostly do not.

**Do not over-read it either.** Six is a small sample, and it is biased: a
dedicated online academy with hundreds of enrolments buys a real LMS, which is
exactly the kind of organisation whose LMS is discoverable from a login link.
Google Classroom is free with Google Workspace for Education, so it most likely
lives in the tail this method cannot see — small co-ops, microschools, single
teachers — which is precisely where a login link does not exist to be found.

**What to do about it:** nothing yet, and specifically *not* build the Canvas
connector. `CANVAS_SPIKE.md` already says the connector decision waits on the
live run, and that is still right. What changes is that question 1 in both
emails has stopped being a nice-to-have and is now the single most load-bearing
line in the outreach. Read the answers as a group before deciding anything.

### 2. The co-op half of the segment is mostly in-person

`OUTREACH.md` is built around two comparable segments — academies and co-ops —
and the co-op draft assumes a co-op running live classes on Zoom. Most local
homeschool co-ops do not. L.I.F.E. (Adrian, Michigan) is representative and was
checked: *"Co-Op classes are held every Thursday morning throughout the school
year in Adrian, Michigan"*, and the page states it is **not a drop-off
activity** — parents attend and assist in the classrooms in person. There is no
video platform to connect Anchor to, because there is no video.

**So the co-op draft's real audience is not the literal local co-op.** It is the
founder-led *online* programme — Blue Tent, Learn Beyond The Book, Athena's —
where the decision chain is one person who is also a parent, which is the
reader the co-op draft was actually written for. That draft is still the right
one to send them; it is the targeting that was wrong, not the copy.

This also means the addressable pool on the co-op side is much smaller than the
academy side. Weight the sending accordingly rather than splitting 50/50.

### 3. A marketplace like Kepler is the per-teacher branch wearing a school's clothes

Kepler Education looks like one organisation to email and is not one. Its own
About page: *"a free-market platform for Classical Christian Education"* where
*"vetted and qualified teachers set their own prices and schedules."* Teachers
are independent contractors. There is no school Zoom account and no Zoom admin
to install the Server-to-Server app, so landing Kepler lands the **per-teacher**
model — the branch `ship-checklist.md` prices as a much bigger build, where the
bot becomes a hard dependency rather than a differentiator.

One detail worth carrying into the call: Kepler's classes are **90-minute weekly
meetings**. Zoom Basic caps meetings at 40 minutes, so those teachers are
already on paid plans — but **Pro still has no participant scopes**, so paid
does not solve the REST path. Paid only rules out the 40-minute problem.

Kepler is worth talking to. It is not worth talking to as if it were a school.

### 4. You cannot pre-qualify on LMS, and that is why the email asks

For most of these organisations the LMS is simply not stated anywhere public.
Where it *is* findable, it is almost always a login link in the site footer —
`*.instructure.com`, `*.myschoolapp.com`, a named portal. That is a one-minute
check per prospect and it is already done below for everyone it worked on.

For the rest, question 1 in the email is the only way to know. This is the
strongest argument for not editing those two questions out to shorten the
email: they are not qualification theatre, they are the only channel that
exists for this information.

---

## The list

Fourteen organisations. Sorted by how short the decision chain looks, because
that is what decides whether a reply turns into a call before term starts.

Each entry says what was **confirmed**, what was **not**, and which draft to
send. "Draft" means the academy version or the co-op version from
`OUTREACH.md` — pick by who reads it, not by what the organisation calls
itself, exactly as that file says.

### Shortest chain — one person decides

**1. Blue Tent Online** — `bluetentonline.com`
- **Live classes on Zoom, LMS is Moodle.** Third-party sourced (a homeschool
  magazine profile and the Institute for Educational Advancement), *not* their
  own site — worth confirming on the call rather than asserting to them.
- Middle and high school math, science, English. Founder-led.
- Contact: `bluetentonline@gmail.com`
- **Draft: co-op.** A gmail contact address and a named founder is the whole
  profile the co-op draft was written for.

**2. Learn Beyond The Book** — `learnbeyondthebook.com`
- Runs a page literally titled *Live Virtual Homeschool Classes* at the path
  `/live-zoom-homeschool-classes/`. **Zoom is in their own URL.**
- Their site refuses automated fetches, so grades, size and LMS are unconfirmed
  — open it in a browser before sending.
- **Draft: co-op.**

**3. Athena's Advanced Academy** — `athenasacademy.com`
- Gifted and twice-exceptional students. Two components per course: **live
  weekly webinars** plus virtual classrooms. Cognia-accredited.
- Platform not stated publicly; site refuses automated fetches.
- **Draft: co-op.** The audience is parents of 2e children, who read a privacy
  paragraph more carefully than anyone else on this list. That is a feature —
  the co-op draft leads with privacy for exactly this reader.

**4. Schoolhouse Online Co-Op+** — `schoolhouseonline.com`
- Live online classes PreK–12, subscription priced per child ($47–$129/month by
  family size), built for multi-child families.
- **Contact is a text number** (1-804-722-7859) and a Skool community. No email
  published. Treat the email drafts as a script for a text, not a paste.
- **Draft: co-op.**

**5. Gather 'Round Homeschool Academy** — `gatherroundhomeschool.com`
- Live and on-demand classes. Small publisher-run academy.
- Platform and LMS unconfirmed.
- **Draft: co-op.**

### Small academies — two or three people, an admin exists

**6. Excelsior Classes** — `excelsiorclasses.com`
- **Live via Zoom on a consistent weekly schedule** — their own words, on their
  live-classes page. Grades 4/5–12, Christian.
- **LMS: Canvas.** So question 1 is already answered, and the answer is not
  Google Classroom. Send anyway — a Canvas answer from a real prospect is worth
  more than a guess, and it is a vote for the connector.
- Contact: `registration@excelsiorclasses.com`, 1-832-620-2423 (Mon–Fri
  10:00–17:00 ET). **They publish a Calendly for a free 30-minute meeting** —
  the lowest-friction way onto a call with anyone on this list.
- **Draft: academy.**

**7. True North Academy** — `truenorthhomeschool.academy`
- **"Real-time classes on Zoom"**, their own words, with small class sizes as
  the stated selling point — which is the condition Anchor is least useful in
  and most credible in. Ask what "small" means.
- **LMS: Blackbaud / MySchoolApp.**
- Contact: `TNHAStaff@gmail.com`, `enrollment@truenorthhomeschoolacademy.com`,
  (605) 496-9681.
- **Draft: academy.**

**8. Aim Academy Online** — `aimacademy.online`
- Live online homeschool classes. **LMS: Canvas.**
- Contact: `office@aimacademy.online`, 717-388-0147, Camp Hill PA.
- **They offer free academic advising calls with no obligation** — a published
  route to a human that does not require them to say yes to anything first.
- **Draft: academy.**

**9. Homeschool Connections** — `homeschoolconnections.com`
- Catholic; live classes weekly, some upper-level twice weekly. **LMS: Caravel.**
- Contact: `info@homeschoolconnections.com`, 888-372-4757.
- **The detail that makes this one interesting:** their standard classroom
  already contains a *"Course Monitor — another adult in the classroom"*. A
  visible extra participant is not a novelty here, it is their existing model.
  The bot paragraph in the email will land softer on them than on anyone else,
  and that is worth saying explicitly when you write to them.
- **Draft: academy.**

**10. Wilson Hill Academy** — `wilsonhillacademy.com`
- Live online classical Christian, grades 3/4–12. **LMS: Canvas.**
- Contact: 512.655.9421 and a web form; no email published.
- **The reason it is on the list:** their **EdVantage** programme exists to
  supply live online courses *to other Christian schools and co-ops*. They are
  already in the business of being the account other people's students learn
  under, which is the exact shape the per-school Zoom model needs — and it
  means one yes here could be several classrooms.
- **Draft: academy.**

### Larger — worth sending, expect a longer chain

**11. The Potter's School (TPS)** — `at-tps.org`
- Accredited non-profit online Christian school, **live synchronous classes
  since 1997**, grades 4–12, AP and dual credit. The oldest organisation of
  this shape that exists.
- **Zoom is confirmed for their public open houses** (*"Meetings are in
  Zoom"*). Their classes are stated as live and synchronous but the **class**
  platform was not confirmed — their site blocks automated fetching. Check in a
  browser; do not assume Zoom in the email.
- **Do this before emailing:** they run a **public open house every Monday,
  11:00 and 20:00 US ET, in Zoom.** Attend one. It costs an hour, it is the
  closest thing available to watching this segment's live-class format without
  a partner, and turning up before writing changes the first line of the email
  from a cold open to a reference.
- **Draft: academy.**

**12. HSLDA Online Academy** — `academy.hslda.org`
- Grades 6/7–12, 40+ classes, each with a weekly live session.
- Contact: `academy@hslda.org`, 540-338-8290 (Mon–Fri 09:00–16:00 ET).
- **Caveat that decides the ordering:** this is part of HSLDA, a large national
  organisation with a legal arm. The academy is small; the institution around
  it is not, and a student-data question will go somewhere formal. Send it — but
  send it after the ones that can answer in a week, and expect the privacy
  paragraph to be read by a lawyer. That paragraph is written to survive that.
- **Draft: academy.**

**13. Apologia Live Classes** — `apologia.com/live-classes`
- Instructor-led live classes, grades 6–12, across science, math, language
  arts, history, government, languages.
- A curriculum publisher first and a class provider second, so the classes sit
  inside a much larger commercial operation.
- **Draft: academy.**

**14. Kepler Education** — `kepler.education`
- Marketplace of independent classical Christian teachers. 90-minute weekly
  meetings, flipped-classroom model.
- **Leadership emails are published on their own About page:** Dr. Scott Postma,
  President & CEO, `scott@kepler.education`; Dr. Robert Woods, Dean of
  Academics, `robert.woods@kepler.education`. They also publish a free
  consultation booking.
- **Read finding 3 before writing to them.** This is the per-teacher branch, and
  the academy draft's line about "about an hour of a Zoom admin's time" is
  wrong for them — there is no Zoom admin. Cut or reword that sentence for this
  one email.
- **Draft: academy**, amended as above.

---

## Added 2026-08-20 — five more, and one named person on an existing entry

Same standard as above: quoted from the organisation's own site or from the
person's own LinkedIn profile, and marked where it is neither.

### The best single lead found: Aim Academy already has a named founder

**Debra Bell — "Aim Academy Online, executive director, founder"**, Greater
Harrisburg Area, from her own LinkedIn headline. Her profile states Aim Academy
*"offers 150 live, introductory and college prep online classes."*

Aim Academy is already **#8 on the list above**, where the contact was a role
address. This converts it into the shortest chain there is: founder and
executive director are the same person, so there is nobody to forward it to.
**Send email 1 to her by name rather than to the role address.**

### 15. Well-Trained Mind Academy — `wtmacademy.com`

- **Confirmed from their own site:** live online classes for middle and high
  school, *"led by live teachers who guide students through real time
  instruction and discussion."* Contact published: **844-986-9862**, a contact
  form via their Zendesk help centre, and a postal address in Charles City, VA.
- **Not confirmed:** the video platform. Their live-classes page does not name
  Zoom or anything else, so **question 2 covers it and do not assume**.
- **Why it belongs here:** it sits in exactly the same bracket as Wilson Hill and
  Excelsior, which are already on the list, and it is well known in the
  classical-education world. Send **email 1**.

### 16. Schoolhouse.world — `schoolhouse.world`

- **Confirmed:** *"All programs take place on Zoom"* and all programs are free.
  Founded by Sal Khan. Peer-led tutoring at scale.
- **Why it is interesting and also awkward:** the Zoom question is answered
  before the email, which no other prospect manages. But the tutors are
  volunteers rather than staff, so "an hour of your Zoom admin's time" needs
  rewording, and a free nonprofit has different reasons to say yes than a school
  does. **Worth a different, shorter email** than either draft.

### 17. Premier Prep Online Academy — Chandler, Arizona

- **Source: LinkedIn only.** Sarah Williams lists herself as **Director of
  Education at Premier Prep Online Academy**. Nothing was verified from an
  organisation website. **Check the site before sending.**

### 18. Feynman Academy — Oklahoma City metro

- **Source: LinkedIn only.** Yulie Jennings lists herself as **Managing
  Director, Feynman Academy**, focusing on *"Science, Math, and Technology"*,
  with a homeschool managing-director role since 2012. Not verified elsewhere.
  **Check the site before sending.**

### 19. Score Academy Online — `score-academy.online`

- **Confirmed from their own material:** accredited online private school,
  *"the smallest classes of any accredited online private school, averaging 4
  students with a maximum of 6."*
- **Read that number before sending.** Anchor's whole pitch is the student who
  is easy to miss in a grid of thirty. In a class of four the teacher can see
  everyone, so the value is genuinely lower and the email should not pretend
  otherwise. Listed because they are a real school with a real admin, not
  because the fit is obvious.

### Outschool: the open question in the section below is now answered, and it
raised a better one

`Where to find more` records Outschool as *"unverified, and it decides whether
their teachers are prospects at all."*

**It is verified: Outschool runs live classes on Zoom.** From Outschool's own
support documentation, *"Outschool integrates with the video conferencing tool,
Zoom for live meetings"*, each section has its own Zoom link, and teachers get
standard Zoom features including live captioning.

**But the same page raises the thing that probably rules them out.** It also
says that for Zoom classes teachers *"don't need to worry about logging in, it's
handled automatically"*, and that each section has its own generated link. That
reads as Outschool provisioning the meeting from Outschool's account rather than
the teacher's. If so, a teacher's own Zoom grant would not find that meeting at
all, because Anchor's REST path looks for meetings on the account that signed
in. **That is a technical question, not a sales one, and it should be settled
before any Outschool teacher is contacted.** It was not settled here.

## Where to find more, when these run out

- **`homeschool-life.com`** hosts hundreds of individual co-op sites on
  subdomains, each with its own class schedule and contact. It is the densest
  directory found. Filter hard for *online* — per finding 2, most are in-person
  and are not prospects at all.
- **State homeschool organisation directories** list co-ops by region; same
  filter applies.
- **Cathy Duffy Reviews** (`cathyduffyreviews.com`) maintains categorised lists
  of online schools and individual online course providers. It surfaced several
  of the names above and has more.
- **Outschool** is a large live-class marketplace, but it runs its own
  classroom rather than Zoom as far as could be determined — **unverified, and
  it decides whether their teachers are prospects at all.** Check before
  spending time there.

## What is deliberately not here

- **No personal email addresses of individuals**, except the two that Kepler
  publishes itself on its own leadership page for exactly this purpose. Every
  other contact is a role address the organisation publishes for enquiries.
- **No enrolment numbers, revenue, or headcount.** None of it was reliably
  available, and a guessed number in a prospect list becomes a stated fact in a
  call three weeks later.
- **No claim about anyone's Zoom plan.** That is question 2, and there is no way
  to know it from outside. It is also the answer that decides whether the REST
  participant path exists for them at all.
