//
//  TranscriptCaptureService.swift
//  Anchor
//
//  Turns Zoom's raw caption stream into an attributed, bounded transcript, and
//  decides when it has changed enough to be worth re-reading.
//
//  Three things happen here and nowhere else:
//
//  1. **Attribution.** Zoom names a speaker; it does not say whether that person
//     is the teacher, a student, or Anchor's own bot. `MeetingRoles` knows, and
//     the distinction matters — the teacher's speech is what carries the topic
//     and the questions, so a transcript that can't tell the two apart would ask
//     the model to find the lesson inside a student's answer.
//
//  2. **Windowing.** A class period is thousands of lines and the model is asked
//     what is being taught *now*. Only the recent window is ever analysed.
//
//  3. **Change detection.** The poll loop runs every ten seconds; the topic
//     changes every ten minutes. Re-running inference on an unchanged transcript
//     would burn battery to re-derive an answer already on screen.
//
//  Privacy: this is a recording of children speaking in a classroom. It lives in
//  memory, is bounded, is dropped when the meeting ends, and is never written to
//  disk — `SessionArchive` records scores and Zoom signals, never words. Nothing
//  here is Codable, which is the enforcement mechanism rather than a convention.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TranscriptCaptureService: ObservableObject {

    static let shared = TranscriptCaptureService()

    /// Only the typed topic is persisted — never a line of captured speech.
    /// Transcripts are children talking in a classroom and stay in memory.
    private static let manualTopicKey = "anchor.transcript.manualTopic"

    /// Pinned by a test; `nil` follows whichever account is signed in.
    private let pinnedDefaults: UserDefaults?
    private var defaults: UserDefaults { pinnedDefaults ?? AccountScope.shared.defaults }
    private var scopeObserver: Any?

    init(defaults: UserDefaults? = nil) {
        self.pinnedDefaults = defaults
        restoreManualTopic()
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// A typed topic describes one teacher's lesson. Reloaded for the account
    /// that just signed in, which for a new one means nothing at all.
    ///
    /// Cleared *first*, and that is the whole substance of this method:
    /// `restoreManualTopic` returns early when the incoming account has nothing
    /// stored, so on its own it would leave the previous teacher's topic on the
    /// chip above a new teacher's class.
    private func accountDidChange() {
        guard pinnedDefaults == nil else { return }
        manualTopic = nil
        restoreManualTopic()
    }

    // MARK: - Tuning

    /// How far back the model is allowed to look.
    ///
    /// Three minutes is roughly one explanation plus the question that follows
    /// it. Shorter and a topic introduced before the current question falls out
    /// of view; longer and the model starts reporting the previous topic as
    /// though it were current.
    static let analysisWindow: TimeInterval = 180

    /// Hard cap on what is handed to the model, independent of the time window —
    /// a fast talker can fill three minutes with more text than a short prompt
    /// should carry, and Apple's guidance is to keep context small.
    private static let maxWindowCharacters = 1_400

    /// Ceiling on retained lines. Well above the window; this exists so a
    /// three-hour session can't grow without bound, not to shape the analysis.
    private static let lineLimit = 2_000

    // MARK: - Published state

    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var availability: TranscriptAvailability = .notStarted

    /// The topic the teacher typed in themselves — "Option C", and the only path
    /// that works in a meeting where Zoom will not transcribe at all.
    ///
    /// Kept separate from the extracted topic rather than overwriting it: a typed
    /// topic is an assertion about the whole lesson, an extracted one is a
    /// reading of the last three minutes. `LiveCoachViewModel` prefers the
    /// extracted topic while one is current and falls back to this, so a teacher
    /// who types "Photosynthesis" before class still gets topic-aware
    /// recommendations the moment the transcript goes dark.
    @Published private(set) var manualTopic: ClassTopic?

    // MARK: - Derived

    /// True when there is enough recent speech to ask the model about.
    ///
    /// Two lines rather than one: a single "okay" is not a lesson, and asking
    /// the model to extract a topic from it produces a confident answer about
    /// nothing.
    var hasUsableTranscript: Bool {
        recentLines().filter { !$0.text.isEmpty }.count >= 2
    }

    /// The most recent thing the teacher said, for the detail view.
    var lastTeacherLine: TranscriptLine? {
        lines.last { $0.speaker.isInstruction }
    }

    /// Changes exactly when new speech has been *finalised*.
    ///
    /// The window text itself is a poor trigger: Zoom revises the tail line
    /// several times a second, so a fingerprint over all of it would fire on
    /// every revision. Counting finalised lines and naming the newest one is
    /// stable between revisions and moves as soon as a sentence completes.
    var analysisFingerprint: String {
        let final = lines.filter(\.isFinal)
        return "\(final.count):\(final.last?.id ?? "none")"
    }

    // MARK: - Ingestion

    /// Folds one poll's worth of raw caption lines in, attributing each speaker.
    ///
    /// Called on every bot poll with the *whole* buffer rather than a delta —
    /// the SDK bridge owns the buffer and revises lines in place, so a delta
    /// would have to re-derive which lines changed. Re-attributing a couple of
    /// thousand lines is a dictionary lookup each and costs nothing next to the
    /// scoring pass that follows it.
    func ingest(
        raw: [RawTranscriptLine],
        participants: [ZoomParticipant],
        roles: MeetingRoles,
        availability newAvailability: TranscriptAvailability
    ) {
        availability = newAvailability

        guard !raw.isEmpty else {
            // Deliberately not clearing `lines`: a poll that returns nothing
            // because the bot is momentarily reconnecting must not wipe the
            // transcript the recommendations on screen were built from.
            return
        }

        let bySpeakerID = Dictionary(
            participants.compactMap { participant -> (String, ZoomParticipant)? in
                guard let userID = participant.userID?.trimmed, !userID.isEmpty else { return nil }
                return (userID, participant)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Names collide far more often than ids, so an ambiguous name is dropped
        // rather than guessed at — the same rule AcademicMatchTable applies to
        // the roster, and for the same reason.
        var byName: [String: ZoomParticipant] = [:]
        var ambiguousNames: Set<String> = []
        for participant in participants {
            guard let key = ClassroomNameKey.make(participant.name) else { continue }
            if let existing = byName[key], existing.id != participant.id {
                ambiguousNames.insert(key)
            } else {
                byName[key] = participant
            }
        }
        for key in ambiguousNames { byName.removeValue(forKey: key) }

        let attributed = raw.map { line -> TranscriptLine in
            TranscriptLine(
                id: line.id,
                speakerID: line.speakerID,
                speaker: Self.speaker(
                    for: line,
                    bySpeakerID: bySpeakerID,
                    byName: byName,
                    roles: roles
                ),
                text: line.text,
                timestamp: line.timestamp,
                isFinal: line.isFinal
            )
        }

        // Zoom emits lines in order, but a revision to an older line arrives
        // late; sorting keeps "the last three minutes" honest.
        lines = attributed
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(Self.lineLimit)
    }

    /// Which of the three kinds of speaker this line is.
    ///
    /// The participant list is the authority — it is where role, email and
    /// account identity live. The caption's own display name is only consulted
    /// when the speaker id matches nobody, which happens when someone leaves
    /// between the utterance and the poll that reads it.
    private static func speaker(
        for line: RawTranscriptLine,
        bySpeakerID: [String: ZoomParticipant],
        byName: [String: ZoomParticipant],
        roles: MeetingRoles
    ) -> TranscriptLine.Speaker {
        let participant = line.speakerID.flatMap { bySpeakerID[$0] }
            ?? ClassroomNameKey.make(line.speakerName).flatMap { byName[$0] }

        guard let participant else { return .unknown(name: line.speakerName) }

        switch roles.role(of: participant) {
        case .teacher: return .teacher
        case .anchorBot: return .anchorBot
        case .student: return .student(name: participant.name)
        }
    }

    // MARK: - The window handed to the model

    /// Lines inside the analysis window, oldest first.
    ///
    /// Anchor's own bot is excluded outright. It never speaks, so a line
    /// attributed to it is Zoom mis-attributing during a reconnect — and a
    /// caption stamped with the bot's name is the one thing guaranteed not to be
    /// part of the lesson.
    func recentLines(now: Date = Date()) -> [TranscriptLine] {
        let cutoff = now.addingTimeInterval(-Self.analysisWindow)
        return lines.filter { line in
            line.timestamp >= cutoff
                && line.speaker != .anchorBot
                && !line.text.trimmed.isEmpty
        }
    }

    /// The transcript excerpt for the model, newest speech guaranteed to survive
    /// the character cap.
    ///
    /// Trimmed from the *front* when it is too long: the question the teacher
    /// just asked is the point of the exercise, and dropping the tail to fit
    /// would throw away the only part that can't be reconstructed.
    func analysisExcerpt(now: Date = Date()) -> String {
        var kept: [String] = []
        var budget = Self.maxWindowCharacters

        for line in recentLines(now: now).reversed() {
            let rendered = line.attributed
            guard rendered.count <= budget else { break }
            budget -= rendered.count + 1
            kept.append(rendered)
        }

        return kept.reversed().joined(separator: "\n")
    }

    // MARK: - Manual topic (Option C)

    /// Records the topic the teacher typed in.
    ///
    /// Concepts are derived from what they wrote rather than demanded of them:
    /// asking a teacher to enumerate keywords before class is exactly the kind
    /// of setup work that means the feature never gets used.
    /// Records the topic the teacher typed, and remembers it across launches.
    ///
    /// Topic only — there is deliberately nowhere to type the current *question*.
    /// A question changes every few minutes, so a field for it is a field a
    /// teacher has to keep going back to mid-lesson, and a stale one is worse
    /// than none: it points the recommendation at something the class finished
    /// twenty minutes ago. The live transcript is where a question legitimately
    /// comes from, because only that can keep up. This path exists for the topic,
    /// which holds for the whole lesson.
    func setManualTopic(topic: String) {
        let trimmedTopic = topic.trimmed
        guard !trimmedTopic.isEmpty else {
            manualTopic = nil
            defaults.removeObject(forKey: Self.manualTopicKey)
            return
        }

        manualTopic = ClassTopic(
            topic: trimmedTopic,
            questionLabel: nil,
            questionText: nil,
            concepts: TopicKeywords.extract(from: trimmedTopic),
            capturedAt: Date(),
            source: .manual
        )
        // Persisted so it survives a relaunch. A teacher on a unit teaches the
        // same topic for weeks, and retyping it every morning is exactly the
        // friction that stops a fallback being used at all.
        defaults.set(trimmedTopic, forKey: Self.manualTopicKey)
    }

    /// Restores the last typed topic. Called at init.
    private func restoreManualTopic() {
        guard let saved = defaults.string(forKey: Self.manualTopicKey)?.trimmed,
              !saved.isEmpty
        else { return }

        manualTopic = ClassTopic(
            topic: saved,
            questionLabel: nil,
            questionText: nil,
            concepts: TopicKeywords.extract(from: saved),
            // Now, not when it was typed: `capturedAt` is what `topicLifetime`
            // ages an *extracted* topic against, and a restored manual topic
            // that looked hours old would read as stale on the chip.
            capturedAt: Date(),
            source: .manual
        )
    }

    func clearManualTopic() {
        manualTopic = nil
        defaults.removeObject(forKey: Self.manualTopicKey)
    }

    // MARK: - Lifecycle

    /// Drops the captured speech, keeping whatever the teacher typed.
    ///
    /// This is the between-meetings reset. The typed topic deliberately survives
    /// it: entering the topic *before* the class starts is the whole point of
    /// Option C, and Anchor sits in "waiting for a live meeting" for the entire
    /// window in which a teacher would do that.
    func clearTranscript() {
        lines = []
        availability = .notStarted
    }

    /// Drops everything, including the typed topic. Called when the session
    /// genuinely ends.
    ///
    /// The typed topic goes here because it was typed for *that* lesson, and
    /// carrying it forward would silently match next week's students against
    /// last week's subject.
    func clear() {
        clearTranscript()
        manualTopic = nil
    }
}
