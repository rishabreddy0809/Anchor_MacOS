//
//  TopicMatcher.swift
//  Anchor
//
//  Answers "has this student struggled with *this* before?"
//
//  Google Classroom has no notion of what an assignment is about. All it gives
//  Anchor is a title, so matching a live topic to a student's history is a
//  language problem, solved here in two passes:
//
//  1. **Lemma overlap** — "Photosynthesis Lab" against the topic "photosynthesis"
//     matches on the word itself, once both sides are lower-cased and lemmatised
//     so "cells" and "cell" are the same word.
//  2. **Word embeddings** — NaturalLanguage's on-device vectors catch the cases
//     overlap misses: "Chlorophyll Worksheet" is about photosynthesis without
//     sharing a word with it.
//
//  Both run on-device and neither involves the language model: this is a lookup
//  against the roster, and spending an inference on it would be slower, less
//  predictable, and no more accurate.
//
//  The bar for calling an assignment "related" is deliberately high
//  (`minimumRelevance`). Telling a teacher that a quiet student struggled with
//  the current topic is a claim that will be acted on in front of the class, and
//  a false one — built on an assignment that merely shared the word "unit" — is
//  worse than saying nothing.
//

import Foundation
import NaturalLanguage

// MARK: - Keywords

/// Pulls the content words out of a phrase.
nonisolated enum TopicKeywords {

    /// Words that carry no subject matter but appear in most assignment titles.
    ///
    /// Without this list, "Photosynthesis Quiz" and "Trigonometry Quiz" share a
    /// word, and every quiz in the course reads as related to every topic.
    private static let coursewordStopwords: Set<String> = [
        "quiz", "test", "exam", "homework", "assignment", "worksheet", "lab",
        "practice", "review", "chapter", "unit", "week", "lesson", "activity",
        "project", "packet", "problem", "problems", "set", "part", "day",
        "notes", "reading", "study", "guide", "warmup", "exit", "ticket",
        "final", "midterm", "draft", "revision", "due", "extra", "credit"
    ]

    /// Ordinary English function words the lexical-class filter doesn't catch.
    private static let generalStopwords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "in", "on", "for", "to", "with",
        "about", "what", "which", "how", "why", "is", "are", "was", "were",
        "be", "been", "do", "does", "did", "this", "that", "these", "those",
        "it", "its", "you", "your", "we", "our", "they", "them", "anyone",
        "someone", "thing", "things", "question", "questions", "answer",
        "answers", "number", "one", "two", "three", "four", "five"
    ]

    /// Content words from a phrase, lemmatised and deduplicated, in order.
    ///
    /// Nouns and adjectives only. Verbs are deliberately excluded: "convert",
    /// "explain" and "describe" are what a teacher does *to* a topic, and
    /// keeping them makes every explanation-shaped assignment look related to
    /// every explanation-shaped question.
    static func extract(from text: String, limit: Int = 8) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for token in tokens(in: text) where token.isContentWord {
            guard seen.insert(token.lemma).inserted else { continue }
            result.append(token.lemma)
            if result.count >= limit { break }
        }

        return result
    }

    /// Every lemma in a phrase, including the ones `extract` filters out. Used
    /// for overlap scoring, where a match on any word is still evidence.
    static func lemmaSet(in text: String) -> Set<String> {
        Set(tokens(in: text).filter(\.isMatchable).map(\.lemma))
    }

    // MARK: Tokenising

    private struct Token {
        var lemma: String
        var lexicalClass: NLTag?

        /// Worth treating as subject matter.
        var isContentWord: Bool {
            guard isMatchable else { return false }
            guard let lexicalClass else { return true }
            return lexicalClass == .noun || lexicalClass == .adjective
        }

        /// Worth comparing at all — excludes stopwords and one-letter fragments.
        var isMatchable: Bool {
            lemma.count > 2
                && !generalStopwords.contains(lemma)
                && !coursewordStopwords.contains(lemma)
        }
    }

    private static func tokens(in text: String) -> [Token] {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = trimmed

        var tokens: [Token] = []
        tagger.enumerateTags(
            in: trimmed.startIndex..<trimmed.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { lexicalClass, range in
            let surface = String(trimmed[range]).lowercased()
            // Fall back to the surface form: the lemmatiser has no entry for
            // most scientific vocabulary, and "chlorophyll" is exactly the word
            // that matters most here.
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?
                .rawValue.lowercased() ?? surface
            tokens.append(Token(lemma: lemma.isEmpty ? surface : lemma, lexicalClass: lexicalClass))
            return true
        }

        return tokens
    }
}

// MARK: - Embeddings

