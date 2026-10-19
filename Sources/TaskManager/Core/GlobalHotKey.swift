import Carbon

/// Registers Control-Shift-Escape (the Windows Task Manager shortcut) system-wide.
/// Carbon hot keys don't need Accessibility permission.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var action: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handlerInstalled = false

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard reference == nil else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { GlobalHotKey.shared.action?() }
                }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x544D_4752), id: 1)  // 'TMGR'
        RegisterEventHotKey(UInt32(kVK_Escape), UInt32(controlKey | shiftKey), id, GetApplicationEventTarget(), 0, &reference)
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }
}
