//
//  ZoomMeetingSDKBridge.swift
//  Anchor
//
//  Bridges Zoom's Objective-C Meeting SDK — delegate/callback based — to Swift
//  async/await, so `ZoomMeetingSDKBot` (in MeetingBot.swift) can `await` a join
//  the same way it awaits everything else.
//
//  Zoom's delegate protocols require an NSObject-conforming class, which is why
//  this is a plain `@MainActor final class` rather than an `actor`: the SDK's
//  UI-adjacent calls are documented as main-thread-only, and delegate callbacks
//  arrive on the main thread already.
//

import Foundation
import OSLog
import ZoomSDK

/// Zoom encrypts its own SDK logs, so when the SDK refuses a call there is
/// nothing readable on disk to explain why. These entries are the only record
/// of what Anchor actually handed it. Read with:
///   log show --last 10m --predicate 'subsystem == "com.anchor.zoomsdk"'
private let sdkLog = Logger(subsystem: "com.anchor.zoomsdk", category: "bridge")

final class ZoomMeetingSDKBridge: NSObject, @unchecked Sendable {

    static let shared = ZoomMeetingSDKBridge()

    private var isSDKInitialized = false
    private var authContinuation: CheckedContinuation<Void, Error>?
    private var joinContinuation: CheckedContinuation<Void, Error>?

    /// Chat arrives as one-shot delegate callbacks — the SDK keeps no history we
    /// can query — so every message has to be buffered here as it lands.
    /// Bounded because this runs for a whole class period: past the cap the
    /// oldest messages are dropped, since scoring cares about recent activity.
    private var chatMessages: [ZoomChat] = []
    private static let chatBufferLimit = 500

    /// Transcript lines in arrival order, and the index of each line's position
    /// by message id.
    ///
    /// Two structures rather than one because Zoom revises a line repeatedly as
    /// its recogniser firms up the words: a revision has to *replace* the line
    /// it revises, which needs a lookup, while the analyzer needs them in the
    /// order they were spoken. Appending revisions instead would feed the model
    /// "photo… photosyn… photosynthesis is when plants" as three separate
    /// utterances.
    private var transcriptLines: [RawTranscriptLine] = []
    private var transcriptIndexByID: [String: Int] = [:]
    /// A class period of captions is far more text than a class period of chat,
    /// and only the recent window is ever analysed — see
    /// TranscriptCaptureService.analysisWindow.
    private static let transcriptBufferLimit = 2_000
    private(set) var transcriptAvailability: TranscriptAvailability = .notStarted
    /// Set once `startLiveTranscription` has been accepted, so the poll loop can
    /// keep calling it without re-asking Zoom every ten seconds.
    private var didRequestTranscription = false

    private override init() {
        super.init()
    }

    // MARK: - Init

