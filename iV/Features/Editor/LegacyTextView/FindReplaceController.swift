import AppKit
import SwiftUI

@MainActor
@Observable
final class FindReplaceController {
    var findText = ""
    var replaceText = ""
    var isVisible = false
    var matchCount = 0
    var currentMatch = 0

    weak var textView: NSTextView?

    func show(in textView: NSTextView) {
        self.textView = textView
        isVisible = true
        updateMatchCount()
    }

    func hide() {
        isVisible = false
        textView?.window?.makeFirstResponder(textView)
    }

    func findNext() {
        guard let textView, !findText.isEmpty else { return }
        let options: NSString.CompareOptions = [.caseInsensitive]
        let source = textView.string as NSString
        let start = textView.selectedRange().location + 1
        let searchRange = NSRange(location: min(start, source.length), length: source.length - min(start, source.length))
        var found = source.range(of: findText, options: options, range: searchRange)
        if found.location == NSNotFound {
            found = source.range(of: findText, options: options, range: NSRange(location: 0, length: source.length))
        }
        guard found.location != NSNotFound else { return }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        textView.showFindIndicator(for: found)
        updateMatchCount()
    }

    func findPrevious() {
        guard let textView, !findText.isEmpty else { return }
        let options: NSString.CompareOptions = [.caseInsensitive, .backwards]
        let source = textView.string as NSString
        let end = max(0, textView.selectedRange().location - 1)
        var found = source.range(of: findText, options: options, range: NSRange(location: 0, length: end))
        if found.location == NSNotFound {
            found = source.range(of: findText, options: options, range: NSRange(location: 0, length: source.length))
        }
        guard found.location != NSNotFound else { return }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        updateMatchCount()
    }

    func replace() {
        guard let textView, textView.shouldChangeText(in: textView.selectedRange(), replacementString: replaceText) else { return }
        textView.insertText(replaceText, replacementRange: textView.selectedRange())
        findNext()
    }

    func replaceAll() {
        guard let textView, !findText.isEmpty else { return }
        let source = textView.string
        let replaced = source.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
        guard replaced != source else { return }
        textView.string = replaced
        updateMatchCount()
    }

    func updateMatchCount() {
        guard let textView, !findText.isEmpty else { matchCount = 0; currentMatch = 0; return }
        let source = textView.string as NSString
        var count = 0
        var searchRange = NSRange(location: 0, length: source.length)
        while true {
            let found = source.range(of: findText, options: .caseInsensitive, range: searchRange)
            if found.location == NSNotFound { break }
            count += 1
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: source.length - next)
        }
        matchCount = count
        if count > 0, textView.selectedRange().location != NSNotFound {
            let before = source.substring(to: textView.selectedRange().location)
            currentMatch = (before as NSString).ranges(of: findText, options: .caseInsensitive).count
        } else {
            currentMatch = 0
        }
    }
}

private extension NSString {
    func ranges(of search: String, options: CompareOptions) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: length)
        while true {
            let found = range(of: search, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            ranges.append(found)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: length - next)
        }
        return ranges
    }
}

struct FindReplaceBar: View {
    @Bindable var controller: FindReplaceController

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $controller.findText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit { controller.findNext() }
            TextField("Replace", text: $controller.replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            Text("\(controller.matchCount) matches")
                .ivMutedCaption()
            Button(action: controller.findPrevious) { Image(systemName: "chevron.up") }
                .buttonStyle(.ivIcon)
            Button(action: controller.findNext) { Image(systemName: "chevron.down") }
                .buttonStyle(.ivIcon)
            Button("Replace") { controller.replace() }
                .buttonStyle(.ivGhost)
            Button("All") { controller.replaceAll() }
                .buttonStyle(.ivGhost)
            Button(action: controller.hide) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Close")
                        .font(.caption)
                }
            }
            .buttonStyle(.ivGhost)
            .help("Close find bar")
        }
        .padding(8)
        .ivForestElevatedBar()
        .foregroundStyle(IVColor.chromePrimary)
        .onChange(of: controller.findText) { controller.updateMatchCount() }
    }
}