/// The on-device English word-vector space, loaded once.
///
/// `NLEmbedding` is an immutable lookup table once built and is safe to read
/// from any thread; loading it costs tens of milliseconds and megabytes, which
/// is worth paying once and not once per assignment title. Nil on a system that
/// ships without the asset — in which case matching falls back to lemma overlap
/// alone, which is weaker but never wrong in a way that invents a match.
nonisolated enum TopicEmbedding {
    nonisolated(unsafe) static let english: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)

    /// Raw cosine distance between two words — 0 is identical, larger is less
    /// alike. Nil when either word is out of the model's vocabulary, which for
    /// school vocabulary is common ("stomata" and "Juliet" are both absent).
    ///
    /// Returned raw rather than converted to a 0...1 similarity because this
    /// embedding's distances do not span anything like that range, and squashing
    /// them into one throws away the only part that discriminates. Measured on
    /// this model:
    ///
    ///     car/automobile                 0.873
    ///     dog/puppy                      0.790
    ///     volcano/eruption               0.763
    ///     photosynthesis/chlorophyll     0.875
    ///     photosynthesis/chloroplast     0.925
    ///     respiration/breathing          1.023
    ///     car/photosynthesis             1.334
    ///
    /// So genuinely related words sit around 0.76–0.93 and unrelated ones above
    /// 1.0. Everything is near-orthogonal; the signal lives in a narrow band,
    /// which is what `TopicMatcher.semanticCeiling` is calibrated against.
    static func distance(_ lhs: String, _ rhs: String) -> Double? {
        guard let english else { return nil }
        guard english.contains(lhs), english.contains(rhs) else { return nil }
        return english.distance(between: lhs, and: rhs, distanceType: .cosine)
    }
}

// MARK: - Matcher

