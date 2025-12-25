//
//  RealityKitMazeView.swift
//  RecastNavigationExample
//
//  Created by Tatsuya Ogawa on 2025/12/24.
//

import SwiftUI
import UIKit
import RealityKit
import Combine
import simd
import RecastNavigationKit

struct MazeRealityView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)

        context.coordinator.setupScene(in: arView)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
//        tap.numberOfTouchesRequired = 2
        arView.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pinch)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

final class Coordinator: NSObject {
    private weak var arView: ARView?
    private var updateCancellable: Cancellable?

    private var navMesh: RecastNavMesh?
    private var rootAnchor: AnchorEntity?
    private var navMeshDebug: ModelEntity?
    private var character: ModelEntity?
    private var camera: PerspectiveCamera?
    private var targetMarker: ModelEntity?
    private var targetMarkerBase: SIMD3<Float>?
    private var markerTime: Float = 0
    private var pathPoints: [SIMD3<Float>] = []
    private var pathIndex: Int = 0

    private let sphereRadius: Float = 0.06
    private let speed: Float = 0.5
    private var orbitYaw: Float = 0
    private var orbitPitch: Float = 0
    private var orbitDistance: Float = 5.0
    private let orbitTarget = SIMD3<Float>(0, 0, 0)

    private let cellSize: Float = 0.45
    private let wallThickness: Float = 0.05
    private let wallHeight: Float = 0.25
    private let upperFloorY: Float = 0.4
    private let mazeSize = (width: 9, height: 9)

