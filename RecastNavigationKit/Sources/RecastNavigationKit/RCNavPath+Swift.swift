//
//  RCNavPath+Swift.swift
//  RecastNavigationExample
//
//  Created by Tatsuya Ogawa on 2025/12/24.
//

import Foundation
import RecastNavigationObjC
import simd

extension RCNavPath {
    public struct PointSequence: Sequence {
        let path: RCNavPath
        public func makeIterator() -> PointIterator { PointIterator(path: path) }
    }

    public struct PointIterator: IteratorProtocol {
        let path: RCNavPath
        private var index: Int = 0

        init(path: RCNavPath) {
            self.path = path
            self.index = 0
        }

        mutating public func next() -> SIMD3<Float>? {
            guard index < Int(path.pointCount) else { return nil }
            let value = path.point(at: Int32(index))
            index += 1
            return value
        }
    }

    public func points() -> PointSequence { PointSequence(path: self) }
}
