import AppKit
import QuartzCore

/// Plays a `PageTransition` with Core Animation: image layers of the old and the new page
/// above the (already updated) vector page view, removed when done. Layer coordinates are
/// y-up, like `/Di` directions.
@MainActor
enum PageTransitionAnimator {
    static let layerName = "pageTransition"

    /// Returns the overlay (to cancel it: remove it from its superlayer).
    @discardableResult
    static func play(_ t: PageTransition, in host: CALayer, size: CGSize, scale: CGFloat,
                     old: CGImage, new: CGImage, completion: @escaping () -> Void) -> CALayer {
        let full = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: full.midX, y: full.midY)
        let container = CALayer()
        container.name = layerName
        container.frame = full
        container.masksToBounds = true

        func imageLayer(_ image: CGImage) -> CALayer {
            let l = CALayer()
            l.frame = full
            l.contents = image
            l.contentsGravity = .resize
            l.contentsScale = scale
            return l
        }
        func solid(_ frame: CGRect, anchor: CGPoint) -> CALayer {
            let l = CALayer()
            l.backgroundColor = CGColor(gray: 0, alpha: 1)
            l.anchorPoint = anchor
            l.bounds = CGRect(origin: .zero, size: frame.size)
            l.position = CGPoint(x: frame.minX + anchor.x * frame.width, y: frame.minY + anchor.y * frame.height)
            return l
        }

        let o = imageLayer(old), n = imageLayer(new)
        let v = t.motion
        let shift = CGPoint(x: v.dx * size.width, y: v.dy * size.height)
        var animations: [Step] = []
        func animate(_ layer: CALayer, _ keyPath: String, _ from: Any, _ to: Any,
                     begin: Double = 0, length: Double = 1, timing: CAMediaTimingFunctionName = .easeInEaseOut) {
            animations.append(Step(layer: layer, keyPath: keyPath, from: from, to: to, begin: begin, length: length, timing: timing))
        }

