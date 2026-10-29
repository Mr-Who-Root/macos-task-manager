import Foundation
import Testing
@testable import TaskManager
import TaskManagerShared

@Suite("Timeline")
@MainActor
struct TimelineTests {
    func sample(cpu: Double, apps: [(String, Double, UInt64)]) -> TimelineStore.Sample {
        TimelineStore.Sample(
            cpu: cpu, memory: 0.5, disk: 1_000, network: 2_000, power: 8, temperature: 50,
            apps: apps.map { (key: "/Applications/\($0.0).app", name: $0.0, cpu: $0.1, memory: $0.2, power: 0.5, disk: 0, network: 0) }
        )
    }

    @Test func averagesAMinuteAndKeepsTheAppsThatStoodOut() {
        let store = TimelineStore(fileURL: Fixtures.temporaryFile("Timeline.json"))
        let start = Date(timeIntervalSinceReferenceDate: 60 * 1_000_000)
        store.record(sample(cpu: 0.2, apps: [("Xcode", 40, 3_000_000_000), ("Mail", 0, 10)]), at: start)
        store.record(sample(cpu: 0.4, apps: [("Xcode", 20, 3_500_000_000)]), at: start.addingTimeInterval(30))
        store.note("Safari stopped responding")
        #expect(store.minutes.isEmpty)
        // The next minute starts, so the first one is written.
        store.record(sample(cpu: 0.1, apps: []), at: start.addingTimeInterval(61))
        let minute = store.minutes.first
        #expect(minute?.time == start)
        #expect(abs((minute?.cpu ?? 0) - 0.3) < 0.0001)
        let xcode = minute?.apps.first { $0.name == "Xcode" }
        #expect(abs((xcode?.cpu ?? 0) - 30) < 0.0001)
        #expect(xcode?.memory == 3_500_000_000)
        #expect(minute?.events == ["Safari stopped responding"])
    }

    @Test func savesAndReloads() {
        let url = Fixtures.temporaryFile("Timeline.json")
        let store = TimelineStore(fileURL: url)
        store.record(sample(cpu: 0.5, apps: [("Xcode", 10, 1)]), at: Date())
        store.save()
        let reloaded = TimelineStore(fileURL: url)
        #expect(reloaded.minutes.count == 1)
        #expect(reloaded.minutes.first?.apps.first?.iconPath == "/Applications/Xcode.app")
    }

    @Test func gapsSplitTheGraph() {
        let base = Date(timeIntervalSinceReferenceDate: 600_000_000)
        let points: [(Date, Double)] = [0, 60, 120, 600, 660].map { (base.addingTimeInterval($0), 0.5) }
        #expect(TimelinePage.segmented(points).map(\.segment) == [0, 0, 0, 1, 1])
    }

    @Test func axisTicksAreOnTheClockAndClearOfTheEdges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 31))!
        let ticks = TimelinePage.ticks(from: end.addingTimeInterval(-3600), to: end, range: .hour, calendar: calendar)
        let minutes = ticks.map { calendar.component(.minute, from: $0) }
        #expect(minutes == [45, 0, 15])
        // Nothing within 6% of either end (the 22:31 start and the 23:31 end).
        #expect(ticks.allSatisfy { $0.timeIntervalSince(end.addingTimeInterval(-3600)) >= 216 && end.timeIntervalSince($0) >= 216 })
    }

    @Test func biggestMomentsAreSpreadOut() {
        let base = Date(timeIntervalSinceReferenceDate: 600_000_000)
        let busy: Set<Int> = [10, 11, 40]
        var minutes: [TimelineStore.Minute] = []
        for i in 0..<60 {
            let cpu: Double = busy.contains(i) ? 0.9 : 0.1
            let time = base.addingTimeInterval(Double(i) * 60)
            minutes.append(TimelineStore.Minute(time: time, cpu: cpu, memory: 0.5, disk: 0, network: 0,
                                                power: nil, temperature: nil, apps: [], events: []))
        }
        let moments = TimelinePage.biggestMoments(minutes, metric: .cpu)
        #expect(moments.count == 3)
        // 10 and 11 are a minute apart, so only one of them counts.
        let topTwo: Set<Date> = Set(moments.prefix(2).map { (m: TimelineStore.Minute) -> Date in m.time })
        let expected: Set<Date> = [base.addingTimeInterval(600), base.addingTimeInterval(2_400)]
        #expect(topTwo == expected)
    }
}

