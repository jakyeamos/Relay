import AppKit
import RelayCore

@MainActor
enum RelayDesign {
    static let sidebarWidth: CGFloat = 242
    static let inspectorWidth: CGFloat = 360
    static let minimumListWidth: CGFloat = 320
    static let rowHeight: CGFloat = 62
    static let compactRowHeight: CGFloat = 46
    static let spacing: CGFloat = 12

    static let signal = NSColor.systemBlue
    static let attention = NSColor.systemOrange
    static let destructive = NSColor.systemRed
    static let success = NSColor.systemGreen

    static func statusColor(_ status: AgentStatus) -> NSColor {
        switch status {
        case .running: return success
        case .waiting: return attention
        case .approvalRequired, .failed: return destructive
        case .completed: return signal
        case .idle, .discovered, .unknown, .abandoned: return .secondaryLabelColor
        }
    }

    static func lifecycleColor(_ lifecycle: CandidateLifecycle) -> NSColor {
        switch lifecycle {
        case .pending, .reviewed: return attention
        case .applied: return success
        case .undone: return signal
        case .snoozed, .dismissed: return .secondaryLabelColor
        }
    }
}

@MainActor
func relayLabel(
    _ text: String,
    size: CGFloat = 13,
    weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor
) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = NSFont.systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
}

@MainActor
func relayButton(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.setAccessibilityLabel(title)
    return button
}

@MainActor
func relayToolbarButton(
    symbol: String,
    label: String,
    target: AnyObject?,
    action: Selector
) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: target, action: action)
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = label
    button.setAccessibilityLabel(label)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 30),
        button.heightAnchor.constraint(equalToConstant: 28)
    ])
    return button
}

@MainActor
func relaySectionHeader(_ title: String, detail: String? = nil) -> NSView {
    let titleLabel = relayLabel(title.uppercased(), size: 11, weight: .bold, color: .secondaryLabelColor)
    titleLabel.setContentHuggingPriority(.required, for: .horizontal)
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    stack.addArrangedSubview(titleLabel)
    if let detail {
        let detailLabel = relayLabel(detail, size: 11, color: .tertiaryLabelColor)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(detailLabel)
    }
    return stack
}

@MainActor
func relayDivider() -> NSView {
    let divider = NSView()
    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    divider.translatesAutoresizingMaskIntoConstraints = false
    divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return divider
}

@MainActor
func relaySurface(material: NSVisualEffectView.Material = .contentBackground) -> NSVisualEffectView {
    let surface = NSVisualEffectView()
    surface.material = material
    surface.blendingMode = .withinWindow
    surface.state = .active
    surface.wantsLayer = true
    surface.layer?.cornerRadius = 10
    return surface
}

@MainActor
final class RelayStatusBadge: NSView {
    private let label = NSTextField(labelWithString: "")

    init(status: AgentStatus) {
        super.init(frame: .zero)
        configure(text: status.displayName, color: RelayDesign.statusColor(status))
        setAccessibilityLabel(status.displayName)
    }

    init(text: String, color: NSColor) {
        super.init(frame: .zero)
        configure(text: text, color: color)
        setAccessibilityLabel(text)
    }

    private func configure(text: String, color: NSColor) {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        label.stringValue = text
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class RelayEmptyStateView: NSView {
    init(title: String, message: String, symbol: String = "sparkles") {
        super.init(frame: .zero)
        let imageView = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage())
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = relayLabel(title, size: 18, weight: .semibold)
        let messageLabel = relayLabel(message, size: 13, color: .secondaryLabelColor)
        messageLabel.alignment = .center
        let stack = NSStackView(views: [imageView, titleLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -36)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class RelayInlineBanner: NSView {
    init(message: String, tone: NSColor = RelayDesign.signal) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = tone.withAlphaComponent(0.12).cgColor
        let icon = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Information") ?? NSImage())
        icon.contentTintColor = tone
        let label = relayLabel(message, size: 12, color: .labelColor)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class RelaySparklineView: NSView {
    var values: [CGFloat] = [] { didSet { needsDisplay = true } }
    var strokeColor: NSColor = RelayDesign.signal { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard values.count > 1 else { return }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let range = max(0.0001, maximum - minimum)
        let path = NSBezierPath()
        for (index, value) in values.enumerated() {
            let x = bounds.minX + bounds.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = bounds.minY + bounds.height * (value - minimum) / range
            if index == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        strokeColor.setStroke()
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.stroke()
    }
}

@MainActor
final class RelayTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 6, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
func relayTextView(_ text: String, font: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)) -> NSScrollView {
    let textView = NSTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.font = font
    textView.textColor = .labelColor
    textView.string = text
    let scroll = NSScrollView()
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.drawsBackground = false
    scroll.borderType = .bezelBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
    return scroll
}
