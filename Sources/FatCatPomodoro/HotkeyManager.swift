import Foundation
import Carbon
import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var hotKeyRefL: EventHotKeyRef?
    private var hotKeyRefS: EventHotKeyRef?
    
    var onToggleExpansion: (() -> Void)?
    var onToggleTimer: (() -> Void)?
    
    private init() {}
    
    func setup() {
        registerHotKeys()
    }
    
    private func registerHotKeys() {
        // Cmd + Shift + L (37 is L)
        let hotKeyIDL = EventHotKeyID(signature: OSType(1718512964), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | shiftKey), hotKeyIDL, GetApplicationEventTarget(), 0, &hotKeyRefL)
        
        // Cmd + Shift + S (1 is S)
        let hotKeyIDS = EventHotKeyID(signature: OSType(1718512964), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), hotKeyIDS, GetApplicationEventTarget(), 0, &hotKeyRefS)
        
        var eventUI = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if status == noErr {
                if hotKeyID.id == 1 {
                    HotkeyManager.shared.onToggleExpansion?()
                } else if hotKeyID.id == 2 {
                    HotkeyManager.shared.onToggleTimer?()
                }
            }
            
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventUI, nil, nil)
    }
}
