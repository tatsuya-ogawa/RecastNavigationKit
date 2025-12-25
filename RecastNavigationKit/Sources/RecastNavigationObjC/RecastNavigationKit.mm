//
//  RecastNavigationKit.mm
//  RecastNavigationExample
//
//  Created by Tatsuya Ogawa on 2025/12/24.
//

#import "RecastNavigationKit.h"

// C++ headers
#include "DetourNavMesh.h"
#include "DetourNavMeshQuery.h"
#include "DetourCommon.h"
#include <vector>
#include <cstring>
#include <cstdlib>

@interface RCNavPath ()
{
    dtPolyRef *_polyRefs;
    float *_points; // xyz xyz ...
}
@property (nonatomic, readwrite) int polyCount;
@property (nonatomic, readwrite) int pointCount;
- (instancetype)initWithPolyRefs:(dtPolyRef *)polyRefs
                        polyCount:(int)polyCount
                           points:(float *)points
                       pointCount:(int)pointCount;
@end

@implementation RCNavPath

- (instancetype)initWithPolyRefs:(dtPolyRef *)polyRefs
                        polyCount:(int)polyCount
                           points:(float *)points
                       pointCount:(int)pointCount
{
    self = [super init];
    if (!self) return nil;
    _polyRefs = polyRefs;
    _points = points;
    _polyCount = polyCount;
    _pointCount = pointCount;
    return self;
}

- (void)dealloc
{
    free(_polyRefs);
    free(_points);
}

- (vector_float3)pointAtIndex:(int)index
{
    if (index < 0 || index >= _pointCount || !_points) {
        return (vector_float3){ 0, 0, 0 };
    }
    const float *p = _points + (index * 3);
    return (vector_float3){ p[0], p[1], p[2] };
}

- (uint64_t)polyRefAtIndex:(int)index
{
    if (index < 0 || index >= _polyCount || !_polyRefs) return 0;
    return (uint64_t)_polyRefs[index];
}

@end

@interface RecastNavMesh ()
{
    dtNavMesh* _navMesh;
    dtNavMeshQuery* _query;
    NSData* _ownedData;
}
@end

@implementation RecastNavMesh

- (instancetype)initWithNavMeshData:(NSData *)data
{
    self = [super init];
    if (!self) return nil;

    _navMesh = dtAllocNavMesh();
    if (!_navMesh) return nil;

    dtStatus status = _navMesh->init(
        (unsigned char*)data.bytes,
        (int)data.length,
        0 /* Do not use DT_TILE_FREE_DATA: memory managed by NSData */
    );

    if (dtStatusFailed(status)) {
        dtFreeNavMesh(_navMesh);
        return nil;
    }

    _query = dtAllocNavMeshQuery();
    _query->init(_navMesh, 2048);

    _ownedData = data;

    return self;
}

- (instancetype)initWithNavMeshBytes:(unsigned char *)bytes length:(int)length
{
    self = [super init];
    if (!self) { return nil; }

    _navMesh = dtAllocNavMesh();
    if (!_navMesh) { return nil; }

    dtStatus status = _navMesh->init(
        bytes,
        length,
        DT_TILE_FREE_DATA /* Freed by Detour */
    );

    if (dtStatusFailed(status)) {
        dtFreeNavMesh(_navMesh);
        return nil;
    }

    _query = dtAllocNavMeshQuery();
    _query->init(_navMesh, 2048);

    return self;
}

- (void)dealloc
{
    if (_query) dtFreeNavMeshQuery(_query);
    if (_navMesh) dtFreeNavMesh(_navMesh);
}

