// Pixels: two desktop pets. The cat nags you to drink water, the ghost nags you to take a walk.
// The pets are the GIFs in assets/, played exactly as given.
// Build: ./build.sh   Run: open Pixels.app   Demo (reminders in a few seconds): open Pixels.app --args --demo
import AppKit
import CoreAudio
import CoreMediaIO
import Carbon.HIToolbox
import ImageIO
import SwiftUI

let demo = CommandLine.arguments.contains("--demo")

// MARK: - Sprites

/// A GIF's frames, cropped to the area any frame ever uses so the animation keeps its own motion.
struct Sprite {
    let frames: [CGImage]
    let delay: Double
    let scale: CGFloat      // display points per source pixel
    let crisp: Bool         // nearest-neighbour when the scale lands art pixels on whole points

    var size: CGSize { CGSize(width: CGFloat(frames[0].width) * scale, height: CGFloat(frames[0].height) * scale) }
    /// Height of the creature itself in the first frame, measured up from the bottom of its box (points).
    var restBodyHeight: CGFloat {
        guard let b = Sprite.alphaBounds(frames[0]) else { return size.height }
        return (CGFloat(frames[0].height) - b.minY) * scale
    }

    init?(url: URL, scale: CGFloat, crisp: Bool) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        var raw: [CGImage] = []
        var delay = 0.1
        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            raw.append(img)
            if i == 0, let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
               let g = p[kCGImagePropertyGIFDictionary] as? [CFString: Any],
               let d = (g[kCGImagePropertyGIFUnclampedDelayTime] ?? g[kCGImagePropertyGIFDelayTime]) as? Double, d > 0 {
                delay = d
            }
        }
        guard let first = raw.first else { return nil }
        let union = raw.compactMap(Sprite.alphaBounds).reduce(CGRect.null) { $0.union($1) }
        let crop = union.isNull ? CGRect(x: 0, y: 0, width: first.width, height: first.height) : union
        frames = raw.compactMap { $0.cropping(to: crop) }
        self.delay = delay
        self.scale = scale
        self.crisp = crisp
    }

    /// Load any GIF/PNG so the creature's body (first frame) is about `targetHeight` points tall. Removes a
    /// solid background; for upscaled pixel art the scale snaps to quarter steps of the art grid so pixels stay sharp.
    init?(url: URL, targetHeight: CGFloat) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
              let first = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let opaqueBackground = Sprite.rgba(first).map { $0.buf[3] == 255 } ?? false
        let k = Sprite.pixelGrid(first)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        guard Sprite.writeFrames(src, to: tmp, keyBackground: opaqueBackground),
              let probe = Sprite(url: tmp, scale: 1, crisp: true) else { return nil }
        let h = Sprite.alphaBounds(probe.frames[0])?.height ?? CGFloat(probe.frames[0].height)
        let scale: CGFloat
        if k >= 2 {
            let artHeight = h / CGFloat(k)
            scale = max(1, (targetHeight / artHeight * 4).rounded() / 4) / CGFloat(k)
        } else {
            scale = targetHeight / h
        }
        self.init(url: tmp, scale: scale, crisp: k >= 2)
        try? FileManager.default.removeItem(at: tmp)
    }

    static func rgba(_ img: CGImage) -> (buf: [UInt8], w: Int, h: Int)? {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (buf, w, h)
    }

    /// Size of the pixel-art grid (how many image pixels per art pixel), or 1 if it isn't clean pixel art.
    static func pixelGrid(_ img: CGImage) -> Int {
        guard let (buf, w, h) = rgba(img) else { return 1 }
        var changes: [Int] = []
        for y in stride(from: 0, to: h, by: max(1, h / 60)) {
            for x in 1..<w where buf[(y * w + x) * 4..<(y * w + x) * 4 + 4] != buf[(y * w + x - 1) * 4..<(y * w + x - 1) * 4 + 4] {
                changes.append(x)
            }
        }
        guard changes.count >= 40 else { return 1 }
        for k in stride(from: 12, through: 2, by: -1) {
            let onGrid = changes.filter { $0 % k == 0 }.count
            if Double(onGrid) >= Double(changes.count) * 0.97 { return k }
        }
        return 1
    }

    /// Re-encode every frame (optionally with the edge-connected background made transparent) as a GIF.
    static func writeFrames(_ src: CGImageSource, to url: URL, keyBackground: Bool) -> Bool {
        let n = CGImageSourceGetCount(src)
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, n, nil) else { return false }
        for i in 0..<n {
            guard var img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            if keyBackground, let keyed = removeBackground(img) { img = keyed }
            CGImageDestinationAddImage(dst, img, CGImageSourceCopyPropertiesAtIndex(src, i, nil))
        }
        return CGImageDestinationFinalize(dst)
    }

    /// Flood-fill from the edges, clearing pixels close to the corner colour (keeps inner whites like teeth/eyes).
    static func removeBackground(_ img: CGImage) -> CGImage? {
        guard var (buf, w, h) = rgba(img) else { return nil }
        let bg = Array(buf[0..<4])
        func near(_ i: Int) -> Bool {
            (0..<3).allSatisfy { abs(Int(buf[i + $0]) - Int(bg[$0])) <= 24 } && buf[i + 3] > 0
        }
        var stack: [Int] = []
        for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
        for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
        while let p = stack.popLast() {
            let i = p * 4
            guard near(i) else { continue }
            buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
            let x = p % w, y = p / w
            if x > 0 { stack.append(p - 1) }
            if x < w - 1 { stack.append(p + 1) }
            if y > 0 { stack.append(p - w) }
            if y < h - 1 { stack.append(p + w) }
        }
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return ctx.makeImage()
    }

    /// Bounding box of non-transparent pixels, in image coordinates (origin top-left).
    static func alphaBounds(_ img: CGImage) -> CGRect? {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where buf[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

// MARK: - Reminders

final class Reminder: ObservableObject {
    let key: String
    private let d = UserDefaults.standard
    @Published var intervalMin: Int { didSet { d.set(intervalMin, forKey: key + ".interval"); restart() } }
    @Published var count: Int { didSet { d.set(count, forKey: key + ".count") } }
    @Published var nagging = false
    var due = Date()
    /// Escalation: stage 1 when due, 2 after one step ignored, 3 (full-screen) after two.
    static let step: TimeInterval = demo ? 8 : 300

    init(key: String, defaultInterval: Int) {
        self.key = key
        intervalMin = d.object(forKey: key + ".interval") as? Int ?? defaultInterval
        count = d.integer(forKey: key + ".count")
        restart()
        if demo { due = Date().addingTimeInterval(key == "water" ? 4 : 9) }
    }

    var minutesLeft: Int { max(1, Int(ceil(due.timeIntervalSinceNow / 60))) }
    func restart() { due = Date().addingTimeInterval(TimeInterval(intervalMin * 60)); nagging = false }
    func done() { count += 1; restart() }
    func snooze(_ min: Int) { due = Date().addingTimeInterval(TimeInterval(min * 60)); nagging = false }

    func stage(at now: Date) -> Int {
        guard now >= due else { return 0 }
        let t = now.timeIntervalSince(due)
        return t < Self.step ? 1 : t < 2 * Self.step ? 2 : 3
    }
}

// MARK: - Pet view

final class Pet: ObservableObject {
    let sprite: Sprite
    @Published private(set) var tick = 0      // advances once per GIF frame, forever, like the GIF itself
    @Published var nagging = false
    @Published var facingLeft = false
    @Published var grow: CGFloat = 1     // >1 while an ignored reminder makes it big
    @Published var shake = false
    @Published var bubble: String? = nil
    private var bubbleHide: Date? = nil
    private var timer: Timer?

    /// Little moves layered on top of the GIF so every pet feels alive.
    enum Action {
        case none, hop, lookAround, stretch, nap, loop, celebrate
        case vanish, sneak, melt, sing, transform     // signature moves (see Personality)
        var duration: Double {
            switch self {
            case .none: return 0
            case .hop: return 1.2
            case .lookAround: return 1.8
            case .stretch: return 1.6
            case .nap: return 8
            case .loop: return 1.6
            case .celebrate: return 1.8
            case .vanish: return 1.2
            case .sneak: return 8
            case .melt: return 3
            case .sing: return 3
            case .transform: return 4
            }
        }
    }
    @Published private(set) var action: Action = .none
    @Published private(set) var actionT: Double = 0     // seconds into the current action
    var rewardEmoji = "💧"
    var personality = Personality.generic
    var disguises: [Sprite] = []                // what "transform" can turn into
    @Published private(set) var disguise: Sprite?
    private var actionStart = Date()
    private var actionTimer: Timer?

    func finish() {
        actionTimer?.invalidate()
        action = .none
        actionT = 0
        disguise = nil
    }

    func perform(_ a: Action) {
        action = a
        actionT = 0
        disguise = a == .transform ? disguises.randomElement() : nil
        actionStart = Date()
        actionTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] tm in
            guard let self else { tm.invalidate(); return }
            self.actionT = Date().timeIntervalSince(self.actionStart)
            if self.actionT >= a.duration { self.finish() }
        }
        RunLoop.main.add(t, forMode: .common)
        actionTimer = t
    }

    var actionX: CGFloat { action == .loop ? CGFloat(sin(actionT * 2 * .pi / 1.6)) * 24 : 0 }
    var actionY: CGFloat {
        switch action {
        case .hop: return -CGFloat(abs(sin(actionT * .pi / 0.6))) * 14
        case .celebrate: return -CGFloat(abs(sin(actionT * .pi / 0.45))) * 22
        case .loop: return -CGFloat(1 - cos(actionT * 2 * .pi / 1.6)) * 18
        default: return 0
        }
    }
    /// 0…1 how melted Vaporeon is.
    private var melt: CGFloat {
        guard action == .melt else { return 0 }
        let t = actionT
        return CGFloat(t < 0.8 ? t / 0.8 : t < 2.2 ? 1 : max(0, 1 - (t - 2.2) / 0.8))
    }
    var alpha: Double {
        switch action {
        case .vanish: return actionT < 0.6 ? 1 - actionT / 0.6 : min(1, (actionT - 0.6) / 0.6)
        case .melt: return 1 - 0.15 * Double(melt)
        default: return 1
        }
    }
    var rotation: Double { action == .sing ? sin(actionT * 3) * 6 : 0 }
    var tinted: Bool { disguise != nil }
    /// Little symbols floating up during some moves.
    var particles: [String] {
        switch action {
        case .celebrate: return [rewardEmoji]
        case .sing: return ["♪", "🎵"]
        case .transform: return actionT < 0.6 || actionT > 3.4 ? ["✨"] : []
        case .melt: return actionT > 0.6 && actionT < 2.4 ? ["🫧"] : []
        default: return []
        }
    }
    var particleT: Double {
        switch action {
        case .sing: return actionT.truncatingRemainder(dividingBy: 1.5)
        case .transform: return actionT < 0.6 ? actionT : actionT - 3.4
        case .melt: return (actionT - 0.6).truncatingRemainder(dividingBy: 1.8)
        default: return actionT
        }
    }
    var particleSpan: Double { action == .sing ? 1.5 : action == .transform ? 0.6 : 1.8 }
    var scaleX: CGFloat {
        if action == .melt { return 1 + 0.5 * melt }
        switch action {
        case .stretch: return 1 - 0.08 * CGFloat(sin(actionT * .pi / 0.8))
        case .celebrate: return 1 + 0.08 * CGFloat(abs(sin(actionT * .pi / 0.45)))
        default: return 1
        }
    }
    var scaleY: CGFloat {
        if action == .melt { return 1 - 0.75 * melt }
        switch action {
        case .stretch: return 1 + 0.12 * CGFloat(sin(actionT * .pi / 0.8))
        case .nap: return 1 + 0.04 * CGFloat(sin(actionT * 2.2))
        case .celebrate: return 1 + 0.08 * CGFloat(abs(sin(actionT * .pi / 0.45)))
        default: return 1
        }
    }
    /// Facing after "look around" flips it back and forth.
    var flipped: Bool { facingLeft != (action == .lookAround && Int(actionT / 0.45) % 2 == 1) }

    init(sprite: Sprite) {
        self.sprite = sprite
        let t = Timer(timeInterval: sprite.delay, repeats: true) { [weak self] _ in self?.tick &+= 1 }
        RunLoop.main.add(t, forMode: .common)   // keep playing while a menu is open or the pet is dragged
        timer = t
    }

    var frame: CGImage {
        if let d = disguise { return d.frames[tick % d.frames.count] }
        return sprite.frames[tick % sprite.frames.count]
    }
    var crispNow: Bool { disguise?.crisp ?? sprite.crisp }
    /// Size on screen: a disguise keeps the look-alike's own size.
    var shownSize: CGSize { disguise?.size ?? sprite.size }
    /// Hop in place while the reminder is due.
    var hop: CGFloat { nagging ? -CGFloat(abs(sin(Double(tick) * 0.9))) * 12 * min(grow, 2) : 0 }
    var jitter: CGFloat { shake ? CGFloat(sin(Double(tick) * 2.6)) * 6 : 0 }

    func say(_ s: String?, for secs: Double? = nil) {
        bubble = s
        bubbleHide = secs.map { Date().addingTimeInterval($0) }
    }

    func clearExpiredBubble(_ now: Date) {
        if let t = bubbleHide, now >= t { bubble = nil; bubbleHide = nil }
    }
}

