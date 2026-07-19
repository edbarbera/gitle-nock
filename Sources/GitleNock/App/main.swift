import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
// Accessory: lives in the notch, no Dock icon and no menu bar of its own.
app.setActivationPolicy(.accessory)
app.run()
