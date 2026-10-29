import AppKit
import SwiftUI

/// "Why is my Mac slow?": what's slowing the Mac down right now, in plain words, with fixes.
/// Updates live while it's open.
struct DiagnosisSheet: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let findings = Diagnosis.findings(monitor.diagnosisInput)
        let problems = findings.filter { $0.severity > .info }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: problems.isEmpty ? "checkmark.seal.fill" : "stethoscope")
                    .font(.system(size: 26))
                    .foregroundStyle(problems.isEmpty ? Fluent.efficiency : Fluent.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why is my Mac slow?")
                        .font(.system(size: 18, weight: .semibold))
                    Text(headline(problems: problems.count, notes: findings.count - problems.count))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Fluent.textSecondary)
                }
            }
            SummaryStrip(monitor: monitor, fahrenheit: settings.useFahrenheit)
            ScrollView {
                VStack(spacing: 10) {
                    if findings.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.thumbsup").font(.system(size: 24)).foregroundStyle(Fluent.efficiency)
                            Text("Nothing looks wrong right now. The processor, memory, disk and temperatures are all fine.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Fluent.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                    ForEach(findings) { finding in
                        FindingCard(finding: finding, perform: perform)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 140, maxHeight: 400)
            HStack(spacing: 8) {
                Text("Checks update live while this is open.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Fluent.textTertiary)
                Spacer()
                Button("Open Timeline") {
                    state.page = .timeline
                    dismiss()
                }
                .buttonStyle(StandardButtonStyle())
                Button("Done") { dismiss() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func headline(problems: Int, notes: Int) -> String {
        switch problems {
        case 0: return notes == 0 ? "Your Mac looks healthy." : "Your Mac looks healthy. A few things worth knowing:"
        case 1: return "1 thing is slowing your Mac down."
        default: return "\(problems) things are slowing your Mac down."
        }
    }

    private func perform(_ action: Finding.Action) {
        func target(_ pid: Int32) -> RowTarget? {
            monitor.nodes.first { $0.mainPID == pid }.map(RowTarget.init(node:))
        }
        switch action {
        case .endTask(let pid):
            guard let target = target(pid) else { return }
            // Confirmations appear on the main window, so close this sheet first.
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                ProcessActions.requestEndTask(target)
            }
        case .efficiency(let pid):
            guard let target = target(pid) else { return }
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                ProcessActions.requestEfficiency(target, enabled: true)
            }
        case .showDetails(let pid):
            state.showDetails(for: pid)
            dismiss()
        case .openURL(let string):
            if let url = URL(string: string) { NSWorkspace.shared.open(url) }
        case .revealFile(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .openPage(let raw):
            if let page = Page(rawValue: raw) { state.page = page }
            dismiss()
        }
    }
}

private struct SummaryStrip: View {
    let monitor: Monitor
    let fahrenheit: Bool

    var body: some View {
        let s = monitor.system
        HStack(spacing: 0) {
            stat("CPU", Fmt.wholePercent(s.cpu.total))
            stat("Memory", "\(Fmt.wholePercent(s.memory.usedFraction)) · \(s.memory.pressureText)")
            if let gpu = s.gpu { stat("GPU", Fmt.wholePercent(gpu.utilization)) }
            if let celsius = s.sensors.cpuTemperature { stat("CPU temp", Fmt.temperature(celsius, fahrenheit: fahrenheit)) }
            stat("Thermal", s.sensors.thermalStateText)
        }
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Fluent.textSecondary)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FindingCard: View {
    let finding: Finding
    let perform: (Finding.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: finding.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Self.color(finding.severity))
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(finding.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Fluent.textPrimary)
                    if finding.severity == .critical {
                        Text("Needs attention")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Self.color(.critical))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Self.color(.critical).opacity(0.14)))
                    }
                }
                Text(finding.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Fluent.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !finding.buttons.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(finding.buttons, id: \.self) { button in
                            Button(button.title) { perform(button.action) }
                                .buttonStyle(StandardButtonStyle())
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).fill(Fluent.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Self.color(finding.severity)).frame(width: 3).padding(.vertical, 10)
        }
        .overlay(RoundedRectangle(cornerRadius: Fluent.cardRadius, style: .continuous).strokeBorder(Fluent.cardStroke))
    }

    static func color(_ severity: Finding.Severity) -> Color {
        switch severity {
        case .critical: return ResourceColor.thermal
        case .warning: return ChargeScale.low
        case .info: return Fluent.accent
        }
    }
}