/// Each pet's voice and favourite moves.
struct Personality {
    var lines: [String]      // idle emotes
    var curious: [String]    // when the pointer first touches it
    var moves: [Pet.Action]  // idle move pool (repeats = more likely)
    var cheer: [String]      // group jump

    static let generic = Personality(lines: ["♪", "!", "?", "~"], curious: ["!"],
                                     moves: [.hop, .lookAround, .stretch], cheer: ["!"])
    static let cat = Personality(lines: ["…", "mrrp", "hmph", "feed me", "mrow?"], curious: ["mrrp?", "…"],
                                 moves: [.hop, .lookAround, .stretch, .stretch, .nap], cheer: ["MRAOW!", "mrrp!"])
    static let gengar = Personality(lines: ["hehe", "boo!", "👻", ">:)", "gotcha"], curious: ["hehe", "boo!"],
                                    moves: [.vanish, .vanish, .sneak, .loop, .lookAround], cheer: ["hehehe!", "BOO!"])
    static let vaporeon = Personality(lines: ["~", "blub", "🫧", "splash", "🌊"], curious: ["blub?", "~"],
                                      moves: [.melt, .melt, .hop, .lookAround, .stretch, .nap], cheer: ["splash!", "blub!"])
    static let lapras = Personality(lines: ["♪", "la~", "🎵", "la la~"], curious: ["♪?", "la?"],
                                    moves: [.sing, .sing, .lookAround, .stretch, .nap], cheer: ["♪!", "la la!"])
    static let mew = Personality(lines: ["mew!", "✨", "?", "♥", "mew mew"], curious: ["mew?", "✨"],
                                 moves: [.transform, .transform, .loop, .hop, .lookAround], cheer: ["mew!!", "✨"])

