import UIKit
import SceneKit
import AVFoundation

let S = UserDefaults.standard
var lang: String { get { S.string(forKey: "lang") ?? "" } set { S.set(newValue, forKey: "lang") } }
var vol: Float { get { S.object(forKey: "vol") as? Float ?? 0.6 } set { S.set(newValue, forKey: "vol") } }
var sens: Float { get { S.object(forKey: "sens") as? Float ?? 1 } set { S.set(newValue, forKey: "sens") } }
var fxOn: Bool { get { S.object(forKey: "fx") as? Bool ?? true } set { S.set(newValue, forKey: "fx") } }
let RED = UIColor(red: 0.75, green: 0.12, blue: 0.1, alpha: 1)

let TXT: [String: (String, String)] = [
    "title": ("THE DREAM", "الحلم"), "play": ("PLAY", "ابدأ"), "settings": ("SETTINGS", "الإعدادات"),
    "back": ("BACK", "رجوع"), "lang": ("LANGUAGE: ENGLISH", "اللغة: العربية"), "vol": ("MUSIC", "الموسيقى"),
    "sens": ("LOOK SPEED", "سرعة النظر"), "fx": ("EFFECTS", "التأثيرات"),
    "n1": ("NIGHT 1", "الليلة الأولى"), "n2": ("NIGHT 2", "الليلة الثانية"),
    "wake": ("He wakes up.\nThe same wound is on his leg.", "يستيقظ...\nويجد الجرح نفسه في ساقه."),
    "end": ("END OF PART 1", "نهاية الجزء الأول")
]
func T(_ k: String) -> String { let v = TXT[k]!; return lang == "ar" ? v.1 : v.0 }

func img(_ n: String, _ e: String) -> UIImage? { Bundle.main.path(forResource: n, ofType: e).flatMap { UIImage(contentsOfFile: $0) } }
func mat(_ c: UIColor, lit: Bool = true) -> SCNMaterial {
    let m = SCNMaterial(); m.diffuse.contents = c; m.isDoubleSided = true
    m.lightingModel = lit ? .lambert : .constant
    return m
}
func btn(_ t: String, _ target: Any?, _ a: Selector) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(t, for: .normal); b.setTitleColor(UIColor(white: 0.9, alpha: 1), for: .normal)
    b.titleLabel?.font = UIFont(name: "Courier-Bold", size: 20) ?? .boldSystemFont(ofSize: 20)
    b.layer.borderColor = RED.cgColor; b.layer.borderWidth = 1.5
    b.addTarget(target, action: a, for: .touchUpInside)
    b.widthAnchor.constraint(equalToConstant: 260).isActive = true
    b.heightAnchor.constraint(equalToConstant: 40).isActive = true
    return b
}
func hall(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, floor: UIColor, wall: UIColor) -> SCNNode {
    let n = SCNNode()
    func p(_ pw: CGFloat, _ ph: CGFloat, _ pos: SCNVector3, _ ang: SCNVector3, _ c: UIColor) {
        let k = SCNNode(geometry: SCNPlane(width: pw, height: ph))
        k.geometry?.firstMaterial = mat(c); k.position = pos; k.eulerAngles = ang; n.addChildNode(k)
    }
    let H = Float(h), W = Float(w), L = Float(l), pi = Float.pi
    p(w, l, SCNVector3(0, 0, 0), SCNVector3(-pi / 2, 0, 0), floor)
    p(w, l, SCNVector3(0, H, 0), SCNVector3(pi / 2, 0, 0), wall)
    p(w, h, SCNVector3(0, H / 2, -L / 2), SCNVector3(0, 0, 0), wall)
    p(w, h, SCNVector3(0, H / 2, L / 2), SCNVector3(0, pi, 0), wall)
    p(l, h, SCNVector3(-W / 2, H / 2, 0), SCNVector3(0, pi / 2, 0), wall)
    p(l, h, SCNVector3(W / 2, H / 2, 0), SCNVector3(0, -pi / 2, 0), wall)
    return n
}
func addLight(_ t: SCNLight.LightType, _ i: CGFloat, _ c: UIColor, to p: SCNNode, at pos: SCNVector3) {
    let l = SCNLight(); l.type = t; l.intensity = i; l.color = c
    let n = SCNNode(); n.light = l; n.position = pos; p.addChildNode(n)
}

