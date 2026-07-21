import AppKit
import RelayCore

final class RelayUsageViewController: NSViewController {
    private let store: SQLiteStore
    private let usageService = UsageService()
    private let stack = NSStackView()

    init(store: SQLiteStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    private func refresh() {
        let sessions = (try? store.sessions()) ?? []
        let metrics = usageService.localMetrics(sessions: sessions)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for pair in stride(from: 0, to: metrics.count, by: 2) {
            let first = RelayMetricCard(metric: metrics[pair])
            let second = pair + 1 < metrics.count
                ? RelayMetricCard(metric: metrics[pair + 1])
                : NSView()
            let row = NSStackView(views: [first, second])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            row.distribution = .fillEqually
            stack.addArrangedSubview(row)
        }
    }
}