    static func named(_ name: String) -> Personality {
        let n = name.lowercased()
        if n.contains("vaporeon") { return vaporeon }
        if n.contains("lapras") { return lapras }
        if n.contains("mew") { return mew }
        if n.contains("gengar") { return gengar }
        if n.contains("cat") { return cat }
        return generic
    }
}

struct PetView: View {
    @ObservedObject var pet: Pet
    var onTap: () -> Void
    static let ink = Color(red: 0.12, green: 0.07, blue: 0.22)

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            if let text = pet.bubble {
                Text(text)
                    .font(.system(size: pet.grow > 1 ? 18 : 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.ink)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(
                        ZStack {
                            Rectangle().fill(Self.ink).offset(x: 3, y: 3)
                            Rectangle().fill(Color(red: 1, green: 0.973, blue: 0.906))
                            Rectangle().stroke(Self.ink, lineWidth: 3)
                        })
                    .fixedSize()
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            ZStack {
                Image(decorative: pet.frame, scale: 1).resizable().interpolation(pet.crispNow ? .none : .high)
                if pet.tinted {   // Mew in disguise: same shape, washed pink
                    Image(decorative: pet.frame, scale: 1).resizable().interpolation(pet.crispNow ? .none : .high)
                        .renderingMode(.template)
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.8).opacity(0.55))
                }
            }
                .frame(width: pet.shownSize.width * pet.grow, height: pet.shownSize.height * pet.grow)
                .scaleEffect(x: (pet.flipped ? -1 : 1) * pet.scaleX, y: pet.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(pet.rotation), anchor: .bottom)
                .opacity(pet.alpha)
                .offset(x: pet.jitter + pet.actionX, y: pet.hop + pet.actionY)
                .overlay(alignment: .top) {
                    let sym = pet.particles
                    if !sym.isEmpty {   // reward drops/stars, Lapras's notes, Mew's sparkles, Vaporeon's bubbles
                        ZStack {
                            ForEach(0..<5, id: \.self) { i in
                                Text(sym[i % sym.count])
                                    .font(.system(size: 16))
                                    .offset(x: CGFloat(i - 2) * 18, y: -CGFloat(pet.particleT) * 55 - CGFloat(i % 2) * 12)
                                    .opacity(max(0, 1 - pet.particleT / pet.particleSpan))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .frame(width: PetPanel.width(for: pet.sprite, grow: pet.grow), height: PetPanel.height(for: pet.sprite, grow: pet.grow),
               alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pet.bubble)
    }
}

// MARK: - Windows

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    static func width(for s: Sprite, grow: CGFloat = 1) -> CGFloat { max(s.size.width * grow + 16, grow > 1 ? 360 : 240).rounded() }
    static func height(for s: Sprite, grow: CGFloat = 1) -> CGFloat {   // room for bubble + hop
        (s.size.height * grow + (grow > 1 ? 90 : 56)).rounded()
    }

    convenience init(sprite: Sprite) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: PetPanel.width(for: sprite), height: PetPanel.height(for: sprite)),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
    }
}

