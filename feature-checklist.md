# Anchor — Feature Checklist for v1

## Bugs to fix

- [ ] Bot appears as a scored "student" in its own roster — filter with the SDK's `isMySelf` flag (unused today in `ZoomMeetingSDKBridge.swift`)
- [ ] "Send check-in" button is a UI stub — shows a confirmation toast but never actually sends a chat message via `sendChatMsgTo:`. Either wire it to the real Zoom chat controller or relabel it so it doesn't imply an action that didn't happen
- [ ] "Pair in breakout" button is the same — confirms locally but doesn't call Zoom's breakout room controller (`ZoomSDKNewBreakoutRoomController`, already in the linked SDK). Wire it up or remove it
- [ ] Reconnection handling untested: meeting drop, laptop sleep, Wi-Fi blip mid-session — verify the dashboard recovers instead of silently going stale
- [ ] Multi-participant scale untested: everything's been validated with 2–3 known accounts, not a real 20–30 student class — check UI, polling cadence, and Classroom sync cost at real scale

## Matching & identity

- [ ] Accept that verified-email matching will not work for most individual teachers (Zoom Dashboard API needs a Business+ plan on the account being queried — this is a Zoom-side limitation, not fixable by more code) — stop treating it as the primary path
- [ ] Make name-matching + manual "Link to student" override the polished, primary flow instead of an unverified fallback — it's already built, just needs to feel intentional rather than second-best
- [ ] Handle the ambiguous-name case gracefully in the UI (two students, same normalized name) — right now the match table silently drops both; the teacher should see *why* neither linked, not just a blank

## Core experience gaps

- [ ] Class-level historical trend — you already store 9+ recorded sessions per class but the Home view only shows single point-in-time numbers. A simple chart of class average across sessions is cheap to build and is the difference between "here's a number" and "here's whether this class is improving"
- [ ] Surface the existing `TrainingDataExporter.swift` capability in the UI if it's meant for teachers/admins to export data — right now it exists in code but isn't reachable from anywhere a user would find it
- [ ] Meeting join flow: currently separate meeting-number and passcode fields; accept a pasted Zoom link and auto-parse both
- [ ] Review every empty/error state for plain-language clarity — a teacher, not a developer, is the one reading "REST directory is empty" style messages if any slipped through

## The differentiator feature

- [ ] Live transcript capture via `ZoomSDKCloseCaptionController` (delegate-based, confirmed available in your linked SDK — `onLiveTranscriptionMsgInfoReceived:`)
- [ ] Verify live transcription is actually enabled/available on your Zoom account/plan before building further — some Zoom plans gate this
- [ ] Rolling transcript buffer, same bounded pattern already used for chat
- [ ] Topic extraction from the transcript window (Featherless or another lightweight model — don't burn a full LLM call on every line)
- [ ] Cross-reference extracted topic against `ClassroomAssignment` titles / `AcademicSnapshot` missing work — this data already exists, just needs to be read at the right moment
- [ ] Trigger condition: only generate a recommendation when a student is already silent/struggling *and* the live topic matches something they're weak in — keeps it from being noisy and keeps API cost sane
- [ ] Feed the generated recommendation into the existing "Suggested Next Steps" panel, tagged clearly as AI-generated so it's distinguishable from the rule-based suggestions already there

## Nice-to-haves once the above is solid

- [ ] Feedback loop on suggestions ("was this helpful?") to eventually improve the model instead of it staying static
- [ ] Notification/alert tuning beyond the current on/off toggles — e.g. quiet hours, per-class thresholds
- [ ] Support for monitoring more than one class/meeting concurrently, if that's a real use case for your target teachers