    func setupScene(in arView: ARView) {
        self.arView = arView

        let anchor = AnchorEntity(world: .zero)
        rootAnchor = anchor
        arView.scene.addAnchor(anchor)

        // Camera
        let camera = PerspectiveCamera()
        camera.position = [0, 4.5, 2.0]
        camera.look(at: orbitTarget, from: camera.position, relativeTo: nil)
        anchor.addChild(camera)
        self.camera = camera
        let toCam = camera.position - orbitTarget
        orbitDistance = simd_length(toCam)
        orbitYaw = atan2f(toCam.x, toCam.z)
        orbitPitch = atan2f(toCam.y, sqrtf(toCam.x * toCam.x + toCam.z * toCam.z))
        updateCamera()

        // Light
        let light = DirectionalLight()
        light.light.intensity = 5000
        light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        anchor.addChild(light)

        // Build maze geometry
        let maze = MazeGenerator(width: mazeSize.width,
                                 height: mazeSize.height,
                                 cellSize: cellSize,
                                 wallThickness: wallThickness,
                                 wallHeight: wallHeight,
                                 seed: 0xC0FFEE)

        let floorSize = SIMD2<Float>(Float(mazeSize.width) * cellSize,
                                     Float(mazeSize.height) * cellSize)
        let floorEntity = ModelEntity(mesh: .generatePlane(width: floorSize.x, depth: floorSize.y),
                                materials: [SimpleMaterial(color: UIColor.darkGray, isMetallic: false)])
        floorEntity.position = [0, 0, 0]
        floorEntity.generateCollisionShapes(recursive: true)
        anchor.addChild(floorEntity)

        let upperFloorOffsetX: Float = floorSize.x * 0.6
        let rampLength = cellSize * 3.0
        let rampWidth = cellSize * 0.8
        let rampHeight = upperFloorY
        let rampOrigin = SIMD3<Float>(maze.origin.x + cellSize * 2.0 + upperFloorOffsetX,
                                      0,
                                      maze.origin.z + cellSize * 2.0)
        let rampMinX = rampOrigin.x - rampLength * 0.5 - wallThickness
        let rampMaxX = rampOrigin.x + rampLength * 0.5 + wallThickness
        let rampMinZ = rampOrigin.z - rampWidth * 0.5 - wallThickness
        let rampMaxZ = rampOrigin.z + rampWidth * 0.5 + wallThickness

        func wallIntersectsRamp(_ wall: MazeGenerator.WallBox, xOffset: Float = 0) -> Bool {
            let wallMinX = (wall.center.x + xOffset) - wall.size.x * 0.5
            let wallMaxX = (wall.center.x + xOffset) + wall.size.x * 0.5
            let wallMinZ = wall.center.z - wall.size.z * 0.5
            let wallMaxZ = wall.center.z + wall.size.z * 0.5
            return !(wallMaxX < rampMinX || wallMinX > rampMaxX ||
                     wallMaxZ < rampMinZ || wallMinZ > rampMaxZ)
        }

        func addUpperFloorPiece(centerX: Float, centerZ: Float, width: Float, depth: Float) {
            if width <= 0 || depth <= 0 { return }
            let piece = ModelEntity(mesh: .generatePlane(width: width, depth: depth),
                                    materials: [SimpleMaterial(color: UIColor(white: 0.18, alpha: 1.0),
                                                               isMetallic: false)])
            piece.position = [centerX, upperFloorY, centerZ]
            piece.generateCollisionShapes(recursive: true)
            anchor.addChild(piece)
        }

        let floorHalfX = floorSize.x * 0.5
        let floorHalfZ = floorSize.y * 0.5
        let upperMinX = -floorHalfX + upperFloorOffsetX
        let upperMaxX = floorHalfX + upperFloorOffsetX

        // Upper floor pieces around the ramp footprint.
        addUpperFloorPiece(centerX: (rampMinX + upperMinX) * 0.5,
                           centerZ: 0,
                           width: rampMinX - upperMinX,
                           depth: floorSize.y)
        addUpperFloorPiece(centerX: (upperMaxX + rampMaxX) * 0.5,
                           centerZ: 0,
                           width: upperMaxX - rampMaxX,
                           depth: floorSize.y)
        addUpperFloorPiece(centerX: (rampMinX + rampMaxX) * 0.5,
                           centerZ: (rampMinZ + (-floorHalfZ)) * 0.5,
                           width: rampMaxX - rampMinX,
                           depth: rampMinZ - (-floorHalfZ))
        addUpperFloorPiece(centerX: (rampMinX + rampMaxX) * 0.5,
                           centerZ: (floorHalfZ + rampMaxZ) * 0.5,
                           width: rampMaxX - rampMinX,
                           depth: floorHalfZ - rampMaxZ)

        for wall in maze.wallBoxes(origin: maze.origin) {
            if wallIntersectsRamp(wall) { continue }
            let wallEntity = ModelEntity(mesh: .generateBox(size: wall.size),
                                         materials: [SimpleMaterial(color: UIColor.gray, isMetallic: false)])
            wallEntity.position = wall.center
            anchor.addChild(wallEntity)
        }

        for wall in maze.wallBoxes(origin: maze.origin) {
            if wallIntersectsRamp(wall, xOffset: upperFloorOffsetX) { continue }
            let upperCenter = SIMD3<Float>(wall.center.x,
                                           wall.center.y + upperFloorY,
                                           wall.center.z)
            let offsetUpperCenter = SIMD3<Float>(upperCenter.x + upperFloorOffsetX,
                                                 upperCenter.y,
                                                 upperCenter.z)
            let wallEntity = ModelEntity(mesh: .generateBox(size: wall.size),
                                         materials: [SimpleMaterial(color: UIColor.gray, isMetallic: false)])
            wallEntity.position = offsetUpperCenter
            anchor.addChild(wallEntity)
        }

        if let rampMesh = GeometryBuilder.makeRampSurfaceMesh(length: rampLength,
                                                              width: rampWidth,
                                                              height: rampHeight) {
            let rampEntity = ModelEntity(mesh: rampMesh,
                                         materials: [SimpleMaterial(color: UIColor.brown, isMetallic: false)])
            rampEntity.position = rampOrigin
            anchor.addChild(rampEntity)
        }

        let sphere = ModelEntity(mesh: .generateSphere(radius: sphereRadius),
                                 materials: [SimpleMaterial(color: UIColor.red, isMetallic: false)])
        sphere.position = [maze.origin.x + cellSize * 0.5, sphereRadius, maze.origin.z + cellSize * 0.5]
        anchor.addChild(sphere)
        character = sphere

        // Build navmesh from the same geometry
        var vertices: [Float] = []
        var indices: [Int32] = []

        GeometryBuilder.appendPlane(centerY: 0,
                                    size: floorSize,
                                    vertices: &vertices,
                                    indices: &indices)
        GeometryBuilder.appendPlane(center: SIMD3<Float>((rampMinX + upperMinX) * 0.5,
                                                         upperFloorY,
                                                         0),
                                    size: SIMD2<Float>(rampMinX - upperMinX, floorSize.y),
                                    vertices: &vertices,
                                    indices: &indices)
        GeometryBuilder.appendPlane(center: SIMD3<Float>((upperMaxX + rampMaxX) * 0.5,
                                                         upperFloorY,
                                                         0),
                                    size: SIMD2<Float>(upperMaxX - rampMaxX, floorSize.y),
                                    vertices: &vertices,
                                    indices: &indices)
        GeometryBuilder.appendPlane(center: SIMD3<Float>((rampMinX + rampMaxX) * 0.5,
                                                         upperFloorY,
                                                         (rampMinZ + (-floorHalfZ)) * 0.5),
                                    size: SIMD2<Float>(rampMaxX - rampMinX,
                                                       rampMinZ - (-floorHalfZ)),
                                    vertices: &vertices,
                                    indices: &indices)
        GeometryBuilder.appendPlane(center: SIMD3<Float>((rampMinX + rampMaxX) * 0.5,
                                                         upperFloorY,
                                                         (floorHalfZ + rampMaxZ) * 0.5),
                                    size: SIMD2<Float>(rampMaxX - rampMinX,
                                                       floorHalfZ - rampMaxZ),
                                    vertices: &vertices,
                                    indices: &indices)

        for wall in maze.wallBoxes(origin: maze.origin) {
            if wallIntersectsRamp(wall) { continue }
            GeometryBuilder.appendBox(center: wall.center,
                                      size: wall.size,
                                      vertices: &vertices,
                                      indices: &indices)
        }
        for wall in maze.wallBoxes(origin: maze.origin) {
            if wallIntersectsRamp(wall, xOffset: upperFloorOffsetX) { continue }
            let upperCenter = SIMD3<Float>(wall.center.x,
                                           wall.center.y + upperFloorY,
                                           wall.center.z)
            let offsetUpperCenter = SIMD3<Float>(upperCenter.x + upperFloorOffsetX,
                                                 upperCenter.y,
                                                 upperCenter.z)
            GeometryBuilder.appendBox(center: offsetUpperCenter,
                                      size: wall.size,
                                      vertices: &vertices,
                                      indices: &indices)
        }

        GeometryBuilder.appendRampTop(origin: rampOrigin,
                                      length: rampLength,
                                      width: rampWidth,
                                      height: rampHeight,
                                      vertices: &vertices,
                                      indices: &indices)

        let agentHeight: Float = 0.2
        let agentClimb: Float = 0.1
        let config = RCNavMeshConfig.defaultConfig(withAgentHeight: agentHeight,
                                                   radius: sphereRadius,
                                                   climb: agentClimb)
        // Use finer voxels so thin walls don't wipe walkable spans.
        config.cellSize = 0.05
        config.cellHeight = 0.05
        config.walkableHeight = Int32(Int(ceil(agentHeight / config.cellHeight)))
        config.walkableClimb = Int32(Int(floor(agentClimb / config.cellHeight)))
        config.walkableRadius = Int32(Int(ceil(sphereRadius / config.cellSize)))
        // Debug-friendly params: avoid eroding everything while tuning
        config.walkableRadius = 0
        config.minRegionArea = 0
        config.mergeRegionArea = 0

        var buildError: NSError?
        navMesh = RCNavMeshBuilder.buildNavMesh(withVertices: vertices,
                                                vertexCount: Int32(vertices.count / 3),
                                                indices: indices,
                                                indexCount: Int32(indices.count),
                                                config: config,
                                                error: &buildError)
        if let err = buildError {
            assertionFailure("NavMesh build failed: \(err)")
            navMesh = nil
        }

        guard navMesh != nil else {
            fatalError("Unable to build navmesh")
        }

        buildNavMeshDebug()

        updateCancellable = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.update(deltaTime: Float(event.deltaTime))
        }
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        let location = recognizer.location(in: arView)

