//  Copyright (c) 2014 James Linnell
//      2026 nilFinx

#import <Foundation/Foundation.h>

@interface TXCConferenceObject : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *publicKey; // String for the public key, needed mainly for accepting invite, etc.
@property (nonatomic, strong) NSMutableArray *members; // So far, this will be comprised of strings for the names.

@end
