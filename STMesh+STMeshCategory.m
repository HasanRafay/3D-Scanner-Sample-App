//
//  STMesh+STMeshCategory.m
//  RoomCapture
//
//  Created by Rafay Hasan on 18/12/18.
//  Copyright © 2018 Occipital. All rights reserved.
//

#import "STMesh+STMeshCategory.h"

@implementation STMesh (STMeshCategory)

- (void)encodeWithCoder:(NSCoder *)coder
{
    //Encode properties, other class variables, etc
//    [coder encodeObject:[NSNumber numberWithInt:self.numberOfMeshes] forKey:@"numberOfMeshes"];
//    [coder encodeObject:[NSNumber numberWithBool:self.hasPerVertexNormals] forKey:@"perVertexNormal"];
//    [coder encodeObject:[NSNumber numberWithBool:self.hasPerVertexColors] forKey:@"perVertexColors"];
//    [coder encodeObject:[NSNumber numberWithBool:self.hasPerVertexUVTextureCoords] forKey:@"perVertexUVTextureCoords"];
   // [coder encodeObject:self.meshYCbCrTexture forKey:@"meshYCbCrTexture"];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
//        self.numberOfMeshes = [decoder decodeObjectForKey:@"numberOfMeshes"];
//        self.hasPerVertexNormals = [decoder decodeObjectForKey:@"perVertexNormal"];
//        self.numberOfMeshes = [decoder decodeObjectForKey:@"numberOfMeshes"];
//        self.hasPerVertexNormals = [decoder decodeObjectForKey:@"perVertexNormal"];
    }
    return self;
}

@end

