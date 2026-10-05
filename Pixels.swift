// Pixels: two desktop pets. The cat nags you to drink water, the ghost nags you to take a walk.
// The pets are the GIFs in assets/, played exactly as given.
// Build: ./build.sh   Run: open Pixels.app   Demo (reminders in a few seconds): open Pixels.app --args --demo
import AppKit
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
    var lastNudge = Date.distantPast

    init(key: String, defaultInterval: Int) {
        self.key = key
        intervalMin = d.object(forKey: key + ".interval") as? Int ?? defaultInterval
        count = d.integer(forKey: key + ".count")
        restart()
        if demo { due = Date().addingTimeInterval(key == "water" ? 4 : 9) }
    }

    var minutesLeft: Int { max(1, Int(ceil(due.timeIntervalSinceNow / 60))) }
    func restart() { due = Date().addingTimeInterval(TimeInterval(intervalMin * 60)); nagging = false; lastNudge = .distantPast }
    func done() { count += 1; restart() }
    func snooze(_ min: Int) { due = Date().addingTimeInterval(TimeInterval(min * 60)); nagging = false; lastNudge = .distantPast }

    /// Returns true when it is time to (re)nudge: first at the due time, then every 5 minutes.
    func tick(_ now: Date) -> Bool {
        guard now >= due else { return false }
        nagging = true
        guard now.timeIntervalSince(lastNudge) >= (demo ? 20 : 300) else { return false }
        lastNudge = now
        return true
    }
}

// MARK: - Pet view

final class Pet: ObservableObject {
    let sprite: Sprite
    @Published private(set) var tick = 0      // advances once per GIF frame, forever, like the GIF itself
    @Published var nagging = false
    @Published var facingLeft = false
    @Published var bubble: String? = nil
    private var bubbleHide: Date? = nil
    private var timer: Timer?

    init(sprite: Sprite) {
        self.sprite = sprite
        let t = Timer(timeInterval: sprite.delay, repeats: true) { [weak self] _ in self?.tick &+= 1 }
        RunLoop.main.add(t, forMode: .common)   // keep playing while a menu is open or the pet is dragged
        timer = t
    }

    var frame: CGImage { sprite.frames[tick % sprite.frames.count] }
    /// Hop in place while the reminder is due.
    var hop: CGFloat { nagging ? -CGFloat(abs(sin(Double(tick) * 0.9))) * 12 : 0 }

    func say(_ s: String?, for secs: Double? = nil) {
        bubble = s
        bubbleHide = secs.map { Date().addingTimeInterval($0) }
    }

    func clearExpiredBubble(_ now: Date) {
        if let t = bubbleHide, now >= t { bubble = nil; bubbleHide = nil }
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
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
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
            Image(decorative: pet.frame, scale: 1)
                .resizable()
                .interpolation(pet.sprite.crisp ? .none : .high)
                .frame(width: pet.sprite.size.width, height: pet.sprite.size.height)
                .scaleEffect(x: pet.facingLeft ? -1 : 1, y: 1)
                .offset(y: pet.hop)
                .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .frame(width: PetPanel.width(for: pet.sprite), height: PetPanel.height(for: pet.sprite), alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pet.bubble)
    }
}

