//
//  StruggleDetectionService.swift
//  Anchor
//
//  Loads the trained Core ML struggle model once and runs predictions against
//  it for the lifetime of the app.
//
//  The model is deliberately loaded through the raw MLModel API rather than the
//  class Xcode generates from the .mlmodel. Two reasons:
//
//    1. The generated class name is derived from the filename, so renaming or
//       retraining the model would break every call site. Here a rename is
//       absorbed by `candidateResourceNames` — or by the bundle scan, which
//       finds any compiled model exposing the 11 features we know how to fill.
//    2. CreateML emits the probability dictionary with String keys ("0"/"1")
//       even though the label column is Int64. The untyped API lets us read
//       either shape instead of compiling against whichever one Xcode picked.
//
//  Predictions on this model (a two-stage pipeline ending in a logistic
//  regression) take well under a millisecond, so callers may run them inline.
//

import CoreML
import Foundation
import os

// MARK: - State

nonisolated enum StruggleModelState: Equatable, Sendable {
    case notLoaded
    case ready(modelName: String)
    case unavailable(reason: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// One line for Settings / the dashboard footer.
    var summary: String {
        switch self {
        case .notLoaded:
            "Struggle model not loaded yet."
        case .ready(let name):
            "Scoring with \(name)."
        case .unavailable(let reason):
            "Core ML model unavailable — \(reason) Falling back to signal heuristics."
        }
    }
}

// MARK: - Service

/// Singleton owner of the Core ML model.
///
/// `nonisolated` and lock-guarded rather than an actor: the mapper that calls it
/// is a synchronous value type running inside `EngagementStore.ingest`, and
/// making prediction async would force the whole ingest path to become async for
/// a sub-millisecond call.
nonisolated final class StruggleDetectionService: @unchecked Sendable {

    static let shared = StruggleDetectionService()

    private let lock = NSLock()
    private var model: MLModel?
    /// The input columns the loaded model actually declares.
    ///
    /// The vector carries 16 features; the model shipped today understands 11.
    /// Core ML throws if handed a column it doesn't declare, so every prediction
    /// is filtered through this set. A retrained 16-feature model widens it
    /// automatically and starts consuming the academic signals with no code
    /// change.
    private var declaredInputs: Set<String> = []
    private var loadedState: StruggleModelState = .notLoaded
    private let logger = Logger(subsystem: "com.anchor.coreml", category: "StruggleDetection")

    /// Filenames to try before falling back to scanning the bundle, in
    /// preference order.
    ///
    /// `StudentStruggleModel_PRODUCTION` is the shipping model: all 16
    /// features (11 engagement + the full academic five), trained on 10,000
    /// messy synthetic sessions whose columns match `FeatureCalculator.swift`
    /// exactly — including the *uncapped* `missing_assignments` and
    /// `late_submissions` counts that production actually sends, and a
    /// `confidence_level` computed with the same formula rather than drawn
    /// independently. See retraining/model_evaluation_production.txt.
    ///
    /// `StudentStruggleModel_CORRECTED` is the previous 13-feature model, kept
    /// one rung down as a fallback: it is a genuinely usable model (it scores
    /// an obviously-struggling student at ~86%), just blind to
    /// `grade_average`, `days_since_submission` and `late_submissions`.
    ///
    /// Nothing else belongs in this list. `Anchor_Accurate` used to sit here
    /// and was removed on 2026-08-12: it was trained with
    /// `missing_assignments` constant at 0 (zero variance, unlearnable) and
    /// `grade_trend` on a -2...19 scale while production sends 70...130, so
    /// every real prediction landed outside anything it had seen. Measured
    /// against the bundled build it returned **0.0%** for an obviously
    /// struggling student — every student reads as fine, while the UI
    /// truthfully reports "Scoring with Anchor_Accurate". A fallback that
    /// fails silently in the exact direction this product exists to prevent is
    /// worse than no fallback: if both models above are missing, the
    /// `StruggleScoreCalculator` heuristic takes over and says so. The file
    /// now lives in retraining/archive/.
    ///
    /// Any model declaring the academic columns flips `usesAcademicFeatures`
    /// on automatically, and the rule-based `AcademicEscalation` layer stands
    /// down for it (see that file's header).
    private static let candidateResourceNames = [
        "StudentStruggleModel_PRODUCTION",
        "StudentStruggleModel_CORRECTED",
        "StudentStruggleModel",
        "StruggleModel"
    ]

    private init() {}

    // MARK: - Loading

    var state: StruggleModelState {
        lock.lock()
        defer { lock.unlock() }
        return loadedState
    }

    var isReady: Bool { state.isReady }

    /// Warms the model up off the main thread at launch so the first refresh
    /// doesn't pay the load cost. Safe to call more than once.
    func preload() {
        Task.detached(priority: .utility) { [self] in
            _ = requireModel()
        }
    }

    /// Returns the loaded model, loading it on first use. Caller holds no lock.
    private func requireModel() -> MLModel? {
        lock.lock()
        defer { lock.unlock() }

        if let model { return model }
        if case .unavailable = loadedState { return nil }   // don't retry a known failure

        do {
            let (loaded, name) = try loadModel()
            model = loaded
            declaredInputs = Set(loaded.modelDescription.inputDescriptionsByName.keys)
            let inputCount = declaredInputs.count
            loadedState = .ready(modelName: name)
            let academicCount = StruggleFeatures.academicFeatureNames
                .intersection(declaredInputs).count
            logger.info(
                "Model \(name, privacy: .public) declares \(inputCount, privacy: .public) inputs, \(academicCount, privacy: .public) academic"
            )
            logger.info("Loaded struggle model \(name, privacy: .public)")
            return loaded
        } catch {
            let reason = (error as? LoadError)?.message ?? error.localizedDescription
            loadedState = .unavailable(reason: reason)
            logger.error("Struggle model unavailable: \(reason, privacy: .public)")
            return nil
        }
    }

    private enum LoadError: Error {
        case notFound
        case noMatchingFeatures(String)

        var message: String {
            switch self {
            case .notFound:
                "no compiled .mlmodelc in the app bundle."
            case .noMatchingFeatures(let names):
                "the bundled model expects \(names), not the 11 engagement features."
            }
        }
    }

    /// Whether the loaded model consumes the Google Classroom features.
    ///
    /// True for `StudentStruggleModel_PRODUCTION`, which declares all five, so
    /// `AcademicEscalation` stands down and the academic signals move the
    /// score through the model itself. It stays false only if the app falls
    /// all the way back to a model that predates them, in which case the
    /// rule-based escalation layer resumes — see `AcademicEscalation`.
    var usesAcademicFeatures: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !StruggleFeatures.academicFeatureNames.isDisjoint(with: declaredInputs)
    }

    private func loadModel() throws -> (MLModel, String) {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly   // a tiny GLM; the ANE costs more than it saves

        var lastMismatch: String?

        for url in candidateModelURLs() {
            do {
                let candidate = try MLModel(contentsOf: url)
                let inputs = Set(candidate.modelDescription.inputDescriptionsByName.keys)

                // Only the 11 engagement features are required. A model that
                // also declares the academic five passes the same check and is
                // used to its full extent.
                guard StruggleFeatures.requiredFeatureNames.isSubset(of: inputs) else {
                    lastMismatch = inputs.sorted().joined(separator: ", ")
                    continue
                }
                return (candidate, url.deletingPathExtension().lastPathComponent)
            } catch {
                logger.debug("Skipping \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if let lastMismatch { throw LoadError.noMatchingFeatures(lastMismatch) }
        throw LoadError.notFound
    }

    /// Compiled models first, then any raw .mlmodel that slipped into the bundle
    /// uncompiled (compiling it at runtime is slow but beats not scoring at all).
    private func candidateModelURLs() -> [URL] {
        var urls: [URL] = []

        for name in Self.candidateResourceNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                urls.append(url)
            }
        }
        urls += Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []

        for url in Bundle.main.urls(forResourcesWithExtension: "mlmodel", subdirectory: nil) ?? [] {
            if let compiled = try? MLModel.compileModel(at: url) {
                urls.append(compiled)
            }
        }

        // Preserve probe order while dropping duplicates.
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    // MARK: - Prediction

    /// Struggle probability as a whole percentage, 0...100.
    /// Returns nil when the model is unavailable or the prediction fails —
    /// callers fall back to `StruggleScoreCalculator`.
    func predictStruggle(_ features: StruggleFeatures) -> Int? {
        guard let probability = probability(for: features) else { return nil }
        return Int((probability * 100).rounded())
    }

    /// Struggle probability as 0...1, the unit the rest of the app scores in.
    func probability(for features: StruggleFeatures) -> Double? {
        guard let model = requireModel() else { return nil }

        do {
            // Filtered to the columns this model declares. The shipped model
            // ignores extra keys, but relying on that is relying on a quirk of
            // how it was converted — see StruggleFeatures.modelInputs(accepting:).
            lock.lock()
            let declared = declaredInputs
            lock.unlock()

            let inputs = features.modelInputs(accepting: declared)
                .mapValues { NSNumber(value: $0) }
            let provider = try MLDictionaryFeatureProvider(dictionary: inputs)

            // MLModel.prediction is documented as thread-safe, but the load path
            // shares this lock and a single serialisation point keeps that
            // guarantee independent of the Core ML backend in use.
            lock.lock()
            defer { lock.unlock() }

            let output = try model.prediction(from: provider)
            return Self.struggleProbability(from: output)
        } catch {
            logger.error("Prediction failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reads P(struggling) out of whatever shape the classifier returned.
    ///
    /// The class labels are ordinal (0 = coping, 1 = struggling), so weighting
    /// each label by its share of the maximum both collapses to plain P(1) for
    /// the binary model shipped today and keeps working if the model is later
    /// retrained with severity bands.
    private static func struggleProbability(from output: MLFeatureProvider) -> Double? {
        if let dictionary = probabilityDictionary(from: output),
           !dictionary.isEmpty {
            var byLabel: [Int: Double] = [:]
            for (key, value) in dictionary {
                guard let label = label(from: key) else { continue }
                byLabel[label] = value.doubleValue
            }

            if let maximum = byLabel.keys.max(), maximum > 0 {
                let weighted = byLabel.reduce(0.0) { total, entry in
                    total + entry.value * (Double(entry.key) / Double(maximum))
                }
                return min(1, max(0, weighted))
            }
        }

        // No probabilities (or a single-class model): fall back to the hard label.
        if let label = output.featureValue(for: "struggle_label")?.int64Value {
            return label > 0 ? 1 : 0
        }
        return nil
    }

    /// The class-probability dictionary, whichever name the exporter gave it.
    ///
    /// CreateML emits `<label>Probability`; coremltools' scikit-learn
    /// converter emits `classProbability`. Hard-coding either one means a
    /// model exported by the other tool still loads, still predicts, and
    /// silently returns nothing here — the caller then falls back to the hard
    /// 0/1 label, so every student reads as exactly 0% or 100% and no error is
    /// logged anywhere. The retraining pipeline normalises the name on export;
    /// this is the belt to that braces, and it costs one dictionary lookup.
    private static func probabilityDictionary(
        from output: MLFeatureProvider
    ) -> [AnyHashable: NSNumber]? {
        for name in ["struggle_labelProbability", "classProbability"] {
            if let dictionary = output.featureValue(for: name)?.dictionaryValue,
               !dictionary.isEmpty {
                return dictionary
            }
        }
        // Any other name: take the first dictionary-valued output there is.
        for name in output.featureNames {
            if let dictionary = output.featureValue(for: name)?.dictionaryValue,
               !dictionary.isEmpty {
                return dictionary
            }
        }
        return nil
    }

    private static func label(from key: AnyHashable) -> Int? {
        if let number = key as? NSNumber { return number.intValue }
        if let string = key as? String { return Int(string) }
        return nil
    }

    // MARK: - Attribution

    /// Why the model produced this score.
    ///
    /// For each measured feature, the prediction is re-run with that one feature
    /// moved to the value an engaged student would have. The drop in score is
    /// how much of the struggle the model is attributing to that signal — a real
    /// measurement of the loaded model, not a hand-written rule that could drift
    /// away from what the model actually learned.
    ///
    /// `confidence_level` is re-derived after each substitution rather than held
    /// fixed. It summarises the other features, so pinning it would credit a
    /// student with, say, a camera that came on while still describing them as
    /// having the participation profile of someone whose camera is off.
    ///
    /// Costs one extra prediction per feature (still sub-millisecond each), so
    /// it is computed on demand for the student a teacher opens rather than for
    /// the whole roster on every refresh.
    func factors(for features: StruggleFeatures) -> [StruggleFactor] {
        guard let baseline = probability(for: features) else { return [] }

        var found: [StruggleFactor] = []

        for feature in StruggleFeature.allCases where !feature.isDerived {
            let current = features[feature]
            let healthy = feature.engagedBaseline(given: current)
            guard healthy != current else { continue }

            var improved = features
            improved[feature] = healthy
            improved.refreshConfidenceLevel()
            guard let score = probability(for: improved) else { continue }

            let impact = baseline - score
            guard let weight = StruggleFactor.Weight(impact: impact) else { continue }
            guard let title = feature.explanation(value: current) else { continue }

            found.append(
                StruggleFactor(feature: feature, title: title, weight: weight, impact: impact)
            )
        }

        return found.sorted { $0.impact > $1.impact }
    }
}
