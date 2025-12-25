//
//  Recast.mm
//  RecastNavigationExample
//
//  Created by Tatsuya Ogawa on 2025/12/24.
//

#import "RCNavMeshBuilder.h"
#import "RecastNavigationKit.h"

// Recast / Detour
#include "Recast.h"
#include "DetourNavMesh.h"
#include "DetourNavMeshBuilder.h"
#include <cstring>
#include <cmath>

NSString * const RCNavMeshBuilderErrorDomain = @"RCNavMeshBuilderErrorDomain";

static void RCSetBuilderError(NSError **error, RCNavMeshBuilderErrorCode code, NSString *message)
{
    if (!error) return;
    *error = [NSError errorWithDomain:RCNavMeshBuilderErrorDomain
                                 code:code
                             userInfo:@{ NSLocalizedDescriptionKey : message ?: @"Unknown error" }];
}

static NSString *RCDescribeNavMeshCreateParamsFailure(const dtNavMeshCreateParams &params)
{
    if (params.nvp > DT_VERTS_PER_POLYGON) {
        return [NSString stringWithFormat:@"nvp (%d) is greater than DT_VERTS_PER_POLYGON (%d).",
                params.nvp, DT_VERTS_PER_POLYGON];
    }
    if (params.vertCount >= 0xffff) {
        return [NSString stringWithFormat:@"vertCount (%d) exceeds 0xffff.", params.vertCount];
    }
    if (!params.vertCount || !params.verts) {
        return @"Missing verts or vertCount is zero.";
    }
    if (!params.polyCount || !params.polys) {
        return @"Missing polys or polyCount is zero.";
    }
    if (params.nvp < 3) {
        return @"nvp must be >= 3.";
    }
    if (params.cs <= 0.0f || params.ch <= 0.0f) {
        return @"cs/ch must be > 0.";
    }
    if (params.walkableHeight <= 0.0f) {
        return @"walkableHeight must be > 0.";
    }
    if (params.walkableRadius < 0.0f) {
        return @"walkableRadius must be >= 0.";
    }
    if (params.walkableClimb < 0.0f) {
        return @"walkableClimb must be >= 0.";
    }
    if (params.detailMeshes) {
        if (!params.detailVerts || !params.detailTris) {
            return @"detailMeshes is set but detailVerts/detailTris is null.";
        }
        if (params.detailVertsCount < 0 || params.detailTriCount < 0) {
            return @"detailVertsCount/detailTriCount must be >= 0.";
        }
    }
    return nil;
}

@implementation RCNavMeshConfig

+ (instancetype)defaultConfigWithAgentHeight:(float)agentHeight
                                      radius:(float)agentRadius
                                       climb:(float)agentClimb
{
    RCNavMeshConfig *config = [[RCNavMeshConfig alloc] init];
    config.cellSize = 0.2f;
    config.cellHeight = 0.1f;
    config.walkableSlopeAngle = 45.0f;
    config.walkableHeight = (int)ceilf(agentHeight / config.cellHeight);
    config.walkableClimb  = (int)floorf(agentClimb  / config.cellHeight);
    config.walkableRadius = (int)ceilf(agentRadius / config.cellSize);
    config.maxEdgeLen = (int)(12.0f / config.cellSize);
    config.maxSimplificationError = 1.3f;
    config.minRegionArea = (int)rcSqr(8);
    config.mergeRegionArea = (int)rcSqr(20);
    config.maxVertsPerPoly = 6;
    config.detailSampleDist = 6.0f;
    config.detailSampleMaxError = 1.0f;
    config.clipMinY = NAN;
    config.clipMaxY = NAN;
    return config;
}

@end

static NSString *RCValidateConfig(RCNavMeshConfig *config)
{
    if (!config) return @"Config is nil.";
    if (config.cellSize <= 0.0f) return @"cellSize must be > 0.";
    if (config.cellHeight <= 0.0f) return @"cellHeight must be > 0.";
    if (config.walkableHeight <= 0) return @"walkableHeight must be > 0.";
    if (config.walkableClimb < 0) return @"walkableClimb must be >= 0.";
    if (config.walkableRadius < 0) return @"walkableRadius must be >= 0.";
    if (config.maxVertsPerPoly < 3) return @"maxVertsPerPoly must be >= 3.";
    if (config.maxEdgeLen < 0) return @"maxEdgeLen must be >= 0.";
    if (config.detailSampleDist < 0.0f) return @"detailSampleDist must be >= 0.";
    if (config.detailSampleMaxError < 0.0f) return @"detailSampleMaxError must be >= 0.";
    const bool hasClipMin = !std::isnan(config.clipMinY);
    const bool hasClipMax = !std::isnan(config.clipMaxY);
    if (hasClipMin != hasClipMax) return @"clipMinY/clipMaxY must be both set or both NaN.";
    if (hasClipMin && config.clipMinY >= config.clipMaxY) return @"clipMinY must be < clipMaxY.";
    return nil;
}

@implementation RCNavMeshBuilder