    @MainActor
    private func initializeIfNeeded() throws {
        guard !isSDKInitialized else { return }

        let params = ZoomSDKInitParams()
        params.zoomDomain = "zoom.us"
        params.enableLog = true

        if let fwPath = Bundle.main.privateFrameworksPath {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: fwPath).count) ?? -1
            print("ANCHOR-DIAG Frameworks dir (\(fwPath)) item count = \(count)")
        } else {
            print("ANCHOR-DIAG Bundle.main.privateFrameworksPath is nil")
        }

        let result = ZoomSDK.shared().initSDK(with: params)
        sdkLog.info("initSDK -> \(result.rawValue, privacy: .public)")
        print("ANCHOR-DIAG initSDK -> \(result.rawValue)")
        guard result == ZoomSDKError_Success else {
            throw ZoomError.unsupported("Zoom Meeting SDK failed to initialize (code \(result.rawValue)).")
        }

        let authService = ZoomSDK.shared().getAuthService()
        // Only the auth service exists before authentication; the meeting
        // service is created by the SDK once auth succeeds, so its delegate is
        // attached in joinMeeting(_:) instead.
        sdkLog.info("services: meeting=\(ZoomSDK.shared().getMeetingService() != nil, privacy: .public)")
        authService.delegate = self
        isSDKInitialized = true
    }

    // MARK: - Auth

    /// Authenticates the SDK with a locally signed SDK JWT. Must succeed before `join`.
    @MainActor
    func authenticate(jwtToken: String) async throws {
        try initializeIfNeeded()

        let authService = ZoomSDK.shared().getAuthService()

        if authService.isAuthorized() {
            sdkLog.info("already authorized; skipping sdkAuth")
            print("ANCHOR-DIAG already authorized; skipping sdkAuth")
            return
        }

        // The JWT is a bearer credential — log only its shape, never the token.
        let segments = jwtToken.split(separator: ".")
        sdkLog.info("""
            sdkAuth: jwt len=\(jwtToken.count, privacy: .public) \
            segments=\(segments.count, privacy: .public) \
            identity=\(authService.getSDKIdentity() ?? "nil", privacy: .public)
            """)
        print("ANCHOR-DIAG sdkAuth: jwt len=\(jwtToken.count) segments=\(segments.count) identity=\(authService.getSDKIdentity() ?? "nil")")

        let context = ZoomSDKAuthContext()
        context.jwtToken = jwtToken

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.authContinuation = continuation
            let result = authService.sdkAuth(context)
            sdkLog.info("sdkAuth -> \(result.rawValue, privacy: .public)")
            print("ANCHOR-DIAG sdkAuth -> \(result.rawValue)")
            if result != ZoomSDKError_Success {
                self.authContinuation = nil
                // Synchronous rejection — a local/parameter problem, distinct
                // from the delegate's ZoomSDKAuthError. Name the enum so the
                // two are never confused.
                continuation.resume(throwing: ZoomError.unsupported(
                    "Zoom Meeting SDK rejected the auth request before sending it "
                    + "(ZoomSDKError \(result.rawValue))."
                ))
            }
        }
    }

    // MARK: - Join

    /// Joins a meeting headlessly: the bot sends no video or audio of its own.
    @MainActor
    func joinMeeting(
        meetingNumber: String,
        passcode: String?,
        displayName: String,
        zak: String?
    ) async throws {
        guard let meetingService = ZoomSDK.shared().getMeetingService() else {
            throw ZoomError.unsupported("Zoom Meeting SDK has no meeting service.")
        }

        // Attach here, not in initializeIfNeeded(): getMeetingService() returns
        // nil until the SDK has authenticated, so setting the delegate at init
        // was a silent no-op. Without it onMeetingStatusChange never fires, and
        // the continuation below waits forever on a join that was accepted.
        meetingService.delegate = self
        attachChatDelegate()

        guard let number = Int64(meetingNumber) else {
            throw ZoomError.unsupported("\"\(meetingNumber)\" is not a valid Zoom meeting number.")
        }

        let elements = ZoomSDKJoinMeetingElements()
        elements.meetingNumber = number
        elements.displayName = displayName
        elements.password = passcode
        elements.zak = zak
        // The bot observes; it does not need to be seen or heard.
        elements.isNoVideo = true
        elements.isNoAudio = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.joinContinuation = continuation
            let result = meetingService.joinMeeting(elements)
            print("ANCHOR-DIAG joinMeeting -> \(result.rawValue)")
            if result != ZoomSDKError_Success {
                self.joinContinuation = nil
                continuation.resume(throwing: ZoomError.unsupported(
                    "Zoom Meeting SDK rejected the join request (code \(result.rawValue))."
                ))
            }
        }
    }

    @MainActor
    func leaveMeeting() {
        ZoomSDK.shared().getMeetingService()?.leaveMeeting(with: LeaveMeetingCmd_Leave)
        // A new session starts with an empty transcript; leftover messages would
        // be scored against the next class.
        chatMessages.removeAll()
        // Captions doubly so: this is a recording of children speaking, and it
        // has no reason to outlive the lesson by even one meeting.
        transcriptLines.removeAll()
        transcriptIndexByID.removeAll()
        transcriptAvailability = .notStarted
        didRequestTranscription = false
    }

    // MARK: - Chat

    /// Attaches the chat delegate. Called from `joinMeeting(_:)` and again once
    /// the meeting reports `InMeeting`, because the chat controller is created
    /// somewhere inside that window and the header's non-null annotation hides
    /// which side of it we are on: if `getMeetingChatController()` is still nil,
    /// the assignment below is an Objective-C message to nil — a silent no-op,
    /// exactly the failure mode the meeting-service delegate already hit once.
    /// Attaching twice is harmless (the property is a plain assign), so this
    /// runs on both edges rather than betting on one.
    @MainActor
    private func attachChatDelegate() {
        guard let meetingService = ZoomSDK.shared().getMeetingService() else { return }
        let chatController = meetingService.getMeetingChatController()
        chatController.delegate = self
        sdkLog.info("chat delegate attached")
        print("ANCHOR-DIAG chat delegate attached")
    }

    /// Snapshot of everything said in chat so far, oldest first.
    @MainActor
    func currentChatMessages() -> [ZoomChat] {
        chatMessages
    }

    // MARK: - Live transcript

    /// Attaches the caption delegate and asks Zoom to start transcribing.
    ///
    /// Safe to call repeatedly — the poll loop does, because the controller is
    /// created somewhere inside the join window and the header's non-null
    /// annotation hides which side of it we are on. The actual `start` request
    /// is sent at most once per meeting, guarded by `didRequestTranscription`.
    @MainActor
    func startLiveTranscription() {
        guard let meetingService = ZoomSDK.shared().getMeetingService() else { return }
        let controller = meetingService.getCloseCaptionController()
        controller.delegate = self

        // Already running — either we started it, or the teacher did in their
        // own Zoom client, which is just as good and is the common case.
        switch controller.getLiveTranscriptionStatus() {
        case ZoomSDK_LiveTranscription_Status_Start, ZoomSDK_LiveTranscription_Status_User_Sub:
            transcriptAvailability = .live(lines: transcriptLines.count)
            didRequestTranscription = true
            return
        case ZoomSDK_LiveTranscription_Status_Connecting:
            transcriptAvailability = .starting
            return
        default:
            break
        }

        guard !didRequestTranscription else { return }

        guard controller.isLiveTranscriptionFeatureEnabled() else {
            // A plan/account setting, not something a retry will fix.
            transcriptAvailability = .unsupported
            didRequestTranscription = true
            sdkLog.info("live transcription: feature disabled for this account")
            print("ANCHOR-DIAG live transcription: feature disabled for this account")
            return
        }

        let permitted = controller.canStartLiveTranscription()
        guard permitted == ZoomSDKError_Success else {
            transcriptAvailability = Self.transcriptAvailability(for: permitted)
            // A refusal that only the host can lift: ask them. Zoom shows the
            // teacher a prompt in their own client, and approving it fires
            // `onStartCaptionsRequestApproved` — which is where we try again.
            // Without this, a bot that is (correctly) not the host could never
            // get captions in the meeting it was invited to monitor.
            if permitted == ZoomSDKError_NoPermission, controller.isSupportRequestCaptions() {
                let asked = controller.request(toStartCaptions: false)
                sdkLog.info("live transcription: asked host to start captions -> \(asked.rawValue, privacy: .public)")
                print("ANCHOR-DIAG live transcription: asked host to start captions -> \(asked.rawValue)")
            }
            didRequestTranscription = transcriptAvailability.isBlocked
            return
        }

        let result = controller.startLiveTranscription()
        sdkLog.info("startLiveTranscription -> \(result.rawValue, privacy: .public)")
        print("ANCHOR-DIAG startLiveTranscription -> \(result.rawValue)")

        if result == ZoomSDKError_Success {
            transcriptAvailability = .starting
            didRequestTranscription = true
        } else {
            transcriptAvailability = Self.transcriptAvailability(for: result)
            // Only stop asking when the answer will not change. `NotInMeeting`
            // during a reconnect is exactly the case worth retrying.
            didRequestTranscription = transcriptAvailability.isBlocked
        }
    }

    /// Transcript so far, oldest first.
    @MainActor
    func currentTranscript() -> [RawTranscriptLine] {
        transcriptLines
    }

    /// Maps an SDK refusal onto the teacher-facing reason.
    private static func transcriptAvailability(for error: ZoomSDKError) -> TranscriptAvailability {
        switch error {
        case ZoomSDKError_NoPermission:
            .needsHost
        case ZoomSDKError_UnSupportedFeature, ZoomSDKError_NoLicense:
            .unsupported
        default:
            .refused("SDK error \(error.rawValue)")
        }
    }

    /// Inserts a line, or replaces the earlier version of the same utterance.
    ///
    /// Zoom emits one message id many times as its recogniser revises the words.
    /// Replacing in place keeps the transcript readable and, more importantly,
    /// keeps the analysis window meaning "the last 90 seconds of speech" rather
    /// than "the last 90 seconds of keystroke-level revisions".
    @MainActor
    private func upsert(_ line: RawTranscriptLine) {
        if let index = transcriptIndexByID[line.id] {
            transcriptLines[index] = line
            return
        }
        transcriptIndexByID[line.id] = transcriptLines.count
        transcriptLines.append(line)

        guard transcriptLines.count > Self.transcriptBufferLimit else { return }
        // Trimming invalidates every stored offset, so the index is rebuilt
        // rather than patched. This happens once per couple of thousand lines.
        transcriptLines.removeFirst(transcriptLines.count - Self.transcriptBufferLimit)
        rebuildTranscriptIndex()
    }

    @MainActor
    private func remove(transcriptID: String) {
        guard transcriptIndexByID[transcriptID] != nil else { return }
        transcriptLines.removeAll { $0.id == transcriptID }
        rebuildTranscriptIndex()
    }

    @MainActor
    private func rebuildTranscriptIndex() {
        transcriptIndexByID = Dictionary(
            transcriptLines.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { _, last in last }
        )
    }

    /// Zoom's caption timestamps are documented as `time_t` but have been seen
    /// carrying milliseconds, and occasionally zero.
    ///
    /// A wrong timestamp is not cosmetic here: the analyser selects "what was
    /// said recently" by time, so a line stamped in 1970 or in the year 57000
    /// either never enters the window or never leaves it. Anything that doesn't
    /// land near now is treated as unstamped and given the arrival time, which
    /// for a live caption is accurate to within a second anyway.
    private static func date(fromZoomTimestamp raw: time_t, now: Date = Date()) -> Date {
        guard raw > 0 else { return now }

        let asSeconds = Date(timeIntervalSince1970: TimeInterval(raw))
        if abs(asSeconds.timeIntervalSince(now)) < 86_400 { return asSeconds }

        let asMilliseconds = Date(timeIntervalSince1970: TimeInterval(raw) / 1000)
        if abs(asMilliseconds.timeIntervalSince(now)) < 86_400 { return asMilliseconds }

        return now
    }

    /// Shared by the new-message and edited-message callbacks.
    private func makeChat(from chatInfo: ZoomSDKChatInfo) -> ZoomChat {
        let senderName = chatInfo.getSenderDisplayName()
        return ZoomChat(
            id: chatInfo.getMessageID(),
            senderID: String(chatInfo.getSenderUserID()),
            senderName: senderName.isEmpty ? "Unknown" : senderName,
            message: chatInfo.getMsgContent(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(chatInfo.getTimeStamp())),
            // The SDK reports chat per-session, not per-meeting-ID; the caller
            // already knows which meeting the bot is in.
            meetingID: nil
        )
    }

    // MARK: - Participants

    /// Live participant snapshot from the meeting action controller — the
    /// signals the REST API cannot supply: mute, video, hand-raise, talking.
    @MainActor
    func currentParticipants() -> [ZoomParticipant] {
        guard
            let meetingService = ZoomSDK.shared().getMeetingService()
        else {
            return []
        }
        let actionController = meetingService.getMeetingActionController()
        guard let userIDs = actionController.getParticipantsList() as? [NSNumber] else {
            return []
        }

        return userIDs.compactMap { boxedID in
            let userID = boxedID.uint32Value
            guard let info = actionController.getUserByUserID(userID) else { return nil }

            let audioStatus = info.getAudioStatus()
            let isMuted: Bool?
            switch audioStatus {
            case ZoomSDKAudioStatus_Muted, ZoomSDKAudioStatus_MutedByHost, ZoomSDKAudioStatus_MutedAllByHost:
                isMuted = true
            case ZoomSDKAudioStatus_UnMuted, ZoomSDKAudioStatus_UnMutedByHost, ZoomSDKAudioStatus_UnMutedAllByHost:
                isMuted = false
            default:
                isMuted = nil
            }

            // Co-hosts count as teaching staff, not students: a co-host is the
            // teacher's second device or a colleague running the room, and
            // scoring either one would put a non-student at the top of the
            // engagement list.
            let role = info.getUserRole()
            let isHost = info.isHost()
                || role == UserRole_Host
                || role == UserRole_CoHost

            return ZoomParticipant(
                id: String(userID),
                participantID: String(userID),
                userID: String(userID),
                name: info.getUserName() ?? "Unknown",
                email: nil,
                joinTime: nil,
                leaveTime: nil,
                isInMeeting: true,
                isMuted: isMuted,
                hasVideo: info.isVideoOn(),
                handRaised: info.isRaisingHand(),
                speakingSeconds: nil,
                audioLevel: info.isTalking() ? 100 : 0,
                isSharing: nil,
                device: nil,
                status: "in_meeting",
                accountUserID: nil,
                isHost: isHost,
                isSelf: info.isMySelf()
            )
        }
    }
}

