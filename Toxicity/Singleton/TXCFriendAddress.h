//  Copyright (c) 2014 James Linnell
//      2026 nilFinx

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, TXCFriendAddressError) {
    TXCFriendAddressError_None,
    TXCFriendAddressError_NoData,
    TXCFriendAddressError_Nil,
    TXCFriendAddressError_OwnKey,
    TXCFriendAddressError_AlreadyAdded,
    TXCFriendAddressError_BadNoSpam,
    TXCFriendAddressError_Invalid,
    TXCFriendAddressError_UnknownFormat
};

@interface TXCFriendAddress : NSObject

@property (nonatomic, strong) NSString *resolvedAddress;
@property (nonatomic, strong) NSString *originalInput;
@property (nonatomic, strong) void (^completionBlock)(NSString *resolvedAddress, TXCFriendAddressError error);

- (id)init;
- (id)initWithToxAddress:(NSString *)ambiguousAddress;

- (void)resolveAddressWithCompletionBlock:(void (^)(NSString *resolvedAddress, TXCFriendAddressError error))completion;
- (void)showError:(TXCFriendAddressError)error;

+ (TXCFriendAddressError)friendAddressIsValid:(NSString *)theKey;

@end
