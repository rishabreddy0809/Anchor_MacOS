# Anchor — the first email

Partner outreach is the real gate on the whole timeline. Everything else in
`ship-checklist.md` is either support for landing one design partner or
preparation for what comes after, so this file exists to make the sending
mechanical: two ready emails, and the reasons behind each line so they survive
being edited.

**These are drafts to send, not templates to fill in.** Both are deliberately
short. The instinct to add a paragraph explaining the model should be resisted —
the reply you want is "tell me more", and every extra claim is another thing a
cautious co-op parent has to check.

Three checklist lines are satisfied by the copy below rather than by sending it:
the bot is named out loud, privacy leads the first paragraph, and both questions
are asked. **Sending is a separate task** (*Contact 10–15 online K-12 academies
and homeschool co-ops*).

---

## Before you send: the form works — tested, link `/apply` freely

**Settled 2026-08-19.** The form was submitted through the live site and the
application landed in the **Primary inbox** within seconds — not spam, not
Promotions. So **link `/apply` from both emails below**; the paragraph about
cutting that line is kept only as a record of why it was ever in doubt.

The pilot form had been recorded as broken — "applications from strangers fail
silently". **Reading the code, that is not what happens**, and the difference
decides whether these emails can link to `/apply` at all.

`submitPilotApplication` sends **one** email: `to: CONTACT_EMAIL`,
`reply_to:` the applicant, `from:` the Resend sandbox address. The applicant is
never a recipient and never gets a confirmation — by design, not a failure. So
the sandbox restriction ("delivers only to the Resend account owner") lands on
the *only* recipient there is, which is you. If `rishabreddy0809@gmail.com` is
the address the Resend account was opened with, **the application reaches you
normally.**

And every failure path is loud, not silent. No API key gives *"The application
form isn't connected yet. Please email … instead."*; a Resend rejection gives
*"We couldn't send that just now…"*. **There is no path where an applicant
believes they applied and did not.**

**The one real residual risk is your own spam folder** — mail from
`onboarding@resend.dev` to Gmail is exactly what filters distrust, and that
failure *is* silent, because nothing tells you an application arrived.

> **Done — 2026-08-19.** A live submission through `/apply` arrived in the
> Primary inbox, flagged Important, `signed-by: resend.dev`. `from:resend.dev
> in:spam` returns nothing across four sends. `reply-to` carried the
> applicant's address rather than `onboarding@resend.dev`, so hitting Reply on
> an application reaches the teacher. **Link `/apply`.** Do not re-run this
> before every send — the thing that would change the answer is the sending
> domain, and that only changes when `PILOT_FROM_EMAIL` is finally set.

One caveat, so it is not over-read: that send came from the mailbox's own
owner, and three earlier test applications already sit in it. A stranger's
application does not inherit that history — but it does inherit the sending
domain and its DKIM reputation, which is what actually decides the filter.
**If the first real applicant emails to say they applied and you have nothing,
check spam before assuming they are confused.**

---

## Email 1 — online K-12 academies

**Who this is for:** a head of school, director of online learning, or academic
lead. There is an IT function, a Zoom admin, and a decision chain of two or
three people, so this email has to survive being forwarded.

**Subject:** `Engagement signals for your live classes — no video, runs on the teacher's Mac`

