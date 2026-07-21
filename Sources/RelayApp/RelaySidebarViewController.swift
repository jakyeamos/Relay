import AppKit

final class RelaySidebarViewController: NSViewController {
    var onSelect: ((RelayDestination) -> Void)?
    private var buttons: [RelayDestination: NSButton] = [:]

    override func loadView() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        view = visualEffect

        let title = NSTextField(labelWithString: "RELAY")
        title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        title.textColor = .secondaryLabelColor

        let subtitle = NSTextField(wrappingLabelWithString: "A calm control plane for your AI coding workflow.")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .tertiaryLabelColor

        let navigation = NSStackView(views: RelayDestination.allCases.map(makeButton))
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 5

        let status = NSTextField(wrappingLabelWithString: "Local-first · background monitor on")
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [title, subtitle, navigation, NSView(), status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 34),
            stack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -18),
            navigation.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func select(destination: RelayDestination) {
        buttons.forEach { $0.value.state = $0.key == destination ? .on : .off }
    }

    private func makeButton(destination: RelayDestination) -> NSButton {
        let button = NSButton(title: "  \(destination.title)", target: self, action: #selector(selectButton(_:)))
        button.image = NSImage(systemSymbolName: symbol(for: destination), accessibilityDescription: destination.title)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.setButtonType(.pushOnPushOff)
        button.contentTintColor = .labelColor
        button.identifier = NSUserInterfaceItemIdentifier(destination.title.lowercased())
        button.translatesAutoresizingMaskIntoConstraints = false
        buttons[destination] = button
        if destination == .today { button.state = .on }
        return button
    }

    @objc private func selectButton(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let destination = RelayDestination.allCases.first(where: { $0.title.lowercased() == rawValue }) else { return }
        select(destination: destination)
        onSelect?(destination)
    }

    private func symbol(for destination: RelayDestination) -> String {
        switch destination {
        case .today: return "circle.grid.2x2"
        case .playbook: return "books.vertical"
        case .usage: return "chart.bar.xaxis"
        }
    }
}
