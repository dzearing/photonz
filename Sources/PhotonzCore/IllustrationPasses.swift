import CoreGraphics
import Foundation

// Each pass of an illustration as a picture, and the checks each makes
// (`Illustrator`). Passes 3 to 5 are painted in grey, the way a value study
// is; colour comes in pass 6.

extension IllustrationWork {

    var paper: String { IllustrationPalette.paper }
    var inkColour: String { IllustrationPalette.ink }

    func passes() -> [IllustrationPass] {
        let checks = checksByPass()
        return Illustrator.passTitles.enumerated().map { index, title in
            IllustrationPass(number: index + 1, title: title, scene: scene(stage: index + 1), checks: checks[index] ?? [])
        }
    }

    /// Every check of every pass, flattened: what the critique reads.
    func critique() -> [IllustrationCheck] {
        let checks = checksByPass()
        return checks.keys.sorted().flatMap { checks[$0] ?? [] }
    }

    // MARK: Pictures

    func scene(stage: Int) -> IllustrationScene {
        var nodes: [IllustrationNode] = []
        let grey = stage < 6
        switch stage {
        case 1:
            nodes.append(.shape(frame.shape(named: "Frame", fill: .flat("#F4F4F6"), stroke: "#8E8E93", strokeWidth: 3)))
            return IllustrationScene(size: size, nodes: nodes)
        case 2:
            nodes.append(.shape(frame.shape(named: "Frame", fill: .flat("#FFFFFF"), stroke: "#8E8E93", strokeWidth: 3)))
            var blocks: [IllustrationNode] = []
            for plane in planes {
                blocks.append(.shape(IllustrationShape("\(plane.name) block", .rect(plane.block, radius: 0),
                                                       fill: .flat(IllustrationColor.alpha("#8E8E93", 0.08)),
                                                       stroke: "#8E8E93", strokeWidth: 2)))
            }
            nodes.append(.group("Blocking", blocks))
            nodes.append(.shape(.path("Horizon", IllustrationPath([CGPoint(x: 0, y: horizon), CGPoint(x: size.width, y: horizon)], closed: false),
                                      stroke: "#FF3B30", strokeWidth: 2)))
            nodes.append(.shape(IllustrationShape("Light", .ellipse(lightBox), stroke: "#FF9500", strokeWidth: 3)))
            let mark = CGRect(x: focal.x - 14, y: focal.y - 14, width: 28, height: 28)
            nodes.append(.shape(IllustrationShape("Focal point", .ellipse(mark), fill: .flat("#007AFF"))))
            return IllustrationScene(size: size, nodes: nodes).clipped(to: frame)
        case 3:
            nodes.append(.shape(frame.shape(named: "Sky", fill: .flat(IllustrationColor.grey(ink ? 1 : palette.horizonValue)))))
            nodes.append(.shape(IllustrationShape("Light", .ellipse(lightBox), fill: .flat(IllustrationColor.grey(0.97)))))
            for plane in planes {
                var mass = plane.block
                mass.origin.y += plane.block.height * 0.18
                mass.size.height = size.height + 20 - mass.minY
                let value = ink ? (plane.depth == 0 && style == .silhouette ? 1 : 0.1) : plane.value
                nodes.append(.shape(IllustrationShape(plane.name, .rect(mass, radius: 0), fill: .flat(IllustrationColor.grey(value)),
                                                      stroke: ink ? "#FFFFFF" : nil, strokeWidth: ink ? 4 : 0)))
            }
            return finish(nodes)
        default:
            break
        }
        // Passes 4 to 8: the forms.
        if !ink {
            nodes.append(.group("Sky", skyNodes(grey: grey, stage: stage)))
        } else if brief.badge {
            nodes.append(.shape(frame.shape(named: "Paper", fill: .flat(paper))))
        }
        nodes.append(.group(brief.time == .night ? "Moon" : "Sun", lightNodes(grey: grey, stage: stage)))
        if stage >= 7 { nodes += skyDetail() }
        let snow = stage >= 7 ? snowCaps() : []
        for (index, form) in forms.enumerated() {
            nodes.append(.group(form.plane.name, formNodes(form, index: index, grey: grey, stage: stage,
                                                           snow: snow.filter { $0.0 == index }.map(\.1))))
        }
        if stage >= 5, !ink, !castShadows.isEmpty {
            nodes.append(.group("Cast shadows", castShadows.enumerated().map { index, points in
                .shape(.path(castShadows.count == 1 ? "Cast shadow" : "Cast shadow \(index + 1)", IllustrationPath(points, smooth: true),
                             fill: .flat(grey ? "#000000" : palette.shadow), opacity: 0.32))
            }))
        }
        if vignette, stage >= 4 {
            let y = size.height * 0.9
            nodes.append(.shape(.path("Ground", IllustrationPath([CGPoint(x: size.width * 0.03, y: y), CGPoint(x: size.width * 0.97, y: y)], closed: false),
                                      stroke: inkColour, strokeWidth: 4.5)))
        }
        if !props.isEmpty {
            if stage >= 7 { nodes += beamNodes() }
            nodes.append(.group(brief.has(.fox) ? "Fox" : "Lighthouse", propNodes(grey: grey, stage: stage)))
        }
        if stage >= 7, !ink || style == .lineArt || style == .silhouette, brief.has(.birds) || brief.time != .night {
            var random = stream(900)
            let x = light.x > size.width / 2 ? light.x - lightRadius * 3.6 : light.x + lightRadius * 3.6
            var near = CGPoint(x: min(max(x, size.width * 0.14), size.width * 0.76),
                               y: min(max(light.y - lightRadius * 2.4, size.height * 0.14), horizon - size.height * 0.28))
            // Birds fly in clear sky: never across a cloud, the light or the lighthouse.
            func found(_ node: IllustrationNode) -> [CGRect] {
                switch node {
                case .shape(let shape): return shape.name == "Sun" || shape.name == "Moon" ? [shape.bounds] : []
                case .group(let name, let children):
                    if name.hasPrefix("Cloud ") { return [children.flatMap(\.shapes).reduce(CGRect.null) { $0.union($1.bounds) }] }
                    return children.flatMap(found)
                }
            }
            let busy = nodes.flatMap(found) + props.map(\.geometryBounds)
            let reach = size.width * 0.02
            var birds = IllustrationPieces.birds(near: near, size: reach, count: 3, random: &random)
            for _ in 0..<12 {
                let flock = birds.reduce(CGRect.null) { $0.union($1.bounds) }.insetBy(dx: -reach * 0.6, dy: -reach * 0.6)
                guard busy.contains(where: { $0.intersects(flock) }) else { break }
                near.y += reach * 1.5
                if near.y > horizon - reach * 3 { near = CGPoint(x: size.width - near.x, y: size.height * 0.14) }
                var again = stream(900)
                birds = IllustrationPieces.birds(near: near, size: reach, count: 3, random: &again)
            }
            let colour = ink || grey ? inkColour : IllustrationColor.relit(palette.near, to: 0.18)
            nodes.append(.group("Birds", birds.enumerated().map { index, bird in
                .shape(IllustrationShape("Bird \(index + 1)", .path([bird]), stroke: colour, strokeWidth: size.width * 0.0032))
            }))
        }
        return finish(nodes)
    }

