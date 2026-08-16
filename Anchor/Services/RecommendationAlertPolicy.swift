//
//  RecommendationAlertPolicy.swift
//  Anchor
//
//  Decides which recommendations are worth interrupting a teacher for.
//
//  Split out from LiveCoachViewModel and kept free of UserNotifications on
//  purpose. This is the rule that decides when a banner appears over a lesson in
//  progress, and getting it wrong in either direction is expensive: too eager
//  and the teacher turns notifications off in the first week, too shy and the
//  feature may as well not exist. A plain value type is something that can be
//  reasoned about and, later, tested at a hundred simulated polls without a
//  notification centre anywhere near it.
//
//  Three rules, in order:
//
//  * **High urgency only.** The dashboard shows three cards; a student who is
//    merely "elevated" is someone to notice on the next glance, not someone to
//    pull a teacher out of their sentence for.
//  * **Once per student, then a cooldown.** The scoring pass runs every ten
//    seconds and a student stays disengaged for minutes at a time, so without
//    this the same student notifies dozens of times about one silence.
//  * **One at a time.** If three students go high together, three simultaneous
//    banners is not three times the information — it's a wall the teacher
//    dismisses without reading. The rest follow on later passes, ten seconds
//    apart, in urgency order.
//

import Foundation

nonisolated struct RecommendationAlertPolicy: Sendable {

    /// How long a student stays quiet after being announced.
    ///
    /// Ten minutes is roughly the length of one classroom activity: long enough
    /// that a teacher who acted on the first alert isn't told again while they
    /// are still acting on it, short enough that a student who is *still* gone
    /// after a whole activity gets raised a second time.
    static let defaultCooldown: TimeInterval = 600

    var cooldown: TimeInterval

    init(cooldown: TimeInterval = defaultCooldown) {
        self.cooldown = cooldown
    }

    /// The one recommendation to announce this pass, if any.
    ///
    /// `recommendations` is expected in the order `RecommendationGenerator.rank`
    /// produced — most urgent first — so "the first eligible one" is also the
    /// most deserving one.
    func next(
        from recommendations: [LiveRecommendation],
        alreadyNotified: [UUID: Date],
        now: Date = Date()
    ) -> LiveRecommendation? {
        recommendations.first { recommendation in
            guard recommendation.urgency == .high else { return false }
            guard let last = alreadyNotified[recommendation.studentID] else { return true }
            return now.timeIntervalSince(last) >= cooldown
        }
    }

    /// Forgets students whose cooldown has long expired, so a three-hour session
    /// doesn't carry a growing dictionary of every student ever announced.
    ///
    /// Kept well beyond the cooldown itself: dropping an entry the moment it
    /// expires is the same as having no record, and the point of the record is
    /// that it survives the student dipping in and out of the list.
    func pruned(_ alreadyNotified: [UUID: Date], now: Date = Date()) -> [UUID: Date] {
        alreadyNotified.filter { now.timeIntervalSince($0.value) < cooldown * 6 }
    }
}