        guard let ray = arView.ray(through: location) else { return }
        let hits = arView.scene.raycast(origin: ray.origin,
                                        direction: ray.direction,
                                        length: 10,
                                        query: .nearest)
        guard let hit = hits.first else { return }

        let target = hit.position
        placeTargetMarker(at: target)
        guard let character = character, let navMesh = navMesh else { return }

        let start = character.position(relativeTo: nil)
        guard let path = navMesh.findPathResult(from: start, to: target) else {
            pathPoints = []
            pathIndex = 0
            return
        }

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(Int(path.pointCount))
        for p in path.points() {
            points.append(SIMD3<Float>(p.x, p.y + sphereRadius, p.z))
        }

        if points.isEmpty {
            pathPoints = []
            pathIndex = 0
            return
        }

        pathPoints = points
        pathIndex = 0
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let arView = arView else { return }
        let delta = recognizer.translation(in: arView)
        recognizer.setTranslation(.zero, in: arView)

        orbitYaw -= Float(delta.x) * 0.005
        orbitPitch -= Float(delta.y) * 0.005
        orbitPitch = clamp(orbitPitch, min: -1.2, max: 1.2)
        updateCamera()
    }

    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let scale = Float(recognizer.scale)
        if scale != 0 {
            orbitDistance = orbitDistance / scale
            orbitDistance = clamp(orbitDistance, min: 1.5, max: 12.0)
            recognizer.scale = 1.0
            updateCamera()
        }
    }

    private func update(deltaTime: Float) {
        guard let character = character else { return }
        guard pathIndex < pathPoints.count else { return }

        let target = pathPoints[pathIndex]
        var pos = character.position(relativeTo: nil)

        let toTarget = target - pos
        let dist = simd_length(toTarget)

        if dist < 0.02 {
            pathIndex += 1
            return
        }

        let step = min(speed * deltaTime, dist)
        pos += simd_normalize(toTarget) * step
        character.position = pos

        if let marker = targetMarker, let base = targetMarkerBase {
            markerTime += deltaTime
            let float = sinf(markerTime * 2.5) * 0.02
            let pulse = 1.0 + 0.15 * sinf(markerTime * 3.5)
            marker.position = [base.x, base.y + float + 0.2, base.z]
            marker.scale = [pulse, pulse, pulse]
            marker.orientation = simd_quatf(angle: markerTime * 1.6, axis: [0, 1, 0])
        }
    }

    private func placeTargetMarker(at position: SIMD3<Float>) {
        guard let anchor = rootAnchor else { return }
        let base = SIMD3<Float>(position.x, position.y, position.z)

        if targetMarker == nil {
            let mesh = MeshResource.generateSphere(radius: 0.045)
            let material = SimpleMaterial(color: UIColor.systemTeal.withAlphaComponent(0.9),
                                           isMetallic: true)
            let marker = ModelEntity(mesh: mesh, materials: [material])
            targetMarker = marker
            anchor.addChild(marker)
        }

        targetMarker?.position = base
        targetMarkerBase = base
        markerTime = 0
    }

    private func updateCamera() {
        guard let camera = camera else { return }
        let cosPitch = cosf(orbitPitch)
        let sinPitch = sinf(orbitPitch)
        let sinYaw = sinf(orbitYaw)
        let cosYaw = cosf(orbitYaw)

        let x = orbitTarget.x + orbitDistance * cosPitch * sinYaw
        let z = orbitTarget.z + orbitDistance * cosPitch * cosYaw
        let y = orbitTarget.y + orbitDistance * sinPitch

        camera.position = [x, y, z]
        camera.look(at: orbitTarget, from: camera.position, relativeTo: nil)
    }

    private func clamp(_ value: Float, min: Float, max: Float) -> Float {
        if value < min { return min }
        if value > max { return max }
        return value
    }

    private func buildNavMeshDebug() {
        guard let navMesh = navMesh, let anchor = rootAnchor else { return }

        var vertexCount: Int32 = 0
        let data = navMesh.navMeshTriangleVertices(withVertexCount: &vertexCount)
        if vertexCount <= 0 || data.isEmpty { return }

        let positions: [SIMD3<Float>] = data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            let count = min(Int(vertexCount), floats.count / 3)
            var out: [SIMD3<Float>] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                let base = i * 3
                out.append(SIMD3<Float>(floats[base], floats[base + 1], floats[base + 2]))
            }
            return out
        }

        var desc = MeshDescriptor()
        desc.positions = MeshBuffer(positions)
        let indices = (0..<positions.count).map { UInt32($0) }
        desc.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [desc]) else { return }

        let material = SimpleMaterial(color: UIColor.green.withAlphaComponent(0.35),
                                      isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position.y += 0.005

        navMeshDebug?.removeFromParent()
        navMeshDebug = entity
        anchor.addChild(entity)
    }
}

