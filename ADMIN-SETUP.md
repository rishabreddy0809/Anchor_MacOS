# Anchor — setting up a school's Zoom account

For the **partner setup call**: a school's Zoom admin, with Rishab on the call.
Budget an hour. It is done once per school, not once per teacher.

This is the whole reason the per-school route exists. An app created under the
school's own Zoom account makes every teacher on that account an **internal
user**, and none of Zoom's Marketplace review applies. That is what turns a
multi-week review queue into an hour of an admin's time.

> **Nothing here is asked of a teacher.** A teacher's entire setup is pressing
> **Connect Zoom** once. If any of this leaks into a teacher's day, something
> has gone wrong.

---

## Before the call

- The admin needs to be a **Zoom account owner or admin** on the school's
  account. A teacher account cannot create Marketplace apps.
- **Find out the plan first, because it changes what Anchor can see.** The two
  participant scopes (`dashboard:read:list_meeting_participants:admin`,
  `report:read:list_meeting_participants:admin`) are gated on **Business,
  Education or Enterprise**. On Pro or Basic the Marketplace scope picker does
  not offer the Dashboard or Report categories at all — this is not a checkbox
  someone forgot, the categories are absent.
  - **Business/Education or better:** Anchor reads participants over the REST
    API *and* can run the in-meeting bot.
  - **Pro or Basic:** the REST path can find the meeting and identify the
    teacher but can never read who is in the room. **The bot becomes the only
    source of live signal.** A pilot on Basic or Pro that also cannot run the
    bot has no live signal at all, and the dashboard will correctly stay empty.
    Better to know this before the call than during it.

---

## Step 1 — the sign-in app (General app)

This is what makes **Connect Zoom** open a browser instead of asking a teacher
for a credential.

1. <https://marketplace.zoom.us> → **Develop → Build App → General App**,
   *user-managed*.
   - A **Server-to-Server OAuth app cannot be used here.** It has no
     authorization page at all, so there is nothing for a teacher to sign in to.
2. **App Listing → App Name** → set it to `Anchor`.
   - The consent screen shows this string **verbatim**. A freshly created app
     arrives named something like *"General app 392"*, and a teacher should not
     be asked to approve that. It is set on **App Listing**, *not* the pencil
     beside the page header.
3. **OAuth Redirect URL**, on the **Development** credentials tab:

   ```
   https://anchor-oauth-bounce.vercel.app/oauth/zoom
   ```

   Paste the **identical** string into the **OAuth allow list** below it as
   well. Setting only one of the two fields is the most common way this breaks,
   and it fails with an unhelpful `Invalid redirect URL`.
   - Zoom matches **character for character** — no trailing slash.
   - Development and Production carry separate credentials *and* separate
     redirect registrations. Use **Development**; editing Production has no
     effect on the Development pair.
4. **Scopes** — add exactly:
   - `meeting:read:list_meetings` — find the class
   - `user:read:user` — identify the teacher
   - `user:read:zak` — mint the token the bot joins with
   - Plus the two participant scopes **if the plan offers them** (see above).
5. Copy the **Client ID** and **Client Secret** from the Development tab.

## Step 2 — the Meeting SDK app (the in-meeting bot)

A **separate, third** Marketplace registration. It authenticates *Anchor itself*
to the Meeting SDK; the sign-in app in step 1 authenticates the *teacher*. They
are easy to confuse — both are called a "Client ID/Secret" — and swapping them
makes the join fail locally with an error indistinguishable from a malformed
token.

1. **Develop → Build App → General App**, then enable **Embed → Meeting SDK**.
2. Answer **yes** to *"Are you developing a programmatic join use case?"*.
3. Copy its **Client ID** (this is the SDK **Key**) and **Client Secret**.

> **Why the school creates this one too.** Anchor ships with a Meeting SDK key,
> but it belongs to the developer's account and is unpublished, so it is not
> something teachers on another account can rely on. A Keychain entry wins over
> the shipped default, so pointing Anchor at the school's own SDK app needs no
> rebuild — see step 3.

## Step 3 — provision the four values into Anchor, once

**This is the step that does not have a GUI, on purpose.** The Settings →
Advanced panel that accepts credentials is compiled out of release builds
entirely, because a teacher should never be asked for one. Provisioning is
therefore a single Terminal command, run once on the teacher's Mac, by whoever
is doing the setup:

```bash
ANCHOR_ZOOM_OAUTH_CLIENT_ID='<step 1 Client ID>' \
ANCHOR_ZOOM_OAUTH_CLIENT_SECRET='<step 1 Client Secret>' \
ANCHOR_ZOOM_SDK_KEY='<step 2 Client ID>' \
ANCHOR_ZOOM_SDK_SECRET='<step 2 Client Secret>' \
/Applications/Anchor.app/Contents/MacOS/Anchor
```

- **Once is enough.** The values are written to the Keychain on that launch and
  read from there afterwards, so every later launch is an ordinary
  double-click. The environment variables are not needed again.
- **`ANCHOR_ZOOM_OAUTH_CLIENT_ID` and `ANCHOR_ZOOM_OAUTH_CLIENT_SECRET` must
  arrive together.** They are one registration, and Anchor will not complete
  half of it with the id it ships: the shipped public client belongs to
  *Anchor's* Marketplace app, so falling back to it would sign your teachers
  into the wrong app and fail with the "You cannot authorize" page below. If
  only the id lands, **Connect Zoom stays off** and this launch prints a line
  to the Terminal saying so — read it before closing the window. Rotating only
  the secret later is fine; both halves are then present.
- Quote the values. Zoom secrets can contain characters the shell would
  otherwise interpret.
- Nothing is echoed or written to a file. Close the Terminal window afterwards
  so the values do not sit in shell history — or prefix each line with a space
  if the admin's shell is configured to skip those.

> ### The trap this step exists to avoid
>
> If Anchor is launched *without* provisioning, it silently falls back to the
> developer's own Client ID. A teacher on the school's account is then an
> external user of an unpublished app, and Zoom answers **"You cannot
> authorize"** — which is the *same page* a misconfigured redirect URL
> produces. So a skipped provisioning step and a typo'd redirect URL look
> identical, and the natural reaction is to go back and re-check step 1, which
> is not where the problem is.
>
> **If you see "You cannot authorize", check step 3 before step 1.**
>
> Since 2026-08-20 this trap has one fewer way in: a *half*-run step 3 — the
> client ID without its secret — no longer reaches Zoom at all. It leaves
> Connect Zoom off, with a reason, and prints one to the Terminal. Only a step
> 3 that was skipped entirely still produces the misleading page.

## Step 4 — the teacher's part

One click. **Settings → Zoom → Connect Zoom**, sign in, land back in Anchor.

Their tokens go to the Keychain, the refresh token rotates on every use, and the
bot joins meetings *as them* using a token minted from their own grant. No
teacher registers anything, and no teacher types a credential.

---

## Before you end the call, confirm these four

Do not treat the setup as done on the strength of the app existing in the
Marketplace. Each of these fails in a way that is quiet or misleading:

1. **The consent screen says "Anchor"**, not "General app N". If it does not,
   step 1.2 was set on the wrong field and every teacher sees it.
2. **A teacher who is not the admin can complete Connect Zoom** — sign in as one
   during the call. The admin succeeding proves less than it appears to, because
   the admin is the app's owner.
3. **The dashboard shows participants once a test meeting has someone in it.**
   Empty here separates the two plan cases: on Business/Education it means
   something is wrong, on Pro/Basic it is expected and the bot is the only path.
4. **The bot appears in the participant list**, named
   **"Anchor (engagement assistant)"**. If it is absent, the Meeting SDK
   credentials from step 2 did not land — that is step 3, not step 2.

## What is deliberately not here

- **Publishing to the Marketplace.** The whole point of this route is that an
  internal app needs no review. Do not "activate for production" — that means
  Marketplace publication, which is the queue this exists to avoid.
- **A Server-to-Server app.** It used to be required for the bot and is not any
  more; the bot joins with the teacher's own identity. It remains supported for
  a school that specifically wants a dedicated robot account, and only then.

  **It does not connect Zoom on a teacher's behalf** (changed 2026-08-27). A
  Server-to-Server credential used to satisfy Anchor's "is Zoom connected?"
  check for everybody on the Mac, which meant the second teacher to sign in
  found Zoom already connected — to an account that was not theirs, holding
  none of their classes, so the dashboard sat empty with no explanation. Every
  teacher now connects their own Zoom in onboarding or Settings, whatever else
  is provisioned on the machine. See `ZoomViewModel.hasTeacherZoomConnection`.
