import SwiftUI
import AppKit

// Configuration source is exact text. Swift String equality treats canonically
// equivalent Unicode as equal, which can suppress native updates and onChange.
struct SourceTextSnapshot: Equatable {
    let value: String
    static func == (left: Self, right: Self) -> Bool {
        let first = left.value as NSString, second = right.value as NSString
        return first.length == second.length && first.compare(right.value, options: .literal) == .orderedSame
    }
}

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    private let sourceSnapshot: SourceTextSnapshot
    @Environment(\.isEnabled) private var isEnabled
    var editable: Bool
    var syntax: SourceSyntax.Language = .javascript
    init(text: Binding<String>, editable: Bool, syntax: SourceSyntax.Language = .javascript) {
        self._text = text; self.editable = editable; self.syntax = syntax
        self.sourceSnapshot = SourceTextSnapshot(value: text.wrappedValue)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 120)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = AppPalette.codeNS
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        let editor = SourceTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        editor.isRichText = false
        editor.setInteraction(enabled: isEnabled, editable: editable)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.enabledTextCheckingTypes = 0
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.backgroundColor = AppPalette.codeNS
        editor.textColor = AppPalette.inkNS
        editor.insertionPointColor = NSColor(srgbRed: 109/255, green: 40/255, blue: 66/255, alpha: 1)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(srgbRed: 253/255, green: 232/255, blue: 239/255, alpha: 1), .foregroundColor: AppPalette.inkNS]
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.syntax = syntax
        editor.string = sourceSnapshot.value
        scroll.documentView = editor
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.verticalRulerView = LineNumberRuler(textView: editor)
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observation = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak editor] _ in
            Task { @MainActor in editor?.enclosingScrollView?.verticalRulerView?.needsDisplay = true }
        }
        editor.refreshSyntax()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? SourceTextView else { return }
        if editor.syntax != syntax { editor.syntax = syntax; editor.refreshSyntax() }
        if SourceTextSnapshot(value: editor.string) != sourceSnapshot { editor.replaceSource(sourceSnapshot.value) }
        editor.setInteraction(enabled: isEnabled, editable: editable)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        nonisolated(unsafe) var observation: NSObjectProtocol?
        deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
        init(_ parent: SourceEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard parent.isEnabled && parent.editable else { return }
            if let editor = notification.object as? SourceTextView { parent.text = editor.string; editor.refreshSyntax() }
        }
    }
}