// MARK: - ZoomSDKAuthDelegate

extension ZoomMeetingSDKBridge: ZoomSDKAuthDelegate {
    func onZoomSDKAuthReturn(_ returnValue: ZoomSDKAuthError) {
        print("ANCHOR-DIAG onZoomSDKAuthReturn -> \(returnValue.rawValue) (\(Self.describe(returnValue)))")
        let continuation = authContinuation
        authContinuation = nil
        if returnValue == ZoomSDKAuthError_Success {
            continuation?.resume()
        } else {
            continuation?.resume(throwing: ZoomError.unsupported(
                "Zoom Meeting SDK auth failed: \(Self.describe(returnValue))."
            ))
        }
    }

    /// `ZoomSDKAuthError` and `ZoomSDKError` are different enums whose raw
    /// values overlap, so a bare number is genuinely ambiguous — and this one
    /// carries the actionable cause, which is worth spelling out.
    static func describe(_ error: ZoomSDKAuthError) -> String {
        switch error {
        case ZoomSDKAuthError_Success:
            "success"
        case ZoomSDKAuthError_KeyOrSecretWrong:
            "the SDK Key or Secret is wrong (check the Meeting SDK app's Client ID/Secret)"
        case ZoomSDKAuthError_AccountNotSupport:
            "this Zoom account does not support the Meeting SDK"
        case ZoomSDKAuthError_AccountNotEnableSDK:
            "the Meeting SDK is not enabled for this Zoom account — activate the Meeting SDK app in the Marketplace"
        case ZoomSDKAuthError_Timeout:
            "the auth request timed out"
        case ZoomSDKAuthError_NetworkIssue:
            "a network problem reaching Zoom"
        case ZoomSDKAuthError_Client_Incompatible:
            "this SDK version is incompatible with Zoom's service"
        case ZoomSDKAuthError_JwtTokenWrong:
            "Zoom rejected the signed JWT (check the claim set and that exp is 30 min–48 h out)"
        case ZoomSDKAuthError_KeyOrSecretEmpty:
            "the SDK Key or Secret was empty"
        case ZoomSDKAuthError_LimitExceededException:
            "the account's SDK auth rate limit was exceeded"
        default:
            "unknown auth error (code \(error.rawValue))"
        }
    }