private struct MazeGenerator {
    struct WallBox {
        let center: SIMD3<Float>
        let size: SIMD3<Float>
    }

    private let width: Int
    private let height: Int
    private let cellSize: Float
    private let wallThickness: Float
    private let wallHeight: Float
    let origin: SIMD3<Float>

    private var walls: [UInt8]

    init(width: Int, height: Int, cellSize: Float, wallThickness: Float, wallHeight: Float, seed: UInt64) {
        self.width = width
        self.height = height
        self.cellSize = cellSize
        self.wallThickness = wallThickness
        self.wallHeight = wallHeight
        self.origin = [-Float(width) * cellSize / 2, 0, -Float(height) * cellSize / 2]

        self.walls = Array(repeating: 0b1111, count: width * height)
        generate(seed: seed)
    }

    mutating private func generate(seed: UInt64) {
        var visited = Array(repeating: false, count: width * height)
        var stack: [(Int, Int)] = []
        var rng = SeededGenerator(seed: seed)

        stack.append((0, 0))
        visited[index(0, 0)] = true

        while let (x, y) = stack.last {
            var neighbors: [(Dir, Int, Int)] = []
            for dir in Dir.allCases {
                let nx = x + dir.dx
                let ny = y + dir.dy
                if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                if visited[index(nx, ny)] { continue }
                neighbors.append((dir, nx, ny))
            }

            if neighbors.isEmpty {
                stack.removeLast()
                continue
            }

            let choice = neighbors[Int(rng.next() % UInt64(neighbors.count))]
            removeWall(x: x, y: y, dir: choice.0)
            visited[index(choice.1, choice.2)] = true
            stack.append((choice.1, choice.2))
        }
    }

