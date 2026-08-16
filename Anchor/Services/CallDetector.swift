//
//  CallDetector.swift
//  Anchor
//
//  Notices locally when the teacher is in a Zoom call, without needing Zoom's
//  cooperation or host privileges.
//
//  Two independent signals are combined:
//    1. Zoom's in-meeting helper process (`CptHost`) — it only runs while a
//       meeting is actually in progress, not when Zoom is merely open.
//    2. The default input device being live (CoreAudio). Reading
//       `kAudioDevicePropertyDeviceIsRunningSomewhere` is a device property, so
//       it needs no microphone permission and captures no audio.
//

import AppKit
import Combine
import CoreAudio
import Foundation

@MainActor
final class CallDetector: ObservableObject {

    struct Signals: Equatable {
        var zoomRunning = false
        var meetingHelperRunning = false
        var inputDeviceLive = false

        /// Zoom open on its own means nothing; a meeting needs the helper
        /// process or a live input device alongside it.
        var indicatesCall: Bool {
            zoomRunning && (meetingHelperRunning || inputDeviceLive)
        }
    }

    @Published private(set) var signals = Signals()
    @Published private(set) var isInCall = false

    /// Fired once per call, on the transition into a meeting.
    var onCallStarted: (() -> Void)?
    var onCallEnded: (() -> Void)?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 5
    /// Requires two consecutive positives before firing, so a brief mic blip
    /// (a Slack huddle notification sound, say) doesn't nag the teacher.
    private var consecutivePositives = 0
    private let confirmationsRequired = 2

    private static let zoomBundleIDs: Set<String> = [
        "us.zoom.xos",          // Zoom desktop client
        "us.zoom.ZoomClips"
    ]
    private static let meetingHelperNames: Set<String> = ["CptHost", "aomhost", "zTscoder"]

    // MARK: - Control

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        consecutivePositives = 0
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Polling

    private func poll() {
        var next = Signals()

        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier, Self.zoomBundleIDs.contains(bundleID) {
                next.zoomRunning = true
            }
            if let executable = app.executableURL?.lastPathComponent,
               Self.meetingHelperNames.contains(executable) {
                next.meetingHelperRunning = true
                next.zoomRunning = true      // the helper only exists under Zoom
            }
        }

        next.inputDeviceLive = Self.isDefaultInputLive()
        signals = next

        if next.indicatesCall {
            consecutivePositives += 1
        } else {
            consecutivePositives = 0
        }

        let detected = consecutivePositives >= confirmationsRequired
        guard detected != isInCall else { return }

        isInCall = detected
        detected ? onCallStarted?() : onCallEnded?()
    }

    // MARK: - CoreAudio

    /// True when something on this Mac is actively using the default input.
    /// This reads a device property only — no audio is opened or captured.
    nonisolated static func isDefaultInputLive() -> Bool {
        guard let device = defaultInputDevice() else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &isRunning)
        return status == noErr && isRunning != 0
    }

    nonisolated private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
}