    /// Same reasoning as `describe(_: ZoomSDKAuthError)` — these arrive as bare
    /// integers on a delegate callback, and several of them are ordinary
    /// operational states a teacher can act on rather than bugs.
    static func describe(_ error: ZoomSDKMeetingError) -> String {
        switch error {
        case ZoomSDKMeetingError_Success:
            "success"
        case ZoomSDKMeetingError_ConnectionError:
            "could not connect to Zoom"
        case ZoomSDKMeetingError_ReconnectFailed:
            "reconnecting to the meeting failed"
        case ZoomSDKMeetingError_MMRError:
            "Zoom's media server rejected the connection"
        case ZoomSDKMeetingError_PasswordError:
            "the meeting passcode is wrong or missing"
        case ZoomSDKMeetingError_SessionError:
            "the meeting session could not be established"
        case ZoomSDKMeetingError_MeetingOver:
            "the meeting has already ended"
        case ZoomSDKMeetingError_MeetingNotStart:
            "the meeting has not started yet"
        case ZoomSDKMeetingError_MeetingNotExist:
            "no meeting exists with that number"
        case ZoomSDKMeetingError_UserFull:
            "the meeting is full"
        case ZoomSDKMeetingError_ClientIncompatible:
            "this Meeting SDK version is too old for the meeting"
        default:
            "Zoom meeting error \(error.rawValue)"
        }
    }