// Native text input remains mounted while Settings covers the workspace.
@MainActor final class SourceTextView: NSTextView, @preconcurrency NSTextStorageDelegate {
    var syntax: SourceSyntax.Language = .javascript { didSet { if syntax != oldValue { syntaxDirty = true } } }
    // Keep AppKit's own text-system construction and ownership. Attach to it
    // before the first source replacement, refresh or native insertion.
    private func observeEdits() {
        guard let storage = textStorage, storage.delegate !== self else { return }
        storage.delegate = self
        textStorage(storage, didProcessEditing: .editedCharacters, range: NSRange(location: 0, length: storage.length), changeInLength: storage.length - indexedLength)
    }
    override var string: String {
        get { super.string }
        set { observeEdits(); super.string = newValue }
    }
    private let sourceUndoManager = UndoManager()
    override var undoManager: UndoManager? { sourceUndoManager }
    // Imported/swapped sources start a new document history. Never clear the
    // other editor's history, or apply old undo ranges to a replacement file.
    func replaceSource(_ source: String) {
        if hasMarkedText() { unmarkText() }
        breakUndoCoalescing()
        sourceUndoManager.removeAllActions()
        string = source
        refreshSyntax()
    }
    private var interactionEnabled = true
    private(set) var lineStarts: [Int] = [0]
    private var indexedLength = 0
    private var syntaxDirty = true
    private var decoratedLength = 0
    // NSTextStorage's processed range is in the resulting UTF-16 string.
    // Revisit the edited span and two adjacent units to account for CR/LF joins.
    // Attribute-only edits never affect this index or the source's undo history.
    func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
        guard mask.contains(.editedCharacters) else { return }
        let source = storage.string as NSString
        let start = max(0, range.location - 2)
        var end = min(storage.length, NSMaxRange(range) + 2)
        if end > 0 && end < storage.length && source.character(at: end - 1) == 13 && source.character(at: end) == 10 { end += 1 }
        let oldEnd = min(indexedLength, end - delta)
        func upperBound(_ offset: Int) -> Int {
            var low = 0, high = lineStarts.count
            while low < high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let lower = upperBound(start), upper = upperBound(oldEnd)
        var replacement: [Int] = []
        var index = start
        while index < end {
            let unit = source.character(at: index)
            if unit == 13 {
                if index + 1 < storage.length && source.character(at: index + 1) == 10 { index += 1 }
                replacement.append(index + 1)
            } else if unit == 10 { replacement.append(index + 1) }
            index += 1
        }
        lineStarts.replaceSubrange(lower..<upper, with: replacement)
        let tail = lower + replacement.count
        if delta != 0 && tail < lineStarts.count {
            for position in tail..<lineStarts.count { lineStarts[position] += delta }
        }
        indexedLength = storage.length
        // Deferred refreshes (for example composition) can leave a shifted
        // colored tail past the cap. Later edits must track that pending tail,
        // including the replacement span, until it has actually been cleared.
        if range.location <= max(decoratedLength, SourceSyntax.limit) {
            syntaxDirty = true
            decoratedLength = min(storage.length, max(decoratedLength + delta, NSMaxRange(range), SourceSyntax.limit))
        }
    }
    func lineNumber(at character: Int) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= character { low = mid + 1 } else { high = mid }
        }
        return max(1, low)
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { enclosingScrollView?.layer?.borderWidth = 1; enclosingScrollView?.layer?.borderColor = NSColor(srgbRed: 0.88, green: 0.60, blue: 0.70, alpha: 1).cgColor }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { enclosingScrollView?.layer?.borderWidth = 0 }
        return accepted
    }
    func refreshSyntax() {
        observeEdits()
        (enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.updateWidth()
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        guard syntaxDirty, !hasMarkedText(), let manager = layoutManager else { return }
        let length = textStorage?.length ?? 0
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: min(length, decoratedLength)))
        for token in SourceSyntax.tokens(in: string, language: syntax) {
            manager.addTemporaryAttribute(.foregroundColor, value: token.color, forCharacterRange: token.range)
        }
        decoratedLength = min(length, SourceSyntax.limit)
        syntaxDirty = false
    }
    private var savedSelection: [NSValue]?
    override var acceptsFirstResponder: Bool { interactionEnabled && super.acceptsFirstResponder }

    func setInteraction(enabled: Bool, editable: Bool) {
        if interactionEnabled && !enabled {
            savedSelection = selectedRanges
            // End composition without rewriting the already displayed source text.
            if hasMarkedText() { unmarkText() }
        }
        let wasDisabled = !interactionEnabled
        interactionEnabled = enabled
        isEditable = enabled && editable
        isSelectable = enabled
        if !enabled, window?.firstResponder === self { window?.makeFirstResponder(nil) }
        if enabled && wasDisabled, let ranges = savedSelection {
            let length = (string as NSString).length
            selectedRanges = ranges.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
            savedSelection = nil
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard interactionEnabled && isEditable else { return }
        observeEdits()
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard interactionEnabled && isEditable else { return }
        observeEdits()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
}

// Highlighting is decorative and never feeds the parser or changes source text.
// Bound work on very large files: later code remains clearly readable in neutral ink.
@MainActor enum SourceSyntax {
    enum Language { case javascript, json, yaml }
    struct Token { let range: NSRange; let color: NSColor; let kind: String }
    static let limit = 200_000
    static func tokens(in text: String, language: Language = .javascript) -> [Token] {
        // One forward pass also handles unfinished comments/strings; a backtracking
        // regex could freeze the main thread on repeated unclosed comment openers.
        let units = Array(text.utf16.prefix(limit))
        var index = 0, lineStart = 0, flowDepth = 0, yamlBlockParent: Int?
        var tokens: [Token] = []
        func whitespace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 13 }
        func scalarStart(_ position: Int) -> Bool {
            var previous = position - 1
            while previous >= lineStart && whitespace(units[previous]) { previous -= 1 }
            guard previous >= lineStart else { return true }
            switch units[previous] {
            case 58: return previous < position - 1 || flowDepth > 0
            case 91, 123, 44: return flowDepth > 0
            case 45, 63: return previous < position - 1
            default: return false
            }
        }
        func identifier(_ unit: UInt16) -> Bool {
            (65...90).contains(unit) || (97...122).contains(unit) || (48...57).contains(unit) || unit == 95 || unit == 36 || unit >= 128
        }
        func emit(_ start: Int, _ kind: String) {
            let color: NSColor
            switch kind {
            case "comment": color = NSColor(srgbRed: 0.40, green: 0.47, blue: 0.52, alpha: 1)
            case "string": color = NSColor(srgbRed: 0.20, green: 0.43, blue: 0.33, alpha: 1)
            case "number": color = NSColor(srgbRed: 0.58, green: 0.34, blue: 0.14, alpha: 1)
            default: color = NSColor(srgbRed: 0.48, green: 0.29, blue: 0.51, alpha: 1)
            }
            tokens.append(Token(range: NSRange(location: start, length: index - start), color: color, kind: kind))
        }
        let keywords: Set<String> = ["var", "let", "const", "export", "default", "module", "function", "return", "true", "false", "null", "undefined"]
        while index < units.count {
            if language == .yaml, index == lineStart {
                var content = index
                while content < units.count && (units[content] == 32 || units[content] == 9) { content += 1 }
                if let parent = yamlBlockParent {
                    if content == units.count || units[content] == 10 || units[content] == 13 || content - lineStart > parent {
                        let start = index
                        while index < units.count && units[index] != 10 && units[index] != 13 { index += 1 }
                        if index > start { emit(start, "string") }
                        if index < units.count { index += 1; lineStart = index }
                        continue
                    }
                    yamlBlockParent = nil
                }
            }
            let start = index, unit = units[index]
            let next = index + 1 < units.count ? units[index + 1] : 0
            if (language == .yaml && unit == 35 && (index == 0 || whitespace(units[index - 1]))) ||
                (language == .javascript && ((unit == 47 && next == 47) || (index == 0 && unit == 35 && next == 33))) {
                index += language == .yaml ? 1 : 2
                while index < units.count && units[index] != 10 && units[index] != 13 { index += 1 }
                emit(start, "comment")
            } else if language == .javascript && unit == 47 && next == 42 {
                index += 2
                while index < units.count {
                    if units[index] == 42 && index + 1 < units.count && units[index + 1] == 47 { index += 2; break }
                    index += 1
                }
                emit(start, "comment")
            } else if (language == .javascript && (unit == 34 || unit == 39 || unit == 96)) ||
                (language == .json && unit == 34) ||
                (language == .yaml && (unit == 34 || unit == 39) && scalarStart(index)) {
                index += 1
                while index < units.count {
                    let current = units[index]
                    if language != .yaml && unit != 96 && (current == 10 || current == 13) { break }
                    index += 1
                    if current == 10 || current == 13 { lineStart = index }
                    if current == 92 && index < units.count && !(language == .yaml && unit == 39) {
                        if units[index] == 13 && index + 1 < units.count && units[index + 1] == 10 {
                            index += 2; lineStart = index
                        } else {
                            if units[index] == 10 || units[index] == 13 { lineStart = index + 1 }
                            index += 1
                        }
                    } else if current == unit {
                        if language == .yaml && unit == 39 && index < units.count && units[index] == 39 { index += 1 }
                        else { break }
                    }
                }
                emit(start, "string")
            } else if (48...57).contains(unit) && (language != .yaml || scalarStart(index)) {
                index += 1
                while index < units.count && (48...57).contains(units[index]) { index += 1 }
                if index < units.count && units[index] == 46 {
                    index += 1
                    while index < units.count && (48...57).contains(units[index]) { index += 1 }
                }
                if index < units.count && (units[index] == 101 || units[index] == 69) {
                    index += 1
                    if index < units.count && (units[index] == 43 || units[index] == 45) { index += 1 }
                    while index < units.count && (48...57).contains(units[index]) { index += 1 }
                }
                if index < units.count && units[index] == 110 { index += 1 }
                emit(start, "number")
            } else if identifier(unit) {
                index += 1
                while index < units.count && identifier(units[index]) { index += 1 }
                let word = String(decoding: units[start..<index], as: UTF16.self)
                if language == .javascript ? keywords.contains(word) : (["true", "false", "null"].contains(word) && (language != .yaml || scalarStart(start))) { emit(start, "keyword") }
            } else {
                if language == .yaml {
                    if (unit == 124 || unit == 62) && scalarStart(index) {
                        var indentation = lineStart
                        while indentation < index && units[indentation] == 32 { indentation += 1 }
                        yamlBlockParent = indentation - lineStart
                    }
                    if unit == 91 || unit == 123 { flowDepth += 1 }
                    else if unit == 93 || unit == 125 { flowDepth = max(0, flowDepth - 1) }
                }
                index += 1
                if unit == 10 || unit == 13 { lineStart = index }
            }
        }
        return tokens
    }
}