        switch t.style {
        case .replace:
            break
        case .dissolve, .fade:
            container.addSublayer(n)
            container.addSublayer(o)
            animate(o, "opacity", 1.0, 0.0)
        case .glitter:
            // Small tiles of the new page appear in random order, sweeping in the direction of motion.
            container.addSublayer(o)
            container.addSublayer(n)
            let columns = 24, rows = max(1, Int((Double(columns) * size.height / size.width).rounded()))
            let tile = CGSize(width: size.width / Double(columns), height: size.height / Double(rows))
            let length = hypot(v.dx, v.dy), dir = length > 0 ? CGVector(dx: v.dx / length, dy: v.dy / length) : CGVector(dx: 1, dy: 0)
            // Projection of a point onto the direction, normalized to 0…1 over the page.
            let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
                .map { $0.x * dir.dx + $0.y * dir.dy }
            let lo = corners.min()!, span = max(corners.max()! - lo, 1)
            var rng = SystemRandomNumberGenerator()
            let tiles = CALayer()
            tiles.frame = full
            for row in 0..<rows {
                for column in 0..<columns {
                    let frame = CGRect(x: Double(column) * tile.width, y: Double(row) * tile.height,
                                       width: tile.width + 0.5, height: tile.height + 0.5)
                    let l = solid(frame, anchor: CGPoint(x: 0.5, y: 0.5))
                    l.opacity = 0
                    tiles.addSublayer(l)
                    let along = (frame.midX * dir.dx + frame.midY * dir.dy - lo) / span
                    let begin = min(along * 0.6 + Double.random(in: 0...0.25, using: &rng), 0.85)
                    animate(l, "opacity", 0.0, 1.0, begin: begin, length: 0.15, timing: .linear)
                }
            }
            n.mask = tiles
        case .fly:
            // The new page flies in from the direction it moves to, growing and getting opaque.
            container.addSublayer(o)
            container.addSublayer(n)
            animate(n, "position", CGPoint(x: center.x - shift.x, y: center.y - shift.y), center, timing: .easeOut)
            animate(n, "transform.scale", 0.3, 1.0, timing: .easeOut)
            animate(n, "opacity", 0.0, 1.0, length: 0.5)
        case .fadeThroughBlack:
            container.backgroundColor = CGColor(gray: 0, alpha: 1)
            container.addSublayer(o)
            container.addSublayer(n)
            n.opacity = 0
            animate(o, "opacity", 1.0, 0.0, length: 0.5)
            animate(n, "opacity", 0.0, 1.0, begin: 0.5, length: 0.5)
        case .zoom:
            // In: the new page grows from the center. Out: the old page grows and fades away.
            if t.inward {
                container.addSublayer(o)
                container.addSublayer(n)
                animate(n, "transform.scale", 0.2, 1.0)
                animate(n, "opacity", 0.0, 1.0)
            } else {
                container.addSublayer(n)
                container.addSublayer(o)
                animate(o, "transform.scale", 1.0, 1.6)
                animate(o, "opacity", 1.0, 0.0)
            }
        case .flip:
            // The old page turns edge-on, then the new one turns in from the other side.
            container.backgroundColor = CGColor(gray: 0, alpha: 1)
            container.sublayerTransform = perspective(size)
            container.addSublayer(o)
            container.addSublayer(n)
            let (key, sign) = rotation(v)
            // Edge-on (invisible) before its half starts and after its half ends.
            animate(o, key, 0.0, sign * .pi / 2, length: 0.5, timing: .easeIn)
            animate(n, key, -sign * .pi / 2, 0.0, begin: 0.5, length: 0.5, timing: .easeOut)
        case .cube:
            // Both pages are faces of a cube turning in the direction of motion.
            container.backgroundColor = CGColor(gray: 0, alpha: 1)
            container.sublayerTransform = perspective(size)
            container.addSublayer(o)
            container.addSublayer(n)
            // Each face turns about the cube's center, half a page behind the screen (anchorPointZ):
            // animating a whole `transform` would interpolate translation and rotation separately.
            let depth = (v.dx != 0 ? size.width : size.height) / 2
            let (key, sign) = rotation(v)
            for l in [o, n] {
                l.isDoubleSided = false
                l.anchorPointZ = -depth
                l.zPosition = -depth
            }
            animate(o, key, 0.0, sign * .pi / 2)
            animate(n, key, -sign * .pi / 2, 0.0)
        case .push:
            container.addSublayer(o)
            container.addSublayer(n)
            animate(o, "position", center, CGPoint(x: center.x + shift.x, y: center.y + shift.y))
            animate(n, "position", CGPoint(x: center.x - shift.x, y: center.y - shift.y), center)
        case .cover:
            container.addSublayer(o)
            container.addSublayer(n)
            animate(n, "position", CGPoint(x: center.x - shift.x, y: center.y - shift.y), center)
        case .moveIn:
            // Like Keynote's "Move In": the new page slides over the old one, which drifts a
            // little the same way (parallax), shrinks back and darkens.
            let dim = CALayer()
            dim.frame = full
            dim.backgroundColor = CGColor(gray: 0, alpha: 1)
            dim.opacity = 0
            n.shadowColor = CGColor(gray: 0, alpha: 1)
            n.shadowOpacity = 0.5
            n.shadowRadius = 12
            container.backgroundColor = CGColor(gray: 0, alpha: 1)
            container.addSublayer(o)
            container.addSublayer(dim)
            container.addSublayer(n)
            animate(o, "position", center, CGPoint(x: center.x + 0.3 * shift.x, y: center.y + 0.3 * shift.y))
            animate(o, "transform.scale", 1.0, 0.9)
            animate(dim, "opacity", 0.0, 0.5)
            animate(n, "position", CGPoint(x: center.x - shift.x, y: center.y - shift.y), center)
        case .uncover:
            container.addSublayer(n)
            container.addSublayer(o)
            animate(o, "position", center, CGPoint(x: center.x + shift.x, y: center.y + shift.y))
        case .wipe:
            // The new page is revealed by an edge moving in the direction of motion.
            container.addSublayer(o)
            container.addSublayer(n)
            let anchor = CGPoint(x: v.dx > 0 ? 0 : v.dx < 0 ? 1 : 0.5, y: v.dy > 0 ? 0 : v.dy < 0 ? 1 : 0.5)
            let mask = solid(full, anchor: anchor)
            n.mask = mask
            animate(mask, v.dx != 0 ? "transform.scale.x" : "transform.scale.y", 0.0, 1.0)
        case .box, .split:
            // Outward: the new page grows from the center. Inward: the old page shrinks to it.
            let key = t.style == .box ? "transform.scale" : (t.horizontal ? "transform.scale.y" : "transform.scale.x")
            let mask = solid(full, anchor: CGPoint(x: 0.5, y: 0.5))
            if t.inward {
                container.addSublayer(n)
                container.addSublayer(o)
                o.mask = mask
                animate(mask, key, 1.0, 0.0)
            } else {
                container.addSublayer(o)
                container.addSublayer(n)
                n.mask = mask
                animate(mask, key, 0.0, 1.0)
            }
        case .blinds:
            container.addSublayer(o)
            container.addSublayer(n)
            let count = 6
            let stripes = CALayer()
            stripes.frame = full
            for i in 0..<count {
                let f = Double(i) / Double(count)
                let frame = t.horizontal
                    ? CGRect(x: 0, y: size.height * f, width: size.width, height: size.height / Double(count))
                    : CGRect(x: size.width * f, y: 0, width: size.width / Double(count), height: size.height)
                let stripe = solid(frame, anchor: t.horizontal ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 0, y: 0.5))
                stripes.addSublayer(stripe)
                animate(stripe, t.horizontal ? "transform.scale.y" : "transform.scale.x", 0.0, 1.0)
            }
            n.mask = stripes
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.addSublayer(container)
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            container.removeFromSuperlayer()
            completion()
        }
        let now = container.convertTime(CACurrentMediaTime(), from: nil)
        for step in animations {
            let a = CABasicAnimation(keyPath: step.keyPath)
            a.fromValue = step.from
            a.toValue = step.to
            a.beginTime = step.begin > 0 ? now + step.begin * t.duration : 0
            a.duration = step.length * t.duration
            a.timingFunction = CAMediaTimingFunction(name: step.timing)
            a.fillMode = .both   // delayed steps show their start value meanwhile
            a.isRemovedOnCompletion = false
            step.layer.add(a, forKey: step.keyPath)
        }
        if animations.isEmpty {
            // Nothing to animate (replace): drop the overlay right away.
            CATransaction.setAnimationDuration(0)
        }
        CATransaction.commit()
        return container
    }

    /// One animation; `begin` and `length` are fractions of the transition's duration.
    private struct Step {
        var layer: CALayer
        var keyPath: String
        var from: Any
        var to: Any
        var begin: Double
        var length: Double
        var timing: CAMediaTimingFunctionName
    }

    /// Perspective for the 3D styles, the eye a bit more than a page width away.
    private static func perspective(_ size: CGSize) -> CATransform3D {
        var p = CATransform3DIdentity
        p.m34 = -1 / (2.5 * max(size.width, size.height))
        return p
    }

    /// Rotation key path and sign that turn a page's front edge in the direction of motion
    /// (y-up layer space: rotating about y by +90° moves the front to the right, about x to the bottom).
    private static func rotation(_ v: CGVector) -> (String, Double) {
        v.dx != 0 ? ("transform.rotation.y", v.dx > 0 ? 1 : -1) : ("transform.rotation.x", v.dy > 0 ? -1 : 1)
    }
}