    func onZoomAuthIdentityExpired() {
        // The SDK JWT is minted fresh for every join (see MeetingSDKTokenProvider),
        // so there is no long-lived identity to refresh here.
    }
}

// MARK: - ZoomSDKMeetingServiceDelegate

extension ZoomMeetingSDKBridge: ZoomSDKMeetingServiceDelegate {
    func onMeetingStatusChange(_ state: ZoomSDKMeetingStatus, meetingError error: ZoomSDKMeetingError, end reason: EndMeetingReason) {
        print("ANCHOR-DIAG onMeetingStatusChange state=\(state.rawValue) error=\(error.rawValue) reason=\(reason.rawValue)")

        // Unconditional, before the continuation guard: on a reconnect this
        // fires again with no join in flight, and the chat controller may have
        // been rebuilt underneath us.
        if state == ZoomSDKMeetingStatus_InMeeting {
            MainActor.assumeIsolated {
                attachChatDelegate()
                // Same reasoning as the chat controller: the caption controller
                // is created somewhere inside the join window, so the attach is
                // attempted on both edges. `startLiveTranscription` is
                // idempotent and re-attaches the delegate itself.
                startLiveTranscription()
            }
        }

        guard let continuation = joinContinuation else { return }

        switch state {
        case ZoomSDKMeetingStatus_InMeeting:
            joinContinuation = nil
            continuation.resume()
        case ZoomSDKMeetingStatus_Failed:
            joinContinuation = nil
            continuation.resume(throwing: ZoomError.unsupported(
                "The bot could not join: \(Self.describe(error))."
            ))
        default:
            // Connecting / WaitingForHost / other transient states — keep waiting.
            break
        }
    }
}

