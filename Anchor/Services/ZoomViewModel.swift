//
//  ZoomViewModel.swift
//  Anchor
//
//  Owns the polling loop, converts Zoom data into Student objects, and pushes
//  them into EngagementStore. All connection state the UI shows lives here.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ZoomViewModel: ObservableObject {

    // MARK: - Connection state

    enum ConnectionState: Equatable {
        case idle                        // never connected
        case connecting
        case connected(meetingTopic: String)
        case waitingForMeeting           // authenticated, no live meeting yet
        case retrying(after: TimeInterval, reason: String)
        case failed(ZoomError)

        var isActive: Bool {
            switch self {
            case .connected, .waitingForMeeting, .connecting, .retrying: true
            case .idle, .failed: false
            }
        }

        var label: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting…"
            case .connected: "Connected"
            case .waitingForMeeting: "Waiting for meeting"
            case .retrying: "Reconnecting…"
            case .failed: "Disconnected"
            }
        }

        var symbolName: String {
            switch self {
            case .idle: "circle.dashed"
            case .connecting, .retrying: "arrow.triangle.2.circlepath"
            case .connected: "checkmark.circle.fill"
            case .waitingForMeeting: "clock.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }

    // MARK: - Published

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var account: ZoomAccountInfo?
    @Published private(set) var meeting: ZoomMeeting?
    @Published private(set) var capabilities = ZoomCapabilities()
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: ZoomError?
    @Published private(set) var consecutiveFailures = 0

#if DEBUG
    /// Presents a connected Zoom session without one, for website screenshots.
    /// Stores no credentials and opens no connection — see DemoData.swift.
    func applyDemoConnection() {
        state = .connected(meetingTopic: DemoData.meeting.title)
        lastSyncedAt = Date()
        lastError = nil
        consecutiveFailures = 0
        capabilities = ZoomCapabilities(
            liveMeetingList: true, liveParticipants: true, muteState: true,
            videoState: true, handRaised: true, audioLevel: true, chat: true
        )
    }
#endif
    /// True while the browser sign-in is open, so Settings can say so rather
    /// than looking inert while the teacher is in Safari.
    @Published private(set) var isConnectingAccount = false

    // MARK: - Bot

    @Published private(set) var botSession: BotSession?
    /// Set when a call was detected but Anchor can't work out which meeting it
    /// is — the teacher joined someone else's call, so REST can't see it.
    @Published private(set) var needsMeetingNumber = false
    @Published private(set) var botStatus: String?
    /// Presented after every successful bot join. A topic belongs to one class,
    /// so this deliberately does not remember a dismissal for the next join.
    @Published private(set) var isLessonTopicPromptPresented = false

    // MARK: - Dependencies

    private let store: EngagementStore
    /// Live topic and recommendations. Driven from here rather than observing
    /// the store, so a pass always runs against the roster that was just
    /// ingested rather than one refresh behind it.
    private let coach: LiveCoachViewModel
    private var service: ZoomDataProviding
    private var pollTask: Task<Void, Never>?
    private var bot: MeetingBotProviding?
    /// Whether the bot path has already tried to read the teacher's own account.
    /// See `syncFromBot`.
    private var didAttemptAccountLookup = false

    static let shared = ZoomViewModel(store: .shared)

    init(
        store: EngagementStore,
        service: ZoomDataProviding? = nil,
        coach: LiveCoachViewModel = .shared
    ) {
        self.store = store
        self.coach = coach
        self.service = service ?? Self.makeLiveService()
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Control

    /// Swaps the backing service — used to run against the mock.
    func useService(_ new: ZoomDataProviding) {
        stop()
        service = new
        // The identity behind the old service says nothing about this one.
        account = nil
        didAttemptAccountLookup = false
    }

    /// Rebuilds the live service around whichever Zoom credential is available.
    ///
    /// Order matters: a teacher's browser sign-in wins over Server-to-Server
    /// credentials. Both can be present — a school may still provision the S2S
    /// pair for the bot — and the teacher's own grant is the one that reflects
    /// *their* meetings and their plan.
    func useLiveService() {
        useService(Self.makeLiveService())
    }

    static func makeLiveService() -> ZoomDataProviding {
        if ZoomOAuthStore.shared.isConnected {
            return ZoomService(userTokens: .shared)
        }
        return ZoomService(credentialsProvider: { await ZoomCredentialsStore.shared.snapshot() })
    }

    /// Whether Anchor can talk to Zoom at all, by either route.
    static var hasAnyZoomCredential: Bool {
        ZoomOAuthStore.shared.isConnected || ZoomCredentialsStore.shared.hasCredentials
    }

    // MARK: - Browser sign-in

    /// Runs the Zoom OAuth flow, then proves the token works before claiming a
    /// connection. `verifyConnection` is not ceremony: a grant can come back
    /// valid and still be unusable — wrong account type, or a scope the
    /// Marketplace app lost since it was registered — and finding that out here
    /// means Settings can say so instead of the dashboard sitting empty.
    func connectAccount() async -> Result<ZoomAccountInfo, ZoomError> {
        isConnectingAccount = true
        defer { isConnectingAccount = false }

        do {
            _ = try await ZoomUserTokenProvider.shared.connect()
        } catch let error as ZoomError {
            return fail(with: error)
        } catch {
            return fail(with: .authorizationFailed(error.localizedDescription))
        }

        useService(ZoomService(userTokens: .shared))

        do {
            let info = try await service.verifyConnection()
            account = info
            ZoomOAuthStore.shared.setAccountLabel(info.email ?? info.displayName)
            lastError = nil
            start()
            return .success(info)
        } catch let error as ZoomError {
            return fail(with: error)
        } catch {
            return fail(with: .network(error.localizedDescription))
        }
    }

    private func fail(with error: ZoomError) -> Result<ZoomAccountInfo, ZoomError> {
        lastError = error
        state = .failed(error)
        return .failure(error)
    }

    /// Signs the teacher out: revokes at Zoom, clears the Keychain, and drops
    /// back to whatever credential is left — usually none.
    func disconnectAccount() async {
        stop()
        await ZoomUserTokenProvider.shared.disconnect()
        account = nil
        useLiveService()
    }

    func start() {
        guard pollTask == nil else { return }
        store.setDataSource(.zoom)
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        state = .idle
        store.setDataSource(.none)      // clears the roster; nothing stale lingers
        store.setConnectionSummary(nil)
        clearParticipantEmails()
        // The transcript, the topic and the recommendations all belong to the
        // meeting that just ended.
        coach.clear()
        // A fresh connection gets a fresh attempt at reading the teacher's
        // account — the credentials may be exactly what was just fixed.
        didAttemptAccountLookup = false
    }

    // MARK: - Detected-call flow

    /// Called when the teacher taps "Yes, connect" on the call notification.
    ///
    /// Anchor knows a call is happening but not *which* meeting. If they're the
    /// host, REST can tell us. If they joined someone else's call, it can't —
    /// and we ask rather than guess.
    func connectToDetectedCall() async {
        state = .connecting
        botStatus = "Looking for the meeting…"

        if let resolved = await resolveMeetingNumber() {
            await joinBot(meetingNumber: resolved, passcode: nil)
        } else {
            needsMeetingNumber = true
            botStatus = "Enter the meeting number to let Anchor join."
            store.setConnectionSummary("Call detected — Anchor needs the meeting number to join.")
        }
    }

    /// Asks Zoom for a live meeting hosted by this account.
    private func resolveMeetingNumber() async -> String? {
        guard Self.hasAnyZoomCredential else { return nil }
        guard let live = try? await service.liveMeetings(), let first = live.first else { return nil }
        meeting = first
        return first.id
    }

    /// Live meetings the *teacher's* account hosts. Used by the coordinator to
    /// confirm host status before prompting.
    func hostedLiveMeetings() async throws -> [ZoomMeeting] {
        try await service.liveMeetings()
    }

    /// Builds a bot from the credentials in the Keychain and sends it in.
    /// This is the "Yes" path: Keychain → bot OAuth → join.
    /// Sends the bot in using whatever Zoom identity is already available.
    ///
    /// This is the "Yes, monitor" path, so it has to work for a teacher who has
    /// only ever clicked **Connect Zoom** — a pilot cannot ask every teacher to
    /// register a Server-to-Server app. Two credentials are involved, and only
    /// one of them is per-teacher:
    ///
    /// - The **Meeting SDK Key/Secret** authenticates Anchor itself to the SDK.
    ///   App-level, shipped with the build, identical for every teacher.
    /// - The **account identity** supplies the ZAK, which decides *who* the bot
    ///   joins as. This is the teacher's own browser grant when there is one —
    ///   `makeLiveService` already prefers it — falling back to the
    ///   Server-to-Server pair where a school provisioned one for a dedicated
    ///   bot account.
    ///
    /// Both failures are reported before the bot is built, because a missing
    /// credential otherwise surfaces four steps later as an opaque SDK error.
    func joinBotUsingStoredCredentials(
        meetingNumber: String,
        passcode: String?
    ) async -> Result<BotSession, ZoomError> {
        guard let sdk = MeetingSDKCredentialStore.resolved() else {
            let error = ZoomError.missingSDKCredentials
            botStatus = error.errorDescription
            return .failure(error)
        }

        // Some Zoom identity has to exist, or there is no ZAK and no way to
        // verify the meeting — `notSignedIn` says which button to press,
        // whereas the SDK's own failure would not.
        guard Self.hasAnyZoomCredential else {
            let error = ZoomError.notSignedIn
            botStatus = error.errorDescription
            return .failure(error)
        }

        bot = ZoomMeetingSDKBot(
            tokenProvider: MeetingSDKTokenProvider(sdkKey: sdk.key, sdkSecret: sdk.secret),
            accountService: Self.makeLiveService()
        )
        await joinBot(meetingNumber: meetingNumber, passcode: passcode)

        if let session = botSession { return .success(session) }
        return .failure(lastError ?? .unsupported(botStatus ?? "The bot could not join."))
    }

    /// The bot authenticates against its own Zoom account (real OAuth), and
    /// signs Meeting SDK tokens with the SDK Key/Secret when those are present.
    private func makeBot(from credentials: ZoomCredentials) -> MeetingBotProviding {
        let accountService = ZoomService(
            credentialsProvider: { credentials }
        )
        return ZoomMeetingSDKBot(
            tokenProvider: MeetingSDKTokenProvider(
                sdkKey: credentials.sdkKey ?? "",
                sdkSecret: credentials.sdkSecret ?? ""
            ),
            accountService: accountService
        )
    }

    /// Sends the bot into the meeting and switches the dashboard onto its data.
    func joinBot(meetingNumber: String, passcode: String?) async {
        needsMeetingNumber = false

        let bot = bot ?? makeDefaultBot()
        self.bot = bot

        botStatus = "Joining meeting \(meetingNumber)…"

        do {
            let session = try await bot.join(
                BotJoinRequest(meetingNumber: meetingNumber, passcode: passcode)
            )
            // A manually entered topic is scoped to the class that just ended.
            // Do this before showing the prompt so it cannot be seeded with a
            // previous lesson's subject.
            coach.clear()
            botSession = session
            clearParticipantEmails()
            capabilities = await bot.capabilities()
            botStatus = "Anchor joined as \"\(session.displayName)\"."
            store.setConnectionSummary("Bot in meeting \(meetingNumber)")

            start()
            await performSync()
            isLessonTopicPromptPresented = true
        } catch let error as ZoomError {
            botSession = nil
            botStatus = error.errorDescription
            handle(error)
        } catch {
            botSession = nil
            botStatus = error.localizedDescription
            handle(.network(error.localizedDescription))
        }
    }

    func leaveBot() async {
        try? await bot?.leave()
        botSession = nil
        botStatus = nil
        capabilities = ZoomCapabilities()
        clearParticipantEmails()
        coach.clear()
        isLessonTopicPromptPresented = false
    }

    /// Called by the per-class topic sheet after either saving a topic or
    /// intentionally continuing without one.
    func dismissLessonTopicPrompt() {
        isLessonTopicPromptPresented = false
    }

    func useSDKBot(sdkKey: String, sdkSecret: String) {
        bot = ZoomMeetingSDKBot(
            tokenProvider: MeetingSDKTokenProvider(sdkKey: sdkKey, sdkSecret: sdkSecret)
        )
    }

    /// Used by the manual "Join" field, which has no credentials of its own.
    ///
    /// Prefers the bot's own account and falls back to the teacher's. Both go
    /// through `makeBot(from:)` so the manual path gets the same account service
    /// as the notification path — without one the bot cannot authenticate or
    /// fetch a ZAK, and every join fails before it reaches the SDK.
    private func makeDefaultBot() -> MeetingBotProviding {
        let store = ZoomCredentialsStore.shared
        guard let credentials = store.botSnapshot() ?? store.snapshot() else {
            // Nothing on file at all — the adapter will explain itself.
            return ZoomMeetingSDKBot(
                tokenProvider: MeetingSDKTokenProvider(sdkKey: "", sdkSecret: "")
            )
        }
        return makeBot(from: credentials)
    }

    /// One-shot connectivity check for the Settings "Test Connection" button.
    func testConnection() async -> Result<ZoomAccountInfo, ZoomError> {
        do {
            let info = try await service.verifyConnection()
            account = info
            lastError = nil
            return .success(info)
        } catch let error as ZoomError {
            lastError = error
            return .failure(error)
        } catch {
            let wrapped = ZoomError.network(error.localizedDescription)
            lastError = wrapped
            return .failure(wrapped)
        }
    }

    func refreshNow() async {
        await performSync()
    }

    // MARK: - Polling loop

    private func pollLoop() async {
        while !Task.isCancelled {
            await performSync()

            if consecutiveFailures > 0 {
                state = .retrying(
                    after: nextInterval(),
                    reason: lastError?.errorDescription ?? "Retrying"
                )
            }

            // Wait in short slices and re-check the target each time, so
            // dropping the refresh interval — or the bot joining and unlocking
            // the faster floor — takes effect within half a second instead of
            // after the current wait runs out.
            let waitStartedAt = Date()
            while !Task.isCancelled {
                if Date().timeIntervalSince(waitStartedAt) >= nextInterval() { break }
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return   // cancelled
                }
            }
        }
    }

    /// Poll interval on success; exponential backoff after failures.
    ///
    /// The floor depends on where the data comes from. A joined bot is read
    /// in-process, so it can honour a 10-second setting exactly; the REST
    /// Dashboard path is heavy rate-limited and stays at 30 seconds however low
    /// the setting goes. `pollFloorNotice` tells the teacher when that applies
    /// rather than silently ignoring what they picked.
    private func nextInterval() -> TimeInterval {
        guard consecutiveFailures > 0 else {
            return max(currentPollFloor, store.settings.refreshInterval.seconds)
        }
        let index = min(consecutiveFailures - 1, ZoomConfig.backoffLadder.count - 1)
        let base = ZoomConfig.backoffLadder[index]
        // Jitter so multiple clients don't retry in lockstep.
        return base + Double.random(in: 0...(base * 0.2))
    }

    /// Fastest cadence the current data source can sustain.
    private var currentPollFloor: TimeInterval {
        botSession != nil ? ZoomConfig.minimumBotPollInterval : ZoomConfig.minimumPollInterval
    }

    /// Set when the chosen refresh interval can't be honoured on this path, so
    /// Settings can explain the gap instead of appearing to ignore the picker.
    var pollFloorNotice: String? {
        let chosen = store.settings.refreshInterval
        guard chosen.seconds < currentPollFloor else { return nil }
        return "Zoom's REST API is rate limited — refreshing every "
            + "\(Int(currentPollFloor))s. Have the bot join the meeting for "
            + "\(chosen.label) updates."
    }

    // MARK: - Sync

    private func performSync() async {
        if case .idle = state { state = .connecting }
        if case .failed = state { state = .connecting }

        // The dashboard shows "Updating scores…" for the whole cycle. `defer`
        // rather than clearing it on the happy path, so a sync that throws or
        // returns early can't leave the indicator spinning forever.
        store.beginRefresh()
        defer { store.endRefresh() }

        do {
            // Bot path takes priority: it sees mute, camera, hands and audio,
            // and works even when the teacher is a guest in someone else's call
            // (where REST can see nothing at all).
            if let bot, await bot.isJoined {
                try await syncFromBot(bot)
                return
            }

            if account == nil {
                account = try await service.verifyConnection()
            }

            let live = try await service.liveMeetings()

            guard let current = live.first else {
                meeting = nil
                state = .waitingForMeeting
                consecutiveFailures = 0
                lastError = nil
                store.clear()   // no meeting means no roster
                // And no roster means no one to recommend anything about. Left
                // alone, the last lesson's cards would sit under a "waiting for
                // a meeting" header until the next class started.
                //
                // `clearLiveState`, not `clear`: this branch runs on every poll
                // before the class begins, which is precisely when a teacher
                // would be typing tomorrow's topic into Settings.
                coach.clearLiveState()
                store.setConnectionSummary("Connected · waiting for a live meeting you host")
                return
            }

            meeting = current

            let participants = classRoster(
                from: try await service.liveParticipants(meeting: current),
                meeting: current
            )

            // Chat is expected to be unavailable over REST; treat it as an empty
            // feed rather than a sync failure.
            let chat: [ZoomChat]
            do {
                chat = try await service.chatMessages(meeting: current)
            } catch {
                chat = []
            }

            if capabilities == ZoomCapabilities() {
                capabilities = await service.probeCapabilities(meeting: current)
            }

            store.ingest(
                meeting: current,
                participants: participants,
                chat: chat,
                capabilities: capabilities
            )

            lastSyncedAt = Date()
            consecutiveFailures = 0
            lastError = nil
            state = .connected(meetingTopic: current.topic)
            // No transcript on this path — REST cannot see captions in a live
            // meeting any more than it can see chat. Recommendations still run:
            // they fall back to the topic the teacher typed, and to the
            // engagement signals alone if there isn't one.
            coach.refresh(
                students: store.students,
                sensitivity: store.settings.sensitivity,
                notifiesOnHighRisk: store.settings.notifyOnHighRisk
            )

            // Students, not participants: the teacher and the bot were filtered
            // out above, so calling this "in meeting" would read as a headcount
            // that is always two short of what Zoom shows.
            store.setConnectionSummary(
                "Live · \(participants.filter(\.isInMeeting).count) students in meeting"
            )

        } catch let error as ZoomError {
            handle(error)
        } catch {
            handle(.network(error.localizedDescription))
        }
    }

    private func syncFromBot(_ bot: MeetingBotProviding) async throws {
        // Who the teacher is, for `classRoster`. The REST path learns this on
        // its way past; the bot path never calls it otherwise. Deliberately
        // non-fatal — the SDK reports host status directly, so this only sharpens
        // the case where the teacher is in the call without hosting it, and a
        // credentials problem here must not cost the class a scoring pass. Tried
        // once, not once per poll: an account Anchor can't read now won't have
        // become readable ten seconds later.
        if account == nil, !didAttemptAccountLookup {
            didAttemptAccountLookup = true
            account = try? await service.verifyConnection()
        }

        // The Meeting SDK never reports emails, so anyone the bot sees would be
        // name-only identity — and unmatchable against a Classroom roster.
        // REST knows the addresses for participants on this account; fold them
        // in before scoring so those students link on a verified email.
        //
        // Roles are applied *after* the email fill, not before: an address is
        // one of the ways the teacher is recognised, and filtering first would
        // throw away the evidence. It does mean the bot and the teacher cost one
        // directory lookup each, which is a lookup already made for the class.
        //
        // Both lists are kept. Scoring wants students only; transcript
        // attribution wants everyone, because the teacher is the speaker whose
        // lines carry the lesson.
        let everyone = await withRESTEmails(try await bot.participants())
        let roles = roles(for: meeting)
        roles.traceExclusions(from: everyone)
        let participants = roles.students(from: everyone)

        // Unlike the REST path, the bot *is* a client in the meeting, so chat is
        // genuinely available here. Still non-fatal: a chat read that fails
        // should not throw away a good participant sync.
        let chat = (try? await bot.chatMessages()) ?? []

        // Live captions, on the same terms as chat: only a joined client can see
        // them, and a transcript that fails to arrive costs the topic-aware half
        // of the recommendations and nothing else. `startTranscription` is
        // idempotent — it sends the actual request to Zoom at most once.
        await bot.startTranscription()
        let rawTranscript = (try? await bot.transcript()) ?? []
        let transcriptAvailability = await bot.transcriptAvailability()

        let session = botSession

        // Use the REST meeting when we have it; otherwise synthesise one from
        // what the bot knows, so the dashboard still has a title and a clock.
        let subject = meeting ?? ZoomMeeting(
            id: session?.meetingNumber ?? "unknown",
            uuid: nil,
            topic: "Meeting \(session?.meetingNumber ?? "")",
            hostID: nil,
            hostEmail: nil,
            startTime: session?.joinedAt,
            durationMinutes: nil,
            participantCount: participants.filter(\.isInMeeting).count,
            isLive: true,
            timezone: TimeZone.current.identifier
        )

        store.ingest(
            meeting: subject,
            participants: participants,
            chat: chat,
            capabilities: capabilities
        )

        coach.transcript.ingest(
            raw: rawTranscript,
            participants: everyone,
            roles: roles,
            availability: transcriptAvailability
        )
        coach.refresh(
            students: store.students,
            sensitivity: store.settings.sensitivity,
            notifiesOnHighRisk: store.settings.notifyOnHighRisk
        )

        lastSyncedAt = Date()
        consecutiveFailures = 0
        lastError = nil
        state = .connected(meetingTopic: subject.topic)
        store.setConnectionSummary(
            "Bot in meeting · \(participants.filter(\.isInMeeting).count) students"
        )
    }

    // MARK: - Who counts as a student

    /// Drops the two people in every call who are not being taught: the teacher
    /// and Anchor's own bot. See MeetingRoles for how each is recognised.
    ///
    /// Applied here rather than in the store so *everything* downstream agrees —
    /// the roster, the "N in meeting" summary, the archive and next week's recap
    /// are all built from what this returns.
    private func classRoster(
        from participants: [ZoomParticipant],
        meeting: ZoomMeeting?
    ) -> [ZoomParticipant] {
        let roles = roles(for: meeting)
        roles.traceExclusions(from: participants)
        return roles.students(from: participants)
    }

    /// Who Anchor believes the teacher and the bot are in this meeting.
    ///
    /// Separate from `classRoster` because the bot path needs the roles
    /// themselves, not just their verdict: transcript attribution has to know
    /// which speaker is the teacher, and that question is only answerable with
    /// the full participant list in hand.
    private func roles(for meeting: ZoomMeeting?) -> MeetingRoles {
        MeetingRoles(
            hostEmail: meeting?.hostEmail,
            hostAccountID: meeting?.hostID,
            teacherEmail: account?.email,
            teacherName: account?.displayName,
            botName: botSession?.displayName
        )
    }

    // MARK: - Participant emails on the bot path

    /// Whether participants are getting verified email identities, and if not,
    /// why. Read by Settings and by the per-student academic panel — without it
    /// the reason lived only in a `#if DEBUG` console trace.
    @Published private(set) var emailVerification: ZoomEmailVerification = .notAttempted

    /// Emails Zoom's Dashboard API reported for the current meeting, keyed the
    /// same way `Self.directoryKeys(for:)` keys an SDK participant.
    private var participantEmails: [String: String] = [:]
    private var participantEmailsFetchedAt: Date?
    private var participantEmailFailures = 0

    /// Addresses don't change during a class, and `/metrics` is one of Zoom's
    /// rate-limited "heavy" endpoints — so this runs on its own slow clock
    /// rather than on every 10-second bot poll.
    private static let participantEmailInterval: TimeInterval = 120
    /// After this many failures the meeting is assumed to be invisible to REST
    /// — the teacher is a guest in someone else's call, or the account has no
    /// Dashboard access — and Anchor stops asking for the rest of the session.
    private static let participantEmailFailureLimit = 3

    /// Fills in emails the Meeting SDK can't supply, from the REST Dashboard.
    ///
    /// Best effort by design: when REST can't see the meeting, participants come
    /// back exactly as the SDK gave them and matching falls back to display
    /// name. A failure here must never cost the teacher a scoring pass.
    private func withRESTEmails(_ participants: [ZoomParticipant]) async -> [ZoomParticipant] {
        let missing = participants.filter { ($0.email ?? "").trimmed.isEmpty }
        guard !missing.isEmpty else { return participants }

        await refreshParticipantEmailsIfNeeded()
        guard !participantEmails.isEmpty else {
            // Distinguish "Zoom refused to answer" from "Zoom answered and had
            // nothing" — they look identical here but need different fixes, and
            // only one of them is anything the teacher can act on.
            if case .unavailable = emailVerification {} else {
                emailVerification = .unreported(participants: missing.count)
            }
            AnchorDiag.log(
                "email-fill: \(missing.count) participant(s) without an email, "
                + "REST directory is empty — \(emailVerification.headline)"
            )
            return participants
        }

        var filled = 0
        let enriched = participants.map { participant -> ZoomParticipant in
            guard (participant.email ?? "").trimmed.isEmpty else { return participant }
            guard let email = Self.directoryKeys(for: participant)
                .lazy
                .compactMap({ self.participantEmails[$0] })
                .first
            else {
                AnchorDiag.log(
                    "email-fill: no REST address for \"\(participant.name)\" under keys "
                    + "\(Self.directoryKeys(for: participant)) — directory holds "
                    + "\(Array(participantEmails.keys).sorted())"
                )
                return participant
            }

            filled += 1
            var copy = participant
            copy.email = email
            return copy
        }

        emailVerification = filled > 0
            ? .verified(filled: filled, of: missing.count)
            : .unreported(participants: missing.count)

        AnchorDiag.log("email-fill: filled \(filled) of \(missing.count) missing address(es)")
        return enriched
    }

    private func refreshParticipantEmailsIfNeeded() async {
        guard participantEmailFailures < Self.participantEmailFailureLimit else { return }
        if let fetchedAt = participantEmailsFetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.participantEmailInterval {
            return
        }

        // The REST meeting when we have one — it carries the instance UUID the
        // Dashboard endpoint prefers. Otherwise the number the bot dialled.
        guard let subject = meeting ?? botSession.map({ session in
            ZoomMeeting(
                id: session.meetingNumber,
                uuid: nil,
                topic: "",
                hostID: nil,
                hostEmail: nil,
                startTime: session.joinedAt,
                durationMinutes: nil,
                participantCount: 0,
                isLive: true,
                timezone: nil
            )
        }) else {
            AnchorDiag.log("email-fill: no meeting to query — REST lookup skipped")
            return
        }

        participantEmailsFetchedAt = Date()
        do {
            let rest = try await service.liveParticipants(meeting: subject)
            participantEmails = Self.emailDirectory(from: rest)
            participantEmailFailures = 0
            if participantEmails.isEmpty {
                emailVerification = .unreported(participants: rest.count)
            }
            AnchorDiag.log(
                "email-fill: REST returned \(rest.count) participant(s) for meeting "
                + "\(subject.id); "
                + rest.map { "\"\($0.name)\" user=\($0.userID ?? "-") "
                    + "email=\($0.email?.trimmed.isEmpty == false ? $0.email! : "none")" }
                    .joined(separator: ", ")
            )
        } catch {
            let zoomError = (error as? ZoomError) ?? .network(error.localizedDescription)
            emailVerification = .unavailable(zoomError)

            // A plan tier or a missing scope is a permanent no. Spending the
            // remaining attempts on it just delays the honest answer by four
            // minutes, so treat the first refusal as final.
            participantEmailFailures = zoomError.isRetryable
                ? participantEmailFailures + 1
                : Self.participantEmailFailureLimit

            AnchorDiag.log(
                "email-fill: REST lookup for meeting \(subject.id) failed "
                + "(\(participantEmailFailures)/\(Self.participantEmailFailureLimit)"
                + "\(zoomError.isRetryable ? "" : ", permanent")): "
                + "\(zoomError.errorDescription ?? "unknown")"
            )
        }
    }

    /// Discards the directory when the meeting changes — an address indexed
    /// under an in-meeting participant id means nothing in the next call.
    private func clearParticipantEmails() {
        participantEmails = [:]
        participantEmailsFetchedAt = nil
        participantEmailFailures = 0
        emailVerification = .notAttempted
    }

    /// Every key a participant could be found under, most trustworthy first.
    ///
    /// Zoom's Dashboard `user_id` is the participant's id *within this meeting*,
    /// which is the same number the Meeting SDK hands out — so the two sources
    /// join on it exactly. Display name is the fallback for when they don't.
    private static func directoryKeys(for participant: ZoomParticipant) -> [String] {
        var keys: [String] = []
        for candidate in [participant.userID, participant.participantID] {
            guard let candidate = candidate?.trimmed, !candidate.isEmpty else { continue }
            let key = "user:" + candidate
            if !keys.contains(key) { keys.append(key) }
        }
        if let name = ClassroomNameKey.make(participant.name) {
            keys.append("name:" + name)
        }
        return keys
    }

    /// Index of REST-reported addresses. A key that two different people answer
    /// to — two "Jane"s in the same call — is dropped rather than guessed at.
    static func emailDirectory(from participants: [ZoomParticipant]) -> [String: String] {
        var directory: [String: String] = [:]
        var ambiguous: Set<String> = []

        for participant in participants {
            guard let email = participant.email?.trimmed, !email.isEmpty else { continue }
            for key in directoryKeys(for: participant) {
                if let existing = directory[key], existing.lowercased() != email.lowercased() {
                    ambiguous.insert(key)
                } else {
                    directory[key] = email
                }
            }
        }

        for key in ambiguous { directory.removeValue(forKey: key) }
        return directory
    }

    private func handle(_ error: ZoomError) {
        guard error != .cancelled else { return }

        lastError = error
        consecutiveFailures += 1
        state = .failed(error)

        store.setConnectionSummary(
            [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        )

        // Bad credentials or missing scopes will never fix themselves — stop
        // burning API quota and wait for the teacher.
        if error.requiresUserAction {
            pollTask?.cancel()
            pollTask = nil
        }
    }
}
