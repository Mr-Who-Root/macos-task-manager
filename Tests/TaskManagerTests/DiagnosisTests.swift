import Foundation
import Testing
@testable import TaskManager

@Suite("Why is my Mac slow?")
struct DiagnosisTests {
    @Test func healthyMacHasNoProblems() {
        let input = Fixtures.diagnosis(nodes: [Fixtures.node("Safari", cpu: 3, memory: 800_000_000)])
        #expect(Diagnosis.findings(input).filter { $0.severity > .info }.isEmpty)
    }

    @Test func appThatStoppedRespondingComesFirst() {
        let input = Fixtures.diagnosis(nodes: [
            Fixtures.node("Xcode", pid: 200, cpu: 40),
            Fixtures.node("Safari", pid: 300, notResponding: true),
        ])
        let findings = Diagnosis.findings(input)
        #expect(findings.first?.title == "Safari is not responding")
        #expect(findings.first?.severity == .critical)
        #expect(findings.first?.buttons.contains(Finding.Button(title: "End task", action: .endTask(pid: 300))) == true)
    }

    @Test func sampleIsOfferedForAHungApp() {
        var input = Fixtures.diagnosis(nodes: [Fixtures.node("Safari", pid: 300, notResponding: true)])
        input.hangSamples = [300: "/tmp/Safari.txt"]
        let buttons = Diagnosis.findings(input).first?.buttons ?? []
        #expect(buttons.contains(Finding.Button(title: "Show sample", action: .revealFile("/tmp/Safari.txt"))))
    }

    @Test func cpuHogGetsEfficiencyModeAndEndTask() {
        let input = Fixtures.diagnosis(nodes: [Fixtures.node("Chrome", pid: 400, cpu: 35, cpuTrend: 32)])
        let finding = Diagnosis.findings(input).first { $0.id.hasPrefix("cpu:") }
        #expect(finding?.severity == .warning)
        #expect(finding?.buttons.map(\.action) == [.efficiency(pid: 400), .endTask(pid: 400)])
    }

    @Test func briefSpikeIsNotAHog() {
        // Busy right now, but not over the two-minute trend.
        let input = Fixtures.diagnosis(nodes: [Fixtures.node("Chrome", cpu: 60, cpuTrend: 4)])
        #expect(!Diagnosis.findings(input).contains { $0.id.hasPrefix("cpu:") })
    }

    @Test func spotlightIsExplainedNotBlamed() {
        let input = Fixtures.diagnosis(nodes: [Fixtures.node("mds_stores", kind: .system, cpu: 30, cpuTrend: 30)])
        let findings = Diagnosis.findings(input)
        #expect(findings.contains { $0.title == "Spotlight is indexing" && $0.severity == .info })
        #expect(!findings.contains { $0.id.hasPrefix("cpu:") })
    }

    @Test func criticalMemoryPressure() {
        var memory = MemorySnapshot()
        memory.pressure = 4
        memory.swapUsed = 6_000_000_000
        let input = Fixtures.diagnosis(nodes: [Fixtures.node("Chrome", memory: 9_000_000_000)], memory: memory)
        let finding = Diagnosis.findings(input).first { $0.id == "memory" }
        #expect(finding?.severity == .critical)
        #expect(finding?.detail.contains("Chrome") == true)
    }

    @Test func nearlyFullDisk() {
        var input = Fixtures.diagnosis()
        input.diskFree = 3_000_000_000
        #expect(Diagnosis.findings(input).first { $0.id == "disk:full" }?.severity == .critical)
        input.diskFree = 8_000_000_000
        #expect(Diagnosis.findings(input).first { $0.id == "disk:full" }?.severity == .warning)
    }

    @Test func overheatingAndSettings() {
        var input = Fixtures.diagnosis(nodes: [Fixtures.node("Final Cut Pro", cpu: 15, power: 12)])
        input.thermalState = 2
        input.lowPowerMode = true
        input.uptime = 20 * 86_400
        let findings = Diagnosis.findings(input)
        #expect(findings.first?.id == "thermal")
        #expect(findings.first?.detail.contains("Final Cut Pro") == true)
        #expect(findings.contains { $0.id == "lowpower" })
        #expect(findings.contains { $0.id == "uptime" && $0.title.contains("20 days") })
    }

    @Test func findingsAreOrderedBySeverity() {
        var input = Fixtures.diagnosis(nodes: [
            Fixtures.node("Chrome", pid: 1, cpu: 30, cpuTrend: 30),
            Fixtures.node("Safari", pid: 2, notResponding: true),
        ])
        input.lowPowerMode = true
        let severities = Diagnosis.findings(input).map(\.severity)
        #expect(severities == severities.sorted(by: >))
    }
}

@Suite("Not responding")
struct HangDetectorTests {
    let now = Date(timeIntervalSince1970: 10_000)

    @Test func windowServerFlagCountsAtOnce() {
        let hang = HangDetector.verdict(flaggedSince: now, busySince: nil, now: now)
        #expect(hang == HangDetector.Hang(since: now, busy: false))
    }

    @Test func busyMainThreadNeedsFiveSeconds() {
        #expect(HangDetector.verdict(flaggedSince: nil, busySince: now.addingTimeInterval(-3), now: now) == nil)
        let hang = HangDetector.verdict(flaggedSince: nil, busySince: now.addingTimeInterval(-6), now: now)
        #expect(hang?.busy == true)
        #expect(hang?.since == now.addingTimeInterval(-6))
    }

    @Test func briefDipsDontResetTheClock() {
        let start = now.addingTimeInterval(-4)
        // A dip to 70% (another app competing, or `sample` pausing it) keeps the clock running…
        #expect(HangDetector.busySince(start, busy: 0.7, now: now) == start)
        // …but going quiet ends it.
        #expect(HangDetector.busySince(start, busy: 0.2, now: now) == nil)
        #expect(HangDetector.busySince(nil, busy: 0.9, now: now) == now)
        #expect(HangDetector.busySince(nil, busy: 0.7, now: now) == nil)
    }

    @Test func idleAppIsFine() {
        #expect(HangDetector.verdict(flaggedSince: nil, busySince: nil, now: now) == nil)
    }

    @Test func hungAppShowsNotRespondingStatus() {
        let node = Fixtures.node("Safari", notResponding: true)
        #expect(node.statusText == "Not responding")
        #expect(Fixtures.process(1, "Safari", notResponding: true).detailStatus == "Not responding")
    }
}