// MARK: - ZoomSDKMeetingChatControllerDelegate

extension ZoomMeetingSDKBridge: ZoomSDKMeetingChatControllerDelegate {

    func onChatMessageNotification(_ chatInfo: ZoomSDKChatInfo) {
        let chat = makeChat(from: chatInfo)
        print("ANCHOR-DIAG chat message from \(chat.senderName) (\(chat.message.count) chars)")

        chatMessages.append(chat)
        if chatMessages.count > Self.chatBufferLimit {
            chatMessages.removeFirst(chatMessages.count - Self.chatBufferLimit)
        }
    }

    func onChatMessageEditNotification(_ chatInfo: ZoomSDKChatInfo) {
        let chat = makeChat(from: chatInfo)
        // An edit can arrive for a message sent before the bot joined, or one
        // already dropped off the front of the buffer — then it is simply new.
        if let index = chatMessages.firstIndex(where: { $0.id == chat.id }) {
            chatMessages[index] = chat
        } else {
            onChatMessageNotification(chatInfo)
        }
    }

    // The chat delegate protocol has no @optional methods, so the file-transfer
    // callbacks have to exist to conform. Anchor scores what students say, not
    // what they upload.

    func onFileSendStart(_ sender: ZoomSDKFileSender) {}

    func onFileReceived(_ receiver: ZoomSDKFileReceiver) {}

    func onFileTransferProgress(_ info: ZoomSDKFileTransferInfo) {}
}

// MARK: - ZoomSDKCloseCaptionControllerDelegate

