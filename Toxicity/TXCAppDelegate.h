//  Copyright (c) 2014 James Linnell
//      2026 nilFinx

#import <UIKit/UIKit.h>
#import "TXCSingleton.h"

#include "tox.h"
#include "Messenger.h"

//for the resolve_addr()
#include <netdb.h>

#include <unistd.h>
#define c_sleep(x) usleep(1000*x)

typedef NS_ENUM(NSUInteger, TXCThreadState) {
	TXCThreadState_running,
	TXCThreadState_waitingToKill,
	TXCThreadState_killed
};

typedef NS_ENUM(NSUInteger, TXCLocalNotification) {
	TXCLocalNotification_friendMessage,
	TXCLocalNotification_conferenceMessage
};

@interface TXCAppDelegate : UIResponder <UIApplicationDelegate, UIAlertViewDelegate>

@property (strong, nonatomic) UIWindow *window;

// Tox loop stuff
@property (nonatomic, assign) int on;

@property (nonatomic, strong) dispatch_queue_t toxMainThread;
@property (nonatomic, assign) TXCThreadState toxMainThreadState;
@property (nonatomic, strong) dispatch_queue_t toxBackgroundThread;
@property (nonatomic, assign) TXCThreadState toxBackgroundThreadState;

unsigned char * hex_string_to_bin(char hex_string[]);
char * bin_to_hex_string(uint8_t bin[], size_t size);
int friendNumForID(NSString *theKey);
- (void)toxCoreLoopInBackground:(BOOL)inBackground;

- (BOOL)userNickChanged;
- (BOOL)userStatusChanged;
- (void)userStatusTypeChanged;
- (BOOL)addFriend:(NSString *)address;
- (BOOL)sendMessage:(TXCMessageObject *)message;
- (void)acceptFriendRequests:(NSArray *)keysToAccept;
- (void)acceptConferenceInvites:(NSArray *)keysToAccept;
- (BOOL)deleteFriend:(NSString*)friendKey;
- (BOOL)deleteConference:(uint32_t)cid;

- (void)configureNavigationControllerDesign:(UINavigationController *)navController;

@end