+ (RecastNavMesh *)buildNavMeshWithVertices:(const float *)vertices
                                vertexCount:(int)vertexCount
                                     indices:(const int *)indices
                                   indexCount:(int)indexCount
                                  agentHeight:(float)agentHeight
                                  agentRadius:(float)agentRadius
                                   agentClimb:(float)agentClimb
{
    return [self buildNavMeshWithVertices:vertices
                              vertexCount:vertexCount
                                   indices:indices
                                 indexCount:indexCount
                                agentHeight:agentHeight
                                agentRadius:agentRadius
                                 agentClimb:agentClimb
                                      error:nil];
}

+ (RecastNavMesh *)buildNavMeshWithVertices:(const float *)vertices
                                vertexCount:(int)vertexCount
                                     indices:(const int *)indices
                                   indexCount:(int)indexCount
                                  agentHeight:(float)agentHeight
                                  agentRadius:(float)agentRadius
                                   agentClimb:(float)agentClimb
                                        error:(NSError * _Nullable * _Nullable)error
{
    RCNavMeshConfig *config = [RCNavMeshConfig defaultConfigWithAgentHeight:agentHeight
                                                                     radius:agentRadius
                                                                      climb:agentClimb];
    return [self buildNavMeshWithVertices:vertices
                              vertexCount:vertexCount
                                   indices:indices
                                 indexCount:indexCount
                                    config:config
                                     error:error];
}

