import AppKit
import RelayCore

@MainActor
func relayCard() -> NSView {
    let view = NSVisualEffectView()
    view.material = .contentBackground
    view.blendingMode = .withinWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.borderWidth = 1
    view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    return view
}

@MainActor
func relayLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = NSFont.systemFont(ofSize: size, weight: weight)
    label.textColor = color
    return label
}

@MainActor
func relayButton(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    return button
}

final class RelayStatusBadge: NSView {
    private let label = NSTextField(labelWithString: "")

    init(status: AgentStatus) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = color(for: status).withAlphaComponent(0.14).cgColor
        label.stringValue = status.displayName
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = color(for: status)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func color(for status: AgentStatus) -> NSColor {
        switch status {
        case .running: return .systemGreen
        case .waiting: return .systemOrange
        case .approvalRequired: return .systemRed
        case .completed: return .systemBlue
        case .failed: return .systemRed
        case .idle, .discovered, .unknown, .abandoned: return .secondaryLabelColor
        }
    }
}

final class RelayEmptyStateView: NSView {
    init(title: String, message: String) {
        super.init(frame: .zero)
        let titleLabel = relayLabel(title, size: 18, weight: .semibold)
        let messageLabel = relayLabel(message, size: 13, color: .secondaryLabelColor)
        let stack = NSStackView(views: [titleLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -36)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class RelayMetricCard: NSView {
    init(metric: UsageMetric) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let value: String
        if let metricValue = metric.value {
            if metric.unit == "seconds" {
                value = metricValue < 60 ? "\(Int(metricValue))s" : "\(Int(metricValue / 60))m"
            } else {
                value = metricValue.rounded() == metricValue ? "\(Int(metricValue))" : String(format: "%.1f", metricValue)
            }
        } else {
            value = "Unavailable"
        }
        let valueLabel = relayLabel(value, size: metric.value == nil ? 18 : 30, weight: .bold)
        let titleLabel = relayLabel(metric.label, size: 12, weight: .medium, color: .secondaryLabelColor)
        let sourceLabel = relayLabel("\(metric.precision.rawValue) · \(metric.source)", size: 10, color: .tertiaryLabelColor)
        let stack = NSStackView(views: [valueLabel, titleLabel, sourceLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 112)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
