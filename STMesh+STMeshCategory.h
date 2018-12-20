//
//  STMesh+STMeshCategory.h
//  RoomCapture
//
//  Created by Rafay Hasan on 18/12/18.
//  Copyright © 2018 Occipital. All rights reserved.
//

//#import <Structure/Structure.h>
#define HAS_LIBCXX
#import <Structure/StructureSLAM.h>
NS_ASSUME_NONNULL_BEGIN

@interface STMesh (STMeshCategory) <NSCoding>

- (void)encodeWithCoder:(NSCoder *)coder;
@end

NS_ASSUME_NONNULL_END