    func wallBoxes(origin: SIMD3<Float>) -> [WallBox] {
        var boxes: [WallBox] = []

        for y in 0..<height {
            for x in 0..<width {
                let cellIndex = index(x, y)
                let cellOrigin = SIMD3<Float>(origin.x + Float(x) * cellSize,
                                              origin.y,
                                              origin.z + Float(y) * cellSize)

                if hasWall(cellIndex, .north) {
                    let center = SIMD3<Float>(cellOrigin.x + cellSize * 0.5,
                                              wallHeight * 0.5,
                                              cellOrigin.z)
                    let size = SIMD3<Float>(cellSize, wallHeight, wallThickness)
                    boxes.append(WallBox(center: center, size: size))
                }

                if hasWall(cellIndex, .west) {
                    let center = SIMD3<Float>(cellOrigin.x,
                                              wallHeight * 0.5,
                                              cellOrigin.z + cellSize * 0.5)
                    let size = SIMD3<Float>(wallThickness, wallHeight, cellSize)
                    boxes.append(WallBox(center: center, size: size))
                }

                if y == height - 1 && hasWall(cellIndex, .south) {
                    let center = SIMD3<Float>(cellOrigin.x + cellSize * 0.5,
                                              wallHeight * 0.5,
                                              cellOrigin.z + cellSize)
                    let size = SIMD3<Float>(cellSize, wallHeight, wallThickness)
                    boxes.append(WallBox(center: center, size: size))
                }

                if x == width - 1 && hasWall(cellIndex, .east) {
                    let center = SIMD3<Float>(cellOrigin.x + cellSize,
                                              wallHeight * 0.5,
                                              cellOrigin.z + cellSize * 0.5)
                    let size = SIMD3<Float>(wallThickness, wallHeight, cellSize)
                    boxes.append(WallBox(center: center, size: size))
                }
            }
        }

        return boxes
    }