/// Live transcription. Unlike chat, these callbacks are `@optional`, so only the
/// ones Anchor acts on are implemented.
extension ZoomMeetingSDKBridge: ZoomSDKCloseCaptionControllerDelegate {

    /// The main path: Zoom's own speech recognition, one callback per revision
    /// of each utterance.
    func onLiveTranscriptionMsgInfoReceived(_ messageInfo: ZoomSDKLiveTranscriptionMessageInfo?) {
        guard let messageInfo else { return }

        let content = (messageInfo.messageContent ?? "").trimmed
        let messageID = messageInfo.messageID ?? UUID().uuidString

        MainActor.assumeIsolated {
            switch messageInfo.messageType {
            case ZoomSDK_LiveTranscription_OperationType_Delete:
                remove(transcriptID: messageID)

            case ZoomSDK_LiveTranscription_OperationType_Add,
                 ZoomSDK_LiveTranscription_OperationType_Update,
                 ZoomSDK_LiveTranscription_OperationType_Complete:
                // An empty revision is Zoom clearing a line it got wrong, not an
                // utterance of nothing.
                guard !content.isEmpty else {
                    remove(transcriptID: messageID)
                    return
                }
                let speakerName = messageInfo.speakerName ?? ""
                upsert(
                    RawTranscriptLine(
                        id: messageID,
                        speakerID: String(messageInfo.speakerID),
                        speakerName: speakerName.isEmpty ? "Unknown" : speakerName,
                        text: content,
                        timestamp: Self.date(fromZoomTimestamp: messageInfo.timeStamp),
                        isFinal: messageInfo.messageType
                            == ZoomSDK_LiveTranscription_OperationType_Complete
                    )
                )
                // Lines arriving *is* the proof it is live — the status callback
                // does not always fire when the teacher started captions before
                // the bot joined.
                if !transcriptAvailability.isLive {
                    transcriptAvailability = .live(lines: transcriptLines.count)
                }

            default:
                break   // None / NotSupported
            }
        }
    }

    /// Manually typed or third-party captions. No message id and no speaker
    /// name, so each one is its own line attributed to the sender's user id.
    func onReceiveCCMessage(withString inString: String, senderID: UInt32) {
        let content = inString.trimmed
        guard !content.isEmpty else { return }

        MainActor.assumeIsolated {
            let now = Date()
            upsert(
                RawTranscriptLine(
                    // Zoom gives manual captions no identity of their own, so
                    // one is synthesised. Including the content means a repeated
                    // caption is a new line rather than silently replacing the
                    // previous one.
                    id: "cc-\(senderID)-\(now.timeIntervalSince1970)-\(content.hashValue)",
                    speakerID: String(senderID),
                    speakerName: "Unknown",
                    text: content,
                    timestamp: now,
                    isFinal: true
                )
            )
            if !transcriptAvailability.isLive {
                transcriptAvailability = .live(lines: transcriptLines.count)
            }
        }
    }

    func onLiveTranscriptionStatus(_ status: ZoomSDKLiveTranscriptionStaus) {
        print("ANCHOR-DIAG onLiveTranscriptionStatus -> \(status.rawValue)")
        MainActor.assumeIsolated {
            switch status {
            case ZoomSDK_LiveTranscription_Status_Start,
                 ZoomSDK_LiveTranscription_Status_User_Sub:
                transcriptAvailability = .live(lines: transcriptLines.count)
            case ZoomSDK_LiveTranscription_Status_Connecting:
                transcriptAvailability = .starting
            default:
                // Stopped. Not `.unsupported` — the host can start it again, and
                // claiming the feature is missing would send the teacher off to
                // change an account setting that was never the problem.
                transcriptAvailability = .notStarted
                // Let the next poll ask again now that it genuinely isn't running.
                didRequestTranscription = false
            }
        }
    }

    /// The host approved the bot's request. This is the other half of the
    /// `requestToStartCaptions` call in `startLiveTranscription`.
    func onStartCaptionsRequestApproved() {
        print("ANCHOR-DIAG live transcription: host approved the captions request")
        MainActor.assumeIsolated {
            didRequestTranscription = false
            startLiveTranscription()
        }
    }
}
