import AppKit
import Testing
@testable import CompareUI

@Suite(.serialized)
struct EditorInteractionTests {
    @Test @MainActor func enteringSettingsEndsExistingCompositionWithoutChangingVisibleText() throws {
        let editor = SourceTextView(frame: .zero)
        editor.string = "var env={x:1};"
        editor.setMarkedText("候选", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: 4, length: 3))
        try #require(editor.hasMarkedText())
        let visibleText = editor.string
        let selection = editor.selectedRange()
        editor.setInteraction(enabled: false, editable: true)
        #expect(!editor.hasMarkedText())
        #expect(editor.string == visibleText)
        editor.setInteraction(enabled: true, editable: true)
        #expect(editor.string == visibleText && editor.selectedRange() == selection)
        editor.insertText("config", replacementRange: NSRange(location: 4, length: 2))
        #expect(editor.string == "var config={x:1};")
    }

    @Test @MainActor func selectionRestoreClampsWhenOutputShrinksWhileSettingsIsOpen() {
        let editor = SourceTextView(frame: .zero)
        editor.string = "long formatted output"
        editor.setSelectedRange(NSRange(location: 10, length: 7))
        editor.setInteraction(enabled: false, editable: false)
        editor.string = "短"
        editor.setInteraction(enabled: true, editable: false)
        #expect(editor.selectedRange() == NSRange(location: 1, length: 0))
        #expect(editor.isSelectable && !editor.isEditable)
    }

    // Exercise actual NSTextInputClient insertion rather than checking only SwiftUI modifiers.
    @Test @MainActor func hiddenEditorRejectsInputAndFocusThenRestoresSelection() {
        let editor = SourceTextView(frame: .zero)
        editor.string = "var env={name:'中文',x:1};"
        editor.setSelectedRange(NSRange(location: 4, length: 3))
        let original = editor.string
        let selection = editor.selectedRange()
        editor.setInteraction(enabled: false, editable: true)
        #expect(!editor.acceptsFirstResponder)
        #expect(!editor.isEditable && !editor.isSelectable)
        editor.insertText("must-not-be-inserted", replacementRange: selection)
        editor.setMarkedText("候选", selectedRange: NSRange(location: 0, length: 2), replacementRange: selection)
        #expect(!editor.hasMarkedText())
        #expect(editor.string == original)
        editor.setInteraction(enabled: true, editable: true)
        #expect(editor.acceptsFirstResponder && editor.isEditable && editor.isSelectable)
        #expect(editor.selectedRange() == selection)
        editor.insertText("config", replacementRange: selection)
        #expect(editor.string == "var config={name:'中文',x:1};")
    }

    // Formatting output must remain selectable, while native text input cannot mutate it.
    @Test @MainActor func visibleReadOnlyOutputAllowsSelectionButRejectsInsertion() {
        let editor = SourceTextView(frame: .zero)
        editor.string = "name: '中文'\n"
        editor.setInteraction(enabled: true, editable: false)
        #expect(editor.acceptsFirstResponder && editor.isSelectable && !editor.isEditable)
        editor.setSelectedRange(NSRange(location: 0, length: 4))
        editor.insertText("changed", replacementRange: editor.selectedRange())
        #expect(editor.string == "name: '中文'\n")
        editor.setInteraction(enabled: false, editable: false)
        #expect(!editor.acceptsFirstResponder)
        editor.setInteraction(enabled: true, editable: false)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 4))
    }
}
