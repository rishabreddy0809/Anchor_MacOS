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

Fourteen organisations **in this section**; entries 15 to 25 were added later
and live in the two dated sections below, so the file holds **twenty-five** in
total. Sorted by how short the decision chain looks, because that is what
decides whether a reply turns into a call before term starts.

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

## Added 2026-08-21 — two new segments asked for, and one of them does not exist yet

Rishab asked to open outreach to **smaller K-12 online academies**, **tutoring
agencies**, and **individual tutors "if they can sign in and use the app"**.
That last one is a conditional, and the condition was checked rather than
assumed. **It fails.** The verdict is below, before the names, because it
decides whether a third of this request has any prospects at all.

### Individual tutors are not a segment yet, on three gates in series

Checked in the code and the build on 2026-08-21, not recalled. Keep the three
questions apart, exactly as the per-teacher entry in `HANDOFF.md` insists.

1. **Nobody can install Anchor, tutors included.** `codesign -dv` on the Release
   build reads `Signature=adhoc` and `TeamIdentifier=not set`, and
   `security find-identity -v -p codesigning` returns **one** identity, a free
   *Apple Development* certificate. There is no Developer ID Application cert,
   so there is nothing to notarize and Gatekeeper stops the app on any Mac that
   is not this one. **This gate is shared by every segment on this page** and is
   the reason Apple Developer enrollment is upstream of all outreach, not just
   of tutors.
2. **An outside tutor cannot sign in to Zoom even if they had the app.** The
   *Anchor* Marketplace app is Draft / "Active for internal users", so a tutor
   on their own Zoom account fails at `/oauth/authorize` with "You cannot
   authorize". Removing that gate means Marketplace publication, which was
   **parked on 2026-08-21** for reasons that have not changed: eighteen missing
   required fields, nine of them EU trader disclosures needing a registered
   company.
3. **Past both gates they would still get half a product.**
   `OAuthClientDefaults.meetingSDKSecret` ships as `""`, so an unprovisioned
   install has no bot; participant scopes are ungrantable on Basic and Pro. A
   solo tutor would get the coursework half and **no live lesson signal at
   all**, which is the half the outreach is about.

**And the tempting workaround is the one thing that must not be done.** A solo
tutor is their own Zoom admin, so unlike a school teacher they *could* self
provision through `ANCHOR_ZOOM_SDK_KEY` / `_SECRET` the way `ADMIN-SETUP.md`
step 2 describes. That means handing **Anchor's own Meeting SDK signing secret**
to individuals found by cold email. It is an HS256 key signed locally, so
whoever holds it can mint Meeting SDK tokens as Anchor. With a partner school
that is a controlled relationship with a name attached. With arbitrary tutors it
is publishing the key. **So the mechanism that would technically unblock the
per-tutor segment is the mechanism that makes it unsafe at any scale.**

**What to do:** nothing, and specifically do not write a tutor draft yet.
Revisit only if Marketplace publication is un-parked, and even then the bot
question above has to be answered first. **A tutoring agency is a different
matter entirely, because an agency can be a school in every way that counts.**

### The qualifying test for a tutoring agency, and it is not size

An agency is a prospect when it looks like a school to Zoom, and that turns on
**one** question: are the tutors **employees on a company Zoom account**, or
**independent contractors on their own**?

- **Employees on a company account** means there is a Zoom admin who can install
  the Server-to-Server app once, exactly like an academy. This is a per-school
  deployment wearing different words, and everything in Email 1 applies.
- **Independent contractors** means there is no company Zoom account and no
  admin, so landing them lands the **per-teacher** branch. That is finding 3 on
  this page, and it is why Kepler is not a school. **Wyzant and Varsity Tutors
  are contractor marketplaces and belong in the same bucket as Kepler**, not
  with the agencies below.

**The distinction is often stated on their own site in as many words**, which
makes it a one-minute check like the LMS footer check in finding 4. Revolution
Prep says it outright, quoted below.

**One more filter, and it is about the product rather than the deployment.**
Anchor's value scales with the number of faces a teacher is watching. **For 1:1
tutoring it is close to worthless** and the email should not be sent, because
the tutor already sees everything Anchor would surface. Send only where the
agency runs **group classes**, and say group classes in the first line so the
1:1 half of their business self selects out.

