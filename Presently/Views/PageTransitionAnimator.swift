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
    // One short case per style.
    // swiftlint:disable:next function_body_length
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
        var animations: [(CALayer, String, Any, Any)] = []   // layer, key path, from, to

        switch t.style {
        case .replace:
            break
        case .dissolve, .fade, .glitter:
            container.addSublayer(n)
            container.addSublayer(o)
            animations.append((o, "opacity", 1.0, 0.0))
        case .push:
            container.addSublayer(o)
            container.addSublayer(n)
            animations.append((o, "position", center, CGPoint(x: center.x + shift.x, y: center.y + shift.y)))
            animations.append((n, "position", CGPoint(x: center.x - shift.x, y: center.y - shift.y), center))
        case .cover, .fly:
            container.addSublayer(o)
            container.addSublayer(n)
            animations.append((n, "position", CGPoint(x: center.x - shift.x, y: center.y - shift.y), center))
        case .uncover:
            container.addSublayer(n)
            container.addSublayer(o)
            animations.append((o, "position", center, CGPoint(x: center.x + shift.x, y: center.y + shift.y)))
        case .wipe:
            // The new page is revealed by an edge moving in the direction of motion.
            container.addSublayer(o)
            container.addSublayer(n)
            let anchor = CGPoint(x: v.dx > 0 ? 0 : v.dx < 0 ? 1 : 0.5, y: v.dy > 0 ? 0 : v.dy < 0 ? 1 : 0.5)
            let mask = solid(full, anchor: anchor)
            n.mask = mask
            animations.append((mask, v.dx != 0 ? "transform.scale.x" : "transform.scale.y", 0.0, 1.0))
        case .box, .split:
            // Outward: the new page grows from the center. Inward: the old page shrinks to it.
            let key = t.style == .box ? "transform.scale" : (t.horizontal ? "transform.scale.y" : "transform.scale.x")
            let mask = solid(full, anchor: CGPoint(x: 0.5, y: 0.5))
            if t.inward {
                container.addSublayer(n)
                container.addSublayer(o)
                o.mask = mask
                animations.append((mask, key, 1.0, 0.0))
            } else {
                container.addSublayer(o)
                container.addSublayer(n)
                n.mask = mask
                animations.append((mask, key, 0.0, 1.0))
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
                animations.append((stripe, t.horizontal ? "transform.scale.y" : "transform.scale.x", 0.0, 1.0))
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
        for (layer, keyPath, from, to) in animations {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from
            a.toValue = to
            a.duration = t.duration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: keyPath)
        }
        if animations.isEmpty {
            // Nothing to animate (replace): drop the overlay right away.
            CATransaction.setAnimationDuration(0)
        }
        CATransaction.commit()
        return container
    }
}
