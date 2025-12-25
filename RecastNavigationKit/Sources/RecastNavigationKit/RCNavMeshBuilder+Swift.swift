//
//  RCNavMeshBuilder+Swift.swift
//  RecastNavigationExample
//
//  Created by Tatsuya Ogawa on 2025/12/24.
//

import Foundation
import RecastNavigationObjC

extension RCNavMeshBuilder {
    /// Swift: specify config (throws on failure)
    static func buildNavMesh(vertices: [Float],
                             indices: [Int32],
                             config: RCNavMeshConfig) throws -> RecastNavMesh {
        guard !vertices.isEmpty, !indices.isEmpty else {
            throw NSError(domain: RCNavMeshBuilderErrorDomain,
                          code: RCNavMeshBuilderErrorCode.invalidParams.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "vertices or indices is empty."])
        }
        precondition(vertices.count % 3 == 0, "vertices must be xyz triplets")
        precondition(indices.count % 3 == 0, "indices must be triangle triplets")

        let vertexCount = Int32(vertices.count / 3)
        let indexCount = Int32(indices.count)

        return try vertices.withUnsafeBufferPointer { vbuf in
            return try indices.withUnsafeBufferPointer { ibuf in
                guard let vBase = vbuf.baseAddress, let iBase = ibuf.baseAddress else {
                    throw NSError(domain: RCNavMeshBuilderErrorDomain,
                                  code: RCNavMeshBuilderErrorCode.invalidParams.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to access vertex/index buffer."])
                }

                var nsError: NSError?
                let nav = RCNavMeshBuilder.buildNavMesh(withVertices: vBase,
                                                        vertexCount: vertexCount,
                                                        indices: iBase,
                                                        indexCount: indexCount,
                                                        config: config,
                                                        error: &nsError)
                if let nav = nav { return nav }

                let fallback = NSError(domain: RCNavMeshBuilderErrorDomain,
                                       code: RCNavMeshBuilderErrorCode.navMeshData.rawValue,
                                       userInfo: [NSLocalizedDescriptionKey: "NavMesh build failed."])
                throw nsError ?? fallback
            }
        }
    }

    /// Swift: build from arrays (throws on failure)
    static func buildNavMesh(vertices: [Float],
                             indices: [Int32],
                             agentHeight: Float,
                             agentRadius: Float,
                             agentClimb: Float) throws -> RecastNavMesh {
        guard !vertices.isEmpty, !indices.isEmpty else {
            throw NSError(domain: RCNavMeshBuilderErrorDomain,
                          code: RCNavMeshBuilderErrorCode.invalidParams.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "vertices or indices is empty."])
        }
        precondition(vertices.count % 3 == 0, "vertices must be xyz triplets")
        precondition(indices.count % 3 == 0, "indices must be triangle triplets")

        let vertexCount = Int32(vertices.count / 3)
        let indexCount = Int32(indices.count)

        return try vertices.withUnsafeBufferPointer { vbuf in
            return try indices.withUnsafeBufferPointer { ibuf in
                guard let vBase = vbuf.baseAddress, let iBase = ibuf.baseAddress else {
                    throw NSError(domain: RCNavMeshBuilderErrorDomain,
                                  code: RCNavMeshBuilderErrorCode.invalidParams.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to access vertex/index buffer."])
                }
                return try buildNavMesh(vertices: vBase,
                                        vertexCount: vertexCount,
                                        indices: iBase,
                                        indexCount: indexCount,
                                        agentHeight: agentHeight,
                                        agentRadius: agentRadius,
                                        agentClimb: agentClimb)
            }
        }
    }

    /// Swift: throws on failure
    static func buildNavMesh(vertices: UnsafePointer<Float>,
                             vertexCount: Int32,
                             indices: UnsafePointer<Int32>,
                             indexCount: Int32,
                             agentHeight: Float,
                             agentRadius: Float,
                             agentClimb: Float) throws -> RecastNavMesh {
        var nsError: NSError?
        let nav = RCNavMeshBuilder.buildNavMesh(withVertices: vertices,
                                                vertexCount: vertexCount,
                                                indices: indices,
                                                indexCount: indexCount,
                                                agentHeight: agentHeight,
                                                agentRadius: agentRadius,
                                                agentClimb: agentClimb,
                                                error: &nsError)
        if let nav = nav {
            return nav
        }

        let fallback = NSError(domain: RCNavMeshBuilderErrorDomain,
                               code: RCNavMeshBuilderErrorCode.navMeshData.rawValue,
                               userInfo: [NSLocalizedDescriptionKey: "NavMesh build failed."])
        throw nsError ?? fallback
    }
}
