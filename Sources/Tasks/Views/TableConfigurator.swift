import SwiftUI
import AppKit

// TableConfigurator bridges into the AppKit `NSTableView` that backs a SwiftUI
// `List`, so callers can adjust properties SwiftUI doesn't expose itself. It's
// used here to set `allowsEmptySelection = false`, which stops a click in the
// empty area below the rows from clearing the list selection.
//
// SwiftUI offers no public hook to the backing table, so this drops an invisible
// probe `NSView` into the hierarchy (via `.background(...)`) and walks the view
// tree to find the nearest enclosing `NSTableView`, then hands it to `configure`.
struct TableConfigurator: NSViewRepresentable {

    // The change to apply to the backing table once it's found.
    let configure: (NSTableView) -> Void

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        applyConfiguration(from: probe)
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply on every update. SwiftUI tears the `List` (and its backing
        // table) down and rebuilds it when the data set changes — switching task
        // lists, tasks finishing their load, toggling the completed section — and
        // each rebuild resets the table to its defaults. Re-running keeps
        // `allowsEmptySelection = false` in force across those rebuilds.
        applyConfiguration(from: nsView)
    }

    // Defers the table lookup to the next runloop tick: during make/update the
    // probe isn't attached to its superview chain yet, so there's nothing to walk
    // up to. By the next tick the hierarchy is assembled.
    private func applyConfiguration(from probe: NSView) {
        DispatchQueue.main.async { [weak probe] in
            guard let probe, let tableView = probe.enclosingTableView() else { return }
            configure(tableView)
        }
    }
}

private extension NSView {

    // Finds the nearest `NSTableView` related to this view by climbing the
    // superview chain and searching each ancestor's subtree. Climbing finds the
    // closest table first, so a probe placed beside the task list won't reach the
    // sidebar's table (or any other List) elsewhere in the window.
    func enclosingTableView() -> NSTableView? {
        var ancestor: NSView? = self
        while let current = ancestor {
            if let table = current.firstTableViewInSubtree() {
                return table
            }
            ancestor = current.superview
        }
        return nil
    }

    // Depth-first search for the first `NSTableView` at or below this view. An
    // `NSTableView` lives inside an `NSScrollView`'s clip view, so the descent has
    // to go a few levels deep rather than just checking direct subviews.
    func firstTableViewInSubtree() -> NSTableView? {
        if let table = self as? NSTableView { return table }
        for subview in subviews {
            if let table = subview.firstTableViewInSubtree() { return table }
        }
        return nil
    }
}