> **A positioning question, written down rather than answered, per the funnel
> rule.** There is an obvious second pitch to an agency: not "your tutor may
> miss a student" but "you, the owner, have no visibility into sessions your
> tutors run". That reframes Anchor from a teacher's instrument to a
> **supervision** tool, which is a different product, a different buyer, and a
> privacy story that would have to be rewritten from the first paragraph.
> **Two reasonable people would pick differently, so it is not Claude's call.**
> Email 3 below is written on the existing teacher-facing positioning. Decide
> the other one deliberately or not at all.

### New prospects — smaller academies

Same standard as the rest of this file: quoted from the organisation's own site,
or marked as not confirmed.

| # | Organisation | Confirmed from their own site | Not confirmed | Contact |
| --- | --- | --- | --- | --- |
| 20 | **Apologia Live Classes** `apologia.com` | *"interactive, instructor-led online classes tailored for homeschool students in grades 6–12"*; uses **the Canvas student portal**; *"class sizes may be limited"* | **Video platform is never named.** Zoom is not stated anywhere on the live-classes page | `liveclasses@apologia.com`, 765-608-3280 |
| 21 | **Veritas Press / Veritas Scholars Academy** `veritaspress.com` | K-12; *"200+ credentialed teachers"*; *"Classes meet twice a week... in the virtual classroom"* | **"Virtual classroom" is never identified as Zoom.** Employment model not stated | `info@veritaspress.com`, (717) 519-1974 |
| 22 | **Brilliant Microschools / Brilliant Grades** `brilliantmicroschools.org` | Accredited K-12, all 50 states; *"Strictly 4–6 students per group"* (SpEd) and *"Strictly 8–10 students per group"* (GenEd); daily live instruction | Video platform not named. **No LMS named** — the site lists IXL, Khan, Nearpod, CommonLit and others instead | `admissions@BrilliantMicroschools.org`, +1 904-822-1604 |
| 23 | **Learn Beyond The Book** `learnbeyondthebook.com` | Search result describes *live, virtual homeschool classes* and **custom Zoom classes for microschools, pods, or homeschool groups** | **Nothing confirmed from the site itself: it returned HTTP 403 to an automated fetch.** Everything here is third party and must be re-checked in a browser before sending | Not retrieved. Site must be opened by hand |

**Class size is the reason 22 is the most interesting name here** and 20 and 21
are the safest. Brilliant runs 8-10 per group with a certified teacher, which is
small enough that a teacher plausibly already knows who is struggling. Apologia
and Veritas are large enough for the grid problem to be real.

### New prospects — tutoring agencies

| # | Organisation | Confirmed from their own site | Not confirmed | Contact |
| --- | --- | --- | --- | --- |
| 24 | **Revolution Prep** `revolutionprep.com` | **The qualifying quote, verbatim: tutors** *"are employees – not contractors – and receive continuous training in the latest techniques and research."* Group format is *"Expert tutor, up to 10 students"* with a *"Set schedule"*, grades 9-12; private tutoring K-12 | **Zoom is not named anywhere on the page.** No named leadership on the homepage. Large enough that the chain may be long | `answers@revolutionprep.com`, (877) 738-7737 |
| 25 | **Bay Area Tutoring Association** `bayareatutor.org` | *"501(c)3 non-profit, charitable organization"*; trains its own tutors, who *"work in class rooms during the school day, after school programs, online, and for strategic partners"* | **Online delivery platform not named.** Group classes not mentioned at all, so the group-class filter above is unverified for them. Grade levels not stated | `info@bayareatutor.org`, (408) 945-8003 |

**Neither is confirmed on Zoom, and for this segment that is question 2's
job.** Note what is different from the academy list: for an academy, "which LMS"
is the load-bearing question. For an agency, **"employees or contractors" is**,
and it is worth asking before the LMS question because it decides whether they
are a per-school deployment at all.

### Finding 1 gets worse, not better, and a new possibility appears

The hope behind widening to smaller organisations was finding 1's own
suggestion: that Google Classroom *"most likely lives in the tail this method
cannot see"*. **The tail did not produce it.** Apologia is Canvas, which takes
the tally to **seven organisations with a discoverable LMS and still zero on
Google Classroom** — now four Canvas, one Moodle, one Blackbaud, one Caravel.

**And a third possibility turned up that neither Canvas nor Classroom covers.**
Brilliant Microschools names no LMS at all and lists a dozen adaptive-practice
tools instead. If that is what small operations actually look like, then for
them Anchor's academic half has **no source to connect to**, rather than a
different one. That is a worse answer than "they use Canvas", because a
connector cannot fix it. **Do not act on one data point** — but question 1 in
the emails should be read as three-way from now on: Classroom, another LMS, or
nothing that has an API.

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
