import SwiftUI
import AppKit

@MainActor
struct TextEditingHelper {
    /// Returns the active editable NSTextView in the given window (or key window), if any.
    /// This includes field editors for NSTextField (e.g. TreeInlineTextField, SwiftUI TextField)
    /// and NSTextView instances (e.g. SwiftUI TextEditor in task detail notes).
    static func activeEditableTextView(in window: NSWindow? = NSApp.keyWindow) -> NSTextView? {
        guard let win = window ?? NSApp.keyWindow else { return nil }
        guard let responder = win.firstResponder else { return nil }
        
        if let tv = responder as? NSTextView, tv.isEditable {
            return tv
        }
        if let tf = responder as? NSTextField, tf.isEditable {
            if let currentEditor = tf.currentEditor() as? NSTextView, currentEditor.isEditable {
                return currentEditor
            }
        }
        // Traverse superviews in case the first responder is an internal subview of a text component
        if let view = responder as? NSView {
            var curr: NSView? = view
            while let c = curr {
                if let tv = c as? NSTextView, tv.isEditable {
                    return tv
                }
                if let tf = c as? NSTextField, tf.isEditable {
                    if let currentEditor = tf.currentEditor() as? NSTextView, currentEditor.isEditable {
                        return currentEditor
                    }
                }
                curr = c.superview
            }
        }
        return nil
    }
    
    /// Returns true if the user is currently editing text in the given window or project store.
    static func isEditingText(store: ProjectStore?, in window: NSWindow? = NSApp.keyWindow) -> Bool {
        // 1. Task name inline editing in LeftTreeView is active
        if let store = store, store.editingTaskId != nil {
            return true
        }
        
        // 2. An active editable NSTextView exists (focused in TextField, TextEditor, etc.)
        if activeEditableTextView(in: window) != nil {
            return true
        }
        
        // 3. Fallback responder check
        if let responder = (window ?? NSApp.keyWindow)?.firstResponder {
            if responder is NSTextView || responder is NSTextField {
                return true
            }
        }
        
        return false
    }
    
    /// Handles Cmd + arrow key events specifically for text navigation and selection.
    /// Returns true if the event was handled and consumed, so caller can return nil.
    static func handleTextCursorMovement(event: NSEvent, in window: NSWindow? = NSApp.keyWindow) -> Bool {
        let isCmd = event.modifierFlags.contains(.command)
        let isShift = event.modifierFlags.contains(.shift)
        let isOpt = event.modifierFlags.contains(.option)
        let isCtrl = event.modifierFlags.contains(.control)
        
        guard isCmd && !isOpt && !isCtrl else { return false }
        
        let tv = activeEditableTextView(in: window)
        let responder = (window ?? NSApp.keyWindow)?.firstResponder
        
        switch event.keyCode {
        case 123: // Left Arrow -> Beginning of line
            if let tv = tv {
                if isShift {
                    tv.moveToBeginningOfLineAndModifySelection(nil)
                } else {
                    tv.moveToBeginningOfLine(nil)
                }
                return true
            } else if let responder = responder {
                let sel = isShift ? #selector(NSStandardKeyBindingResponding.moveToBeginningOfLineAndModifySelection(_:)) : #selector(NSStandardKeyBindingResponding.moveToBeginningOfLine(_:))
                return responder.tryToPerform(sel, with: nil)
            }
            
        case 124: // Right Arrow -> End of line
            if let tv = tv {
                if isShift {
                    tv.moveToEndOfLineAndModifySelection(nil)
                } else {
                    tv.moveToEndOfLine(nil)
                }
                return true
            } else if let responder = responder {
                let sel = isShift ? #selector(NSStandardKeyBindingResponding.moveToEndOfLineAndModifySelection(_:)) : #selector(NSStandardKeyBindingResponding.moveToEndOfLine(_:))
                return responder.tryToPerform(sel, with: nil)
            }
            
        case 126: // Up Arrow -> Beginning of document / text
            if let tv = tv {
                if isShift {
                    tv.moveToBeginningOfDocumentAndModifySelection(nil)
                } else {
                    tv.moveToBeginningOfDocument(nil)
                }
                return true
            } else if let responder = responder {
                let sel = isShift ? #selector(NSStandardKeyBindingResponding.moveToBeginningOfDocumentAndModifySelection(_:)) : #selector(NSStandardKeyBindingResponding.moveToBeginningOfDocument(_:))
                return responder.tryToPerform(sel, with: nil)
            }
            
        case 125: // Down Arrow -> End of document / text
            if let tv = tv {
                if isShift {
                    tv.moveToEndOfDocumentAndModifySelection(nil)
                } else {
                    tv.moveToEndOfDocument(nil)
                }
                return true
            } else if let responder = responder {
                let sel = isShift ? #selector(NSStandardKeyBindingResponding.moveToEndOfDocumentAndModifySelection(_:)) : #selector(NSStandardKeyBindingResponding.moveToEndOfDocument(_:))
                return responder.tryToPerform(sel, with: nil)
            }
            
        default:
            break
        }
        
        return false
    }
}