    private func index(_ x: Int, _ y: Int) -> Int {
        y * width + x
    }

    private func hasWall(_ idx: Int, _ dir: Dir) -> Bool {
        (walls[idx] & dir.bit) != 0
    }

    mutating private func removeWall(x: Int, y: Int, dir: Dir) {
        let idx = index(x, y)
        let nx = x + dir.dx
        let ny = y + dir.dy
        let nidx = index(nx, ny)

        walls[idx] &= ~dir.bit
        walls[nidx] &= ~dir.opposite.bit
    }

    enum Dir: CaseIterable {
        case north, south, east, west

        var dx: Int { self == .east ? 1 : self == .west ? -1 : 0 }
        var dy: Int { self == .south ? 1 : self == .north ? -1 : 0 }
        var bit: UInt8 {
            switch self {
            case .north: return 0b0001
            case .south: return 0b0010
            case .east:  return 0b0100
            case .west:  return 0b1000
            }
        }
        var opposite: Dir {
            switch self {
            case .north: return .south
            case .south: return .north
            case .east:  return .west
            case .west:  return .east
            }
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}

private enum GeometryBuilder {
    static func appendPlane(centerY: Float,
                            size: SIMD2<Float>,
                            vertices: inout [Float],
                            indices: inout [Int32]) {
        let hx = size.x * 0.5
        let hz = size.y * 0.5

        let v0 = SIMD3<Float>(-hx, centerY, -hz)
        let v1 = SIMD3<Float>( hx, centerY, -hz)
        let v2 = SIMD3<Float>( hx, centerY,  hz)
        let v3 = SIMD3<Float>(-hx, centerY,  hz)

        let base = Int32(vertices.count / 3)
        addVertex(v0, to: &vertices)
        addVertex(v1, to: &vertices)
        addVertex(v2, to: &vertices)
        addVertex(v3, to: &vertices)

        // Winding produces +Y normal so Recast treats the floor as walkable.
        indices.append(contentsOf: [base, base + 2, base + 1,
                                    base, base + 3, base + 2])
    }

    static func appendPlane(center: SIMD3<Float>,
                            size: SIMD2<Float>,
                            vertices: inout [Float],
                            indices: inout [Int32]) {
        let hx = size.x * 0.5
        let hz = size.y * 0.5

        let v0 = center + SIMD3<Float>(-hx, 0, -hz)
        let v1 = center + SIMD3<Float>( hx, 0, -hz)
        let v2 = center + SIMD3<Float>( hx, 0,  hz)
        let v3 = center + SIMD3<Float>(-hx, 0,  hz)

        let base = Int32(vertices.count / 3)
        addVertex(v0, to: &vertices)
        addVertex(v1, to: &vertices)
        addVertex(v2, to: &vertices)
        addVertex(v3, to: &vertices)

        // Winding produces +Y normal.
        indices.append(contentsOf: [base, base + 2, base + 1,
                                    base, base + 3, base + 2])
    }

