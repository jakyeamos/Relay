import AppKit
import RelayCore

let application = NSApplication.shared
let delegate = RelayAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