final class GameView: UIView {
    var night = 1
    var onExit: (() -> Void)?
    let sv = SCNView(), rig = SCNNode(), cam = SCNNode()
    var yaw: Float = 0, pitch: Float = 0, bob: Float = 0, dist: Float = 0, shake: Float = 0, ft: Float = 0
    var bx: Float = 3, bz: Float = 3
    var state = 0, alive = true
    var jv = CGPoint.zero, moveStart = CGPoint.zero, lastLook = CGPoint.zero
    var moveT: UITouch?, lookT: UITouch?
    var knife: SCNNode?, monster: SCNNode?
    var link: CADisplayLink?
    let ui = UIView(), ring = UIView(), dot = UIView(), cover = UIView(), label = UILabel(), pic = UIImageView()
    let band = CALayer(), tint = CAGradientLayer()
    var tex: [UIImage] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true; backgroundColor = .black; clipsToBounds = true
        sv.isUserInteractionEnabled = false; sv.antialiasingMode = .none; sv.preferredFramesPerSecond = 30
        sv.isPlaying = true; sv.backgroundColor = .black
        addSubview(sv)
        let c = SCNCamera(); c.zNear = 0.05; c.zFar = 200; c.fieldOfView = 75
        c.wantsHDR = true; c.wantsExposureAdaptation = false
        cam.camera = c; rig.addChildNode(cam)
        tex = [img("green1", "png"), img("green2", "png")].compactMap { $0 }
        if tex.isEmpty {
            tex = [UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { UIColor.green.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }]
        }
        // VHS look: scanlines, color wash, moving Betamax band
        ui.isUserInteractionEnabled = false; addSubview(ui)
        let rep = CAReplicatorLayer(); rep.frame = CGRect(x: 0, y: 0, width: 2000, height: 3)
        let ln = CALayer(); ln.frame = CGRect(x: 0, y: 0, width: 2000, height: 1); ln.backgroundColor = UIColor(white: 0, alpha: 0.13).cgColor
        rep.addSublayer(ln); rep.instanceCount = 150; rep.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
        ui.layer.addSublayer(rep)
        tint.colors = [UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1).cgColor, UIColor(red: 0.1, green: 0.35, blue: 0.9, alpha: 1).cgColor]
        tint.endPoint = CGPoint(x: 1, y: 1); tint.opacity = 0.22; tint.compositingFilter = "softLightBlendMode"
        ui.layer.addSublayer(tint)
        band.frame = CGRect(x: 0, y: 0, width: 2000, height: 56)
        let bg = CAGradientLayer(); bg.frame = band.bounds
        bg.colors = [UIColor.clear.cgColor, UIColor(white: 1, alpha: 0.10).cgColor, UIColor.clear.cgColor]
        let bl = CALayer(); bl.frame = CGRect(x: 0, y: 27, width: 2000, height: 2); bl.backgroundColor = UIColor(white: 1, alpha: 0.3).cgColor
        band.addSublayer(bg); band.addSublayer(bl); ui.layer.addSublayer(band)
        for (v, s) in [(ring, 100.0), (dot, 44.0)] {
            v.bounds = CGRect(x: 0, y: 0, width: s, height: s); v.layer.cornerRadius = CGFloat(s / 2)
            v.layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor; v.layer.borderWidth = 2
            v.alpha = 0; v.isUserInteractionEnabled = false; addSubview(v)
        }
        cover.isUserInteractionEnabled = false
        pic.image = img("eye", "jpg"); pic.contentMode = .scaleAspectFit; pic.backgroundColor = .black; pic.alpha = 0
        label.font = UIFont(name: "Courier-Bold", size: 30) ?? .boldSystemFont(ofSize: 30)
        label.textColor = .white; label.textAlignment = .center; label.numberOfLines = 0; label.alpha = 0
        [cover, pic, label].forEach { addSubview($0) }
        let x = UIButton(type: .system); x.setTitle("✕", for: .normal); x.setTitleColor(UIColor(white: 1, alpha: 0.5), for: .normal)
        x.frame = CGRect(x: 10, y: 8, width: 44, height: 44); x.addTarget(self, action: #selector(quit), for: .touchUpInside)
        addSubview(x)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        sv.frame = bounds; sv.contentScaleFactor = fxOn ? 1 : UIScreen.main.scale
        ui.frame = bounds; cover.frame = bounds; pic.frame = bounds; label.frame = bounds.insetBy(dx: 30, dy: 0)
        CATransaction.begin(); CATransaction.setDisableActions(true); tint.frame = bounds; CATransaction.commit()
        if band.animation(forKey: "s") == nil && bounds.height > 0 {
            let a = CABasicAnimation(keyPath: "position.y"); a.fromValue = -30.0; a.toValue = Double(bounds.height) + 30
            a.duration = 5; a.repeatCount = .infinity; band.add(a, forKey: "s")
        }
    }

    func applyFx() {
        let c = cam.camera!, k: CGFloat = fxOn ? 1 : 0
        c.saturation = 1 + 0.3 * k; c.grainIntensity = 0.35 * k; c.colorFringeStrength = 0.7 * k
        c.vignettingIntensity = 0.7 * k; c.vignettingPower = 1
        ui.isHidden = !fxOn
    }
    func after(_ s: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in if self?.alive == true { f() } }
    }
    func card(_ t: String) { label.text = t; label.alpha = 1 }

    func start() {
        link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link?.preferredFramesPerSecond = 30; link?.add(to: .main, forMode: .common)
        begin()
    }
    @objc func quit() {
        guard alive else { return }
        alive = false; link?.invalidate(); link = nil; removeFromSuperview(); onExit?()
    }

    func begin() {
        state = 0; dist = 0; yaw = 0; pitch = 0; bob = 0; shake = 0; monster = nil; jv = .zero
        cover.backgroundColor = .black; cover.alpha = 1; pic.alpha = 0; label.textColor = .white
        cam.childNodes.forEach { $0.removeFromParentNode() }
        let sc = SCNScene(); sc.rootNode.addChildNode(rig); sv.scene = sc; sv.pointOfView = cam
        sc.fogColor = UIColor.black
        rig.position = SCNVector3(0, 1.6, 0)
        if night == 1 { build1(sc) } else { build2(sc) }
        applyFx()
        card(T(night == 1 ? "n1" : "n2"))
        after(2.2) { self.label.alpha = 0; UIView.animate(withDuration: 0.6) { self.cover.alpha = 0 }; self.state = 1 }
    }

    func build1(_ sc: SCNScene) {
        sc.fogStartDistance = 2; sc.fogEndDistance = 14; bx = 3.1; bz = 3.1
        sc.rootNode.addChildNode(hall(7, 3, 7, floor: UIColor(red: 0.2, green: 0.14, blue: 0.1, alpha: 1), wall: UIColor(red: 0.3, green: 0.27, blue: 0.3, alpha: 1)))
        let bed = SCNNode(geometry: SCNBox(width: 1.6, height: 0.5, length: 2.2, chamferRadius: 0.03))
        bed.geometry?.firstMaterial = mat(UIColor(white: 0.6, alpha: 1)); bed.position = SCNVector3(-2.4, 0.25, -2)
        sc.rootNode.addChildNode(bed)
        addLight(.ambient, 250, UIColor(red: 0.5, green: 0.55, blue: 0.95, alpha: 1), to: sc.rootNode, at: SCNVector3Zero)
        addLight(.omni, 450, UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1), to: sc.rootNode, at: SCNVector3(2, 2.6, -1))
        // simple placeholder hand + knife (replace later with the real hand image)
        let k = SCNNode()
        let bl = SCNNode(geometry: SCNBox(width: 0.02, height: 0.3, length: 0.005, chamferRadius: 0))
        bl.geometry?.firstMaterial = mat(UIColor(white: 0.7, alpha: 1), lit: false); bl.position = SCNVector3(0, 0.17, 0)
        let hd = SCNNode(geometry: SCNBox(width: 0.07, height: 0.09, length: 0.07, chamferRadius: 0.01))
        hd.geometry?.firstMaterial = mat(UIColor(red: 0.45, green: 0.32, blue: 0.28, alpha: 1), lit: false)
        k.addChildNode(bl); k.addChildNode(hd)
        k.position = SCNVector3(0.16, -0.22, -0.4); k.eulerAngles = SCNVector3(0.4, 0, -0.2)
        cam.addChildNode(k); knife = k
    }

    func build2(_ sc: SCNScene) {
        sc.fogStartDistance = 8; sc.fogEndDistance = 120; bx = 1.4; bz = 58.5
        sc.rootNode.addChildNode(hall(3.2, 2.8, 120, floor: UIColor(red: 0.28, green: 0.2, blue: 0.13, alpha: 1), wall: UIColor(white: 0.25, alpha: 1)))
        for s: Float in [-1, 1] {
            let e = SCNNode(geometry: SCNPlane(width: 3.2, height: 2.8))
            e.geometry?.firstMaterial = mat(.white, lit: false); e.position = SCNVector3(0, 1.4, s * 59.9)
            sc.rootNode.addChildNode(e)
        }
        addLight(.ambient, 60, .white, to: sc.rootNode, at: SCNVector3Zero)
        addLight(.spot, 1800, UIColor(red: 1, green: 0.93, blue: 0.78, alpha: 1), to: cam, at: SCNVector3Zero)
        if let l = cam.childNodes.last?.light { l.spotInnerAngle = 15; l.spotOuterAngle = 55; l.attenuationEndDistance = 30 }
    }

    func spawn() {
        let h: CGFloat = 2.0, w = h * tex[0].size.width / tex[0].size.height
        let g = SCNPlane(width: w, height: h)
        let m = SCNMaterial(); m.lightingModel = .constant; m.isDoubleSided = true; m.diffuse.contents = tex[0]
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        let p = rig.position, dir: Float = p.z > 0 ? 1 : -1
        n.position = SCNVector3(p.x, 1.0, p.z - dir * 14)
        let bc = SCNBillboardConstraint(); bc.freeAxes = .Y; n.constraints = [bc]
        sv.scene?.rootNode.addChildNode(n); monster = n
    }

    func chase(_ m: SCNNode, _ dt: Float) -> Float {
        ft += dt
        let p = rig.position, q = m.position
        let dir: Float = q.z < p.z ? 1 : -1
        let nz = q.z + dir * 3.5 * dt, nx = q.x + (p.x - q.x) * min(1, dt * 2)
        m.position = SCNVector3(nx, 1.0 + abs(sin(ft * 14)) * 0.1, nz)
        m.geometry?.firstMaterial?.diffuse.contents = tex[Int(ft * 5) % tex.count]
        let d = abs(nz - p.z)
        if d < 1.1 { caught() }
        return max(0, 1 - d / 14)
    }

    func drop() {
        state = 2; shake = 0.05
        knife?.runAction(.group([.moveBy(x: 0, y: -0.5, z: 0.1, duration: 0.5), .rotateBy(x: 1.5, y: 0, z: 0.5, duration: 0.5)]))
        after(0.6) { UIView.animate(withDuration: 0.3) { self.cover.alpha = 1 } }
        after(1.4) { self.card(T("wake")) }
        after(5.2) { self.night = 2; self.begin() }
    }
    func caught() {
        state = 2; cover.alpha = 1; label.alpha = 0; shake = 0
        after(1) { self.pic.alpha = 1 }
        after(3) { self.begin() }
    }
    func win() {
        state = 2; cover.backgroundColor = .white
        UIView.animate(withDuration: 1.5) { self.cover.alpha = 1 }
        after(1.6) { self.label.textColor = .black; self.card(T("end")) }
        after(5) { self.quit() }
    }

    @objc func tick(_ l: CADisplayLink) {
        guard alive else { return }
        let dt = Float(min(l.targetTimestamp - l.timestamp, 0.1))
        var near: Float = 0
        if state == 1 {
            let f = Float(-jv.y), s = Float(jv.x), sp: Float = 3
            let dx = (-sin(yaw) * f + cos(yaw) * s) * sp * dt
            let dz = (-cos(yaw) * f - sin(yaw) * s) * sp * dt
            let o = rig.position
            let nx = max(-bx, min(bx, o.x + dx)), nz = max(-bz, min(bz, o.z + dz))
            rig.position = SCNVector3(nx, o.y, nz)
            let st = hypot(nx - o.x, nz - o.z)
            dist += st; bob += st * 7
            if night == 1 && dist > 6 { drop() }
            if night == 2 {
                if monster == nil && abs(nz) > 10 { spawn() }
                if let m = monster { near = chase(m, dt) }
                if abs(nz) > 58 && state == 1 { win() }
            }
        }
        let amp: Float = fxOn ? 0.006 + near * 0.02 + shake : 0
        func r() -> Float { Float.random(in: -1...1) }
        rig.eulerAngles = SCNVector3(0, yaw, 0)
        cam.eulerAngles = SCNVector3(pitch + r() * amp, r() * amp * 0.5, r() * amp)
        cam.position = SCNVector3(r() * amp * 0.3, sin(bob) * 0.03, 0)
        shake = max(0, shake - dt * 0.06)
    }

    override func touchesBegan(_ ts: Set<UITouch>, with e: UIEvent?) {
        for t in ts {
            let p = t.location(in: self)
            if p.x < bounds.midX && moveT == nil {
                moveT = t; moveStart = p; ring.center = p; dot.center = p; ring.alpha = 1; dot.alpha = 1
            } else if lookT == nil { lookT = t; lastLook = p }
        }
    }
    override func touchesMoved(_ ts: Set<UITouch>, with e: UIEvent?) {
        for t in ts {
            let p = t.location(in: self)
            if t == moveT {
                var dx = (p.x - moveStart.x) / 50, dy = (p.y - moveStart.y) / 50
                let m = hypot(dx, dy); if m > 1 { dx /= m; dy /= m }
                jv = CGPoint(x: dx, y: dy); dot.center = CGPoint(x: moveStart.x + dx * 50, y: moveStart.y + dy * 50)
            } else if t == lookT {
                if state == 1 {
                    yaw -= Float(p.x - lastLook.x) * 0.006 * sens
                    pitch = min(1.2, max(-1.2, pitch - Float(p.y - lastLook.y) * 0.006 * sens))
                }
                lastLook = p
            }
        }
    }
    override func touchesEnded(_ ts: Set<UITouch>, with e: UIEvent?) {
        for t in ts {
            if t == moveT { moveT = nil; jv = .zero; ring.alpha = 0; dot.alpha = 0 }
            if t == lookT { lookT = nil }
        }
    }
    override func touchesCancelled(_ ts: Set<UITouch>, with e: UIEvent?) { touchesEnded(ts, with: e) }
}