+ (RecastNavMesh *)buildNavMeshWithVertices:(const float *)vertices
                                vertexCount:(int)vertexCount
                                     indices:(const int *)indices
                                   indexCount:(int)indexCount
                                      config:(RCNavMeshConfig *)config
                                       error:(NSError * _Nullable * _Nullable)error
{
    rcContext ctx;

    // --- Config ---
    NSString *configError = RCValidateConfig(config);
    if (configError) {
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, configError);
        return nil;
    }

    rcConfig cfg{};
    cfg.cs = config.cellSize;
    cfg.ch = config.cellHeight;

    cfg.walkableSlopeAngle = config.walkableSlopeAngle;
    cfg.walkableHeight = config.walkableHeight;
    cfg.walkableClimb  = config.walkableClimb;
    cfg.walkableRadius = config.walkableRadius;

    cfg.maxEdgeLen = config.maxEdgeLen;
    cfg.maxSimplificationError = config.maxSimplificationError;
    cfg.minRegionArea = config.minRegionArea;
    cfg.mergeRegionArea = config.mergeRegionArea;
    cfg.maxVertsPerPoly = config.maxVertsPerPoly;

    cfg.detailSampleDist = config.detailSampleDist;
    cfg.detailSampleMaxError = config.detailSampleMaxError;

    // --- Bounds ---
    rcCalcBounds(vertices, vertexCount, cfg.bmin, cfg.bmax);
    if (!std::isnan(config.clipMinY) && !std::isnan(config.clipMaxY)) {
        cfg.bmin[1] = config.clipMinY;
        cfg.bmax[1] = config.clipMaxY;
    }
    rcCalcGridSize(cfg.bmin, cfg.bmax, cfg.cs, &cfg.width, &cfg.height);

    // --- Heightfield ---
    rcHeightfield* hf = rcAllocHeightfield();
    if (!hf) {
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"Failed to allocate rcHeightfield.");
        return nil;
    }

    if (!rcCreateHeightfield(
        &ctx, *hf,
        cfg.width, cfg.height,
        cfg.bmin, cfg.bmax,
        cfg.cs, cfg.ch))
    {
        rcFreeHeightField(hf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcCreateHeightfield failed.");
        return nil;
    }

    // --- Walkable triangles ---
    int triCount = indexCount / 3;
    unsigned char* triAreas = new unsigned char[triCount];
    memset(triAreas, 0, sizeof(unsigned char) * triCount);

    rcMarkWalkableTriangles(
        &ctx,
        cfg.walkableSlopeAngle,
        vertices, vertexCount,
        indices, triCount,
        triAreas
    );

    // triAreas are initialized; rcMarkWalkableTriangles sets walkable ones.

    // --- Rasterize ---
    if (!rcRasterizeTriangles(
        &ctx,
        vertices, vertexCount,
        indices, triAreas,
        triCount,
        *hf,
        cfg.walkableClimb
    )) {
        delete[] triAreas;
        rcFreeHeightField(hf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcRasterizeTriangles failed.");
        return nil;
    }

    delete[] triAreas;

    // --- Compact heightfield ---
    rcCompactHeightfield* chf = rcAllocCompactHeightfield();
    if (!chf) {
        rcFreeHeightField(hf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"Failed to allocate rcCompactHeightfield.");
        return nil;
    }

    if (!rcBuildCompactHeightfield(
        &ctx,
        cfg.walkableHeight,
        cfg.walkableClimb,
        *hf,
        *chf
    )) {
        rcFreeHeightField(hf);
        rcFreeCompactHeightfield(chf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcBuildCompactHeightfield failed.");
        return nil;
    }

    rcFreeHeightField(hf);

    // --- Erode ---
    if (!rcErodeWalkableArea(&ctx, cfg.walkableRadius, *chf)) {
        rcFreeCompactHeightfield(chf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcErodeWalkableArea failed.");
        return nil;
    }

    // --- Regions ---
    if (!rcBuildDistanceField(&ctx, *chf)) {
        rcFreeCompactHeightfield(chf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcBuildDistanceField failed.");
        return nil;
    }
    if (!rcBuildRegions(
        &ctx, *chf,
        0,
        cfg.minRegionArea,
        cfg.mergeRegionArea
    )) {
        rcFreeCompactHeightfield(chf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcBuildRegions failed.");
        return nil;
    }

    // --- Contours ---
    rcContourSet* cset = rcAllocContourSet();
    if (!cset) {
        rcFreeCompactHeightfield(chf);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"Failed to allocate rcContourSet.");
        return nil;
    }
    if (!rcBuildContours(
        &ctx,
        *chf,
        cfg.maxSimplificationError,
        cfg.maxEdgeLen,
        *cset
    )) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcBuildContours failed.");
        return nil;
    }

    // --- Poly mesh ---
    rcPolyMesh* pmesh = rcAllocPolyMesh();
    if (!pmesh) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"Failed to allocate rcPolyMesh.");
        return nil;
    }
    if (!rcBuildPolyMesh(
        &ctx,
        *cset,
        cfg.maxVertsPerPoly,
        *pmesh
    )) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcBuildPolyMesh failed.");
        return nil;
    }

    // Set default flags based on area type so Detour queries can find polys.
    for (int i = 0; i < pmesh->npolys; ++i) {
        if (pmesh->areas[i] == RC_WALKABLE_AREA) {
            pmesh->flags[i] = 1;
        } else {
            pmesh->flags[i] = 0;
        }
    }

    if (pmesh->nverts == 0 || pmesh->npolys == 0) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams,
                          [NSString stringWithFormat:@"Empty poly mesh. nverts=%d npolys=%d",
                                                     pmesh->nverts, pmesh->npolys]);
        return nil;
    }

    // --- Detail mesh ---
    rcPolyMeshDetail* dmesh = rcAllocPolyMeshDetail();
    if (!dmesh) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"Failed to allocate rcPolyMeshDetail.");
        return nil;
    }
    if (!rcBuildPolyMeshDetail(
        &ctx,
        *pmesh, *chf,
        cfg.detailSampleDist,
        cfg.detailSampleMaxError,
        *dmesh
    )) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        rcFreePolyMeshDetail(dmesh);
        RCSetBuilderError(error, RCNavMeshBuilderErrorInvalidParams, @"rcBuildPolyMeshDetail failed.");
        return nil;
    }

    rcFreeCompactHeightfield(chf);
    rcFreeContourSet(cset);

    // --- Detour navmesh ---
    dtNavMeshCreateParams params{};
    params.verts = pmesh->verts;
    params.vertCount = pmesh->nverts;
    params.polys = pmesh->polys;
    params.polyAreas = pmesh->areas;
    params.polyFlags = pmesh->flags;
    params.polyCount = pmesh->npolys;
    params.nvp = pmesh->nvp;

    params.detailMeshes = dmesh->meshes;
    params.detailVerts = dmesh->verts;
    params.detailVertsCount = dmesh->nverts;
    params.detailTris = dmesh->tris;
    params.detailTriCount = dmesh->ntris;

    const float agentHeight = cfg.walkableHeight * cfg.ch;
    const float agentRadius = cfg.walkableRadius * cfg.cs;
    const float agentClimb  = cfg.walkableClimb  * cfg.ch;
    params.walkableHeight = agentHeight;
    params.walkableRadius = agentRadius;
    params.walkableClimb  = agentClimb;

    params.bmin[0] = pmesh->bmin[0];
    params.bmin[1] = pmesh->bmin[1];
    params.bmin[2] = pmesh->bmin[2];
    params.bmax[0] = pmesh->bmax[0];
    params.bmax[1] = pmesh->bmax[1];
    params.bmax[2] = pmesh->bmax[2];
    params.cs = cfg.cs;
    params.ch = cfg.ch;

    unsigned char* navData = nullptr;
    int navDataSize = 0;

    if (!dtCreateNavMeshData(&params, &navData, &navDataSize)) {
        rcFreePolyMesh(pmesh);
        rcFreePolyMeshDetail(dmesh);
        NSString *reason = RCDescribeNavMeshCreateParamsFailure(params);
        if (!reason) {
            reason = @"dtCreateNavMeshData failed (allocation or invalid mesh data).";
        }
        RCSetBuilderError(error, RCNavMeshBuilderErrorNavMeshData, reason);
        return nil;
    }

    // Pass the memory returned by dtCreateNavMeshData() directly and let Detour take ownership
    RecastNavMesh *wrapper = [[RecastNavMesh alloc] initWithNavMeshBytes:navData length:navDataSize];

    // If wrapper initialization fails, explicitly free the memory
    if (!wrapper) {
        dtFree(navData);
        RCSetBuilderError(error, RCNavMeshBuilderErrorNavMeshData, @"Failed to initialize RecastNavMesh.");
    }

    rcFreePolyMesh(pmesh);
    rcFreePolyMeshDetail(dmesh);

    return wrapper;
}

@end