nonisolated struct TopicMatcher: Sendable {

    /// How sure Anchor has to be that an assignment is about the topic before it
    /// will quote it to a teacher. Tuned high on purpose — see the file note.
    static let minimumRelevance = 0.55

    /// The embedding distance beyond which two words are not treated as related
    /// at all, and the distance at which they are treated as maximally related.
    ///
    /// Both are measured against this specific model rather than picked — see
    /// `TopicEmbedding.distance` for the readings. The band is deliberately
    /// narrow: at 0.90 it admits roughly a word's two nearest neighbours
    /// ("photosynthesis" → "chlorophyll" at 0.875) and excludes the merely
    /// topical ones ("chloroplast" at 0.925, "nitrogen" at 0.929). Widening it
    /// to catch chloroplast would also catch "acid" and "antioxidant", and a
    /// wrong match here becomes a teacher telling a child they struggled with
    /// something they never studied.
    private static let semanticCeiling = 0.90
    private static let semanticFloor = 0.75

    /// Grades at or above this read as "no concern on this topic".
    private static let comfortableGrade = 0.85
    /// Grades at or below this read as unambiguous difficulty.
    private static let strugglingGrade = 0.50

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    /// What this student's record says about the topic being taught.
    ///
    /// Returns an empty weakness — not nil — when the roster has nothing on the
    /// topic, so callers can tell "no history on photosynthesis" from "no
    /// Classroom connection at all", which is the difference between a
    /// recommendation that omits the academic clause and one that shouldn't
    /// mention topics in the first place.
    func weakness(topic: ClassTopic, snapshot: AcademicSnapshot?) -> TopicWeakness {
        guard let snapshot else { return .empty(topic: topic.topic) }

        let terms = topic.matchTerms
        guard !terms.isEmpty else { return .empty(topic: topic.topic) }

        // Precompute the topic's vocabulary once rather than per assignment.
        let termLemmas = terms.map { TopicKeywords.lemmaSet(in: $0) }
        let allTermLemmas = termLemmas.reduce(into: Set<String>()) { $0.formUnion($1) }

        var related: [TopicWeakness.RelatedWork] = []

        for work in snapshot.gradedWork {
            let relevance = relevance(of: work.title, to: allTermLemmas)
            guard relevance >= Self.minimumRelevance else { continue }
            related.append(
                TopicWeakness.RelatedWork(
                    assignmentID: work.id,
                    title: work.title,
                    fraction: work.fraction,
                    isMissing: false,
                    dueDate: work.date,
                    relevance: relevance
                )
            )
        }

        for assignment in snapshot.missingAssignments {
            let relevance = relevance(of: assignment.title, to: allTermLemmas)
            guard relevance >= Self.minimumRelevance else { continue }
            related.append(
                TopicWeakness.RelatedWork(
                    assignmentID: assignment.id,
                    title: assignment.title,
                    fraction: nil,
                    isMissing: true,
                    dueDate: assignment.dueDate,
                    relevance: relevance
                )
            )
        }

        guard !related.isEmpty else { return .empty(topic: topic.topic) }

        related.sort { lhs, rhs in
            if lhs.relevance != rhs.relevance { return lhs.relevance > rhs.relevance }
            return (lhs.dueDate ?? .distantPast) > (rhs.dueDate ?? .distantPast)
        }

        let graded = related.compactMap { work in work.fraction.map { ($0, work.relevance) } }
        let missingCount = related.filter(\.isMissing).count

        // Weighted by relevance: an assignment Anchor is 0.9 sure is about the
        // topic should count for more than one it is 0.6 sure about.
        let averageFraction: Double? = graded.isEmpty ? nil : {
            let weight = graded.reduce(0) { $0 + $1.1 }
            guard weight > 0 else { return nil }
            return graded.reduce(0) { $0 + $1.0 * $1.1 } / weight
        }()

        return TopicWeakness(
            topic: topic.topic,
            relatedWork: related,
            averageFraction: averageFraction,
            missingCount: missingCount,
            weaknessScore: Self.weaknessScore(
                averageFraction: averageFraction,
                missingCount: missingCount,
                meanRelevance: related.reduce(0) { $0 + $1.relevance } / Double(related.count)
            )
        )
    }

    // MARK: - Relevance

    /// 0...1 — how sure Anchor is that this assignment title is about the topic.
    ///
    /// Overlap first, because a shared subject word is proof rather than
    /// inference. Embeddings only get a say when there is no overlap at all, and
    /// their answer is capped below a lexical match so a semantic hunch can
    /// never outrank the real thing.
    private func relevance(of title: String, to topicLemmas: Set<String>) -> Double {
        let titleLemmas = TopicKeywords.lemmaSet(in: title)
        guard !titleLemmas.isEmpty, !topicLemmas.isEmpty else { return 0 }

        let shared = titleLemmas.intersection(topicLemmas)
        if !shared.isEmpty {
            // How much of the *title* is about the topic. A title that is
            // nothing but the topic scores 1; one where the topic is one word in
            // six scores lower, because it is probably a broader piece of work.
            let coverage = Double(shared.count) / Double(titleLemmas.count)
            return min(1, 0.75 + 0.25 * coverage)
        }

        guard let closest = closestDistance(titleLemmas, topicLemmas),
              closest < Self.semanticCeiling
        else { return 0 }

        // Mapped into `minimumRelevance...0.74`, so a semantic hit always sits
        // above the bar for being counted at all and always below the weakest
        // lexical match. Nothing outside the measured band can produce a match:
        // at the ceiling this returns exactly the minimum, and beyond it the
        // guard above has already returned zero.
        let span = Self.semanticCeiling - Self.semanticFloor
        let closeness = (Self.semanticCeiling - max(closest, Self.semanticFloor)) / span
        return Self.minimumRelevance + closeness * (0.74 - Self.minimumRelevance)
    }

    private func closestDistance(_ titleLemmas: Set<String>, _ topicLemmas: Set<String>) -> Double? {
        var closest: Double?
        for title in titleLemmas {
            for topic in topicLemmas {
                guard let distance = TopicEmbedding.distance(title, topic) else { continue }
                if distance < (closest ?? .greatestFiniteMagnitude) { closest = distance }
            }
        }
        return closest
    }

    // MARK: - Scoring

    /// Folds the evidence into one 0...1 number.
    ///
    /// Two independent signals — a low grade on the topic, and work on the topic
    /// never handed in — so the stronger one leads and the weaker one adds to
    /// it. Summing them outright would let two moderate concerns produce a
    /// maximum-severity claim.
    ///
    /// The whole thing is then scaled by how confident the *match* was. A
    /// weakness derived from an assignment Anchor is only 0.6 sure is on-topic
    /// should be stated more quietly than one derived from a title that names
    /// the topic outright.
    static func weaknessScore(
        averageFraction: Double?,
        missingCount: Int,
        meanRelevance: Double
    ) -> Double {
        let gradeWeakness: Double = averageFraction.map { average in
            let span = comfortableGrade - strugglingGrade
            return max(0, min(1, (comfortableGrade - average) / span))
        } ?? 0

        // One missing piece of work on the current topic is a real signal; a
        // second confirms it. Capped below 1 because a missing assignment says
        // less about understanding than a marked one does.
        let missingWeakness = min(0.8, 0.5 * Double(missingCount))

        let leading = max(gradeWeakness, missingWeakness)
        let supporting = min(gradeWeakness, missingWeakness)
        let combined = min(1, leading + 0.25 * supporting)

        return max(0, min(1, combined * meanRelevance))
    }
}