#pragma mark - Pathfinding
- (RCNavPath *)findPathResultFrom:(vector_float3)start
                               to:(vector_float3)end
{
    dtQueryFilter filter;
    filter.setIncludeFlags(0xFFFF);
    filter.setExcludeFlags(0);

    const float ext[3] = { 10, 10, 10 };

    dtPolyRef startRef, endRef;
    float startPt[3] = { start.x, start.y, start.z };
    float endPt[3]   = { end.x, end.y, end.z };

    float nearestStart[3], nearestEnd[3];

    _query->findNearestPoly(startPt, ext, &filter, &startRef, nearestStart);
    _query->findNearestPoly(endPt,   ext, &filter, &endRef,   nearestEnd);

    if (!startRef || !endRef) {
        const float extLarge[3] = { 50, 50, 50 };
        _query->findNearestPoly(startPt, extLarge, &filter, &startRef, nearestStart);
        _query->findNearestPoly(endPt,   extLarge, &filter, &endRef,   nearestEnd);
    }

    if (!startRef || !endRef) return nil;

    static const int kMaxPathPolys = 4096;
    static const int kMaxStraightPoints = 4096;

    std::vector<dtPolyRef> polys;
    int polyCount = 0;
    int maxPath = 64;
    dtStatus status = 0;

    do {
        polys.assign((size_t)maxPath, 0);
        status = _query->findPath(
            startRef, endRef,
            nearestStart, nearestEnd,
            &filter,
            polys.data(), &polyCount, maxPath
        );

        if (dtStatusFailed(status)) return nil;

        if (status & DT_BUFFER_TOO_SMALL) {
            if (maxPath >= kMaxPathPolys) break;
            maxPath *= 2;
        }
    } while (status & DT_BUFFER_TOO_SMALL);

    if (polyCount <= 0) return nil;
    polys.resize((size_t)polyCount);

    std::vector<float> straight;
    std::vector<unsigned char> straightFlags;
    std::vector<dtPolyRef> straightRefs;
    int straightCount = 0;
    int maxStraight = 64;

    do {
        straight.assign((size_t)maxStraight * 3, 0.0f);
        straightFlags.assign((size_t)maxStraight, 0);
        straightRefs.assign((size_t)maxStraight, 0);

        status = _query->findStraightPath(
            nearestStart, nearestEnd,
            polys.data(), polyCount,
            straight.data(), straightFlags.data(), straightRefs.data(),
            &straightCount, maxStraight
        );

        if (dtStatusFailed(status)) return nil;

        if (status & DT_BUFFER_TOO_SMALL) {
            if (maxStraight >= kMaxStraightPoints) break;
            maxStraight *= 2;
        }
    } while (status & DT_BUFFER_TOO_SMALL);

    if (straightCount <= 0) return nil;

    const size_t polyBytes = (size_t)polyCount * sizeof(dtPolyRef);
    const size_t pointBytes = (size_t)straightCount * 3 * sizeof(float);

    dtPolyRef *polyBuf = (dtPolyRef *)malloc(polyBytes);
    float *pointBuf = (float *)malloc(pointBytes);

    if (!polyBuf || !pointBuf) {
        free(polyBuf);
        free(pointBuf);
        return nil;
    }

    memcpy(polyBuf, polys.data(), polyBytes);
    memcpy(pointBuf, straight.data(), pointBytes);

    RCNavPath *path = [[RCNavPath alloc] initWithPolyRefs:polyBuf
                                                polyCount:polyCount
                                                   points:pointBuf
                                               pointCount:straightCount];
    if (!path) {
        free(polyBuf);
        free(pointBuf);
    }
    return path;
}

#pragma mark - Utility

- (vector_float3)findNearestPoint:(vector_float3)point
{
    dtQueryFilter filter;
    const float ext[3] = { 10, 10, 10 };

    float p[3] = { point.x, point.y, point.z };
    float nearest[3];
    dtPolyRef ref;

    _query->findNearestPoly(p, ext, &filter, &ref, nearest);

    return { nearest[0], nearest[1], nearest[2] };
}

- (NSData *)navMeshTriangleVerticesWithVertexCount:(int *)outVertexCount
{
    if (outVertexCount) *outVertexCount = 0;
    if (!_navMesh) return [NSData data];

    std::vector<float> verts;

    const dtNavMesh* nav = _navMesh;
    const int maxTiles = nav->getMaxTiles();
    for (int i = 0; i < maxTiles; ++i) {
        const dtMeshTile* tile = nav->getTile(i);
        if (!tile || !tile->header) continue;

        const dtMeshHeader* header = tile->header;
        for (int j = 0; j < header->polyCount; ++j) {
            const dtPoly* poly = &tile->polys[j];
            if (poly->getType() == DT_POLYTYPE_OFFMESH_CONNECTION) continue;

            if (tile->detailMeshes && tile->detailTris) {
                const dtPolyDetail* pd = &tile->detailMeshes[j];
                for (int k = 0; k < pd->triCount; ++k) {
                    const unsigned char* t = &tile->detailTris[(pd->triBase + k) * 4];
                    for (int m = 0; m < 3; ++m) {
                        const int v = t[m];
                        const float* pos = nullptr;
                        if (v < poly->vertCount) {
                            const int idx = poly->verts[v];
                            pos = &tile->verts[idx * 3];
                        } else if (tile->detailVerts) {
                            const int idx = pd->vertBase + (v - poly->vertCount);
                            pos = &tile->detailVerts[idx * 3];
                        }
                        if (!pos) continue;
                        verts.push_back(pos[0]);
                        verts.push_back(pos[1]);
                        verts.push_back(pos[2]);
                    }
                }
            } else {
                for (int k = 1; k < poly->vertCount - 1; ++k) {
                    const int idx0 = poly->verts[0];
                    const int idx1 = poly->verts[k];
                    const int idx2 = poly->verts[k + 1];
                    const float* v0 = &tile->verts[idx0 * 3];
                    const float* v1 = &tile->verts[idx1 * 3];
                    const float* v2 = &tile->verts[idx2 * 3];
                    verts.insert(verts.end(), { v0[0], v0[1], v0[2],
                                                v1[0], v1[1], v1[2],
                                                v2[0], v2[1], v2[2] });
                }
            }
        }
    }

    if (verts.empty()) return [NSData data];

    if (outVertexCount) {
        *outVertexCount = (int)(verts.size() / 3);
    }

    return [NSData dataWithBytes:verts.data()
                          length:verts.size() * sizeof(float)];
}

@end
