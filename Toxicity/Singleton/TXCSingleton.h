//  Copyright (c) 2014 James Linnell
//      2026 nilFinx

#import <Foundation/Foundation.h>
#import "TXCDHTNodeObject.h"
#import "TXCFriendObject.h"
#include "tox.h"
#import "TXCMessageObject.h"
#import "TXCConferenceObject.h"

typedef enum {
    AvatarType_Friend,
    AvatarType_Conference
} AvatarType;

@interface TXCSingleton : NSObject

@property (nonatomic, strong) NSMutableArray *dhtNodeList;
@property (nonatomic, assign) time_t lastAttemptedConnect;

@property (nonatomic, strong) NSString *userNick;
@property (nonatomic, strong) NSString *userStatusMessage;
@property (nonatomic, assign) TXCToxFriendUserStatus userStatusType;

@property (nonatomic, strong) NSMutableDictionary *pendingFriendRequests;
@property (nonatomic, strong) NSMutableArray *mainFriendList;
@property (nonatomic, strong) NSMutableArray *mainFriendMessages;
@property (nonatomic, strong) NSIndexPath *currentlyOpenedFriendNumber;

@property (nonatomic, assign) Tox *toxCoreInstance;

@property (nonatomic, strong) UIImage *defaultAvatarImage;
@property (nonatomic, strong) NSCache *avatarImageCache;

@property (nonatomic, strong) NSMutableArray *conferenceList;
@property (nonatomic, strong) NSMutableDictionary *pendingConferenceInvites;
@property (nonatomic, strong) NSMutableDictionary *pendingConferenceInviteFriendNumbers;
@property (nonatomic, strong) NSMutableArray *conferenceMessages;


+ (TXCSingleton *)sharedSingleton;

+ (BOOL)friendNumber:(int)theNumber matchesKey:(NSString *)theKey;
+ (void)saveToxDataInUserDefaults;

- (void)avatarImageForKey:(NSString *)key type:(AvatarType)type finishBlock:(void (^)(UIImage *))finishBlock;

@end