/// Hosting view that drags the window and shows the shared menu on right-click.
final class PetHost<V: View>: NSHostingView<V> {
    var menuProvider: (() -> NSMenu)?
    var onInteract: (() -> Void)?
    override func mouseDown(with e: NSEvent) { onInteract?(); super.mouseDown(with: e) }
    override func mouseDragged(with e: NSEvent) { onInteract?(); window?.performDrag(with: e) }
    override func rightMouseDown(with e: NSEvent) {
        if let m = menuProvider?() { NSMenu.popUpContextMenu(m, with: e, for: self) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Wandering

/// Moves a pet's window around: the cat walks along the bottom of the screen, the ghost floats anywhere.
/// When its reminder is due it comes over to the mouse pointer.
final class Wanderer {
    let panel: PetPanel
    let pet: Pet
    let grounded: Bool
    let speed: CGFloat
    let flips: Bool
    let stationary: Bool          // plays its GIF in place; only moves when dragged
    let saveKey: String?          // remember where a stationary pet was put
    var holdUntil = Date.distantPast    // after a drag, stay where the user put it for a bit
    private var wasOver = false
    private var lastCurious = Date.distantPast
    private var teleported = false
    /// All pets, so each can keep its distance from the others.
    static var all: [Wanderer] = []
    static let gap: CGFloat = 40
    private var pos: CGPoint
    private var target: CGPoint?
    private var restUntil = Date().addingTimeInterval(.random(in: 1...4))

    let id: String
    let label: String
    /// How far to sink when hidden: about 45% of the body, so the head and eyes stay visible.
    private lazy var peekDepth: CGFloat = (pet.sprite.restBodyHeight * 0.45).rounded()
    /// Right-click choices, remembered per pet.
    var still: Bool { didSet { UserDefaults.standard.set(still, forKey: "still." + id) } }
    var peeking: Bool { didSet { UserDefaults.standard.set(peeking, forKey: "peek." + id) } }

    init(panel: PetPanel, pet: Pet, id: String, label: String, grounded: Bool, speed: CGFloat, flips: Bool,
         stationary: Bool = false, saveKey: String? = nil) {
        self.panel = panel; self.pet = pet; self.grounded = grounded; self.speed = speed; self.flips = flips
        self.stationary = stationary; self.saveKey = saveKey
        self.id = id; self.label = label
        still = UserDefaults.standard.bool(forKey: "still." + id)
        peeking = UserDefaults.standard.bool(forKey: "peek." + id)
        if let k = saveKey, let a = UserDefaults.standard.array(forKey: k) as? [Double], a.count == 2 {
            let o = NSPoint(x: a[0], y: a[1])
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -50, dy: -50).contains(o) }) {
                panel.setFrameOrigin(o)
            }
        }
        pos = panel.frame.origin
    }

    /// Where the sprite itself is drawn: bottom-centre of the window.
    var spriteRect: CGRect {
        let f = panel.frame, w = pet.sprite.size.width * pet.grow, h = pet.sprite.size.height * pet.grow
        return CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: h)
    }

    /// Call after resizing the window so wandering continues from its new origin.
    func sync() { pos = panel.frame.origin }

    /// Sprite rect if the window's origin were `o`.
    private func rect(at o: CGPoint) -> CGRect {
        let w = pet.sprite.size.width * pet.grow, h = pet.sprite.size.height * pet.grow
        return CGRect(x: o.x + panel.frame.width / 2 - w / 2, y: o.y, width: w, height: h)
    }

    /// Too close to another pet (where it is, and optionally where it's heading)?
    private func crowded(_ r: CGRect, countTargets: Bool) -> Bool {
        let padded = r.insetBy(dx: -Self.gap, dy: -Self.gap / 2)
        return Self.all.contains { o in
            guard o !== self, o.panel.isVisible else { return false }
            if o.spriteRect.intersects(padded) { return true }
            if countTargets, let t = o.target, o.rect(at: t).intersects(padded) { return true }
            return false
        }
    }

    /// A random free spot on the screen, or nil if none turned up.
    private func freeSpot(in vf: NSRect, maxX: CGFloat, maxY: CGFloat, floating: Bool) -> CGPoint? {
        for _ in 0..<16 {
            let c = CGPoint(x: .random(in: vf.minX...maxX), y: floating ? .random(in: vf.minY...maxY) : vf.minY)
            if !crowded(rect(at: c), countTargets: true) { return c }
        }
        return nil
    }

    /// Group trick: run away from a point.
    func scatter(from p: CGPoint) {
        guard !stationary else { return }
        let c = spriteRect
        let dirX: CGFloat = c.midX < p.x ? -1 : 1
        var t = CGPoint(x: pos.x + dirX * .random(in: 160...320), y: pos.y)
        if !grounded { t.y += (c.midY < p.y ? -1 : 1) * .random(in: 60...160) }
        target = t
        restUntil = Date()
        holdUntil = .distantPast
    }

    func step(dt: CGFloat, wander: Bool, chase: Bool) {
        let mouse = NSEvent.mouseLocation
        let over = spriteRect.contains(mouse)
        // Clicks pass through everything except the pet itself.
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        let now = Date()
        // Curious: a little hop and "!" when the pointer first touches it.
        if over, !wasOver, pet.action == .none, !pet.nagging, now.timeIntervalSince(lastCurious) > 8 {
            lastCurious = now
            pet.perform(.hop)
            pet.say(pet.personality.curious.randomElement()!, for: 1.2)
        }
        wasOver = over
        if pet.action != .vanish { teleported = false }
        if pet.action == .vanish, !teleported, pet.actionT >= 0.6, !still, !peeking {
            // Gengar: gone… and back somewhere else.
            teleported = true
            let size = panel.frame.size
            if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame,
               let spot = freeSpot(in: vf, maxX: max(vf.minX, vf.maxX - size.width), maxY: max(vf.minY, vf.maxY - size.height),
                                   floating: !grounded) {
                pos = spot
                target = nil
                panel.setFrameOrigin(NSPoint(x: pos.x.rounded(), y: pos.y.rounded()))
            }
            return
        }
        if pet.action != .none, pet.action != .sneak, !chase { pos = panel.frame.origin; return }   // stand still to do its move
        if peeking, !chase, now >= holdUntil {
            // Hidden: sunk below the bottom edge so only the head shows; pops up while hovered.
            let vf = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let goalY = over ? vf.minY : vf.minY - peekDepth
            let dy = goalY - pos.y
            pos.y += abs(dy) < 1 ? dy : (dy > 0 ? 1 : -1) * min(abs(dy), 260 * dt)
            let maxX = max(vf.minX, vf.maxX - panel.frame.width)
            // Keep the gap while hidden too: slide along the edge to a free spot. The spot is kept in
            // `target` so the other pets can see it's taken.
            if target == nil, crowded(rect(at: CGPoint(x: pos.x, y: vf.minY)), countTargets: true) {
                target = freeSpot(in: vf, maxX: maxX, maxY: vf.minY, floating: false)
            }
            if let t = target {
                let dx = t.x - pos.x
                pos.x += abs(dx) < 1 ? dx : (dx > 0 ? 1 : -1) * min(abs(dx), 160 * dt)
                if abs(t.x - pos.x) < 1 { target = nil }
            }
            pos.x = min(max(pos.x, vf.minX), maxX)
            panel.setFrameOrigin(NSPoint(x: pos.x.rounded(), y: pos.y.rounded()))
            return
        }
        // Stand still while hovered (so it's easy to click) and for a moment after being dragged.
        if over || now < holdUntil || !(wander || chase || stationary || still) { pos = panel.frame.origin; target = nil; return }

        let size = panel.frame.size
        let screen = chase ? (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? panel.screen)
                           : (panel.screen ?? NSScreen.main)
        guard let vf = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let maxX = max(vf.minX, vf.maxX - size.width), maxY = max(vf.minY, vf.maxY - size.height)

        if stationary || still, !chase {
            // Stay put; if dropped mid-air, fall to the floor, then remember the spot.
            if grounded, pos.y > vf.minY { pos.y = max(vf.minY, pos.y - 600 * dt) }
            pos.x = min(max(pos.x, vf.minX), maxX)
            pos.y = min(max(pos.y, vf.minY), maxY)
            let o = NSPoint(x: pos.x.rounded(), y: pos.y.rounded())
            if o != panel.frame.origin {
                panel.setFrameOrigin(o)
            } else if let k = saveKey, (UserDefaults.standard.array(forKey: k) as? [Double]) != [Double(o.x), Double(o.y)] {
                UserDefaults.standard.set([Double(o.x), Double(o.y)], forKey: k)
            }
            return
        }
        if chase {
            // Come to the pointer: the cat to the floor under it, the ghost just beside it.
            let x = grounded ? mouse.x - size.width / 2 : mouse.x - size.width / 2 - 120
            let y = grounded ? vf.minY : mouse.y - pet.sprite.size.height / 2 - 40
            target = CGPoint(x: min(max(x, vf.minX), maxX), y: min(max(y, vf.minY), maxY))
        } else if pet.action == .sneak {
            // Gengar creeps up just behind the pointer.
            target = CGPoint(x: min(max(mouse.x - size.width / 2 + 70, vf.minX), maxX),
                             y: min(max(mouse.y - pet.sprite.size.height / 2, vf.minY), maxY))
        } else if target == nil, now >= restUntil {
            target = freeSpot(in: vf, maxX: maxX, maxY: maxY, floating: !grounded)
            if target == nil { restUntil = now.addingTimeInterval(2) }
        }

        if grounded, pos.y > vf.minY { pos.y = max(vf.minY, pos.y - 600 * dt) }   // dropped mid-air: fall to the floor
        if let t = target {
            let dx = t.x - pos.x, dy = grounded ? 0 : t.y - pos.y
            let dist = hypot(dx, dy)
            if pet.action == .sneak, dist < 8 {
                pet.finish()
                pet.say("boo!", for: 1.6)
                target = nil
                restUntil = now.addingTimeInterval(3)
            } else if dist < 2 {
                if !chase { target = nil; restUntil = now.addingTimeInterval(.random(in: 2...8)) }
            } else {
                let len = min(dist, speed * (chase ? 3 : pet.action == .sneak ? 2.2 : 1) * dt)
                let next = CGPoint(x: pos.x + dx / dist * len, y: pos.y + dy / dist * len)
                // Keep a gap: stop rather than walk into another pet (unless already stuck in one, or on a mission).
                if !chase, pet.action != .sneak, crowded(rect(at: next), countTargets: false),
                   !crowded(rect(at: pos), countTargets: false) {
                    target = nil
                    restUntil = now.addingTimeInterval(.random(in: 1...3))
                } else {
                    pos = next
                    if flips, abs(dx) > 1, pet.facingLeft != (dx < 0) { pet.facingLeft = dx < 0 }
                }
            }
        }
        pos.x = min(max(pos.x, vf.minX), maxX)
        pos.y = min(max(pos.y, vf.minY), maxY)
        let bob = grounded ? 0 : sin(now.timeIntervalSinceReferenceDate * 1.8) * 4
        panel.setFrameOrigin(NSPoint(x: pos.x.rounded(), y: (pos.y + bob).rounded()))
    }
}