> Hello [name],
>
> I've built a tool for teachers running live classes on Zoom, and I want to
> lead with how it handles student data, because that is usually the first
> question. Anchor runs on the teacher's own Mac. There is no server of mine for
> student data to reach, and none of it is transmitted to me. **No video is
> analysed and no facial recognition is used** — camera state is read as an
> on/off flag and no frame is ever read. Chat is measured as a character count,
> not message text. Live captions stay in memory, are dropped when the meeting
> ends, and are never written to disk.
>
> It joins the call as a **visible participant named "Anchor (engagement
> assistant)"**. It does not join silently, and everyone in the room can see it
> is there.
>
> What it does: it reads participation during a live lesson — speaking time,
> hand raises, chat, whether someone has gone quiet — and optionally pairs that
> with Google Classroom coursework, to point a teacher at a student who may be
> struggling and easy to miss in a grid of thirty faces. It's an estimate worth
> a human look, not a finding about a child. **I don't publish an accuracy
> figure, because I haven't established one on a held-out test set** — measuring
> that honestly is what the pilot is for.
>
> The pilot is free: six weeks, two live classes a week, one 30-minute call at
> the end. Setup needs about an hour of a Zoom admin's time, once.
>
> Two questions that decide whether it fits, before you spend any more time on
> this:
>
> 1. **Which LMS do you use?** (Google Classroom works today; Canvas is the next
>    connector and your answer decides whether I build it.)
> 2. **Is your Zoom account Business/Education, or Pro?** (This changes which
>    signals are available at all, and it's better settled now than on a call.)
>
> The privacy policy is written to be handed to whoever has to assess it:
> [link]. Happy to answer anything before you take it further.
>
> Rishab

### Why each part is there

- **Privacy in the first paragraph, before what it does.** A K-12 buyer's first
  question is never "how accurate"; it is "what happens to the children's data".
  Answering it before being asked is the difference between a reply and silence.
- **The three negatives are specific.** "Privacy-first" is noise. *No frame is
  ever read*, *character count not message text*, *captions never written to
  disk* are checkable claims, and all three are true of the shipped app.
- **The bot is named in its own paragraph** so it survives forwarding. A parent
  who discovers an unexplained participant on the call will never trust you
  again; one told upfront usually shrugs.
- **The accuracy sentence is a feature, not a hedge.** Everyone in this market
  has been pitched an AI number nobody can defend. Declining to quote one is the
  most credible thing in the email — do not let anyone talk you into adding a
  percentage.
- **"About an hour of a Zoom admin's time"** sets the real cost honestly. The
  ask is that they create a Marketplace app under *their* Zoom account, but
  saying that in a first email is jargon; it belongs on the call.
- **The two questions are numbered and last**, so they are the easiest thing to
  reply to. A one-line answer to question 2 is still a live lead.

---

## Email 2 — homeschool co-ops

**Who this is for:** a co-op organiser, who is usually a parent. The decision
chain is short and can close in days, but the parents *are* the decision-makers,
so consent scrutiny is higher and more personal, not lower.

**Subject:** `A quieter way to spot a struggling student in a live class`

> Hi [name],
>
> I've built something for co-ops running live classes on Zoom, and I'd rather
> tell you how it treats the children's data first than bury it.
>
> It runs on the teacher's own laptop. **Nothing about a student is sent to me —
> there is no server of mine for it to go to.** No video is analysed and no
> facial recognition is used; whether a camera is on is read as a yes/no, and no
> picture is ever looked at. Chat messages are measured by length only, never
> read. Anything from live captions stays in memory during the lesson and is
> gone when it ends.
>
> It appears in the meeting as a **visible participant called "Anchor
> (engagement assistant)"** — so if a parent asks what that is on the call, the
> honest answer is already on screen. It never joins quietly.
>
> What it's for: in a live class it's genuinely hard to notice the child who has
> gone quiet, especially the one who was fine last week. Anchor watches
> participation — speaking, hand raises, chat activity — and flags who might
> need a check-in. It's a nudge for the teacher, not a judgement about a child,
> and **I don't quote an accuracy number because I haven't earned one yet.**
> That is exactly what I'm hoping to learn from a few real classes.
>
> It's free for the pilot — six weeks, a couple of live classes a week, and one
> 30-minute conversation at the end about what was useless and what wasn't.
>
> Two things I need to know early, because they decide whether it works for you
> at all:
>
> 1. **Do you use Google Classroom, or something else?**
> 2. **Is your Zoom a paid Business/Education plan, or a personal/Pro one?**
>
> If it's useful, the privacy policy is written in plain English for exactly the
> parent who wants to read it: [link].
>
> Rishab

### Why this one is different

- **Warmer and shorter.** The academy email survives a forward; this one is read
  once by a person who is also a parent.
- **Every privacy claim is de-jargoned.** "State flag" becomes "read as a
  yes/no", "character count" becomes "measured by length only, never read". Same
  claims, same truth, no vocabulary that sounds like it is hiding something.
- **The privacy policy is offered *for the parent to read*, not for compliance.**
  In a co-op the person assessing it has no compliance department; they are a
  parent who wants to read it themselves.
- **The Zoom question is phrased around "personal/Pro"** because that is the
  likely answer here, and it is the one with consequences: the two participant
  scopes cannot be granted below Business/Education, which decides whether
  Anchor reads the meeting through the bot or through the REST API.
- **The pain is stated as a teacher's experience**, not a metric. A co-op
  organiser has watched a child go quiet in a Zoom grid; an academy director has
  read a retention report.

---

## What not to do

- **Don't send both to the same organisation.** Some online academies are
  co-op-shaped and vice versa. Pick by who replies, not by what they call
  themselves.
- **Don't add an accuracy figure**, even a hedged one, even if asked directly.
  The honest answer is that measuring it is what the pilot is for, and that
  answer has never lost a conversation that was going to convert.
- **Don't mention the Zoom Marketplace app in email one.** It is the single most
  jargon-heavy part of setup and it reads as work. It belongs on the call, where
  "I'll walk your admin through it in an hour" is reassuring rather than
  alarming.
- **Don't promise a start date.** A new pilot group starts when the last one
  fills; nothing is scheduled, and inventing a date to create urgency is the one
  lie this whole positioning is built to avoid.