    var lightBox: CGRect {
        CGRect(x: light.x - lightRadius, y: light.y - lightRadius, width: lightRadius * 2, height: lightRadius * 2)
    }

    /// Cut to the frame, with the badge's frame line on top.
    func finish(_ nodes: [IllustrationNode]) -> IllustrationScene {
        var scene = IllustrationScene(size: size, nodes: nodes).clipped(to: frame)
        if brief.badge, case .circle(let c, let inside) = frame {
            let line = ink ? inkColour : IllustrationColor.relit(palette.near, to: 0.12)
            // Ink badges carry a double ring: the scene inside the thin one, the heavy one outside it.
            let outer = ink ? inside + 22 : inside
            var rings: [IllustrationNode] = [.shape(IllustrationShape("Frame line", .ellipse(CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                                                                      stroke: line, strokeWidth: 12))]
            if ink {
                rings.append(.shape(IllustrationShape("Inner frame line", .ellipse(CGRect(x: c.x - inside, y: c.y - inside, width: inside * 2, height: inside * 2)),
                                                      stroke: line, strokeWidth: 3)))
            }
            scene.nodes.append(.group("Frame", rings))
        }
        return scene
    }

    // MARK: Sky and light

    func skyNodes(grey: Bool, stage: Int) -> [IllustrationNode] {
        let fill: IllustrationInk
        if grey {
            let top = IllustrationColor.grey(IllustrationColor.value(palette.sky.first?.hex ?? "#808080"))
            fill = .linear([GradientStop(hex: top, position: 0), GradientStop(hex: IllustrationColor.grey(palette.horizonValue), position: 1)], angle: 180)
        } else if style == .flat {
            let stops = palette.sky
            fill = .flat(stops[min(stops.count - 1, stops.count / 2)].hex)
        } else {
            fill = .linear(palette.sky, angle: 180)
        }
        var nodes: [IllustrationNode] = [.shape(frame.shape(named: "Sky", fill: fill))]
        return nodes
    }

    func lightNodes(grey: Bool, stage: Int) -> [IllustrationNode] {
        var nodes: [IllustrationNode] = []
        let r = lightRadius
        if stage >= 6, !ink {
            if style == .flat {
                for (index, scale) in [2.3, 1.6].enumerated() {
                    let big = r * CGFloat(scale)
                    nodes.append(.shape(IllustrationShape(index == 0 ? "Outer halo" : "Halo",
                                                          .ellipse(CGRect(x: light.x - big, y: light.y - big, width: big * 2, height: big * 2)),
                                                          fill: .flat(palette.glow), opacity: index == 0 ? 0.16 : 0.26)))
                }
            } else {
                let big = r * 4.2
                nodes.append(.shape(IllustrationShape("Glow", .ellipse(CGRect(x: light.x - big, y: light.y - big, width: big * 2, height: big * 2)),
                                                      fill: .radial([GradientStop(hex: IllustrationColor.alpha(palette.glow, 0.65), position: 0),
                                                                     GradientStop(hex: IllustrationColor.alpha(palette.glow, 0.24), position: 0.16),
                                                                     GradientStop(hex: IllustrationColor.alpha(palette.glow, 0.06), position: 0.36),
                                                                     GradientStop(hex: IllustrationColor.alpha(palette.glow, 0), position: 0.52)]))))
            }
        }
        let face: IllustrationInk?
        var stroke: String?
        var width: CGFloat = 0
        switch style {
        case .lineArt: face = .flat(paper); stroke = inkColour; width = 4.5
        case .silhouette: face = .flat(inkColour)
        default: face = .flat(grey ? IllustrationColor.grey(0.97) : palette.light)
        }
        nodes.append(.shape(IllustrationShape(brief.time == .night ? "Moon" : "Sun", .ellipse(lightBox), fill: face,
                                              stroke: stroke, strokeWidth: width)))
        if stage >= 7, ink {
            let rays = IllustrationPieces.rayBurst(center: light, inner: r * 1.4, outer: r * 2.7, count: 13,
                                                   from: .pi * 1.02, to: .pi * 1.98, width: r * 0.16)
            if style == .lineArt {
                // Line art keeps its weights: rays are interior lines.
                let lines = rays.map { ray -> IllustrationPath in
                    let p = ray.points
                    return IllustrationPath([CGPoint(x: (p[0].x + p[3].x) / 2, y: (p[0].y + p[3].y) / 2),
                                             CGPoint(x: (p[1].x + p[2].x) / 2, y: (p[1].y + p[2].y) / 2)], closed: false)
                }
                nodes.append(.shape(IllustrationShape("Rays", .path(lines), stroke: inkColour, strokeWidth: 3)))
            } else {
                nodes.append(.shape(IllustrationShape("Rays", .path(rays), fill: .flat(inkColour))))
            }
        }
        if stage >= 7, brief.time == .night, !ink {
            var random = stream(700)
            let craters = (0..<3).map { _ -> IllustrationPath in
                let c = CGPoint(x: light.x + random.signed() * r * 0.45, y: light.y + random.signed() * r * 0.45)
                let cr = r * random.range(0.08, 0.15)
                return IllustrationPath([CGPoint(x: c.x + cr, y: c.y), CGPoint(x: c.x, y: c.y + cr), CGPoint(x: c.x - cr, y: c.y),
                                         CGPoint(x: c.x, y: c.y - cr)], smooth: true)
            }
            nodes.append(.shape(IllustrationShape("Craters", .path(craters), fill: .flat(IllustrationColor.mix(palette.light, "#8A8670", 0.5)), opacity: 0.35)))
        }
        return nodes
    }

    func skyDetail() -> [IllustrationNode] {
        var nodes: [IllustrationNode] = []
        if brief.has(.city), !ink {
            // The city's own light, a glow low in the sky behind the towers.
            let band = CGRect(x: -20, y: horizon - size.height * 0.42, width: size.width + 40, height: size.height * 0.44)
            nodes.append(.shape(IllustrationShape("City glow", .rect(band, radius: 0),
                                                  fill: .linear([GradientStop(hex: IllustrationColor.alpha(palette.mist, 0), position: 0),
                                                                 GradientStop(hex: IllustrationColor.alpha(IllustrationColor.mix(palette.mist, palette.lamp, 0.25), 0.55), position: 1)], angle: 180))))
        }
        if brief.has(.stars) || brief.time == .night {
            var random = stream(800)
            let sky = CGRect(x: size.width * 0.03, y: size.height * 0.04, width: size.width * 0.94, height: horizon * 0.78)
            let stars = IllustrationPieces.stars(in: sky, count: 70, avoid: lightBox.insetBy(dx: -lightRadius * 1.5, dy: -lightRadius * 1.5),
                                                 random: &random)
            nodes.append(.shape(IllustrationShape("Stars", .path(stars), fill: .flat(ink ? inkColour : "#FFFFFF"), opacity: ink ? 1 : 0.85)))
        }
        if !ink, brief.time != .night || brief.has(.clouds) {
            var random = stream(810)
            let count = brief.has(.clouds) ? 4 : 3
            var clouds: [IllustrationNode] = []
            let lit = brief.time == .day ? palette.cloud : IllustrationColor.mix(palette.cloud, palette.glow, 0.3)
            for index in 0..<count where !(brief.has(.lighthouse) && index == 0) {
                // Streaks drift across the light, never over its face.
                let side: CGFloat = index % 2 == 0 ? -1 : 1
                let width = size.width * random.range(0.18, 0.3)
                // Wholly inside the picture: a streak cut by the edge reads as a mistake.
                let margin = width / 2 + size.width * 0.04
                let x = min(max(light.x + side * lightRadius * random.range(1.4, 3.2), margin), size.width - margin)
                let y = index < 3 ? light.y - lightRadius * (1.3 + CGFloat(index) * 0.75) : size.height * 0.16
                let points = IllustrationPieces.cloud(center: CGPoint(x: x, y: max(y, size.height * 0.08)), width: width, random: &random)
                let fill: IllustrationInk = style == .flat ? .flat(lit)
                    : .linear([GradientStop(hex: lit, position: 0.2), GradientStop(hex: IllustrationColor.mix(lit, palette.shadow, 0.2), position: 1)], angle: 180)
                // A cloud has a shaded underside and a lit top, not one flat lens.
                let under = points.map { CGPoint(x: $0.x + width * 0.04, y: $0.y + width * 0.018) }
                let shade = IllustrationColor.mix(lit, palette.shadow, 0.3)
                let top = points.map { CGPoint(x: x + ($0.x - x) * 0.72 - width * 0.05, y: $0.y - width * 0.012) }
                clouds.append(.group("Cloud \(index + 1)", [
                    .shape(.path("Underside", IllustrationPath(under, smooth: true, corners: [0, 3]), fill: .flat(shade),
                                 opacity: brief.time == .day ? 0.85 : 0.65)),
                    .shape(.path("Top", IllustrationPath(top, smooth: true, corners: [0, 3]), fill: fill,
                                 opacity: brief.time == .day ? 0.95 : 0.8)),
                ]))
            }
            nodes.append(.group("Clouds", clouds))
        }
        return nodes
    }

    // MARK: The planes

    func bodyInk(_ form: IllustrationForm, grey: Bool) -> (IllustrationInk?, String?, CGFloat) {
        let plane = form.plane
        switch style {
        case .lineArt:
            if plane.kind == .water { return (nil, nil, 0) }
            return (.flat(paper), inkColour, plane.depth == 0 ? 3 : 4.5)
        case .silhouette:
            if plane.kind == .water { return (.flat(paper), nil, 0) }
            return (.flat(inkColour), paper, plane.depth > 0.5 ? 6 : 5)
        default:
            break
        }
        if grey { return (.flat(IllustrationColor.grey(plane.value)), nil, 0) }
        let c = colour(plane)
        if plane.kind == .water {
            return (style == .flat ? .flat(palette.water[palette.water.count / 2].hex) : .linear(palette.water, angle: 180), nil, 0)
        }
        guard style != .flat else { return (.flat(c), nil, 0) }
        let haze = palette.mist
        switch plane.kind {
        case .range:
            return (.linear([GradientStop(hex: c, position: 0), GradientStop(hex: IllustrationColor.mix(c, haze, 0.22), position: 1)], angle: 180), nil, 0)
        case .band:
            return (.linear([GradientStop(hex: c, position: 0), GradientStop(hex: IllustrationColor.mix(c, haze, 0.25), position: 0.8)], angle: 180), nil, 0)
        case .hills where plane.depth < 0.5:
            return (.linear([GradientStop(hex: c, position: 0), GradientStop(hex: IllustrationColor.mix(c, haze, 0.3), position: 1)], angle: 180), nil, 0)
        case .hills, .cliff:
            let toward = light.x > size.width / 2 ? 90.0 : 270.0
            return (.linear([GradientStop(hex: IllustrationColor.mix(c, palette.shadow, 0.25), position: 0),
                             GradientStop(hex: IllustrationColor.mix(c, palette.highlight, 0.22), position: 1)], angle: toward), nil, 0)
        default:
            return (.flat(c), nil, 0)
        }
    }

    func formNodes(_ form: IllustrationForm, index: Int, grey: Bool, stage: Int, snow: [[CGPoint]]) -> [IllustrationNode] {
        let plane = form.plane
        var nodes: [IllustrationNode] = []
        let (fill, stroke, width) = bodyInk(form, grey: grey)
        let name: String
        switch plane.kind {
        case .range, .band: name = "Ridge"
        case .hills: name = "Slope"
        case .treeline: name = "Trees"
        case .water: name = "Water"
        case .cliff: name = "Rock"
        case .city: name = "Buildings"
        }
        if plane.kind == .treeline, style == .silhouette {
            // One black row, no outline round each tree.
            nodes.append(.shape(IllustrationShape(name, .path(form.outline), fill: .flat(inkColour))))
        } else if style == .silhouette, let ridge = form.ridge, plane.kind == .range || plane.kind == .band || plane.kind == .hills {
            // Solid ink, separated from the range behind by a paper line along
            // its ridge only, never along the edge the frame cut.
            nodes.append(.shape(IllustrationShape(name, .path(form.outline), fill: .flat(inkColour))))
            if plane.depth > 0 {
                nodes.append(.shape(IllustrationShape("\(name) edge", .path([IllustrationPath(ridge.points, closed: false)]),
                                                      stroke: paper, strokeWidth: 5)))
            }
        } else if style == .lineArt, plane.kind != .city {
            // Line art draws the top edge of a form, never the cut where it
            // meets the frame: paper to hide what is behind, a line along the top.
            nodes.append(.shape(IllustrationShape(name, .path(form.outline), fill: .flat(paper))))
            var lines: [IllustrationPath] = []
            if let ridge = form.ridge, plane.kind != .treeline { lines.append(IllustrationPath(ridge.points, closed: false)) }
            if plane.kind == .treeline {
                if let ground = form.outline.first?.points { lines.append(IllustrationPath(Array(ground.dropLast(2)), closed: false)) }
                lines += form.outline.dropFirst()
            }
            if plane.kind == .cliff, let rock = form.outline.first?.points { lines.append(IllustrationPath(Array(rock.dropFirst(1)), closed: false)) }
            nodes.append(.shape(IllustrationShape("\(name) line", .path(lines), stroke: inkColour, strokeWidth: width)))
        } else if fill != nil || stroke != nil {
            nodes.append(.shape(IllustrationShape(name, .path(form.outline), fill: fill, stroke: stroke, strokeWidth: width)))
        }
        let base = grey ? IllustrationColor.grey(plane.value) : colour(plane)
        let backlit = light.y > horizon - size.height * 0.3
        if plane.kind == .treeline, !ink, stage >= 5, backlit {
            // Rim light: a sliver along each tree's edge on the sun's side.
            var rims: [IllustrationPath] = []
            for tree in form.outline.dropFirst() {
                let box = tree.bounds
                guard box.height < size.height * 0.6 else { continue }
                let width = box.width * 0.22
                let strip = lightAway < 0 ? CGRect(x: box.maxX - width, y: box.minY - 1, width: width + 1, height: box.height * 0.8)
                    : CGRect(x: box.minX - 1, y: box.minY - 1, width: width + 1, height: box.height * 0.8)
                let clip = [CGPoint(x: strip.minX, y: strip.minY), CGPoint(x: strip.maxX, y: strip.minY),
                            CGPoint(x: strip.maxX, y: strip.maxY), CGPoint(x: strip.minX, y: strip.maxY)]
                let lit = IllustrationClip.polygon(tree.flattened(), to: clip)
                if lit.count >= 3 { rims.append(IllustrationPath(lit)) }
            }
            if !rims.isEmpty {
                let rim = IllustrationColor.mix(base, grey ? "#FFFFFF" : palette.glow, 0.35)
                nodes.append(.shape(IllustrationShape("Rim light", .path(rims), fill: .flat(rim), opacity: 0.85)))
            }
        }
        if plane.kind == .treeline, !ink, stage >= 5, backlit, nodes.count >= 1, case .shape(let trees) = nodes[0] {
            // A low sun behind the trees lights their tops, not one side.
            var lit = trees
            let rim = IllustrationColor.mix(base, grey ? "#FFFFFF" : palette.glow, 0.28)
            lit.fill = .linear([GradientStop(hex: rim, position: 0), GradientStop(hex: base, position: 0.45)], angle: 180)
            nodes[0] = .shape(lit)
        }
        if plane.kind == .treeline, !ink, stage >= 5, !backlit {
            // Each tree catches the light on one side.
            var halves: [IllustrationPath] = []
            for tree in form.outline.dropFirst() {
                let box = tree.bounds
                guard box.height < size.height * 0.6 else { continue }
                let toward: CGFloat = light.x < box.midX ? -1 : 1
                let half = toward < 0 ? CGRect(x: box.minX - 1, y: box.minY - 1, width: box.width / 2 + 1, height: box.height + 2)
                    : CGRect(x: box.midX, y: box.minY - 1, width: box.width / 2 + 1, height: box.height + 2)
                let clip = [CGPoint(x: half.minX, y: half.minY), CGPoint(x: half.maxX, y: half.minY),
                            CGPoint(x: half.maxX, y: half.maxY), CGPoint(x: half.minX, y: half.maxY)]
                let lit = IllustrationClip.polygon(tree.flattened(), to: clip)
                if lit.count >= 3 { halves.append(IllustrationPath(lit)) }
            }
            if !halves.isEmpty {
                let lit = IllustrationColor.mix(base, grey ? "#FFFFFF" : palette.highlight, style == .flat ? 0.2 : 0.3)
                nodes.append(.shape(IllustrationShape("Lit side", .path(halves), fill: .flat(lit))))
            }
        }
        if plane.kind == .treeline, !ink, stage >= 6, plane.depth < 0.9, let ground = form.outline.first?.points {
            // Haze settling at the foot of the row, between it and the next.
            let foot = ground.map(\.y).min() ?? plane.block.maxY
            let band = CGRect(x: -20, y: foot - plane.block.height * 0.55, width: size.width + 40, height: plane.block.height * 0.75)
            nodes.append(.shape(IllustrationShape("Mist", .rect(band, radius: 0),
                                                  fill: .linear([GradientStop(hex: IllustrationColor.alpha(palette.mist, 0), position: 0),
                                                                 GradientStop(hex: IllustrationColor.alpha(palette.mist, 0.5), position: 0.7),
                                                                 GradientStop(hex: IllustrationColor.alpha(palette.mist, 0), position: 1)], angle: 180))))
        }
        // Snow first under a glaze, last over opaque shadows.
        let snowInk: String = style == .silhouette ? paper : palette.snow
        func snowNodes() -> [IllustrationNode] {
            guard !snow.isEmpty, style != .lineArt else { return [] }
            // Negative space keeps the peak's line: a white cap is outlined in ink
            // so it does not melt into a white sky.
            return [.shape(IllustrationShape("Snow", .path(snow.map { IllustrationPath($0) }), fill: .flat(snowInk),
                                             stroke: style == .silhouette ? inkColour : nil, strokeWidth: style == .silhouette ? 3 : 0))]
        }
        let glaze = style == .painted || style == .sunset
        if glaze { nodes += snowNodes() }
        if stage >= 5, !form.shadows.isEmpty {
            switch style {
            case .lineArt:
                var lines: [IllustrationPath] = []
                for shadow in form.shadows {
                    lines += Self.hatching(shadow.face, peak: shadow.peak, away: shadow.away)
                }
                nodes.append(.shape(IllustrationShape("Shadow lines", .path(lines), stroke: inkColour, strokeWidth: 2.2)))
            case .silhouette:
                break
            case .flat:
                let tone = IllustrationColor.mix(base, grey ? "#000000" : palette.shadow, 0.34)
                nodes.append(.shape(IllustrationShape("Shadow face", .path(form.shadows.map { IllustrationPath($0.face) }), fill: .flat(tone))))
            default:
                // A glaze that fades toward the foot of the face, so no edge of it reads as a seam.
                let strength: CGFloat = plane.kind == .band ? 0.3 : 0.45
                let tone = grey ? "#000000" : palette.shadow
                let faces = form.shadows.map { shadow -> IllustrationNode in
                    .shape(.path("Shadow face", IllustrationPath(shadow.face),
                                 fill: .linear([GradientStop(hex: IllustrationColor.alpha(tone, strength), position: 0),
                                                GradientStop(hex: IllustrationColor.alpha(tone, strength * 0.85), position: 0.45),
                                                GradientStop(hex: IllustrationColor.alpha(tone, 0), position: 0.8)], angle: 180)))
                }
                nodes.append(contentsOf: faces)
            }
        }
        if !glaze { nodes += snowNodes() }
        if style == .lineArt, !snow.isEmpty {
            // The snow line alone: the ragged lower edge of each cap.
            let edges = snow.map { cap in IllustrationPath(Array(cap.suffix(6)), closed: false) }
            nodes.append(.shape(IllustrationShape("Snow line", .path(edges), stroke: inkColour, strokeWidth: 2.2)))
        }
        if stage >= 5, !form.highlights.isEmpty, style != .lineArt, plane.kind == .range {
            let ink: IllustrationInk = style == .silhouette ? .flat(paper) : .flat(grey ? "#FFFFFF" : palette.highlight)
            let opacity = style == .silhouette ? 1 : (style == .flat ? 0.3 : 0.26)
            if style != .silhouette {
                nodes.append(.shape(IllustrationShape("Ridge light", .path(form.highlights.map { IllustrationPath($0) }),
                                                      fill: ink, opacity: opacity)))
            }
        }
        if let skyline = form.skyline {
            if stage >= 5, !ink {
                let lit = IllustrationColor.mix(base, grey ? "#FFFFFF" : palette.highlight, 0.3)
                nodes.append(.shape(IllustrationShape("Lit sides", .path(skyline.lit), fill: .flat(lit))))
                let dark = IllustrationColor.mix(base, grey ? "#000000" : palette.shadow, 0.45)
                nodes.append(.shape(IllustrationShape("Shadow sides", .path(skyline.shade), fill: .flat(dark))))
            }
            if !skyline.antennas.isEmpty {
                nodes.append(.shape(IllustrationShape("Antennas", .path(skyline.antennas), stroke: ink ? inkColour : base, strokeWidth: 3)))
            }
            if stage >= 7, !skyline.windows.isEmpty {
                let lamp: IllustrationInk = .flat(style == .silhouette ? paper : (style == .lineArt ? inkColour : palette.lamp))
                let rings = skyline.windows.map { r in
                    IllustrationPath([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                                      CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
                }
                nodes.append(.shape(IllustrationShape("Windows", .path(rings), fill: lamp, opacity: ink ? 1 : 0.92)))
            }
        }
        if plane.kind == .water, stage >= 7 { nodes += waterDetail(plane, grey: grey) }
        if plane.kind == .cliff, stage >= 5, !ink { nodes += cliffDetail(form, base: base, grey: grey) }
        return nodes
    }

    /// Line art's shadow: strokes across a shadow face, from its crease
    /// toward its ridge.
    /// Line art's shadow, the way an engraver does it: the crease near the
    /// top, then even parallel strokes across the face, cut to it, thinning
    /// out toward its foot.
    static func hatching(_ face: [CGPoint], peak: CGPoint, away: CGFloat) -> [IllustrationPath] {
        guard face.count > 6 else { return [] }
        let split = face.count / 2
        let crease = Array(face[split...].reversed())
        var lines: [IllustrationPath] = [IllustrationPath(Array(crease.prefix(max(2, crease.count * 11 / 20))), closed: false)]
        let box = face.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        // Strokes slope down and away from the light, 14 points apart.
        let direction = CGPoint(x: away * 0.55, y: 1)
        let gap: CGFloat = 14
        var offset = -box.height
        while offset < box.width {
            let start = CGPoint(x: (away > 0 ? box.minX : box.maxX) + away * offset, y: box.minY)
            let end = CGPoint(x: start.x + direction.x * box.height * 1.2, y: start.y + direction.y * box.height * 1.2)
            for piece in IllustrationClip.inside(segment: (start, end), of: face) {
                // Only the upper part of the face is shaded: the strokes stop as it fades.
                let cut = box.minY + box.height * 0.6
                guard piece.0.y < cut else { continue }
                var b = piece.1
                if b.y > cut { let t = (cut - piece.0.y) / (b.y - piece.0.y); b = CGPoint(x: piece.0.x + (b.x - piece.0.x) * t, y: cut) }
                if hypot(b.x - piece.0.x, b.y - piece.0.y) > 10 { lines.append(IllustrationPath([piece.0, b], closed: false)) }
            }
            offset += gap
        }
        return lines
    }

    func waterDetail(_ plane: IllustrationPlane, grey: Bool) -> [IllustrationNode] {
        var nodes: [IllustrationNode] = []
        let top = plane.block.minY
        let water = CGRect(x: -20, y: top, width: size.width + 40, height: size.height + 20 - top)
        let box = [CGPoint(x: water.minX, y: water.minY), CGPoint(x: water.maxX, y: water.minY),
                   CGPoint(x: water.maxX, y: water.maxY), CGPoint(x: water.minX, y: water.maxY)]
        if !ink, let source = forms.last(where: { $0.reflects }) {
            let rings = source.outline.map { IllustrationClip.polygon(IllustrationPieces.reflected($0.flattened(), in: top), to: box) }
                .filter { $0.count >= 3 }.map { IllustrationPath($0) }
            if !rings.isEmpty {
                let tone = grey ? IllustrationColor.grey(source.plane.value) : colour(source.plane)
                nodes.append(.shape(IllustrationShape("Reflection", .path(rings), fill: .flat(tone), opacity: 0.45)))
            }
        }
        var random = stream(600)
        let lit = light.y < top
        let glitterX = light.x
        let reach = (water.maxY - top) * (lit ? 0.75 : 0.5)
        let lines = IllustrationPieces.glitter(under: glitterX, from: top + 8, to: top + (ink ? size.height * 0.07 : reach),
                                               width: ink ? size.width * 0.5 : lightRadius * 3.2,
                                               count: ink ? 4 : 11, random: &random)
        let glint = ink ? inkColour : (grey ? "#FFFFFF" : IllustrationColor.mix(palette.light, palette.glow, 0.3))
        nodes.append(.shape(IllustrationShape("Glitter", .path(lines), stroke: glint, strokeWidth: ink ? 5 : 4, opacity: ink ? 1 : 0.85)))
        if !ink {
            let ripples = IllustrationPieces.ripples(in: CGRect(x: 0, y: top + 10, width: size.width, height: water.height * 0.7),
                                                     count: 26, random: &random)
            nodes.append(.shape(IllustrationShape("Ripples", .path(ripples), stroke: grey ? "#FFFFFF" : palette.highlight,
                                                  strokeWidth: 2.2, opacity: 0.3)))
        }
        if brief.has(.city), !ink {
            // The city's lights run down into the river.
            var strokes: [IllustrationPath] = []
            for column in stride(from: size.width * 0.05, to: size.width * 0.95, by: size.width * 0.045) {
                let jitter = random.signed() * 10
                for row in 0..<4 where random.unit() < 0.6 {
                    let y = top + 10 + CGFloat(row) * 16 + random.range(0, 6)
                    let half = random.range(4, 14)
                    strokes.append(IllustrationPath([CGPoint(x: column + jitter - half, y: y), CGPoint(x: column + jitter + half, y: y)], closed: false))
                }
            }
            nodes.append(.shape(IllustrationShape("Light trails", .path(strokes), stroke: grey ? "#FFFFFF" : palette.lamp,
                                                  strokeWidth: 3, opacity: 0.55)))
        }
        return nodes
    }

    func cliffDetail(_ form: IllustrationForm, base: String, grey: Bool) -> [IllustrationNode] {
        guard let top = form.ridge?.points else { return [] }
        let block = form.plane.block
        // A cap of grass along the top, and cracks across the face.
        var grassLine = top.map { CGPoint(x: $0.x, y: $0.y - 2) }
        grassLine += top.reversed().map { CGPoint(x: $0.x, y: $0.y + block.height * 0.05) }
        let green = IllustrationColor.mix("#5E7A4A", palette.shadow, brief.time == .day ? 0.1 : 0.35)
        let grass = grey ? IllustrationColor.grey(IllustrationColor.value(green)) : green
        var nodes: [IllustrationNode] = []
        // Rock in planes.
        if let rock = form.outline.first?.points, rock.count > 6 {
            // The face runs from the cliff's front corner down to the sea.
            let face = Array(rock.suffix(7))
            func faceX(_ y: CGFloat) -> CGFloat {
                if let first = face.first, y <= first.y { return first.x + 12 }
                for index in 0..<(face.count - 1) where (face[index].y - y) * (face[index + 1].y - y) <= 0 {
                    let a = face[index], b = face[index + 1]
                    let t = b.y == a.y ? 0 : (y - a.y) / (b.y - a.y)
                    return a.x + (b.x - a.x) * t
                }
                return face.last?.x ?? block.minX
            }
            var random = stream(510)
            // The face the low sun falls on: a lit band down the cliff's front,
            // its inner edge broken like rock, and vertical joints in the stone.
            let bottomY = size.height + 20
            var lit: [CGPoint] = []
            var inner: [CGPoint] = []
            var y = (face.first?.y ?? block.minY) + 4
            while y <= bottomY {
                let x = faceX(y)
                lit.append(CGPoint(x: x + 2, y: y))
                inner.append(CGPoint(x: x + block.width * random.range(0.16, 0.26), y: y))
                y += block.height * 0.06
            }
            let band = lit + inner.reversed()
            var joints: [IllustrationPath] = []
            for step in 1...4 {
                let offset = block.width * (0.12 + CGFloat(step) * 0.11)
                var line: [CGPoint] = []
                var jy = (face.first?.y ?? block.minY) + block.height * random.range(0.06, 0.2)
                while jy < bottomY {
                    line.append(CGPoint(x: faceX(jy) + offset + random.signed() * 6, y: jy))
                    jy += block.height * 0.1
                }
                if line.count >= 2 { joints.append(IllustrationPath(line, closed: false)) }
            }
            let ledge = IllustrationColor.mix(base, grey ? "#FFFFFF" : palette.highlight, 0.3)
            let crack = IllustrationColor.mix(base, grey ? "#000000" : palette.shadow, 0.45)
            let toward: Double = light.x < block.midX ? 90 : 270
            nodes.append(.shape(IllustrationShape("Lit face", .path([IllustrationPath(band, smooth: true)]),
                                                  fill: .linear([GradientStop(hex: IllustrationColor.alpha(ledge, 0.9), position: 0),
                                                                 GradientStop(hex: IllustrationColor.alpha(ledge, 0), position: 1)], angle: toward))))
            _ = joints
            _ = crack
        }
        nodes.append(.shape(.path("Grass", IllustrationPath(grassLine, smooth: true), fill: .flat(grass))))
        return nodes
    }

    // MARK: Props

    func propColour(_ part: IllustrationPieces.Part) -> String {
        let fox = brief.has(.fox)
        switch part.role {
        case .wall: return fox ? "#E2732C" : "#F1EBE0"
        case .stripe: return "#C8463D"
        case .dark: return "#2A2B33"
        case .lamp: return palette.lamp
        case .glass: return "#BFD8E8"
        case .roof: return fox ? "#2A1B16" : "#8E2F2A"
        case .white: return "#F6EFE6"
        case .body: return "#DD6F2A"
        case .shade: return palette.shadow
        case .ink: return "#2A1B16"
        }
    }

    func propNodes(grey: Bool, stage: Int) -> [IllustrationNode] {
        props.map { part in
            switch style {
            case .lineArt:
                let filled = part.role == .ink || part.role == .dark || part.role == .stripe
                return .shape(IllustrationShape(part.name, part.geometry, fill: .flat(filled ? inkColour : paper),
                                                stroke: inkColour, strokeWidth: 3.5))
            case .silhouette:
                let negative = part.role == .white || part.role == .lamp || part.role == .wall
                return .shape(IllustrationShape(part.name, part.geometry, fill: .flat(negative ? paper : inkColour),
                                                stroke: negative ? inkColour : nil, strokeWidth: negative ? 3 : 0))
            default:
                break
            }
            let c = propColour(part)
            let flatColour = grey ? IllustrationColor.grey(IllustrationColor.value(c)) : c
            let shaded = [.wall, .stripe, .body, .white, .roof].contains(part.role)
            guard stage >= 5, shaded, style != .flat || stage >= 5 else {
                return .shape(IllustrationShape(part.name, part.geometry, fill: .flat(flatColour)))
            }
            // Lit on the side toward the light, in shadow on the other.
            let toward = light.x < (part.geometryBounds.midX) ? 270.0 : 90.0
            let lit = IllustrationColor.mix(flatColour, grey ? "#FFFFFF" : palette.highlight, 0.18)
            let shade = IllustrationColor.mix(flatColour, grey ? "#000000" : palette.shadow, 0.38)
            if style == .flat {
                return .shape(IllustrationShape(part.name, part.geometry, fill: .flat(flatColour)))
            }
            return .shape(IllustrationShape(part.name, part.geometry,
                                            fill: .linear([GradientStop(hex: shade, position: 0.1), GradientStop(hex: flatColour, position: 0.55),
                                                           GradientStop(hex: lit, position: 1)], angle: toward)))
        }
    }

    /// The lamp's beams and glow, at dusk and night.
    func beamNodes() -> [IllustrationNode] {
        guard brief.has(.lighthouse), brief.time == .dusk || brief.time == .night, !ink,
              let room = props.first(where: { $0.role == .lamp && $0.name == "Lamp room" }) else { return [] }
        let lamp = CGPoint(x: room.geometryBounds.midX, y: room.geometryBounds.midY)
        let spread = size.height * 0.07
        let left = [lamp, CGPoint(x: -20, y: lamp.y - spread * 1.4), CGPoint(x: -20, y: lamp.y + spread * 1.4)]
        let right = [lamp, CGPoint(x: size.width + 20, y: lamp.y - spread), CGPoint(x: size.width + 20, y: lamp.y + spread)]
        let beam = IllustrationColor.alpha(palette.lamp, 0.55)
        let fade = IllustrationColor.alpha(palette.lamp, 0)
        let glowSize = size.width * 0.07
        return [.group("Beams", [
            .shape(.path("Beam left", IllustrationPath(left), fill: .linear([GradientStop(hex: fade, position: 0), GradientStop(hex: beam, position: 1)], angle: 90))),
            .shape(.path("Beam right", IllustrationPath(right), fill: .linear([GradientStop(hex: beam, position: 0), GradientStop(hex: fade, position: 1)], angle: 90))),
            .shape(IllustrationShape("Lamp glow", .ellipse(CGRect(x: lamp.x - glowSize, y: lamp.y - glowSize, width: glowSize * 2, height: glowSize * 2)),
                                     fill: .radial([GradientStop(hex: IllustrationColor.alpha(palette.lamp, 0.8), position: 0),
                                                    GradientStop(hex: IllustrationColor.alpha(palette.lamp, 0), position: 0.5)]))),
        ])]
    }

    func grass() -> IllustrationNode {
        var random = stream(950)
        var blades: [IllustrationPath] = []
        for _ in 0..<26 {
            let x = size.width * random.range(0.04, 0.96)
            let y = size.height * random.range(0.86, 0.99)
            let h = size.height * random.range(0.025, 0.05)
            blades.append(IllustrationPath([CGPoint(x: x, y: y), CGPoint(x: x + random.signed() * 6, y: y - h / 2),
                                            CGPoint(x: x + random.signed() * 10, y: y - h)], closed: false, smooth: true))
        }
        let colour = ink ? inkColour : IllustrationColor.mix(palette.grass, palette.highlight, 0.25)
        return .shape(IllustrationShape("Grass", .path(blades), stroke: colour, strokeWidth: 3, opacity: ink ? 1 : 0.8))
    }

    // MARK: Checks

    func checksByPass() -> [Int: [IllustrationCheck]] {
        var checks: [Int: [IllustrationCheck]] = [:]
        checks[0] = [IllustrationCheck(name: "brief", passed: !brief.elements.isEmpty,
                                       detail: "\(brief.style.title)\(brief.badge ? " badge" : ""), \(brief.time.rawValue), \(brief.elements.map(\.rawValue).joined(separator: ", "))\(brief.styleNamed ? "" : " (style picked)")")]
        let offCentre = abs(focal.x - size.width / 2) >= size.width * 0.08
        let horizonOff = abs(horizon - size.height / 2) >= size.height * 0.08
        checks[1] = [
            IllustrationCheck(name: "focal", passed: offCentre, detail: "focal point at \(Int(focal.x / size.width * 100))% across"),
            IllustrationCheck(name: "horizon", passed: horizonOff, detail: "horizon at \(Int(horizon / size.height * 100))% down"),
            IllustrationCheck(name: "planes", passed: planes.count >= 3, detail: "\(planes.count) planes"),
        ]
        // Values: nearest darkest, steps a squint can tell apart.
        let land = planes.filter { $0.kind != .water }.sorted { $0.depth < $1.depth }
        let values = land.map(\.value)
        let stepped = zip(values, values.dropFirst()).allSatisfy { $0 - $1 >= 0.05 }
        checks[2] = [IllustrationCheck(name: "values", passed: ink || stepped,
                                       detail: values.map { String(format: "%.2f", Double($0)) }.joined(separator: " > "))]
        // Shape: lopsided peaks and broken ridges.
        var lopsided = true
        for form in forms where form.plane.kind == .range {
            guard let ridge = form.ridge else { continue }
            for peak in ridge.peaks {
                let left = ridge.valleys.last { $0 < peak }.map { ridge.points[peak].x - ridge.points[$0].x }
                let right = ridge.valleys.first { $0 > peak }.map { ridge.points[$0].x - ridge.points[peak].x }
                if let left, let right, abs(left - right) / max(left, right) < 0.1 { lopsided = false }
            }
        }
        let broken = forms.filter { $0.plane.kind == .range || $0.plane.kind == .band }.allSatisfy { ($0.ridge?.points.count ?? 0) > 40 }
        checks[3] = [IllustrationCheck(name: "silhouette", passed: lopsided && broken,
                                       detail: lopsided ? "peaks lopsided, ridgelines broken" : "two slopes of a peak are the same length")]
        // Light: every shadow face is on the side away from the light.
        let faces = forms.flatMap(\.shadows)
        let agrees = faces.allSatisfy { shadow in
            let middle = shadow.face.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(max(1, shadow.face.count))
            return (middle - shadow.peak.x) * shadow.away > 0 && shadow.away == lightAway
        }
        checks[4] = [IllustrationCheck(name: "light", passed: agrees, detail: "\(faces.count) shadow faces, all away from the light: \(agrees)")]
        // Colour: distance is lighter; the sky stands out from the far plane.
        let colours = land.map { colour($0) }
        let measured = colours.map(IllustrationColor.value)
        let distance = zip(measured, measured.dropFirst()).allSatisfy { $0 > $1 }
        let squint = ink || (palette.horizonValue - (measured.first ?? 0)) >= 0.06
        checks[5] = [
            IllustrationCheck(name: "values", passed: ink || distance, detail: "colours read " + measured.map { String(format: "%.2f", Double($0)) }.joined(separator: " > ")),
            IllustrationCheck(name: "squint", passed: squint, detail: String(format: "sky %.2f against the far plane %.2f", Double(palette.horizonValue), Double(measured.first ?? 0))),
        ]
        // Finish: nothing past the frame.
        let finished = scene(stage: 7)
        let edge = frame.bounds.insetBy(dx: -8, dy: -8)
        let inside = finished.shapes.filter { !$0.name.hasSuffix("rame line") }.allSatisfy { shape in
            let box = shape.bounds
            return box.isNull || edge.contains(box.insetBy(dx: shape.strokeWidth / 2, dy: shape.strokeWidth / 2))
        }
        checks[6] = [IllustrationCheck(name: "frame", passed: inside, detail: inside ? "everything inside the frame" : "a shape pokes past the frame")]
        // Thumbnail: the focus is big enough to read at 32 points.
        let focusSize = max(lightRadius * 2, props.reduce(CGRect.null) { $0.union($1.geometryBounds) }.height)
        let readsSmall = focusSize / size.width >= 0.08
        checks[7] = [IllustrationCheck(name: "thumbnail", passed: readsSmall,
                                       detail: "the focus is \(Int(focusSize / size.width * 100))% of the frame")]
        return checks
    }
}

extension IllustrationPieces.Part {
    var geometryBounds: CGRect { IllustrationShape(name, geometry).bounds }
}
