import AppKit

@main
enum DeepSeekFocusMain {
    /// NSApplication.delegate is a weak reference. Keep the delegate alive for the whole
    /// process lifetime, otherwise the hotkey manager and window controllers can be released
    /// after launch even though the app is still running.
    @MainActor private static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
