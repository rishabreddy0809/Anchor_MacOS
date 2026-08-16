//
//  ZoomParticipant+StruggleScore.swift
//  Anchor
//
//  The one-line path from a Zoom participant to a struggle score: build the
//  feature vector, run it through the Core ML model, hand back 0...100.
//
//  Two entry points on purpose. The zero-argument property is for call sites
//  that have nothing but a participant — it scores on live state alone and will
//  therefore read low on the chat- and history-derived features. The contextual
//  method is what the dashboard uses, and is the one to prefer wherever the chat
//  feed and the previous poll's accumulators are in reach.
//

import Foundation

extension ZoomParticipant {

    /// Struggle score, 0...100. Nil when the model can't be loaded or the
    /// prediction fails — callers should fall back to StruggleScoreCalculator
    /// rather than treating nil as "not struggling".
    var struggleScore: Int? {
        struggleScore(chat: [], meetingElapsed: sessionDuration)
    }

    /// Struggle score with the full context the dashboard has available.
    ///
    /// - Parameters:
    ///   - chat: in-meeting chat, used for message length, hesitations and
    ///     whether they asked anything.
    ///   - meetingElapsed: how long the meeting has been running, which sets the
    ///     bar for how much speaking counts as "participating".
    ///   - history: accumulators carried forward from previous polls.
    func struggleScore(
        chat: [ZoomChat],
        meetingElapsed: TimeInterval,
        history: StruggleSignalHistory = StruggleSignalHistory(),
        now: Date = Date()
    ) -> Int? {
        let features = struggleFeatures(
            chat: chat,
            meetingElapsed: meetingElapsed,
            history: history,
            now: now
        )
        return StruggleDetectionService.shared.predictStruggle(features)
    }

    /// The model input vector for this participant.
    func struggleFeatures(
        chat: [ZoomChat] = [],
        meetingElapsed: TimeInterval = 0,
        history: StruggleSignalHistory = StruggleSignalHistory(),
        now: Date = Date()
    ) -> StruggleFeatures {
        FeatureCalculator(now: now).calculateFeatures(
            from: self,
            chat: chat,
            meetingElapsed: meetingElapsed,
            history: history
        )
    }
}
