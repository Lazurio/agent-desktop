// Probe for Lazurio/agent-desktop#2: which scroll bars does AX expose for
// scroll areas whose indicators are hidden or whose content fits on one axis?
import SwiftUI
import AppKit

struct Probe: View {
    var body: some View {
        HStack(spacing: 20) {
            ScrollView(.vertical) {
                VStack { ForEach(0..<60) { Text("v-hidden \($0)") } }
            }.scrollIndicators(.hidden).frame(width: 150, height: 300).accessibilityLabel("sw-vertical-hidden")
            ScrollView(.horizontal) {
                HStack { ForEach(0..<40) { Text("h-hidden \($0)") } }
            }.scrollIndicators(.hidden).frame(width: 150, height: 300).accessibilityLabel("sw-horizontal-hidden")
            ScrollView([.vertical, .horizontal]) {
                Text("small").padding()
            }.frame(width: 300, height: 300).accessibilityLabel("sw-both-fits")
            AppKitScroll().frame(width: 200, height: 300)
        }.padding()
    }
}

struct AppKitScroll: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 800))
        let b = NSButton(title: "far-right", target: nil, action: nil)
        b.frame = NSRect(x: 600, y: 20, width: 100, height: 24)
        doc.addSubview(b)
        sv.documentView = doc
        sv.setAccessibilityLabel("appkit-no-hscroller")
        return sv
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

@main
struct ProbeApp: App {
    var body: some Scene { WindowGroup { Probe() } }
}
