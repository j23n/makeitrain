import SwiftUI
import TrackerCore

// A project's contract, as the projects lists, a project's page and the
// running timer show it on the Mac, iPhone and iPad.

extension ContractStatus {
    /// The color of the time left: amber at or under the alert, red once
    /// the hours are used up, or nil for the usual text color.
    public var leftColor: Color? {
        isUsedUp ? Theme.overText : (isLow ? Theme.amberText : nil)
    }
}

/// The time used of a contract as a bar: in the project's color, amber at
/// or under the alert and red once over, with a tick where an even pace
/// would be, and the alert dotted when `showsAlert` is set.
public struct ContractBar: View {
    let status: ContractStatus
    let tint: ProjectTint
    let height: CGFloat
    let showsPace: Bool
    let showsAlert: Bool

    public init(status: ContractStatus, tint: ProjectTint, height: CGFloat = 5, showsPace: Bool = true, showsAlert: Bool = false) {
        self.status = status
        self.tint = tint
        self.height = height
        self.showsPace = showsPace
        self.showsAlert = showsAlert
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.emptyBar)
                Capsule()
                    .fill(fill)
                    .frame(width: status.used > 0 ? max(height, width * status.usedShare) : 0)
                if showsAlert, let share = status.alertShare {
                    DottedLine()
                        .stroke(Theme.amberText, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2]))
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: width * share - 0.75)
                }
                if showsPace, status.hasStarted {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(status.isOver ? Color.white.opacity(0.9) : Theme.text.opacity(0.6))
                        .frame(width: 2, height: height + 4)
                        .offset(x: min(width - 2, max(0, width * status.paceShare - 1)))
                }
            }
            .frame(height: height + 6)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Format.left(status)) of \(Format.hours(status.contract.hours))"))
    }

    private var fill: Color {
        status.isUsedUp ? Theme.now : (status.isLow ? Theme.amber : tint.bar)
    }

    /// A vertical line, for the alert's dots.
    private struct DottedLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return path
        }
    }
}

/// A contract's time left, such as "33 h 20 m left", in amber with a bell
/// at or under the alert and in red once over.
public struct ContractLeftText: View {
    let status: ContractStatus
    let size: CGFloat

    public init(_ status: ContractStatus, size: CGFloat = 12.5) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            if status.isLow, !status.isUsedUp {
                Image(systemName: "bell.fill")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(Theme.amber)
                    .accessibilityHidden(true)
            }
            Text(Format.left(status))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(status.leftColor ?? Theme.text)
        }
        .font(.system(size: size))
        .lineLimit(1)
    }
}

/// The running timer's contract, such as "3:10 left until Nov 30", in
/// amber at or under the alert and red once over.
public struct RunningContractText: View {
    let status: ContractStatus

    public init(_ status: ContractStatus) {
        self.status = status
    }

    public var body: some View {
        Text("\(Format.left(status)) until \(Format.monthDay(status.contract.end))")
            .fontWeight(status.isLow ? .semibold : .regular)
            .monospacedDigit()
            .foregroundStyle(status.leftColor ?? Theme.text3)
            .lineLimit(1)
    }
}

/// A project's contract on its page: the time left, used, the days to
/// go and the pace, as a bar with the even pace and the alert, and when
/// the hours likely run out. `compact` lays it out for iPhone.
public struct ContractCard: View {
    let status: ContractStatus
    let tint: ProjectTint
    let compact: Bool

    public init(status: ContractStatus, tint: ProjectTint, compact: Bool = false) {
        self.status = status
        self.tint = tint
        self.compact = compact
    }

    private var contract: Contract { status.contract }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            header
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.duration(abs(status.left)))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(status.leftColor ?? Theme.text)
                    Text(status.isOver ? "over \(Format.hours(contract.hours))" : "left of \(Format.hours(contract.hours))")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text2)
                }
                .monospacedDigit()
                ContractBar(status: status, tint: tint, height: 8, showsAlert: true)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                    figures
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Format.duration(abs(status.left)))
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(status.leftColor ?? Theme.text)
                        Text(status.isOver ? "over" : "left")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text2)
                    }
                    figures
                    Spacer(minLength: 0)
                }
                .monospacedDigit()
                ContractBar(status: status, tint: tint, height: 10, showsAlert: true)
            }
            if let note {
                Text(note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: compact ? 14 : 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: compact ? 14 : 12).strokeBorder(status.isLow ? Theme.amberLine : Theme.line))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Contract")
                .font(.system(size: 14, weight: .semibold))
            Text(compact ? Format.days(contract.days) : "\(Format.days(contract.days)) · \(Format.hours(contract.hours))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !compact, status.isLow, status.hasStarted {
                Label(status.isOver ? "Over the hours" : "Under the \(Format.hours(contract.alertsAt)) alert", systemImage: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.isOver ? Theme.overText : Theme.amberText)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(status.isOver ? Theme.now.opacity(0.12) : Theme.amberFill))
            }
        }
    }

    @ViewBuilder
    private var figures: some View {
        figure(Format.duration(status.used), compact ? "used" : "used of \(Format.hours(contract.hours))")
        if !status.hasStarted {
            figure(Format.monthDay(contract.start), "when it starts")
        } else if status.hasEnded {
            figure(Format.monthDay(contract.end), "when it ended")
        } else {
            figure("\(status.daysLeft) \(status.daysLeft == 1 ? "day" : "days")", "to go, \(status.workdaysLeft) \(status.workdaysLeft == 1 ? "workday" : "workdays")")
        }
        if status.hasStarted {
            let ahead = status.aheadOfPace
            figure(Format.duration(abs(ahead)), ahead >= 0 ? "ahead of an even pace" : "behind an even pace")
        }
        if compact {
            figure(contract.alertsAt > 0 ? "\(Format.hours(contract.alertsAt)) left" : "Off", "alerts")
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text(value)
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
        }
    }

    /// When the hours likely run out at the recent pace, or how much is
    /// over.
    private var note: String? {
        if status.isOver, !status.hasEnded {
            return "Time logged from now on counts as over."
        }
        guard let runsOut = status.runsOut, let rate = status.recentRate else { return nil }
        return "At the pace of the last four weeks, about \(Format.duration(rate)) a workday, the hours run out around \(Format.day(runsOut))."
    }
}

#if DEBUG
#Preview("Contracts") {
    let model = PreviewData.model()
    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([PreviewData.website, PreviewData.mobileApp, PreviewData.brand], id: \.self) { id in
                if let status = model.contractStatus(ofProject: id) {
                    let tint = model.ledger.tint(ofProject: id)
                    ContractCard(status: status, tint: tint)
                    ContractCard(status: status, tint: tint, compact: true)
                        .frame(width: 360)
                    HStack {
                        ContractLeftText(status)
                        RunningContractText(status)
                    }
                    ContractBar(status: status, tint: tint)
                        .frame(width: 200)
                }
            }
        }
        .padding()
    }
    .frame(width: 760, height: 900)
    .background(Theme.background)
}
#endif