final class Root: UIViewController {
    var player: AVAudioPlayer?
    var current: UIView?
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let u = Bundle.main.url(forResource: "music", withExtension: "m4a") {
            player = try? AVAudioPlayer(contentsOf: u)
            player?.numberOfLoops = -1; player?.volume = vol; player?.play()
        }
        if lang.isEmpty { showLang() } else { showMenu() }
    }
    func show(_ v: UIView) {
        current?.removeFromSuperview()
        v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(v); current = v
    }
    func screen(_ items: [UIView], _ sp: CGFloat = 12) -> UIView {
        let v = UIView(); v.backgroundColor = .black
        let st = UIStackView(arrangedSubviews: items); st.axis = .vertical; st.spacing = sp; st.alignment = .center
        st.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(st)
        st.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true
        st.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
        return v
    }
    func label(_ t: String, _ s: CGFloat, _ c: UIColor) -> UILabel {
        let l = UILabel(); l.text = t; l.textColor = c
        l.font = UIFont(name: "Courier-Bold", size: s) ?? .boldSystemFont(ofSize: s); return l
    }
    func showLang() {
        show(screen([label("LANGUAGE  /  اللغة", 18, .gray), btn("English", self, #selector(setEn)), btn("العربية", self, #selector(setAr))]))
    }
    func showMenu() {
        show(screen([label(T("title"), 40, RED), btn(T("play"), self, #selector(play)), btn(T("settings"), self, #selector(openSettings))], 14))
    }
    func showSettings() {
        let vs = UISlider(), ss = UISlider(), sw = UISwitch()
        vs.value = vol; vs.tag = 1; ss.minimumValue = 0.4; ss.maximumValue = 2; ss.value = sens; ss.tag = 2; sw.isOn = fxOn
        for s in [vs, ss] { s.addTarget(self, action: #selector(slid(_:)), for: .valueChanged); s.widthAnchor.constraint(equalToConstant: 240).isActive = true }
        sw.addTarget(self, action: #selector(fxChanged(_:)), for: .valueChanged)
        let g = UIColor.gray
        show(screen([label(T("settings"), 24, RED), btn(T("lang"), self, #selector(toggleLang)), label(T("vol"), 14, g), vs,
                     label(T("sens"), 14, g), ss, label(T("fx"), 14, g), sw, btn(T("back"), self, #selector(back))], 6))
    }
    @objc func setEn() { lang = "en"; showMenu() }
    @objc func setAr() { lang = "ar"; showMenu() }
    @objc func openSettings() { showSettings() }
    @objc func back() { showMenu() }
    @objc func toggleLang() { lang = (lang == "ar") ? "en" : "ar"; showSettings() }
    @objc func slid(_ s: UISlider) { if s.tag == 1 { vol = s.value; player?.volume = vol } else { sens = s.value } }
    @objc func fxChanged(_ s: UISwitch) { fxOn = s.isOn }
    @objc func play() {
        let g = GameView(frame: view.bounds)
        g.onExit = { [weak self] in self?.showMenu() }
        show(g); g.start()
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = Root()
        window?.makeKeyAndVisible()
        return true
    }
}
