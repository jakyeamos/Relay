import Foundation
import RelayCore

func argumentValue(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

let configuration = RelayConfiguration.load()
let databaseURL = argumentValue("--database").map { URL(fileURLWithPath: $0) } ?? RelayDatabase.defaultURL()
let adapters: [any ProviderAdapter]
if let sessionsRoot = argumentValue("--sessions-root") {
    adapters = [CodexAdapter(sessionsRoot: URL(fileURLWithPath: sessionsRoot))]
} else {
    adapters = configuration.makeAdapters()
}

let store = try SQLiteStore(url: databaseURL)
let coordinator = MonitoringCoordinator(store: store, adapters: adapters)

if CommandLine.arguments.contains("--once") {
    let result = coordinator.runOnce()
    print("Relay helper imported \(result.importedSessions) session(s).")
} else {
    coordinator.start()
    RunLoop.main.run()
}
