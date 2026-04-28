//  Copyright (c) 2014 James Linnell
//      2026 nilFinx

#import "TXCConferenceObject.h"

@implementation TXCConferenceObject

@synthesize publicKey, members, name;

- (id)init {
    self = [super init];
    if (self) {
		
        publicKey = @"";
        
        members = [[NSMutableArray alloc] init];
        
        name = @"";
        
    }
    return self;
}

@end
