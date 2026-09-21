import SwiftUI
import OdomindCore

/// A vertex of a silhouette, with the radius its corner is rounded to.
///
/// Every body in this file is one closed polygon plus a corner radius per
/// vertex. That is what lets a Wrangler (radius 2, hard edges everywhere) and
/// a coupe (radius 14 over the roof) come out of the same few lines of code,
/// drawn to the same scale, sitting on the same ground.
struct ArtPoint {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat

    init(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        self.x = x
        self.y = y
        self.r = r
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// One drawable vehicle, authored in the 250 × 100 canonical box.
struct SilhouetteSpec {
    /// The outer body, front at the left, wound clockwise.
    var body: [ArtPoint]
    /// The glazed band. Pillars are painted back over it rather than drawn as
    /// separate panes, which is what makes the door count adjustable by a
    /// single array below.
    var greenhouse: [ArtPoint]
    /// Where the pillars fall. Panes = pillars + 1, and that is the door count
    /// the owner will read off the picture.
    var pillars: [CGFloat]
    var frontWheelX: CGFloat
    var rearWheelX: CGFloat
    var wheelRadius: CGFloat = 18
    /// Where the body meets the wheels, used for the shaded rocker and the
    /// door cut lines.
    var bodyBottomY: CGFloat
    var beltlineY: CGFloat
    /// Squared-off arches and flares, the way a body-on-frame off-roader has
    /// them, rather than a smooth radius.
    var squareArches: Bool = false
    var roundHeadlight: Bool = false
    var headlight: CGPoint
    /// A tailgate-mounted spare, which is half of what makes a Wrangler
    /// recognisable from across a car park.
    var spare: CGPoint?
}

enum VehicleDrawing {
    // MARK: - Drawing

    static func draw(_ shape: VehicleShape, tones: VehiclePaintTones, in context: inout GraphicsContext) {
        let spec = specification(for: shape)
        let body = roundedPath(spec.body)

        // Ground shadow. Soft, low, and the same for every vehicle, so the
        // whole garage is lit from the same place.
        let shadow = Path(
            ellipseIn: CGRect(
                x: spec.frontWheelX - spec.wheelRadius - 12,
                y: VehicleArt.groundY - 4,
                width: (spec.rearWheelX + spec.wheelRadius + 12) - (spec.frontWheelX - spec.wheelRadius - 12),
                height: 8
            )
        )
        context.fill(shadow, with: .color(.black.opacity(0.13)))

        if let spare = spec.spare {
            drawWheel(at: spare, radius: 14, tones: tones, in: &context, isSpare: true)
        }

        context.fill(body, with: .color(tones.body))

        // The shaded rocker, clipped to the body so it follows the sills
        // rather than sitting on them as a bar.
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(
                Path(CGRect(x: 0, y: spec.bodyBottomY - 10, width: VehicleArt.boxSize.width, height: 14)),
                with: .color(tones.shade)
            )
        }

        // Glass, then the pillars painted back over it in body colour.
        let greenhouse = roundedPath(spec.greenhouse)
        context.fill(greenhouse, with: .color(tones.glass))
        context.drawLayer { layer in
            layer.clip(to: greenhouse)
            for x in spec.pillars {
                layer.fill(
                    Path(CGRect(x: x - 2.2, y: 0, width: 4.4, height: VehicleArt.boxSize.height)),
                    with: .color(tones.body)
                )
            }
        }

        // Headlight. Round on the off-roaders, a slim lens on everything else.
        // Clipped to the body: on the rounded noses an unclipped lens hangs
        // off the front of the car like a sticker.
        context.drawLayer { layer in
            layer.clip(to: body)
            let glassWhite = Color(uiColor: UIColor(hex: 0xF2F4F0))
            if spec.roundHeadlight {
                let lamp = Path(
                    ellipseIn: CGRect(x: spec.headlight.x - 5, y: spec.headlight.y - 5, width: 10, height: 10)
                )
                layer.fill(lamp, with: .color(glassWhite))
                layer.stroke(lamp, with: .color(tones.trim), lineWidth: 1.4)
            } else {
                let lens = Path(
                    roundedRect: CGRect(x: spec.headlight.x - 6, y: spec.headlight.y - 3, width: 12, height: 6),
                    cornerRadius: 2.5
                )
                layer.fill(lens, with: .color(glassWhite))
            }
        }

        drawWheel(
            at: CGPoint(x: spec.frontWheelX, y: VehicleArt.wheelCenterY),
            radius: spec.wheelRadius, tones: tones, in: &context
        )
        drawWheel(
            at: CGPoint(x: spec.rearWheelX, y: VehicleArt.wheelCenterY),
            radius: spec.wheelRadius, tones: tones, in: &context
        )

        // Arches last, over the wheels, so the body reads as being in front of
        // the tyre rather than behind it.
        for x in [spec.frontWheelX, spec.rearWheelX] {
            context.stroke(
                archPath(centreX: x, spec: spec),
                with: .color(tones.shade),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }

        // Door cuts, from the beltline down to the sill.
        for x in spec.pillars {
            var cut = Path()
            cut.move(to: CGPoint(x: x, y: spec.beltlineY))
            cut.addLine(to: CGPoint(x: x, y: spec.bodyBottomY - 4))
            context.stroke(cut, with: .color(tones.shade), lineWidth: 1.1)
        }

        context.stroke(body, with: .color(tones.trim.opacity(0.55)), lineWidth: 1)
    }

    private static func drawWheel(
        at centre: CGPoint,
        radius: CGFloat,
        tones: VehiclePaintTones,
        in context: inout GraphicsContext,
        isSpare: Bool = false
    ) {
        let tyre = Path(
            ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        )
        context.fill(tyre, with: .color(Color(uiColor: UIColor(hex: 0x24292B))))

        // A fixed rim tone rather than a paint-derived one: wheels are wheels
        // whatever colour the car is, and this is what keeps the garage
        // looking like one set of drawings.
        let rimRadius = radius * (isSpare ? 0.42 : 0.55)
        let rim = Path(
            ellipseIn: CGRect(
                x: centre.x - rimRadius, y: centre.y - rimRadius,
                width: rimRadius * 2, height: rimRadius * 2
            )
        )
        context.fill(rim, with: .color(Color(uiColor: UIColor(hex: 0xB9C2C5))))

        let hubRadius = rimRadius * 0.34
        let hub = Path(
            ellipseIn: CGRect(
                x: centre.x - hubRadius, y: centre.y - hubRadius,
                width: hubRadius * 2, height: hubRadius * 2
            )
        )
        context.fill(hub, with: .color(Color(uiColor: UIColor(hex: 0x6E787B))))
    }

    private static func archPath(centreX: CGFloat, spec: SilhouetteSpec) -> Path {
        let r = spec.wheelRadius
        let bottom = spec.bodyBottomY
        var path = Path()
        if spec.squareArches {
            path.move(to: CGPoint(x: centreX - r - 4, y: bottom))
            path.addLine(to: CGPoint(x: centreX - r - 1, y: bottom - r + 2))
            path.addLine(to: CGPoint(x: centreX - r + 5, y: bottom - r - 3))
            path.addLine(to: CGPoint(x: centreX + r - 5, y: bottom - r - 3))
            path.addLine(to: CGPoint(x: centreX + r + 1, y: bottom - r + 2))
            path.addLine(to: CGPoint(x: centreX + r + 4, y: bottom))
        } else {
            path.move(to: CGPoint(x: centreX - r - 2, y: bottom))
            path.addQuadCurve(
                to: CGPoint(x: centreX + r + 2, y: bottom),
                control: CGPoint(x: centreX, y: bottom - r * 1.75)
            )
        }
        return path
    }

    // MARK: - Geometry

    /// A closed polygon with a fillet at every vertex.
    ///
    /// The fillet is a quadratic with the vertex as its control point, which is
    /// visually an arc and is a great deal less code than one. Each tangent is
    /// clamped to half the shorter adjoining edge so a large radius on a short
    /// edge cannot turn the shape inside out.
    static func roundedPath(_ points: [ArtPoint]) -> Path {
        var path = Path()
        guard points.count >= 3 else { return path }

        func unit(from a: CGPoint, to b: CGPoint) -> (CGVector, CGFloat) {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
            return (CGVector(dx: dx / length, dy: dy / length), length)
        }

        var started = false
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count].point
            let current = points[index]
            let next = points[(index + 1) % points.count].point

            let (toPrevious, lengthPrevious) = unit(from: current.point, to: previous)
            let (toNext, lengthNext) = unit(from: current.point, to: next)
            let inset = min(current.r, lengthPrevious / 2, lengthNext / 2)

            let entry = CGPoint(
                x: current.x + toPrevious.dx * inset,
                y: current.y + toPrevious.dy * inset
            )
            let exit = CGPoint(
                x: current.x + toNext.dx * inset,
                y: current.y + toNext.dy * inset
            )

            if started {
                path.addLine(to: entry)
            } else {
                path.move(to: entry)
                started = true
            }
            if inset > 0.01 {
                path.addQuadCurve(to: exit, control: current.point)
            } else {
                path.addLine(to: exit)
            }
        }
        path.closeSubpath()
        return path
    }
}
