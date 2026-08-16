//
//  TrainingDataExporter.swift
//  Anchor
//
//  Writes the current roster's feature vectors to CSV so a teacher's session can
//  be labelled and fed to retraining/train_struggle_model.py.
//
//  The `struggle` column is intentionally left blank. It is the teacher's
//  judgement — "was Anchor right about this student?" — and the whole point of
//  the retraining loop is that the label comes from a human rather than from the
//  model's own output. Pre-filling it with the current prediction would train the
//  next model to agree with this one.
//
//  Privacy: the export contains student names and, when Classroom is connected,
//  derived academic counts. It is written only where the teacher chooses to save
//  it, never automatically, and never into the app's own storage.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum TrainingDataExporter {

    /// Column order in the exported CSV. The 16 feature columns match
    /// `StruggleFeature.rawValue` exactly, which is what the training script
    /// expects.
    static var columns: [String] {
        ["exported_at", "meeting", "identity_key", "student_name"]
            + StruggleFeature.allCases.map(\.rawValue)
            + ["anchor_score", "anchor_confidence", "score_source", "struggle"]
    }

    /// Builds the CSV text for a roster.
    static func csv(students: [Student], meetingTitle: String, now: Date = Date()) -> String {
        let timestamp = ISO8601DateFormatter().string(from: now)

        var rows = [columns.joined(separator: ",")]

        for student in students {
            // A student with no feature vector was never scored; exporting a row
            // of defaults would put fabricated data in the training set.
            guard let features = student.features else { continue }

            var fields: [String] = [
                timestamp,
                escape(meetingTitle),
                escape(student.identityKey),
                escape(student.name)
            ]

            let inputs = features.allInputs
            for feature in StruggleFeature.allCases {
                fields.append(String(inputs[feature.rawValue] ?? 0))
            }

            fields.append(String(format: "%.4f", student.struggleScore))
            fields.append(String(format: "%.2f", student.confidence))
            fields.append(student.scoreSource.rawValue)
            fields.append("")   // struggle — for the teacher to fill in: 0 or 1

            rows.append(fields.joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 quoting — student names contain commas more often than you'd think.
    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Save panel

    /// Prompts for a location and writes the CSV. Returns the URL on success.
    @MainActor
    @discardableResult
    static func export(students: [Student], meetingTitle: String) -> URL? {
        guard !students.isEmpty else { return nil }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedFilename(meetingTitle: meetingTitle)
        panel.title = "Export training data"
        panel.message = "Leave the 'struggle' column blank, then fill it in with 1 for "
            + "students who were genuinely struggling and 0 for those who weren't."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try csv(students: students, meetingTitle: meetingTitle)
                .write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    private static func suggestedFilename(meetingTitle: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let safe = meetingTitle
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        return "anchor-\(safe.isEmpty ? "session" : safe)-\(formatter.string(from: Date())).csv"
    }
}
