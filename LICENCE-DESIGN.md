# Anchor — licence enforcement for the individual-teacher tier

A sketch, not an implementation. Written 2026-08-28 against what already exists,
so the decisions are made before any of it is built and the shape is not
discovered halfway through.

> **Nothing here gates the pilot.** Per-school needs no licence, no payment and
> no Marketplace review. This is only for the £/$15-a-month individual tier, and
> it is the last of that tier's three blockers — see `ship-checklist.md` §3.

---

## What is already true

Three things this can be built on rather than around:

- **Every teacher already has an identity.** `AnchorAccount` carries a Firebase
  `uid`, and since 2026-08-27 every store on the Mac is scoped to it
  (`AccountScope`). A licence is a fact about a uid, and there is already a
  correct place to keep per-account state.
- **There is already a server that verifies a token before doing work.**
  `POST /api/zoom/sdk-token` takes a bearer token, verifies it with the issuer,
  and answers. A licence endpoint is the same shape with a different issuer, so
  this is a second instance of a pattern rather than a new one.
- **"No account, no app" already ships.** `AccountStore.requiresSignIn` and
  `SignedOutGate` mean there is an established way to hold the app closed, with
  copy that already reassures a teacher their classes are safe. A licence gate
  is a *softer* version of a thing that exists, not a new concept.

---

## Provider

**Stripe**, via the Vercel Marketplace `payments` category — subscriptions with
no product catalog, which is exactly this. Provisioned with
`vercel integration add stripe` once the CLI is installed and the tier is
actually being built; it is a connectable integration, so it finishes in the
dashboard rather than the terminal.

**Deliberately not StoreKit.** Direct download is the distribution channel
(`ship-checklist.md` §"Distribution channel"), and StoreKit is only available to
apps shipped through the App Store. Picking StoreKit would decide distribution
as a side effect of picking a payment library, which is the wrong way round.

---

## Shape

```
Teacher's Mac                     anchorteach.vercel.app              Stripe
─────────────                     ──────────────────────              ──────
LicenceStore                      GET /api/licence
  ├─ Firebase ID token ─────────►   verify with Firebase Admin
  │                                 look up uid → subscription ◄──── webhook
  └─ cached LicenceState ◄────────  { state, renewsAt, trialEndsAt }
```

- **`GET /api/licence`**, `Authorization: Bearer <Firebase ID token>`. The token
  is the same one Firebase already mints for the signed-in teacher; the server
  verifies it and never trusts a uid sent in the body.
- **Stripe's webhook is the writer.** `checkout.session.completed`,
  `customer.subscription.updated`, `.deleted` → persist `uid → state`. The Mac
  never talks to Stripe and never sees a payment detail.
- **Checkout is a browser hop**, the same transport Zoom and Google sign-in
  already use: Anchor opens a Stripe Checkout URL and the teacher comes back.
  No card fields in the app, matching the promise Settings already makes about
  Zoom — *"nothing is typed here"*.

### Where the uid → subscription mapping lives

The app links **FirebaseAuth only** — deliberately, and recorded as such:
*"Not Firestore, Analytics or Crashlytics — each drags in binaries that the Zoom
re-signing build phase would then have to handle."* That constraint is about the
**Mac app**, not the server, so the store can be anything the Vercel side likes.
Simplest that is not a toy: a Marketplace Postgres or Redis instance, holding
one row per uid. Stripe's `customer.metadata.uid` carries the link.

---

## Client

```swift
@MainActor
final class LicenceStore: ObservableObject {
    enum LicenceState: Equatable {
        case unknown          // never checked on this Mac
        case trial(endsAt: Date)
        case active(renewsAt: Date?)
        case lapsed
        case unlicensed
    }
    @Published private(set) var state: LicenceState = .unknown
}
```

Shaped like `AccountStore` on purpose — a `@MainActor` singleton publishing
state with the network work behind it — because that is what every other store
in this project looks like and a licence is not special enough to differ.

**It is scoped, and that is not optional.** A licence belongs to a uid, so it
is written through `AccountScope.shared.defaults` and reloaded on
`AccountScope.didChange` like every other per-teacher store. Two teachers on one
Mac must not share a subscription, and the machinery to prevent that already
exists and is tested.

---

## Four decisions, made here rather than mid-build

### 1. It fails **open**, not closed

If `/api/licence` is unreachable, the cached state stands and the app keeps
working. A teacher mid-lesson on hotel wifi must never have Anchor stop scoring
their class because a licence server had a bad minute.

The precedent is already set and is the right one: `AccountStore.start()`
resolves to `.signedOut` rather than sitting in `.unknown` when Firebase is
absent, because *"a spinner that never stops is the worst of the three states to
ship"*. Same instinct, applied to money.

Practical rule: cache the last good answer with its timestamp; keep honouring it
for a **grace window** (14 days is a term's worth of half-terms and a fortnight
of outages); only after that does a stale licence lapse.

### 2. A lapsed licence never destroys anything

`SignedOutGate` already says the sentence this needs — *"Your classes, rosters
and session history stay on this Mac"* — and it is there because *"sign in to
continue" on an app holding months of a teacher's classes otherwise reads as a
threat*. A lapsed **paid** licence is the same threat with a bill attached, and
must be handled the same way: history stays, exports stay, live scoring stops.

### 3. What actually switches off

Turn off **live scoring during a class** — the thing that costs money to run and
is the thing being sold. Leave readable: session history, recaps, insights,
exports, and the Classroom overlay.

Rationale: a teacher whose card expired in October must still be able to open
March's records for a parents' evening. Locking a teacher out of their own
past is the version of this that gets written about.

### 4. Trials are dated, not counted

Store `trialEndsAt` server-side and let the server decide. Anything counted on
the Mac — sessions used, days elapsed in `UserDefaults` — is reset by deleting a
preferences file, and `AccountScope` now makes per-account suites trivially
findable. Not worth defending against; worth not inviting.

---

## Not building an anti-piracy system, and saying so

Anchor is a signed, notarised Mac binary. Anyone determined can patch out a
licence check, and every hour spent hardening that is an hour not spent on the
product. The check exists so honest people can pay, and to make lapsed
subscriptions visible — not to defeat an attacker with a debugger.

The one thing worth doing properly is **not shipping a bypass**: the licence
state must come from the server, not from a value the app writes and later
trusts.

---

## Order of work

1. Provision Stripe through the Marketplace; add the subscription price.
2. `GET /api/licence` + webhook, alongside the existing `sdk-token` route.
3. `LicenceStore`, scoped, failing open, with the grace window.
4. The gate itself — a soft banner, then a stop on live scoring, never on history.
5. Checkout hop from Settings → Account, beside sign-out.

Steps 2–5 are ordinary work. Step 1 needs a Vercel account and a dashboard
handshake, so it is the one that needs the person, not the agent.