@Suite("Data usage")
@MainActor
struct DataUsageTests {
    @Test func totalsByPeriod() {
        let store = DataUsageStore(fileURL: Fixtures.temporaryFile("DataUsage.json"))
        let calendar = Calendar.current
        let today = Date()
        let lastWeek = calendar.date(byAdding: .day, value: -5, to: today)!
        let lastMonth = calendar.date(byAdding: .day, value: -20, to: today)!
        store.add([(key: "dropbox", name: "Dropbox", iconPath: nil, received: 100, sent: 2_000)], at: today)
        store.add([(key: "dropbox", name: "Dropbox", iconPath: nil, received: 50, sent: 50)], at: lastWeek)
        store.add([(key: "safari", name: "Safari", iconPath: nil, received: 9_000, sent: 10)], at: lastMonth)
        #expect(store.totals(days: 1).map(\.name) == ["Dropbox"])
        #expect(store.totals(days: 7).first?.received == 150)
        #expect(store.totals(days: 7).first?.sent == 2_050)
        #expect(store.totals(days: 30).first?.name == "Safari")
    }

    @Test func savesAndReloads() {
        let url = Fixtures.temporaryFile("DataUsage.json")
        let store = DataUsageStore(fileURL: url)
        store.add([(key: "k", name: "App", iconPath: "/Applications/App.app", received: 5, sent: 6)], at: Date())
        store.save()
        #expect(DataUsageStore(fileURL: url).totals(days: 1).first?.total == 11)
    }

    @Test func dayKeys() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(DataUsageStore.dayKey(Date(timeIntervalSince1970: 0), calendar: calendar) == "1970-01-01")
    }
}

@Suite("Files from earlier versions")
struct CompatibilityTests {
    @Test func appHistoryWithoutEnergy() throws {
        let json = #"{"id":"/Applications/Mail.app","name":"Mail","kind":"app","cpuTime":12,"networkBytes":3,"diskBytes":4,"lastUsed":700000000}"#
        let entry = try JSONDecoder().decode(AppHistoryStore.Entry.self, from: Data(json.utf8))
        #expect(entry.energy == 0)
        #expect(entry.cpuTime == 12)
    }

    @Test func widgetSnapshotFromVersion1_1() throws {
        // Written by 1.1, before battery, power apps and disk history existed.
        let json = """
        {"date":1793289577,"design":"windows11","accent":"automatic","fahrenheit":false,"cpu":0.2,"cpuHistory":[],"perCore":[],
        "cpuName":"Apple M4 Pro","processCount":1,"threadCount":1,"uptime":10,"memoryUsed":1,"memoryTotal":2,"memoryCompressed":0,
        "memoryCached":0,"swapUsed":0,"memoryPressure":"Normal","memoryHistory":[],"gpu":0.1,"gpuName":"GPU","gpuHistory":[],
        "diskName":"Macintosh HD","diskTotal":10,"diskFree":5,"diskRead":0,"diskWrite":0,"networkSend":0,"networkReceive":0,
        "networkSendHistory":[],"networkReceiveHistory":[],"topApps":[],"temperatures":[],"fans":[],"thermalState":"Nominal"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.battery == nil)
        #expect(snapshot.powerApps == nil)
        #expect(snapshot.cpuName == "Apple M4 Pro")
    }

    @Test func formats() {
        #expect(Fmt.watts(0.0861) == "86 mW")
        #expect(Fmt.watts(7.4) == "7.40 W")
        #expect(Fmt.energy(0) == "0 Wh")
        #expect(Fmt.energy(1) == "<1 mWh")
        #expect(Fmt.duration(minutes: 125) == "2 h 05 min")
    }
}
