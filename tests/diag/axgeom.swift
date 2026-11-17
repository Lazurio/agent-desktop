// Diagnostic: dump AX geometry of a labelled element, its ancestors and the
// owning window, plus the CGWindow bounds. Usage:
//   swift axgeom.swift dump <pid> <label>
//   swift axgeom.swift move <pid> <x> <y>
import Cocoa
import ApplicationServices

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    let e = AXUIElementCopyAttributeValue(el, name as CFString, &v)
    return e == .success ? v : nil
}
func str(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }
func point(_ el: AXUIElement) -> CGPoint? {
    guard let v = attr(el, "AXPosition") else { return nil }
    var p = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &p); return p
}
func size(_ el: AXUIElement) -> CGSize? {
    guard let v = attr(el, "AXSize") else { return nil }
    var s = CGSize.zero; AXValueGetValue(v as! AXValue, .cgSize, &s); return s
}
func frameAttr(_ el: AXUIElement) -> CGRect? {
    guard let v = attr(el, "AXFrame") else { return nil }
    var r = CGRect.zero; AXValueGetValue(v as! AXValue, .cgRect, &r); return r
}
func describe(_ el: AXUIElement) -> [String: Any] {
    var d: [String: Any] = [:]
    d["role"] = str(el, "AXRole") ?? ""
    d["subrole"] = str(el, "AXSubrole") ?? ""
    d["desc"] = str(el, "AXDescription") ?? ""
    d["title"] = str(el, "AXTitle") ?? ""
    d["id"] = str(el, "AXIdentifier") ?? ""
    if let p = point(el) { d["pos"] = [p.x, p.y] }
    if let s = size(el) { d["size"] = [s.width, s.height] }
    if let f = frameAttr(el) { d["AXFrame"] = [f.origin.x, f.origin.y, f.size.width, f.size.height] }
    var names: CFArray?
    if AXUIElementCopyAttributeNames(el, &names) == .success, let n = names as? [String] {
        d["attrs"] = n.filter { $0.contains("Scroll") || $0.contains("Visible") || $0.contains("Frame") || $0 == "AXContents" }
    }
    if let vs = attr(el, "AXVerticalScrollBar") { d["vbar"] = describeShort(vs as! AXUIElement) }
    if let hs = attr(el, "AXHorizontalScrollBar") { d["hbar"] = describeShort(hs as! AXUIElement) }
    return d
}
func describeShort(_ el: AXUIElement) -> [String: Any] {
    var d: [String: Any] = ["role": str(el, "AXRole") ?? ""]
    if let p = point(el) { d["pos"] = [p.x, p.y] }
    if let s = size(el) { d["size"] = [s.width, s.height] }
    if let v = attr(el, "AXValue") { d["value"] = "\(v)" }
    return d
}
func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, "AXChildren") as? [AXUIElement]) ?? [] }
func find(_ root: AXUIElement, _ label: String, _ depth: Int = 0) -> AXUIElement? {
    if depth > 60 { return nil }
    if str(root, "AXDescription") == label || str(root, "AXTitle") == label || str(root, "AXIdentifier") == label { return root }
    for c in children(root) { if let f = find(c, label, depth + 1) { return f } }
    return nil
}
func out(_ o: Any) {
    let data = try! JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

let args = CommandLine.arguments
let pid = pid_t(Int32(args[2])!)
let app = AXUIElementCreateApplication(pid)
let windows = (attr(app, "AXWindows") as? [AXUIElement]) ?? []
guard let win = windows.first else { print("{\"error\":\"no window\"}"); exit(1) }

if args[1] == "resize" {
    var sz = CGSize(width: Double(args[3])!, height: Double(args[4])!)
    let v = AXValueCreate(.cgSize, &sz)!
    let e = AXUIElementSetAttributeValue(win, "AXSize" as CFString, v)
    print("{\"resize\": \(e.rawValue)}")
    exit(0)
}
if args[1] == "tree" {
    func walk(_ el: AXUIElement, _ d: Int) -> [String: Any] {
        var r = describeShort(el)
        r["desc"] = str(el, "AXDescription") ?? ""
        if d < Int(args[3])! { r["children"] = children(el).prefix(12).map { walk($0, d + 1) } }
        return r
    }
    out(walk(win, 0))
    exit(0)
}
if args[1] == "scrollareas" {
    func walk(_ el: AXUIElement, _ d: Int) {
        if d > 12 { return }
        if str(el, "AXRole") == "AXScrollArea" {
            var r = describe(el)
            r["children"] = children(el).prefix(3).map { describeShort($0) }
            out(r)
        }
        for c in children(el) { walk(c, d + 1) }
    }
    walk(win, 0)
    print("{\"scrollbar_pref\": \"\(NSScroller.preferredScrollerStyle == .overlay ? "overlay" : "legacy")\"}")
    exit(0)
}
if args[1] == "move" {
    var p = CGPoint(x: Double(args[3])!, y: Double(args[4])!)
    let v = AXValueCreate(.cgPoint, &p)!
    let e = AXUIElementSetAttributeValue(win, "AXPosition" as CFString, v)
    print("{\"move\": \(e.rawValue)}")
    exit(0)
}

var result: [String: Any] = [:]
result["window"] = describe(win)
result["screens"] = NSScreen.screens.map { ["frame": [$0.frame.origin.x, $0.frame.origin.y, $0.frame.width, $0.frame.height], "scale": $0.backingScaleFactor] }
let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
result["cgwindows"] = info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }.map {
    ["id": $0[kCGWindowNumber as String] ?? 0, "layer": $0[kCGWindowLayer as String] ?? 0, "bounds": $0[kCGWindowBounds as String] ?? [:], "onscreen": $0[kCGWindowIsOnscreen as String] ?? false]
}
if let target = find(win, args[3]) {
    var chain: [[String: Any]] = []
    var cur: AXUIElement? = target
    var n = 0
    while let c = cur, n < 40 {
        chain.append(describe(c))
        if str(c, "AXRole") == "AXApplication" { break }
        cur = attr(c, "AXParent") as! AXUIElement?
        n += 1
    }
    result["chain"] = chain
    if let w = attr(target, "AXWindow") { result["target_AXWindow"] = describe(w as! AXUIElement) }
    if let w = attr(target, "AXTopLevelUIElement") { result["target_AXTopLevel"] = describeShort(w as! AXUIElement) }
} else {
    result["chain"] = "not found"
}
out(result)