// MARK: - Don't interrupt

/// The full-screen step is skipped while you're on a call or something is fullscreen.
enum Busy {
    static func now() -> Bool { cameraInUse() || micInUse() || fullscreenWindowInFront() }

    static func micInUse() -> Bool {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return false }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return false }
        for id in ids {
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var n: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &n) == noErr, n > 0 else { continue }   // inputs only
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var on: UInt32 = 0
            var onSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &running, 0, nil, &onSize, &on) == noErr, on != 0 { return true }
        }
        return false
    }

    static func cameraInUse() -> Bool {
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var on: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &on) == 0, on != 0 { return true }
        }
        return false
    }

    /// The frontmost normal window exactly fills a screen (fullscreen video, slides, a fullscreen app).
    static func fullscreenWindowInFront() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let size = CGSize(width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return NSScreen.screens.contains { $0.frame.size == size }
        }
        return false
    }
}

// MARK: - Full-screen takeover

struct PixelButtonStyle: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .heavy, design: .monospaced))
            .foregroundStyle(PetView.ink)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(
                ZStack {
                    Rectangle().fill(PetView.ink).offset(x: 4, y: 4)
                    Rectangle().fill(primary ? Color(red: 1, green: 0.894, blue: 0.098) : Color(red: 1, green: 0.973, blue: 0.906))
                    Rectangle().stroke(PetView.ink, lineWidth: 3)
                })
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
    }
}

struct TakeoverView: View {
    @ObservedObject var pet: Pet
    let title: String
    let subtitle: String
    let spriteHeight: CGFloat
    let onDone: () -> Void
    let onLater: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
            VStack(spacing: 22) {
                Image(decorative: pet.frame, scale: 1)
                    .resizable()
                    .interpolation(pet.sprite.crisp ? .none : .high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: spriteHeight)
                Text(title)
                    .font(.system(size: 48, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 18) {
                    Button("Done ✓", action: onDone).buttonStyle(PixelButtonStyle(primary: true))
                    Button("5 more min", action: onLater).buttonStyle(PixelButtonStyle(primary: false))
                }
                .padding(.top, 8)
            }
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { shown = true } }
    }
}

