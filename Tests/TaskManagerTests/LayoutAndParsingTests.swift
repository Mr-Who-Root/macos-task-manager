import CoreGraphics
import Foundation
import Testing
@testable import TaskManager

@Suite("Process map layout")
struct TreemapTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func areasAreProportionalAndFillTheSpace() {
        let values = [500.0, 250, 125, 75, 50]
        let rects = Treemap.layout(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * value / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 1)
        }
    }

    @Test func tilesStayInsideAndDontOverlap() {
        let values = (1...40).map { Double($0 * $0) }
        let rects = Treemap.layout(values, in: bounds)
        for rect in rects {
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func keepsInputOrderAndSkipsZeros() {
        let rects = Treemap.layout([0, 10, -3, 30], in: bounds)
        #expect(rects[0] == .zero)
        #expect(rects[2] == .zero)
        #expect(rects[3].width * rects[3].height > rects[1].width * rects[1].height)
    }

    @Test func emptyInput() {
        #expect(Treemap.layout([], in: bounds).isEmpty)
        #expect(Treemap.layout([1, 2], in: .zero) == [.zero, .zero])
    }

    @Test func tilesAreReasonablySquare() {
        let rects = Treemap.layout([6, 6, 4, 3, 2, 2, 1], in: bounds)
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 4)
    }

    @Test func mapItemsAreLargestFirstAndSkipIdleOnes() {
        var nodes = (1...200).map { Fixtures.node("App \($0)", pid: Int32($0), memory: UInt64($0) * 1_000_000) }
        nodes.append(Fixtures.node("Idle", pid: 999, memory: 0))
        let items = ProcessMap.items(nodes: nodes, focused: nil, measure: .memory, energyAvailable: true)
        #expect(items.count == 200)
        #expect(items.first?.name == "App 200")
        #expect(!items.contains { $0.name == "Idle" })
        let cpu = ProcessMap.items(nodes: [Fixtures.node("Busy", cpu: 12), Fixtures.node("Quiet", pid: 2)], focused: nil, measure: .cpu, energyAvailable: true)
        #expect(cpu.map(\.name) == ["Busy"])
    }

    @Test func zoomingIntoAnAppShowsItsProcesses() {
        var chrome = Fixtures.node("Chrome", pid: 10, memory: 100)
        chrome.members = [Fixtures.process(10, "Chrome", memory: 100), Fixtures.process(11, "Chrome Helper", memory: 900)]
        let items = ProcessMap.items(nodes: [chrome], focused: chrome, measure: .memory, energyAvailable: true)
        #expect(items.map(\.name) == ["Chrome Helper", "Chrome"])
        #expect(items.first?.id == "\(chrome.id)/11")
    }
}

@Suite("Privacy indicator log")
@MainActor
struct PrivacyTests {
    @Test func parsesAttributions() {
        let parsed = PrivacyMonitor.parseAttributions(#"Active activity attributions changed to ["scr:com.ethanbills.DockDoor", "mic:com.apple.FaceTime"]"#)
        #expect(parsed?.map(\.0) == [.screen, .microphone])
        #expect(parsed?.map(\.1) == ["com.ethanbills.DockDoor", "com.apple.FaceTime"])
        #expect(PrivacyMonitor.parseAttributions("Active activity attributions changed to []")?.isEmpty == true)
        #expect(PrivacyMonitor.parseAttributions("Sorted active attributions from SystemStatus update: []") == nil)
        #expect(PrivacyMonitor.parseAttributions(#"Active activity attributions changed to ["xyz:com.example"]"#)?.isEmpty == true)
    }

    @Test func parsesNDJSONLines() {
        let output = """
        Filtering the log data using "subsystem == ..."
        {"timestamp":"2026-10-28 17:10:09.792353+0530","eventMessage":"Active activity attributions changed to [\\"cam:us.zoom.xos\\"]"}
        {"timestamp":"2026-10-28 17:10:19.861000+0530","eventMessage":"Active activity attributions changed to []"}
        """
        let events = PrivacyMonitor.parseLines(output)
        #expect(events.count == 2)
        #expect(events[0].sensors.first?.1 == "us.zoom.xos")
        #expect(events[1].time.timeIntervalSince(events[0].time) > 10)
    }

    @Test func sessionsStartEndAndMerge() {
        let monitor = PrivacyMonitor()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        monitor.apply([(.camera, "us.zoom.xos")], at: t0)
        #expect(monitor.active(.camera).count == 1)
        monitor.apply([], at: t0.addingTimeInterval(300))
        #expect(monitor.active.isEmpty)
        #expect(monitor.sessions.first?.end == t0.addingTimeInterval(300))
        // Back on within a minute: the same session continues.
        monitor.apply([(.camera, "us.zoom.xos")], at: t0.addingTimeInterval(330))
        #expect(monitor.sessions.count == 1)
        #expect(monitor.sessions.first?.isActive == true)
        // Back on after a long gap: a new session.
        monitor.apply([], at: t0.addingTimeInterval(400))
        monitor.apply([(.camera, "us.zoom.xos"), (.microphone, "us.zoom.xos")], at: t0.addingTimeInterval(1_000))
        #expect(monitor.sessions.count == 3)
        #expect(monitor.active.count == 2)
    }
}

@Suite("Ports and network data")
struct NetworkTests {
    @Test func mergesIPv4AndIPv6Sockets() {
        let ports = NetworkPorts.merge([
            (pid: 10, port: 5000, loopback: false), (pid: 10, port: 5000, loopback: false),
            (pid: 11, port: 8080, loopback: true), (pid: 11, port: 8080, loopback: true),
            (pid: 12, port: 3000, loopback: true), (pid: 12, port: 3000, loopback: false),
        ])
        #expect(ports.count == 3)
        #expect(ports.first { $0.port == 8080 }?.localOnly == true)
        // Open to the network if any of its sockets is.
        #expect(ports.first { $0.port == 3000 }?.localOnly == false)
        #expect(ports.map(\.port) == [3000, 5000, 8080])
    }

    @Test func splitsNettopDownloadsAndUploads() {
        let output = """
        ,bytes_in,bytes_out,
        Google Chrome H.1234,1000,200,
        Google Chrome H.1234,500,50,
        com.apple.Safari.Web, Content.88,70,7,
        """
        let parsed = ProcessSampler.parseNettop(output)
        #expect(parsed[1234]?.received == 1500)
        #expect(parsed[1234]?.sent == 250)
        #expect(parsed[88]?.received == 70)
    }
}
