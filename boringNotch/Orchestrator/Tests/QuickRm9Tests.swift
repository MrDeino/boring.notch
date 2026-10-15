import Foundation
import AppKit

private func bitmapImage(_ w: Int, _ h: Int) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let img = NSImage(size: NSSize(width: w, height: h))
    img.addRepresentation(rep)
    return img
}

func runQuickRm9Tests() {
    // wire text
    precondition(chatTextWithImages("look", paths: ["/a.png", "/b.png"]) == "look [image: /a.png] [image: /b.png]")
    precondition(chatTextWithImages("  ", paths: ["/a.png"]) == "[image: /a.png]")
    precondition(chatTextWithImages("hi", paths: []) == "hi")

    // image request
    let base = URL(string: "http://127.0.0.1:1")!
    let png = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3])
    let q = OrchestratorPost.image(png).request(base: base)!
    precondition(q.httpMethod == "POST" && q.url!.path == "/api/chat/image" && q.value(forHTTPHeaderField: "x-orch") == "1")
    precondition(q.value(forHTTPHeaderField: "Content-Type") == "image/png" && q.httpBody == png)
    precondition(OrchestratorPost.image(Data()).request(base: base) == nil)
    precondition(OrchestratorPost.image(Data(count: 10 * 1024 * 1024 + 1)).request(base: base) == nil)
    precondition(OrchestratorPost.image(Data(count: 10 * 1024 * 1024)).request(base: base) != nil)

    // path decode
    precondition(decodeImagePath(Data(#"{"path":"/x/1.png"}"#.utf8)) == "/x/1.png")
    for bad in ["{}", #"{"error":"e"}"#, "garbage", #"{"path":""}"#] { precondition(decodeImagePath(Data(bad.utf8)) == nil) }

    // PNG resize
    func dims(_ d: Data) -> (Int, Int) { let r = NSBitmapImageRep(data: d)!; return (r.pixelsWide, r.pixelsHigh) }
    let big = orchestratorPNG(from: bitmapImage(3000, 1500))!
    precondition(Array(big.prefix(4)) == [0x89, 0x50, 0x4e, 0x47] && dims(big) == (2000, 1000))
    precondition(dims(orchestratorPNG(from: bitmapImage(100, 50))!) == (100, 50))

    // reconcile claims the wire text
    var m = PendingMessage(id: 1, text: "look", state: .sent, sentAt: Date())
    m.images = [png]; m.paths = ["/a.png"]
    let blk = ChatBlock(pendingID: "u1", text: "look [image: /a.png]")
    let out = reconcilePending([m], blocks: [blk], known: [], now: Date())
    precondition(out.pending.isEmpty && out.known == ["u1"])
}

/// Round trip against /tmp/orch-image-mock.py on 47999 (never the live serve). Only runs with ORCH_IMAGE_MOCK set.
func runQuickRm9Mock() async {
    let b = URL(string: "http://127.0.0.1:47999")!
    let ses = URLSession(configuration: .ephemeral)
    let png = orchestratorPNG(from: bitmapImage(40, 20))!
    let path = await uploadOrchestratorImage(png, base: b, session: ses)
    precondition(path?.hasSuffix(".png") == true && path!.hasPrefix("/tmp/orch-image-mock/"))
    let dead = await uploadOrchestratorImage(png, base: URL(string: "http://127.0.0.1:47998")!, session: ses)
    precondition(dead == nil)
    var bare = URLRequest(url: b.appendingPathComponent("api/chat/image"))
    bare.httpMethod = "POST"; bare.httpBody = png
    bare.setValue("image/png", forHTTPHeaderField: "Content-Type")
    var (_, resp) = try! await ses.data(for: bare)
    precondition((resp as! HTTPURLResponse).statusCode == 400)
    bare.setValue("1", forHTTPHeaderField: "x-orch")
    bare.setValue("text/plain", forHTTPHeaderField: "Content-Type")
    (_, resp) = try! await ses.data(for: bare)
    precondition((resp as! HTTPURLResponse).statusCode == 415)
}