final class TakeoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }   // keyboard can't dismiss it; only the buttons can
}

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let water = Reminder(key: "water", defaultInterval: 45)
    let walk = Reminder(key: "walk", defaultInterval: 60)
    static let goal = 8
    static let pokemonSize: CGFloat = 100   // body height every Pokémon is matched to
    static let bigPet: CGFloat = 120        // "-big" in a friend's filename
    var cat: Pet!
    var ghost: Pet!
    var catPanel: PetPanel!
    var ghostPanel: PetPanel!
    var wanderers: [(w: Wanderer, chase: () -> Bool)] = []
    var friends: [Pet] = []
    static let friendsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pixels/friends")
    private var lastStep = Date()
    var wanderOn: Bool {
        get { UserDefaults.standard.object(forKey: "wander") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "wander") }
    }
    var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sound") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // The cat GIF is 7x-upscaled pixel art: 4/7 puts every art pixel on exactly 4 points.
        // Pokémon are matched to each other: every body ~100 pt tall (the cat keeps its own size).
        guard let catURL = Bundle.main.url(forResource: "water-cat", withExtension: "gif"),
              let ghostURL = Bundle.main.url(forResource: "walk-ghost", withExtension: "gif"),
              let catSprite = Sprite(url: catURL, scale: 4.0 / 7.0, crisp: true),
              let ghostSprite = Sprite(url: ghostURL, targetHeight: Self.pokemonSize) else {
            let a = NSAlert(); a.messageText = "Pixels can't find its pet GIFs in the app bundle."; a.runModal()
            NSApp.terminate(nil); return
        }
        cat = Pet(sprite: catSprite)
        ghost = Pet(sprite: ghostSprite)
        cat.personality = .cat
        ghost.personality = .gengar

        let vf = NSScreen.main?.visibleFrame ?? .zero
        catPanel = makePanel(pet: cat) { [unowned self] in self.tapCat() }
        place(catPanel, at: NSPoint(x: vf.maxX - catPanel.frame.width - 20, y: vf.minY))
        ghostPanel = makePanel(pet: ghost) { [unowned self] in self.tapGhost() }
        place(ghostPanel, at: NSPoint(x: catPanel.frame.minX - ghostPanel.frame.width + 40, y: vf.minY + 120))

        wanderers = [(Wanderer(panel: catPanel, pet: cat, id: "cat", label: "Cat", grounded: true, speed: 45, flips: true,
                               saveKey: "pos.cat"), { [unowned self] in self.water.nagging }),
                     (Wanderer(panel: ghostPanel, pet: ghost, id: "gengar", label: "Gengar", grounded: false, speed: 30, flips: false,
                               saveKey: "pos.gengar"), { [unowned self] in self.walk.nagging })]
        loadFriends(screen: vf)
        Wanderer.all = wanderers.map(\.w)
        let everyone = [cat!, ghost!] + friends
        for f in everyone where f.personality.moves.contains(.transform) {
            f.disguises = everyone.filter { $0 !== f }.map(\.sprite)
        }
        registerJumpHotKey()
        for (w, _) in wanderers {
            let host = w.panel.contentView as? PetHost<PetView>
            host?.onInteract = { [weak w] in w?.holdUntil = Date().addingTimeInterval(6) }
            host?.menuProvider = { [unowned self, weak w] in self.makeMenu(for: w) }
        }
        let mover = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.stepPets() }
        RunLoop.main.add(mover, forMode: .common)

        cat.say("Hi! Water every \(water.intervalMin)m", for: 5)
        ghost.say("Walks every \(walk.intervalMin)m", for: 5)

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        // Only count time you're actually at the screen: pause while the display sleeps, the Mac
        // sleeps or the screen is locked, and start both timers fresh when you're back.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.away = true }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.back() }
        }
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.away = true }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.back() }
        if ProcessInfo.processInfo.environment["WB_DEBUG"] != nil {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                FileHandle.standardError.write(Data("cat tick \(self.cat.tick) ghost tick \(self.ghost.tick) catVisible \(self.catPanel.isVisible) ghostVisible \(self.ghostPanel.isVisible) ghostFrame \(self.ghostPanel.frame) catFrame \(self.catPanel.frame) friends \(self.wanderers.dropFirst(2).map { w in "\(Int(w.w.panel.frame.minX)),\(Int(w.w.panel.frame.minY))" }) overlaps \(self.overlapCount())\n".utf8))
            }
        }
    }

    private func makePanel(pet: Pet, onTap: @escaping () -> Void) -> PetPanel {
        let p = PetPanel(sprite: pet.sprite)
        let host = PetHost(rootView: PetView(pet: pet, onTap: onTap))
        host.menuProvider = { [unowned self] in self.makeMenu(for: nil) }
        p.contentView = host
        return p
    }

    /// They wander, so there's no saved spot to restore: start on the main screen and show.
    private func place(_ p: PetPanel, at origin: NSPoint) {
        let vf = NSScreen.main?.visibleFrame ?? .zero
        p.setFrameOrigin(NSPoint(x: max(vf.minX, min(origin.x, vf.maxX - p.frame.width)), y: origin.y))
        p.orderFrontRegardless()
    }

    private func stepPets() {
        let now = Date()
        let dt = CGFloat(min(0.1, now.timeIntervalSince(lastStep)))
        lastStep = now
        guard !away else { return }
        for (w, chase) in wanderers { w.step(dt: dt, wander: wanderOn, chase: chase()) }
        if mouseShaken(now) { everyoneJump(scatterFrom: NSEvent.mouseLocation) }
    }

    /// Debug: how many pairs of pets are touching.
    private func overlapCount() -> Int {
        let r = wanderers.map(\.w.spriteRect)
        var n = 0
        for i in r.indices { for j in r.indices where j > i && r[i].intersects(r[j]) { n += 1 } }
        return n
    }

    // MARK: group tricks

    private var mouseXs: [(t: Date, x: CGFloat)] = []
    private var lastShake = Date.distantPast

    /// Shake = the pointer turns back and forth 4+ times within 0.7 s, each swing over 40 pt.
    private func mouseShaken(_ now: Date) -> Bool {
        mouseXs.append((now, NSEvent.mouseLocation.x))
        mouseXs.removeAll { now.timeIntervalSince($0.t) > 0.7 }
        guard now.timeIntervalSince(lastShake) > 3, let first = mouseXs.first else { return false }
        var turns = 0, dir: CGFloat = 0, anchor = first.x
        for p in mouseXs where abs(p.x - anchor) > 40 {
            let d: CGFloat = p.x > anchor ? 1 : -1
            if d != dir { if dir != 0 { turns += 1 }; dir = d }
            anchor = p.x
        }
        guard turns >= 4 else { return false }
        lastShake = now
        mouseXs.removeAll()
        return true
    }

    /// Everyone jumps (⌃⌥J); with a point, they also scatter away from it (mouse shake).
    func everyoneJump(scatterFrom point: CGPoint? = nil) {
        for (w, _) in wanderers {
            DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 0...0.25)) {
                w.pet.perform(.hop)
                if !w.pet.nagging, Bool.random() { w.pet.say(w.pet.personality.cheer.randomElement()!, for: 1.5) }
                if let point { w.scatter(from: point) }
            }
        }
    }

    private var hotKey: EventHotKeyRef?

    /// ⌃⌥J anywhere: everyone jumps. A registered hot key needs no Accessibility/Input Monitoring permission.
    private func registerJumpHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.everyoneJump() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x5058_4C53), id: 1)   // 'PXLS'
        RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    /// Every GIF/PNG in ~/Pixels/friends becomes a companion. "-fly" in the name makes it float around;
    /// "-walk" makes it walk the floor (only looks right for GIFs that are a walk cycle); otherwise it stays put.
    /// "-big" makes it a size up from the other Pokémon.
    private func loadFriends(screen vf: NSRect) {
        try? FileManager.default.createDirectory(at: Self.friendsDir, withIntermediateDirectories: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: Self.friendsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["gif", "png", "webp", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for (i, url) in files.enumerated() {
            let name = url.deletingPathExtension().lastPathComponent
            let flies = name.lowercased().contains("-fly")
            let walks = name.lowercased().contains("-walk")
            let big = name.lowercased().contains("-big")
            guard let sprite = Sprite(url: url, targetHeight: big ? Self.bigPet : Self.pokemonSize) else {
                FileHandle.standardError.write(Data("Pixels: couldn't load \(url.lastPathComponent)\n".utf8)); continue
            }
            let pet = Pet(sprite: sprite)
            pet.personality = Personality.named(name)
            let shown = name.replacingOccurrences(of: "-fly", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-walk", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-big", with: "", options: .caseInsensitive).capitalized
            let panel = makePanel(pet: pet) { [weak pet] in
                guard let pet else { return }
                pet.say((pet.personality.lines + ["\(shown)!"]).randomElement()!, for: 2.5)
            }
            let x = vf.minX + CGFloat(i + 1) * vf.width / CGFloat(files.count + 2)
            place(panel, at: NSPoint(x: x, y: flies ? vf.midY : vf.minY))
            friends.append(pet)
            wanderers.append((Wanderer(panel: panel, pet: pet, id: name, label: shown, grounded: !flies, speed: flies ? 35 : 40, flips: true,
                                       stationary: !flies && !walks, saveKey: "friend.pos." + name), { false }))
        }
    }

    // MARK: behaviour

    private var away = false

    private func back() {
        guard away else { return }
        away = false
        water.restart(); walk.restart()
    }

    private func tick() {
        guard !away else { return }
        let now = Date()
        rollDay()
        cat.clearExpiredBubble(now); ghost.clearExpiredBubble(now)
        friends.forEach { $0.clearExpiredBubble(now) }

        refresh(now)
        scheduleActions(now)
    }

    // MARK: idle actions

    private var nextAction: [ObjectIdentifier: Date] = [:]

    /// Every 15–40 s each idle pet does something: a hop, a look around, a stretch, a loop, an emote, rarely a nap.
    private func scheduleActions(_ now: Date) {
        for (w, chase) in wanderers where !chase() && !w.pet.nagging && w.pet.action == .none {
            let id = ObjectIdentifier(w.pet)
            guard let due = nextAction[id] else { nextAction[id] = now.addingTimeInterval(.random(in: 5...20)); continue }
            guard now >= due else { continue }
            nextAction[id] = now.addingTimeInterval(.random(in: 15...40))
            let p = w.pet.personality
            // Loops only for fliers; vanishing/sneaking only for pets that are allowed to move.
            let fixed = w.stationary || w.still || w.peeking
            let moves = p.moves.filter { m in
                m != .nap && !(w.grounded && m == .loop) && !(fixed && (m == .vanish || m == .sneak)) && !(w.peeking && m == .loop)
            }
            switch Int.random(in: 0..<10) {
            case 0 where p.moves.contains(.nap):
                w.pet.perform(.nap)
                w.pet.say("z z Z", for: Pet.Action.nap.duration)
            case 0, 1, 2:
                w.pet.say(p.lines.randomElement()!, for: 2)
            default:
                guard let m = moves.randomElement() else { continue }
                w.pet.perform(m)
                if m == .melt { w.pet.say("blub", for: 1.2) }
                if m == .sing { w.pet.say("la la~", for: 2.5) }
            }
        }
    }

    // MARK: escalation

    private var shownStage: [String: Int] = [:]
    private var takeover: (key: String, panel: TakeoverPanel)?

    /// Bring each pet's look in line with how long its reminder has been ignored.
    private func refresh(_ now: Date) {
        for r in [water, walk] {
            var st = r.stage(at: now)
            if st == 3, Busy.now() { st = 2 }    // on a call / fullscreen: stay at "big and shaking"
            r.nagging = st > 0
            let old = shownStage[r.key, default: 0]
            if st != old { shownStage[r.key] = st; enter(st, from: old, r) }
        }
        if cat.nagging != water.nagging { cat.nagging = water.nagging }
        if ghost.nagging != walk.nagging { ghost.nagging = walk.nagging }
        updateTakeover()
    }

    private func enter(_ st: Int, from old: Int, _ r: Reminder) {
        let isWater = r === water
        let pet: Pet = isWater ? cat : ghost
        let grow: CGFloat = st >= 2 ? (isWater ? 3 : 2) : 1
        pet.shake = st >= 2
        if pet.grow != grow { pet.grow = grow; resize(wanderers[isWater ? 0 : 1].w) }
        guard st > old else { return }        // calming down: no new nag
        switch st {
        case 1:
            pet.say(isWater ? ["Sip time!", "Water break?", "Drink up, human", "Glug glug time!"].randomElement()!
                            : ["Walk break!", "Stretch those legs", "Go for a stroll~", "Up you get!"].randomElement()!)
            play(isWater ? "Glass" : "Purr")
        case 2:
            pet.say(isWater ? "HEY. Drink. Water." : "Up! Walk! Now!")
            play("Funk")
        default:
            play("Sosumi")
        }
    }

    private func play(_ name: String) { if soundOn { NSSound(named: name)?.play() } }

    /// Grow or shrink a pet's window around its bottom-centre, kept on screen.
    private func resize(_ w: Wanderer) {
        let s = w.pet.sprite, g = w.pet.grow
        let size = NSSize(width: PetPanel.width(for: s, grow: g), height: PetPanel.height(for: s, grow: g))
        let f = w.panel.frame
        var o = NSPoint(x: f.midX - size.width / 2, y: f.minY)
        if let vf = (w.panel.screen ?? NSScreen.main)?.visibleFrame {
            o.x = min(max(o.x, vf.minX), vf.maxX - size.width)
            o.y = min(max(o.y, vf.minY), vf.maxY - size.height)
        }
        w.panel.setFrame(NSRect(origin: o, size: size), display: true)
        w.sync()
    }

    /// Stage 3: dim the whole screen with the pet in the middle until Done or "5 more min" is clicked.
    private func updateTakeover() {
        let want = [water, walk].first { shownStage[$0.key] == 3 }
        if takeover?.key == want?.key { return }
        takeover?.panel.orderOut(nil)
        takeover = nil
        guard let r = want else { return }
        let isWater = r === water
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let p = TakeoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.contentView = FirstMouseHost(rootView: TakeoverView(
            pet: isWater ? cat : ghost,
            title: isWater ? "Drink water!" : "Time for a walk!",
            subtitle: isWater ? "Ignored for 10 min · \(water.count)/\(Self.goal) glasses today · click Done once you've had one"
                              : "Ignored for 10 min · \(walk.count) walks today · click Done after your walk",
            spriteHeight: frame.height * 0.36,
            onDone: { [unowned self] in isWater ? self.tapCat() : self.tapGhost() },
            onLater: { [unowned self] in
                r.snooze(5)
                (isWater ? self.cat : self.ghost).say("Fine. 5 minutes.", for: 3)
                self.refresh(Date())
            }))
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        takeover = (r.key, p)
    }

    private func tapCat() {
        if water.nagging {
            water.done()
            refresh(Date())
            cat.rewardEmoji = "💧"
            cat.perform(.celebrate)
            cat.say(water.count >= Self.goal ? "Goal hit! \(water.count) glasses 🎉" : "💧 \(water.count)/\(Self.goal) · nice!", for: 3)
        } else if Double.random(in: 0..<1) < 0.3 {
            cat.facingLeft.toggle()          // sassy: turns its back on you
            cat.say("hmph.", for: 2)
        } else {
            cat.say("Next sip in \(water.minutesLeft)m · \(water.count)/\(Self.goal)", for: 3)
        }
    }

    private func tapGhost() {
        if walk.nagging {
            walk.done()
            refresh(Date())
            ghost.rewardEmoji = "⭐️"
            ghost.perform(.celebrate)
            ghost.say("Nice walk! #\(walk.count) today", for: 3)
        } else {
            ghost.say("Next walk in \(walk.minutesLeft)m", for: 3)
        }
    }

    private func rollDay() {
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        if UserDefaults.standard.string(forKey: "day") != today {
            UserDefaults.standard.set(today, forKey: "day")
            water.count = 0; walk.count = 0
        }
    }

    // MARK: menu

    func makeMenu(for w: Wanderer?) -> NSMenu {
        let m = NSMenu()
        if let w {
            let head = NSMenuItem(title: w.label, action: nil, keyEquivalent: ""); head.isEnabled = false
            m.addItem(head)
            if !w.stationary {
                let mv = item("Move around", #selector(toggleStill(_:)))
                mv.state = w.still ? .off : .on
                mv.representedObject = w
                m.addItem(mv)
            }
            let pk = item("Hide (peek from the bottom)", #selector(togglePeek(_:)))
            pk.state = w.peeking ? .on : .off
            pk.representedObject = w
            m.addItem(pk)
            m.addItem(.separator())
        }
        for t in ["Today: \(water.count)/\(Self.goal) glasses · \(walk.count) walks",
                  "Next sip in \(water.minutesLeft)m · next walk in \(walk.minutesLeft)m"] {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(item("I drank a glass", #selector(drank)))
        m.addItem(item("I took a walk", #selector(walked)))
        m.addItem(item("Snooze water 10 min", #selector(snoozeWater)))
        m.addItem(item("Snooze walk 10 min", #selector(snoozeWalk)))
        m.addItem(.separator())
        m.addItem(intervalMenu("Water every…", [20, 30, 45, 60, 90], water.intervalMin, #selector(setWater(_:))))
        m.addItem(intervalMenu("Walk every…", [30, 45, 60, 90, 120], walk.intervalMin, #selector(setWalk(_:))))
        let wd = item("Let them wander", #selector(toggleWander)); wd.state = wanderOn ? .on : .off
        m.addItem(wd)
        let s = item("Sound", #selector(toggleSound)); s.state = soundOn ? .on : .off
        m.addItem(s)
        m.addItem(item("Show both reminders now", #selector(testNow)))
        m.addItem(item("Reset today's counts", #selector(resetToday)))
        m.addItem(item("Open friends folder…", #selector(openFriends)))
        m.addItem(item("Restart Pixels (reload friends)", #selector(restart)))
        m.addItem(.separator())
        m.addItem(item("Quit Pixels", #selector(quit)))
        return m
    }

    private func intervalMenu(_ title: String, _ values: [Int], _ current: Int, _ sel: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for v in values {
            let i = item("\(v) min", sel); i.tag = v; i.state = v == current ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    private func item(_ t: String, _ a: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: a, keyEquivalent: ""); i.target = self; return i
    }
    @objc func drank() {
        if water.nagging { tapCat() } else { water.done(); cat.say("Glug! \(water.count)/\(Self.goal) today", for: 3) }
    }
    @objc func walked() {
        if walk.nagging { tapGhost() } else { walk.done(); ghost.say("Walk logged (\(walk.count) today)", for: 3) }
    }
    @objc func snoozeWater() { water.snooze(10); refresh(Date()); cat.say("Okay, 10 more min…", for: 2.5) }
    @objc func snoozeWalk() { walk.snooze(10); refresh(Date()); ghost.say("Fine, 10 min…", for: 2.5) }
    @objc func setWater(_ i: NSMenuItem) { water.intervalMin = i.tag; cat.say("Water every \(i.tag) min", for: 2.5) }
    @objc func setWalk(_ i: NSMenuItem) { walk.intervalMin = i.tag; ghost.say("Walks every \(i.tag) min", for: 2.5) }
    @objc func toggleSound() { soundOn.toggle() }
    @objc func toggleStill(_ i: NSMenuItem) {
        guard let w = i.representedObject as? Wanderer else { return }
        w.still.toggle()
        w.sync()
        w.pet.say(w.still ? "staying here" : "off I go!", for: 2)
    }
    @objc func togglePeek(_ i: NSMenuItem) {
        guard let w = i.representedObject as? Wanderer else { return }
        w.peeking.toggle()
        w.sync()
        if !w.peeking { w.pet.say("I'm back!", for: 2) }
    }
    @objc func toggleWander() { wanderOn.toggle() }
    @objc func testNow() { water.due = Date(); walk.due = Date().addingTimeInterval(2) }
    @objc func resetToday() { water.count = 0; walk.count = 0; cat.say("Fresh start", for: 2) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openFriends() { NSWorkspace.shared.open(Self.friendsDir) }
    @objc func restart() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.5; open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
