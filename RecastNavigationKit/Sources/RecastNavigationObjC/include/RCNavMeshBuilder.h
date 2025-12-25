//
//  RCNavMeshBuilder.h
//  RecastNavigationExample
//
//  Created by Tatsuya Ogawa on 2025/12/24.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "RecastNavigationKit.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const RCNavMeshBuilderErrorDomain;

typedef NS_ENUM(NSInteger, RCNavMeshBuilderErrorCode) {
    RCNavMeshBuilderErrorNavMeshData = 1,
    RCNavMeshBuilderErrorInvalidParams = 2,
};

/// Objective-C wrapper for rcConfig
@interface RCNavMeshConfig : NSObject

@property (nonatomic) float cellSize;                 // cs (world units)
@property (nonatomic) float cellHeight;               // ch (world units)
@property (nonatomic) float walkableSlopeAngle;       // degrees
@property (nonatomic) int walkableHeight;             // voxels
@property (nonatomic) int walkableClimb;              // voxels
@property (nonatomic) int walkableRadius;             // voxels
@property (nonatomic) int maxEdgeLen;                 // voxels
@property (nonatomic) float maxSimplificationError;   // voxels
@property (nonatomic) int minRegionArea;              // voxels^2
@property (nonatomic) int mergeRegionArea;            // voxels^2
@property (nonatomic) int maxVertsPerPoly;
@property (nonatomic) float detailSampleDist;         // world units
@property (nonatomic) float detailSampleMaxError;     // world units
@property (nonatomic) float clipMinY;                // optional world units (NaN = unused)
@property (nonatomic) float clipMaxY;                // optional world units (NaN = unused)

/// Create a default-like config (computes walkable values from agent size)
+ (instancetype)defaultConfigWithAgentHeight:(float)agentHeight
                                      radius:(float)agentRadius
                                       climb:(float)agentClimb;

@end

@interface RCNavMeshBuilder : NSObject
/// Generate NavMesh data from triangle mesh (returns failure reason via error)
+ (nullable RecastNavMesh *)buildNavMeshWithVertices:(const float *)vertices
                                         vertexCount:(int)vertexCount
                                              indices:(const int *)indices
                                            indexCount:(int)indexCount
                                           agentHeight:(float)agentHeight
                                           agentRadius:(float)agentRadius
                                            agentClimb:(float)agentClimb
                                                 error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NOTHROW;

/// Build using the rcConfig wrapper
+ (nullable RecastNavMesh *)buildNavMeshWithVertices:(const float *)vertices
                                         vertexCount:(int)vertexCount
                                              indices:(const int *)indices
                                            indexCount:(int)indexCount
                                               config:(RCNavMeshConfig *)config
                                                error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NOTHROW;

@end

NS_ASSUME_NONNULL_END