@MainActor final class LineNumberRuler: NSRulerView {
    weak var editor: SourceTextView?
    private var digitCount = 0
    private let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor(srgbRed: 0.46, green: 0.49, blue: 0.57, alpha: 1)]
    init(textView: SourceTextView) {
        editor = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        // Ruler invalidation can span the scroll view; keep its background in its own column.
        clipsToBounds = true
        clientView = textView
        ruleThickness = 38
        updateWidth()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    func updateWidth() {
        guard let editor else { return }
        let label = String(editor.lineStarts.count) as NSString
        guard label.length != digitCount else { return }
        digitCount = label.length
        // Resizing during draw can cause a layout loop. Update only after a
        // source edit/import changes the digit count, including shrinking files.
        ruleThickness = max(38, ceil(label.size(withAttributes: attributes).width) + 16)
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        AppPalette.codeNS.setFill(); rect.fill()
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let visible = editor.visibleRect
        let range = layout.glyphRange(forBoundingRect: visible, in: container)
        let sourceLength = editor.textStorage?.length ?? 0

        layout.enumerateLineFragments(forGlyphRange: range) { [self] lineRect, _, _, glyphs, _ in
            let character = layout.characterIndexForGlyph(at: glyphs.location)
            if editor.lineStarts.binarySearchContains(character) {
                let label = String(editor.lineNumber(at: character)) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: lineRect.minY + editor.textContainerInset.height - visible.minY + 1), withAttributes: attributes)
            }

        }
        // enumerateLineFragments excludes the empty insertion line after a
        // trailing CR/LF/CRLF. Inspect its geometry only once the visible glyph
        // range reaches EOF; never force full-document layout for this label.
        if sourceLength > 0 && editor.lineStarts.last == sourceLength {
            let characters = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            if NSMaxRange(characters) >= sourceLength && layout.extraLineFragmentTextContainer === container {
                let extra = layout.extraLineFragmentRect
                let y = extra.minY + editor.textContainerOrigin.y - visible.minY + 1
                if extra.height > 0 && y + extra.height >= 0 && y < bounds.height {
                    let label = String(editor.lineStarts.count) as NSString
                    let size = label.size(withAttributes: attributes)
                    label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y), withAttributes: attributes)
                }
            }
        }
        if sourceLength == 0 {
            let label = "1" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: editor.textContainerOrigin.y - visible.minY + 1), withAttributes: attributes)
        }
    }
}

private extension Array where Element == Int {
    func binarySearchContains(_ value: Int) -> Bool {
        var low = 0, high = count
        while low < high { let mid = (low + high) / 2; if self[mid] < value { low = mid + 1 } else { high = mid } }
        return low < count && self[low] == value
    }
}