    static func appendBox(center: SIMD3<Float>,
                          size: SIMD3<Float>,
                          vertices: inout [Float],
                          indices: inout [Int32]) {
        let hx = size.x * 0.5
        let hy = size.y * 0.5
        let hz = size.z * 0.5

        let v0 = center + SIMD3<Float>(-hx, -hy, -hz)
        let v1 = center + SIMD3<Float>( hx, -hy, -hz)
        let v2 = center + SIMD3<Float>( hx, -hy,  hz)
        let v3 = center + SIMD3<Float>(-hx, -hy,  hz)
        let v4 = center + SIMD3<Float>(-hx,  hy, -hz)
        let v5 = center + SIMD3<Float>( hx,  hy, -hz)
        let v6 = center + SIMD3<Float>( hx,  hy,  hz)
        let v7 = center + SIMD3<Float>(-hx,  hy,  hz)

        let base = Int32(vertices.count / 3)
        addVertex(v0, to: &vertices)
        addVertex(v1, to: &vertices)
        addVertex(v2, to: &vertices)
        addVertex(v3, to: &vertices)
        addVertex(v4, to: &vertices)
        addVertex(v5, to: &vertices)
        addVertex(v6, to: &vertices)
        addVertex(v7, to: &vertices)

        // Sides only for navmesh obstacles; skip top/bottom to avoid
        // overlapping the floor and wiping walkable spans.
        // Front (Z+)
        indices.append(contentsOf: [base + 3, base + 2, base + 6,
                                    base + 3, base + 6, base + 7])
        // Back (Z-)
        indices.append(contentsOf: [base + 0, base + 5, base + 1,
                                    base + 0, base + 4, base + 5])
        // Left (X-)
        indices.append(contentsOf: [base + 0, base + 3, base + 7,
                                    base + 0, base + 7, base + 4])
        // Right (X+)
        indices.append(contentsOf: [base + 1, base + 6, base + 2,
                                    base + 1, base + 5, base + 6])
    }

    static func appendRampTop(origin: SIMD3<Float>,
                              length: Float,
                              width: Float,
                              height: Float,
                              vertices: inout [Float],
                              indices: inout [Int32]) {
        let hx = length * 0.5
        let hz = width * 0.5

        let v4 = origin + SIMD3<Float>(-hx, 0, -hz)
        let v5 = origin + SIMD3<Float>( hx, height, -hz)
        let v6 = origin + SIMD3<Float>( hx, height,  hz)
        let v7 = origin + SIMD3<Float>(-hx, 0,  hz)

        let base = Int32(vertices.count / 3)
        addVertex(v4, to: &vertices)
        addVertex(v5, to: &vertices)
        addVertex(v6, to: &vertices)
        addVertex(v7, to: &vertices)

        // Winding with positive Y normal for walkability.
        indices.append(contentsOf: [base + 0, base + 2, base + 1,
                                    base + 0, base + 3, base + 2])
    }

    static func makeRampSurfaceMesh(length: Float,
                                    width: Float,
                                    height: Float) -> MeshResource? {
        let hx = length * 0.5
        let hz = width * 0.5

        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-hx, 0, -hz),
            SIMD3<Float>( hx, height, -hz),
            SIMD3<Float>( hx, height,  hz),
            SIMD3<Float>(-hx, 0,  hz)
        ]

        var desc = MeshDescriptor()
        desc.positions = MeshBuffer(positions)
        let indices: [UInt32] = [0, 2, 1, 0, 3, 2]
        desc.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [desc])
    }

    private static func addVertex(_ v: SIMD3<Float>, to vertices: inout [Float]) {
        vertices.append(v.x)
        vertices.append(v.y)
        vertices.append(v.z)
    }
}