// MARK: - Windows

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    static func width(for s: Sprite) -> CGFloat { max(s.size.width, 240).rounded() }
    static func height(for s: Sprite) -> CGFloat { (s.size.height + 56).rounded() }   // room for bubble + hop

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
    private var pos: CGPoint
    private var target: CGPoint?
    private var restUntil = Date().addingTimeInterval(.random(in: 1...4))

    init(panel: PetPanel, pet: Pet, grounded: Bool, speed: CGFloat, flips: Bool,
         stationary: Bool = false, saveKey: String? = nil) {
        self.panel = panel; self.pet = pet; self.grounded = grounded; self.speed = speed; self.flips = flips
        self.stationary = stationary; self.saveKey = saveKey
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
        let f = panel.frame, s = pet.sprite.size
        return CGRect(x: f.midX - s.width / 2, y: f.minY, width: s.width, height: s.height)
    }

    func step(dt: CGFloat, wander: Bool, chase: Bool) {
        let mouse = NSEvent.mouseLocation
        let over = spriteRect.contains(mouse)
        // Clicks pass through everything except the pet itself.
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        let now = Date()
        // Stand still while hovered (so it's easy to click) and for a moment after being dragged.
        if over || now < holdUntil || !(wander || chase || stationary) { pos = panel.frame.origin; target = nil; return }

        let size = panel.frame.size
        let screen = chase ? (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? panel.screen)
                           : (panel.screen ?? NSScreen.main)
        guard let vf = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let maxX = max(vf.minX, vf.maxX - size.width), maxY = max(vf.minY, vf.maxY - size.height)

        if stationary {
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
        } else if target == nil, now >= restUntil {
            target = CGPoint(x: .random(in: vf.minX...maxX), y: grounded ? vf.minY : .random(in: vf.minY...maxY))
        }

        if grounded, pos.y > vf.minY { pos.y = max(vf.minY, pos.y - 600 * dt) }   // dropped mid-air: fall to the floor
        if let t = target {
            let dx = t.x - pos.x, dy = grounded ? 0 : t.y - pos.y
            let dist = hypot(dx, dy)
            if dist < 2 {
                if !chase { target = nil; restUntil = now.addingTimeInterval(.random(in: 2...8)) }
            } else {
                let len = min(dist, speed * (chase ? 3 : 1) * dt)
                pos.x += dx / dist * len
                pos.y += dy / dist * len
                if flips, abs(dx) > 1, pet.facingLeft != (dx < 0) { pet.facingLeft = dx < 0 }
            }
        }
        pos.x = min(max(pos.x, vf.minX), maxX)
        pos.y = min(max(pos.y, vf.minY), maxY)
        let bob = grounded ? 0 : sin(now.timeIntervalSinceReferenceDate * 1.8) * 4
        panel.setFrameOrigin(NSPoint(x: pos.x.rounded(), y: (pos.y + bob).rounded()))
    }
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

        let vf = NSScreen.main?.visibleFrame ?? .zero
        catPanel = makePanel(pet: cat) { [unowned self] in self.tapCat() }
        place(catPanel, at: NSPoint(x: vf.maxX - catPanel.frame.width - 20, y: vf.minY))
        ghostPanel = makePanel(pet: ghost) { [unowned self] in self.tapGhost() }
        place(ghostPanel, at: NSPoint(x: catPanel.frame.minX - ghostPanel.frame.width + 40, y: vf.minY + 120))

        wanderers = [(Wanderer(panel: catPanel, pet: cat, grounded: true, speed: 45, flips: true), { [unowned self] in self.water.nagging }),
                     (Wanderer(panel: ghostPanel, pet: ghost, grounded: false, speed: 30, flips: false), { [unowned self] in self.walk.nagging })]
        loadFriends(screen: vf)
        for (w, _) in wanderers {
            (w.panel.contentView as? PetHost<PetView>)?.onInteract = { [weak w] in w?.holdUntil = Date().addingTimeInterval(6) }
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
                FileHandle.standardError.write(Data("cat tick \(self.cat.tick) ghost tick \(self.ghost.tick) catVisible \(self.catPanel.isVisible) ghostVisible \(self.ghostPanel.isVisible) ghostFrame \(self.ghostPanel.frame) catFrame \(self.catPanel.frame) friends \(self.wanderers.dropFirst(2).map { w in "\(Int(w.w.panel.frame.minX)),\(Int(w.w.panel.frame.minY))" })\n".utf8))
            }
        }
    }

    private func makePanel(pet: Pet, onTap: @escaping () -> Void) -> PetPanel {
        let p = PetPanel(sprite: pet.sprite)
        let host = PetHost(rootView: PetView(pet: pet, onTap: onTap))
        host.menuProvider = { [unowned self] in self.makeMenu() }
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
            let shown = name.replacingOccurrences(of: "-fly", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-walk", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-big", with: "", options: .caseInsensitive).capitalized
            let panel = makePanel(pet: pet) { [weak pet] in
                pet?.say(["Hi!", "\(shown)!", "♪", "Stay hydrated~", ":)"].randomElement()!, for: 2.5)
            }
            let x = vf.minX + CGFloat(i + 1) * vf.width / CGFloat(files.count + 2)
            place(panel, at: NSPoint(x: x, y: flies ? vf.midY : vf.minY))
            friends.append(pet)
            wanderers.append((Wanderer(panel: panel, pet: pet, grounded: !flies, speed: flies ? 35 : 40, flips: true,
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

        if water.tick(now) {
            cat.say(["Sip time!", "Water break?", "Drink up, human", "Glug glug time!"].randomElement()!)
            if soundOn { NSSound(named: "Glass")?.play() }
        }
        if walk.tick(now) {
            ghost.say(["Walk break!", "Stretch those legs", "Go for a stroll~", "Up you get!"].randomElement()!)
            if soundOn { NSSound(named: "Purr")?.play() }
        }
        if cat.nagging != water.nagging { cat.nagging = water.nagging }
        if ghost.nagging != walk.nagging { ghost.nagging = walk.nagging }
    }

    private func tapCat() {
        if water.nagging {
            water.done(); cat.nagging = false
            cat.say(water.count >= Self.goal ? "Goal hit! \(water.count) glasses" : "Glug! \(water.count)/\(Self.goal) today", for: 3)
        } else {
            cat.say("Next sip in \(water.minutesLeft)m · \(water.count)/\(Self.goal)", for: 3)
        }
    }

    private func tapGhost() {
        if walk.nagging {
            walk.done(); ghost.nagging = false
            ghost.say("Nice walk! (\(walk.count) today)", for: 3)
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

    func makeMenu() -> NSMenu {
        let m = NSMenu()
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
    @objc func snoozeWater() { water.snooze(10); cat.say("Okay, 10 more min…", for: 2.5) }
    @objc func snoozeWalk() { walk.snooze(10); ghost.say("Fine, 10 min…", for: 2.5) }
    @objc func setWater(_ i: NSMenuItem) { water.intervalMin = i.tag; cat.say("Water every \(i.tag) min", for: 2.5) }
    @objc func setWalk(_ i: NSMenuItem) { walk.intervalMin = i.tag; ghost.say("Walks every \(i.tag) min", for: 2.5) }
    @objc func toggleSound() { soundOn.toggle() }
    @objc func toggleWander() { wanderOn.toggle() }
    @objc func testNow() { water.due = Date(); walk.due = Date().addingTimeInterval(2); water.lastNudge = .distantPast; walk.lastNudge = .distantPast }
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
