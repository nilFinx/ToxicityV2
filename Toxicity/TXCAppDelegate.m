//
//  TXCAppDelegate.m
//  Toxicity
//
//  Created by James Linnell on 8/4/13.
//  Copyright (c) 2014 James Linnell
//      2026 nilFinx
//

// Known tags:
// TODO
// TOOD_BUMP
// UNFINISHED

#import "TXCAppDelegate.h"
#import "TWMessageBarManager.h"
#import "JSBubbleView.h"
#import <ZBarReaderView.h>
#import "TXCFriendAddress.h"

NSString *const TXCToxAppDelegateNotificationFriendAdded = @"FriendAdded";
NSString *const TXCToxAppDelegateNotificationGroupAdded = @"GroupAdded";
NSString *const TXCToxAppDelegateNotificationFriendRequestReceived = @"FriendRequestReceived";
NSString *const TXCToxAppDelegateNotificationGroupInviteReceived = @"GroupInviteReceived";
NSString *const TXCToxAppDelegateNotificationNewMessage = @"NewMessage";
NSString *const TXCToxAppDelegateNotificationFriendUserStatusChanged = @"FriendUserStatusChanged";
NSString *const ToxAppDelegateNotificationDHTConnected              = @"DHTConnected";
NSString *const ToxAppDelegateNotificationDHTDisconnected           = @"DHTDisconnected";

NSString *const TXCToxAppDelegateUserDefaultsToxData = @"TXCToxData";

@implementation TXCAppDelegate

#pragma mark - Application Delegation Methods

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [ZBarReaderView class];
    
    [self setupTox];

    [self customizeAppearence];

    // Tox thread
    self.toxMainThread = dispatch_queue_create("com.Jman.Toxicity", DISPATCH_QUEUE_SERIAL);
    self.toxMainThreadState = TXCThreadState_killed;
    self.toxBackgroundThread = dispatch_queue_create("com.Jman.ToxicityBG", DISPATCH_QUEUE_SERIAL);
    self.toxBackgroundThreadState = TXCThreadState_killed;
    
    self.toxWaitData = NULL;
    self.toxWaitBufferSize = 6969;
    self.toxWaitData = malloc(self.toxWaitBufferSize);
    
    
    UILocalNotification *locationNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (locationNotification) {
        // Go to most recent chat message
    }
    application.applicationIconBadgeNumber = 0;

    
    return YES;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    if ([application applicationState] == UIApplicationStateActive) {
        [[TWMessageBarManager sharedInstance] showMessageWithTitle:@"New Message"
                                                       description:notification.alertBody
                                                              type:TWMessageBarMessageTypeInfo];
    }
    application.applicationIconBadgeNumber = 0;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // First and foremost kill our main thread. This is a must.
    [self killToxThreadInBackground:NO];
    while (self.toxMainThreadState != TXCThreadState_killed) {
        // Wait for thread to officially end
    }

    
    if (![[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)]) {
        if (![[UIDevice currentDevice] isMultitaskingSupported]) {
            return;
        }
        return;
    }
    
    // Multitasking supported
    __block UIBackgroundTaskIdentifier background_tox_task = UIBackgroundTaskInvalid;
    
    [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:background_tox_task];
        background_tox_task = UIBackgroundTaskInvalid;
    }];
    
    // Run Tox thread in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self startToxThreadInBackground:YES];
        
        [application endBackgroundTask:background_tox_task];
        background_tox_task = UIBackgroundTaskInvalid;
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    if ([[TXCSingleton sharedSingleton] toxCoreInstance] == NULL) {
        [self setupTox];
    }
    // Kill BG thread, if there is any.
    [self killToxThreadInBackground:YES];
    
    while (self.toxBackgroundThreadState != TXCThreadState_killed) {
        // Wait for thread to officially end
    }
    
    // Start main thread again.
    [self startToxThreadInBackground:NO];
    
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    
    // Kill any threads present
    [self killToxThreadInBackground:YES];
    [self killToxThreadInBackground:NO];
    
    // Wait for them to end (?)
    while (self.toxMainThreadState != TXCThreadState_killed && self.toxBackgroundThreadState != TXCThreadState_killed) {
        // Wait for both threads (only one should be running at a time though) to end
    }
    
    // Properly kill tox.
    tox_kill([[TXCSingleton sharedSingleton] toxCoreInstance]);
    [[TXCSingleton sharedSingleton] setToxCoreInstance:NULL];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    NSLog(@"URL: %@", url);
    
    TXCFriendAddress *friendAddress = [[TXCFriendAddress alloc] initWithToxAddress:url.absoluteString];
    [friendAddress resolveAddressWithCompletionBlock:^(NSString *resolvedAddress, TXCFriendAddressError error){
        if (error == TXCFriendAddressError_None) {
            [self addFriend:resolvedAddress];
        } else {
            [friendAddress showError:error];
        }
    }];
    
    return YES;
}

// TODO Setup setupToxNew
- (void)setupToxNew
{
	// Replace decent amount of stuff with one from toxNew standard
	/*
    // User defaults is the easy way to save info between app launches. Don't have to read a file manually, etc. Basically a plist.
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    // Start messenger here for LAN discorvery without pesky DHT. required for ToxCore
    // TODO_BUMP error handling
    Tox *tempTox = tox_new(0, 0);
    if (tempTox) {
        [[TXCSingleton sharedSingleton] setToxCoreInstance:tempTox];
    }
    
    Tox *toxInstance = [[TXCSingleton sharedSingleton] toxCoreInstance];
    
    // Callbacks
    tox_callback_friend_request(       toxInstance, print_request,                NULL);
    tox_callback_group_invite(         toxInstance, print_groupinvite,            NULL);
    tox_callback_friend_message(       toxInstance, print_message,                NULL);
    tox_callback_group_message(        toxInstance, print_groupmessage,           NULL);
    tox_callback_friend_name(          toxInstance, print_nickchange,             NULL);
    tox_callback_friend_status_message(       toxInstance, print_statuschange,           NULL);
    tox_callback_friend_connection_status(    toxInstance, print_connectionstatuschange, NULL);
    tox_callback_friend_status(          toxInstance, print_userstatuschange,       NULL);
    tox_callback_group_namelist_change(toxInstance, print_groupnamelistchange,    NULL);
    
    // Load save. Which is held in NSData bytes in the user defaults
    if ([prefs objectForKey:TXCToxAppDelegateUserDefaultsToxData] == nil) {
        NSLog(@"saving new save");
        saveToxDataInUserDefaults();
    } else {
        NSLog(@"using already made save");
        // Save already made, load it from memory
        NSData *theKey = [prefs objectForKey:TXCToxAppDelegateUserDefaultsToxData];
        
        uint8_t *data = (uint8_t *)[theKey bytes];
        
        // TODO_BUMP shit tox_load(toxInstance, data, [theKey length]);
    }
    
    // Name
    uint8_t nameUTF8[tox_self_get_name_size(toxInstance)];
    tox_self_get_name(toxInstance, nameUTF8);
    if (strcmp((const char *)nameUTF8, "") == 0) {
        NSLog(@"Using default User name");
        tox_self_set_name(toxInstance, (uint8_t *)"Toxicity User", strlen("Toxicity User") + 1, 0); // TODO_BUMP error handling
        [[TXCSingleton sharedSingleton] setUserNick:@"Toxicity User"];
    } else {
        [[TXCSingleton sharedSingleton] setUserNick:[NSString stringWithUTF8String:(const char *)nameUTF8]];
    }
    
    // Status
    uint8_t statusNoteUTF8[tox_self_get_status_message_size(toxInstance)];
    tox_self_get_status_message(toxInstance, statusNoteUTF8);
    if (strcmp((const char *)statusNoteUTF8, "") == 0) {
        NSLog(@"Using default status note");
        tox_self_set_status_message(toxInstance, (uint8_t *)"Toxing", strlen("Toxing") + 1, 0); // TODO_BUMP error handling
        [[TXCSingleton sharedSingleton] setUserStatusMessage:@"Toxing"];
    } else {
        [[TXCSingleton sharedSingleton] setUserStatusMessage:[NSString stringWithUTF8String:(const char *)statusNoteUTF8]];
    }
    
    // Friends
    uint32_t friendCount = tox_self_get_friend_list_size(toxInstance);
    NSLog(@"Friendlist count: %d", friendCount);
    for (int i = 0; i < friendCount; i++) {
        NSLog(@"Adding friend [%d]", i);
        TXCFriendObject *tempFriend = [[TXCFriendObject alloc] init];
        
        uint8_t theirID[TOX_PUBLIC_KEY_SIZE];
        tox_friend_get_public_key(toxInstance, i, theirID, 0); // TODO_BUMP error handling
        [tempFriend setPublicKey:[NSString stringWithUTF8String:(const char *)theirID]];
        
        uint8_t theirName[tox_friend_get_name_size(toxInstance, i, 0)]; // TODO_BUMP error handling
        tox_friend_get_name(toxInstance, i, theirName, 0); // TODO_BUMP error handling
        [tempFriend setNickname:[NSString stringWithUTF8String:(const char *)theirName]];
        
        uint8_t theirStatus[tox_friend_get_status_message_size(toxInstance, i, 0)]; // TODO_BUMP error handling
        tox_friend_get_status_message(toxInstance, i, theirStatus, 0); // TODO_BUMP error handling
        [tempFriend setStatusMessage:[NSString stringWithUTF8String:(const char *)theirStatus]];

        [tempFriend setStatusType:TXCToxFriendUserStatus_None];
        [tempFriend setConnectionType:TXCToxFriendConnectionStatus_None];
        
        [[[TXCSingleton sharedSingleton] mainFriendList] insertObject:tempFriend atIndex:i];
        [[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSMutableArray array] atIndex:i];
    }

    
    //Miscellaneous
    
    //print our our client id/address
    char convertedKey[(TOX_ADDRESS_SIZE * 2) + 1];
    int pos = 0;
    uint8_t ourAddress1[TOX_ADDRESS_SIZE];
    tox_self_get_address([[TXCSingleton sharedSingleton] toxCoreInstance], ourAddress1);
    for (int i = 0; i < TOX_ADDRESS_SIZE; ++i, pos += 2) {
        sprintf(&convertedKey[pos] ,"%02X", ourAddress1[i] & 0xff);
    }
    NSLog(@"Our Address: %s", convertedKey);
	 */
}

- (void)setupTox
{
    //user defaults is the easy way to save info between app launches. dont have to read a file manually, etc. basically a plist
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    /***** Start Loading from NSUserDefaults *****/
    /***** Load:
     Public/Private Key Data - NSData with bytes
     Our Username/nick and Status Message - NSString for both
     Friend List - NSArray of Archived instances of TXCFriendObject
     Saved DHT Nodes - NSArray of Archived instances of TXCDHTNodeObject
     *****/
    
    TOX_ERR_OPTIONS_NEW optNewErr;
    struct Tox_Options* opt = tox_options_new(&optNewErr);
    
    if (optNewErr != TOX_ERR_OPTIONS_NEW_OK)
        exit(1);
    
    //load save, which is held in NSData bytes in the user defaults
    if ([prefs objectForKey:TXCToxAppDelegateUserDefaultsToxData] != nil) {
        NSLog(@"Loading already made save");
        //key already made, load it from memory
        NSData *theKey = [prefs objectForKey:TXCToxAppDelegateUserDefaultsToxData];
        
        uint8_t *data = (uint8_t *)[theKey bytes];
        
        opt->savedata_type = TOX_SAVEDATA_TYPE_TOX_SAVE;
        opt->savedata_length = [theKey length];
        opt->savedata_data = data;
    }
    
    // TODO_BUMP error handling
    Tox *tempTox = tox_new(0, 0);
    if (tempTox) {
        [[TXCSingleton sharedSingleton] setToxCoreInstance:tempTox];
    }
    // so don't do anything on failure??
    
    if ([prefs objectForKey:TXCToxAppDelegateUserDefaultsToxData] == nil) {
        NSLog(@"Saving new save");
        saveToxDataInUserDefaults();
    }
    
    //callbacks
    tox_callback_friend_request(       [[TXCSingleton sharedSingleton] toxCoreInstance], print_request,                NULL);
    tox_callback_group_invite(         [[TXCSingleton sharedSingleton] toxCoreInstance], print_groupinvite,            NULL);
    tox_callback_friend_message(       [[TXCSingleton sharedSingleton] toxCoreInstance], print_message,                NULL);
    tox_callback_group_message(        [[TXCSingleton sharedSingleton] toxCoreInstance], print_groupmessage,           NULL);
    tox_callback_friend_name(          [[TXCSingleton sharedSingleton] toxCoreInstance], print_nickchange,             NULL);
    tox_callback_friend_status_message(       [[TXCSingleton sharedSingleton] toxCoreInstance], print_statuschange,           NULL);
    tox_callback_friend_connection_status(    [[TXCSingleton sharedSingleton] toxCoreInstance], print_connectionstatuschange, NULL);
    tox_callback_friend_status(          [[TXCSingleton sharedSingleton] toxCoreInstance], print_userstatuschange,       NULL);
    tox_callback_group_namelist_change([[TXCSingleton sharedSingleton] toxCoreInstance], print_groupnamelistchange,    NULL);
    
    //load nick and statusmsg
    if ([prefs objectForKey:@"self_nick"] != nil) {
        [[TXCSingleton sharedSingleton] setUserNick:[prefs objectForKey:@"self_nick"]];
        tox_self_set_name([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)[[[TXCSingleton sharedSingleton] userNick] UTF8String], strlen([[[TXCSingleton sharedSingleton] userNick] UTF8String]) + 1, 0); // TODO_BUMP error handling
    } else {
        [[TXCSingleton sharedSingleton] setUserNick:@"Toxicity User"];
        tox_self_set_name([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)"Toxicity User", strlen("Toxicity User") + 1, 0); // TODO_BUMP error handling
    }
    if ([prefs objectForKey:@"self_status_message"] != nil) {
        [[TXCSingleton sharedSingleton] setUserStatusMessage:[prefs objectForKey:@"self_status_message"]];
        tox_self_set_status_message([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)[[[TXCSingleton sharedSingleton] userStatusMessage] UTF8String], strlen([[[TXCSingleton sharedSingleton] userStatusMessage] UTF8String]) + 1, 0); // TODO_BUMP error handling
    } else {
        [[TXCSingleton sharedSingleton] setUserStatusMessage:@"Toxing on Toxicity"];
        tox_self_set_status_message([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)"Toxing on Toxicity", strlen("Toxing on Toxicity") + 1, 0); // TODO_BUMP error handling
    }
    
    //loads friend list
    if ([prefs objectForKey:@"friend_list"] == nil) {
        
    } else {
        NSMutableArray *array = [[NSMutableArray alloc] init];
        for (NSData *data in [prefs objectForKey:@"friend_list"]) {
            TXCFriendObject *tempFriend = (TXCFriendObject *)[NSKeyedUnarchiver unarchiveObjectWithData:data];
            [array addObject:tempFriend];
            
            unsigned char *idToAdd = hex_string_to_bin((char *)[tempFriend.publicKey UTF8String]);
            int num = tox_friend_add_norequest([[TXCSingleton sharedSingleton] toxCoreInstance], idToAdd, 0); // TODO_BUMP error handling
            if (num >= 0) {
                [[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSArray array] atIndex:num];
                [[[TXCSingleton sharedSingleton] mainFriendList] insertObject:tempFriend atIndex:num];
            }
            free(idToAdd);
        }
    }
    
    //loads any pending friend requests
    if ([prefs objectForKey:@"pending_requests_list"] == nil) {
        
    } else {
        [[TXCSingleton sharedSingleton] setPendingFriendRequests:(NSMutableDictionary *)[prefs objectForKey:@"pending_requests_list"]];
    }
    
    /***** End NSUserDefault Loading *****/
    
    
    //Miscellaneous
    
    //print our our client id/address
    char convertedKey[(TOX_ADDRESS_SIZE * 2) + 1];
    int pos = 0;
    uint8_t ourAddress1[TOX_ADDRESS_SIZE];
    tox_self_get_address([[TXCSingleton sharedSingleton] toxCoreInstance], ourAddress1);
    for (int i = 0; i < TOX_ADDRESS_SIZE; ++i, pos += 2) {
        sprintf(&convertedKey[pos] ,"%02X", ourAddress1[i] & 0xff);
    }
    NSLog(@"Our Address: %s", convertedKey);
}

#pragma mark - End Application Delegation

#pragma mark - Tox related Methods

- (void)connectToDHTWithIP:(TXCDHTNodeObject *)theDHTInfo {
    NSLog(@"Connecting to %@ %@ %@", [theDHTInfo dhtIP], [theDHTInfo dhtPort], [theDHTInfo dhtKey]);
    const char *dht_ip = [[theDHTInfo dhtIP] UTF8String];
    const char *dht_port = [[theDHTInfo dhtPort] UTF8String];
    const char *dht_key = [[theDHTInfo dhtKey] UTF8String];
    
    
    //used from toxic source, this tells tox core to make a connection into the dht network    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        unsigned char *binary_string = hex_string_to_bin((char *)dht_key);
        tox_bootstrap([[TXCSingleton sharedSingleton] toxCoreInstance],
                                   dht_ip,
                                   // TODO_BUMP TOX_ENABLE_IPV6_DEFAULT,
                                   htons(atoi(dht_port)),
                                   binary_string, 0); //actual connection // TODO_BUMP error handling
        free(binary_string);
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

}

- (void)userNickChanged {
    char *newNick = (char *)[[[TXCSingleton sharedSingleton] userNick] UTF8String];
    
    //submit new nick to core
    dispatch_async(self.toxMainThread, ^{
        tox_self_set_name([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)newNick, strlen(newNick) + 1, 0); // TODO_BUMP error handling
    });
    
    //save to user defaults
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[[TXCSingleton sharedSingleton] userNick] forKey:@"self_nick"];
    [prefs synchronize];
}

- (void)userStatusChanged {
    char *newStatus = (char *)[[[TXCSingleton sharedSingleton] userStatusMessage] UTF8String];
    
    //submit new status to core
    dispatch_async(self.toxMainThread, ^{
        tox_self_set_status_message([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)newStatus, strlen(newStatus) + 1, 0); // TODO_BUMP error handling
    });
    
    //save to user defaults
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[[TXCSingleton sharedSingleton] userStatusMessage] forKey:@"self_status_message"];
    [prefs synchronize];
}

- (void)userStatusTypeChanged {
    TOX_USER_STATUS statusType = TOX_USER_STATUS_NONE;
    switch ([[TXCSingleton sharedSingleton] userStatusType]) {
        case TXCToxFriendUserStatus_None:
            statusType = TOX_USER_STATUS_NONE;
            break;
            
        case TXCToxFriendUserStatus_Away:
            statusType = TOX_USER_STATUS_AWAY;
            break;
            
        case TXCToxFriendUserStatus_Busy:
            statusType = TOX_USER_STATUS_BUSY;
            break;
            
        default:
            statusType = TOX_USER_STATUS_NONE;
            break;
    }
    dispatch_async(self.toxMainThread, ^{
        tox_self_set_status([[TXCSingleton sharedSingleton] toxCoreInstance], statusType);
    });
}

- (BOOL)sendMessage:(TXCMessageObject *)theMessage {
    //return type: TRUE = sent, FALSE = not sent, should error
    //send a message to a friend, called primarily from the caht window vc

    
    //organize our message data
    NSString *theirKey = theMessage.recipientKey;
    NSString *messageToSend = theMessage.message;
    BOOL isGroupMessage = theMessage.isGroupMessage;
    BOOL isActionMessage = theMessage.isActionMessage;
    __block NSInteger friendNum = -1;
    if (isGroupMessage) {
        [[[TXCSingleton sharedSingleton] groupList] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            TXCGroupObject *tempGroup = [[[TXCSingleton sharedSingleton] groupList] objectAtIndex:idx];
            if ([theirKey isEqualToString:tempGroup.groupPulicKey]) {
                friendNum = idx;
                *stop = YES;
            }
        }];
    } else {
        friendNum = friendNumForID(theirKey);
    }
    if (friendNum == -1) {
        //in case something data-wise messed up and the friend no longer exists, or the key got messed up
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error"
                                                            message:@"Uh oh, something went wrong! The friend key you're trying to send a message to doesn't seem to be in your friend list. Try restarting the app and send a bug report!"
                                                           delegate:nil
                                                  cancelButtonTitle:@"Okay"
                                                  otherButtonTitles:nil];
        [alertView show];
        return FALSE;
    }
    
    NSLog(@"Sending Message %@", theMessage);

    
    //here we have to check to see if a "/me " exists, but before we do that we have to make sure the length is 5 or more
    //dont want to get out of bounds error
    __block BOOL returnVar = TRUE;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        int num;
        char *utf8Message = (char *)[messageToSend UTF8String];
        
        // TODO_BUMP error handling here
        if (isGroupMessage == NO) { //chat message
            if (isActionMessage) {
                char *utf8FormattedMessage = (char *)[[messageToSend substringFromIndex:2] UTF8String];
                num = tox_friend_send_message([[TXCSingleton sharedSingleton] toxCoreInstance], friendNum, TOX_MESSAGE_TYPE_ACTION, (uint8_t *)utf8FormattedMessage, strlen(utf8FormattedMessage) + 1, 0);
            } else {
                num = tox_friend_send_message([[TXCSingleton sharedSingleton] toxCoreInstance], friendNum, TOX_MESSAGE_TYPE_NORMAL, (uint8_t *)utf8Message, strlen(utf8Message) + 1, 0);
            }
        } else { //group message
            num = tox_group_message_send([[TXCSingleton sharedSingleton] toxCoreInstance], friendNum, (uint8_t *)utf8Message, strlen(utf8Message) + 1);
        }
        
        if (num == -1) {
            NSLog(@"Failed to put message in send queue!");
            returnVar =  FALSE;
        } else {
            returnVar =  TRUE;
        }
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW + (100000 * NSEC_PER_USEC));
    return returnVar;
}

- (void)addFriend:(NSString *)theirKey {
    //sends a request to the key
    
    NSLog(@"Adding: %@", theirKey);
    
    uint8_t *binID = hex_string_to_bin((char *)[theirKey UTF8String]);
    __block int num = 0;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        num = tox_friend_add([[TXCSingleton sharedSingleton] toxCoreInstance], binID, (uint8_t *)"Toxicity for iOS", strlen("Toxicity for iOS") + 1, 0); // TODO_BUMP error handling
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    free(binID);
    
    switch (num) {
        case FAERR_TOOLONG:
        case FAERR_NOMESSAGE:
        case FAERR_OWNKEY:
        case FAERR_ALREADYSENT:
        case FAERR_BADCHECKSUM:
        case FAERR_SETNEWNOSPAM:
        case FAERR_NOMEM: {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Unknown Error"
                                                                message:[NSString stringWithFormat:@"[Error Code: %d] There was an unknown error with adding that ID. Normally I try to prevent that, but something unfortunate happened.", num]
                                                               delegate:nil
                                                      cancelButtonTitle:@"Okay"
                                                      otherButtonTitles:nil];
            [alertView show];
            break;
        }
            
        default: //added friend successfully
        {
            //add friend to singleton array, for use throughout the app
            TXCFriendObject *tempFriend = [[TXCFriendObject alloc] init];
            [tempFriend setPublicKeyWithNoSpam:theirKey];
            [tempFriend setPublicKey:[theirKey substringToIndex:(TOX_PUBLIC_KEY_SIZE * 2)]];
            NSLog(@"new friend key: %@", [tempFriend publicKey]);
            [tempFriend setStatusMessage:@"Sending request..."];
            
            [[[TXCSingleton sharedSingleton] mainFriendList] insertObject:tempFriend atIndex:num];
            [[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSArray array] atIndex:num];
            
            //save in user defaults
            [TXCSingleton saveFriendListInUserDefaults];

            [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
            break;
        }
    }
}

- (void)acceptFriendRequests:(NSArray *)theKeysToAccept {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        
        [theKeysToAccept enumerateObjectsUsingBlock:^(NSString* arrayKey, NSUInteger idx, BOOL *stop) {
            NSData *data = [[[[TXCSingleton sharedSingleton] pendingFriendRequests] objectForKey:arrayKey] copy];
            
            uint8_t *key = (uint8_t *)[data bytes];
            
            int num = tox_friend_add_norequest([[TXCSingleton sharedSingleton] toxCoreInstance], key, 0); // TODO_BUMP error handling
            
            switch (num) {
                case -1: {
                    NSLog(@"Accepting request failed");
                    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Unknown Error"
                                                                        message:[NSString stringWithFormat:@"[Error Code: %d] There was an unknown error with accepting that ID.", num]
                                                                       delegate:nil
                                                              cancelButtonTitle:@"Okay"
                                                              otherButtonTitles:nil];
                    [alertView show];
                    break;
                }
                    
                default: //added friend successfully
                {
                    //friend added through accept request
                    TXCFriendObject *tempFriend = [[TXCFriendObject alloc] init];
                    [tempFriend setPublicKey:[arrayKey substringToIndex:(TOX_PUBLIC_KEY_SIZE * 2)]];
                    NSLog(@"new friend key: %@", [tempFriend publicKey]);
                    [tempFriend setNickname:@""];
                    [tempFriend setStatusMessage:@"Accepted..."];
                    
                    [[[TXCSingleton sharedSingleton] mainFriendList] insertObject:tempFriend atIndex:num];
                    [[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSArray array] atIndex:num];
                    
                    //save in user defaults
                    [TXCSingleton saveFriendListInUserDefaults];
                    
                    //remove from the pending requests
                    [[[TXCSingleton sharedSingleton] pendingFriendRequests] removeObjectForKey:arrayKey];
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
                    
                    break;
                }
            }

        }];
        
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[[TXCSingleton sharedSingleton] pendingFriendRequests] forKey:@"pending_requests_list"];
}

- (void)acceptGroupInvites:(NSArray *)theKeysToAccept {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        for (NSString *arrayKey in theKeysToAccept) {
            
            NSData *data = [[[[TXCSingleton sharedSingleton] pendingGroupInvites] objectForKey:arrayKey] copy];
            NSNumber *friendNumOfGroupKey = [[[TXCSingleton sharedSingleton] pendingGroupInviteFriendNumbers] objectForKey:arrayKey];
            
            uint8_t *key = (uint8_t *)[data bytes];
            int num = 6969; // TODO_BUMP tox_join_groupchat([[TXCSingleton sharedSingleton] toxCoreInstance], [friendNumOfGroupKey integerValue], key);

            switch (num) {
                case -1: {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"Accepting group invite failed");
                        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Unknown Error"
                                                                            message:[NSString stringWithFormat:@"[Error Code: %d] There was an unkown error with accepting that Group", num]
                                                                           delegate:nil
                                                                  cancelButtonTitle:@"Okay"
                                                                  otherButtonTitles:nil];
                        [alertView show];
                    });
                    break;
                }
                    
                default: {
                    TXCGroupObject *tempGroup = [[TXCGroupObject alloc] init];
                    [tempGroup setGroupPulicKey:arrayKey];
                    [[[TXCSingleton sharedSingleton] groupList] insertObject:tempGroup atIndex:num];
                    [[[TXCSingleton sharedSingleton] groupMessages] insertObject:[NSArray array] atIndex:num];
                    
                    [TXCSingleton saveGroupListInUserDefaults];
                    
                    [[[TXCSingleton sharedSingleton] pendingGroupInvites] removeObjectForKey:arrayKey];
                    [[[TXCSingleton sharedSingleton] pendingGroupInviteFriendNumbers] removeObjectForKey:arrayKey];
                    [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationGroupAdded object:nil];
                    
                    break;
                }
            }
        }
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
}

- (int)deleteFriend:(NSString*)friendKey {

    int friendNum = friendNumForID(friendKey);
    if (friendNum == -1) {
        return -1;
    }
    

    __block int num = 0;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        // TODO_BUMP error handling
        tox_friend_delete([[TXCSingleton sharedSingleton] toxCoreInstance], friendNum, 0);
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    //and return delfriend's number
    // TODO_BUMP Figure out what the number is
    return num;
    
}

- (int)deleteGroupchat:(NSInteger)theGroupNumber {
    __block int num = 0;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(self.toxMainThread, ^{
        num = tox_del_groupchat([[TXCSingleton sharedSingleton] toxCoreInstance], theGroupNumber);
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    return num;
}

#pragma mark - End Tox related Methods

#pragma mark - Tox Core Callback Functions

void print_request(Tox *tox, uint8_t *public_key, uint8_t *data, uint16_t length, void *userdata) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Friend Request! From:");
        
        for (int i=0; i<32; i++) {
            printf("%02X", public_key[i] & 0xff);
        }
        printf("\n");
        
        // Convert the bin key to a char key. Reverse of hex_string_to_bin. Used in a lot of places.
        // TODO: Make the bin > char key conversion a function
        char convertedKey[(TOX_PUBLIC_KEY_SIZE * 2) + 1];
        int pos = 0;
        for (int i = 0; i < TOX_PUBLIC_KEY_SIZE; ++i, pos += 2) {
            sprintf(&convertedKey[pos] ,"%02X", public_key[i] & 0xff);
        }
        
        // Check to see if this person is already on our friends list
        for (TXCFriendObject *tempFriend in [[TXCSingleton sharedSingleton] mainFriendList]) {
            if ([tempFriend.publicKey isEqualToString:[NSString stringWithUTF8String:convertedKey]]) {
                NSLog(@"The friend request we got is one of a friend we already have, calling add_no_request: %@ %@", tempFriend.nickname, tempFriend.publicKey);
				// No need to kill thread, this is synchronous
				dispatch_async(((TXCAppDelegate *)[[UIApplication sharedApplication] delegate]).toxMainThread, ^{
					tox_friend_add_norequest([[TXCSingleton sharedSingleton] toxCoreInstance], public_key, 0); // TODO_BUMP error handling
				});
				return;
            }
        }
		
        // If they're not on our friends list then dont add a request, just auto accept
		// We got a friend request, so we have to store it!
        // The pending dictionary has the object as nsdata bytes of the bin version of the publickey, and the dict key is the nsstring of said publickey
        [[[TXCSingleton sharedSingleton] pendingFriendRequests]
		 setObject:[NSData dataWithBytes:public_key length:TOX_PUBLIC_KEY_SIZE]
		 forKey:[NSString stringWithUTF8String:convertedKey]];
        [[NSUserDefaults standardUserDefaults] setObject:[[TXCSingleton sharedSingleton] pendingFriendRequests] forKey:@"pending_requests_list"];
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendRequestReceived object:nil];
    });
}

void print_groupinvite(Tox *tox, int friendnumber, uint8_t *group_public_key, void *userdata) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        char convertedKey[(TOX_PUBLIC_KEY_SIZE * 2) + 1];
        int pos = 0;
        for (int i = 0; i < TOX_PUBLIC_KEY_SIZE; ++i, pos += 2) {
            sprintf(&convertedKey[pos] ,"%02X", group_public_key[i] & 0xff);
        }
        NSString *theConvertedKey = [NSString stringWithUTF8String:convertedKey];
        NSLog(@"Group invite from friend [%d], group_public_key: %@", friendnumber, theConvertedKey);
        
        BOOL alreadyInThisGroup = NO;
        for (TXCGroupObject *tempGroup in [[TXCSingleton sharedSingleton] groupList]) {
            if ([theConvertedKey isEqualToString:[tempGroup groupPulicKey]]) {
                NSLog(@"The group we were invited to is one we're already in! %@", [tempGroup groupPulicKey]);
                alreadyInThisGroup = YES;
                break;
            }
        }
        
        if (alreadyInThisGroup == NO) {
            
            [[[TXCSingleton sharedSingleton] pendingGroupInvites] setObject:[NSData dataWithBytes:group_public_key length:TOX_PUBLIC_KEY_SIZE]
                                                                  forKey:theConvertedKey];
            [[[TXCSingleton sharedSingleton] pendingGroupInviteFriendNumbers] setObject:[NSNumber numberWithInt:friendnumber] forKey:theConvertedKey];
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
            [prefs setObject:[[TXCSingleton sharedSingleton] pendingGroupInvites] forKey:@"pending_invites_list"];
            [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationGroupInviteReceived object:nil];
            
        } else {
            TXCAppDelegate *tempAppDelegate = (TXCAppDelegate *)[[UIApplication sharedApplication] delegate];
            dispatch_async(tempAppDelegate.toxMainThread, ^{
                // TODO_BUMP tox_join_groupchat([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, group_public_key);
            });
        }
        
    });
}

void print_message(Tox *m, int friendnumber, TOX_MESSAGE_TYPE type, uint8_t * string, uint16_t length, void *userdata) {
    // TODO: Action messages
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Message from [%d]: %s", friendnumber, string);
        
        TXCMessageObject *theMessage = [[TXCMessageObject alloc] init];
        theMessage.message = [NSString stringWithUTF8String:(char *)string];
        theMessage.senderName = [[TXCSingleton sharedSingleton] userNick];
        theMessage.origin = MessageLocation_Them;
        theMessage.didFailToSend = NO;
        theMessage.groupMessage = NO;
        theMessage.actionMessage = NO;
        [theMessage setSenderKey:[[[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber] publicKey]];
        
        
        // If the message coming through is not to the currently opened chat window, then fire a notification
        if ((friendnumber != [[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] row] &&
            [[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] section] != 1) ||
            [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground ||
            [[UIApplication sharedApplication] applicationState] == UIApplicationStateInactive) {
            NSMutableArray *tempMessages = [[[[TXCSingleton sharedSingleton] mainFriendMessages] objectAtIndex:friendnumber] mutableCopy];
            [tempMessages addObject:theMessage];
            
            // Add message to singleton
            [[TXCSingleton sharedSingleton] mainFriendMessages][friendnumber] = [tempMessages copy];
            
            // Fire a local notification for the message
            UILocalNotification *friendMessageNotification = [[UILocalNotification alloc] init];
            friendMessageNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
            friendMessageNotification.alertBody = [NSString stringWithFormat:@"[%@]: %@", theMessage.senderName, theMessage.message];
            friendMessageNotification.alertAction = @"show the message";
            friendMessageNotification.timeZone = [NSTimeZone defaultTimeZone];
            friendMessageNotification.applicationIconBadgeNumber = [[UIApplication sharedApplication] applicationIconBadgeNumber] + 1;
            [[UIApplication sharedApplication] scheduleLocalNotification:friendMessageNotification];
            NSLog(@"Sent UILocalNotification: %@", friendMessageNotification.alertBody);
            
            [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationNewMessage object:theMessage];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationNewMessage object:theMessage];
        }
    });
}

void print_groupmessage(Tox *tox, int groupnumber, int friendgroupnumber, uint8_t * message, uint16_t length, void *userdata) {
    NSLog(@"Group message received from group [%d], message: %s. Friend [%d]", groupnumber, message, friendgroupnumber);
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        uint8_t *theirNameC[TOX_MAX_NAME_LENGTH];
        tox_group_peername([[TXCSingleton sharedSingleton] toxCoreInstance], groupnumber, friendgroupnumber, (uint8_t *)theirNameC);
        NSString *theirName = [NSString stringWithUTF8String:(const char *)theirNameC];
        NSString *theirMessage = [NSString stringWithUTF8String:(const char *)message];
        
        TXCMessageObject *theMessage = [[TXCMessageObject alloc] init];
        theMessage.message = theirMessage;
        theMessage.senderName = theirName;
        if ([theirName isEqualToString:[[TXCSingleton sharedSingleton] userNick]]) {
            theMessage.origin = MessageLocation_Me;
        } else {
            theMessage.origin = MessageLocation_Them;
        }
        theMessage.didFailToSend = NO;
        theMessage.actionMessage = NO;
        theMessage.groupMessage = YES;
        theMessage.senderKey = [[[[TXCSingleton sharedSingleton] groupList] objectAtIndex:groupnumber] groupPulicKey];
        //add to singleton
        //if the message coming through is not to the currently opened chat window, then uialertview it
        if ((groupnumber != [[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] row] &&
            [[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] section] != 0) ||
            [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground ||
            [[UIApplication sharedApplication] applicationState] == UIApplicationStateInactive) {
            NSMutableArray *tempMessages = [[[[TXCSingleton sharedSingleton] groupMessages] objectAtIndex:groupnumber] mutableCopy];
            [tempMessages addObject:theMessage];

            // Add message to singleton
            [[TXCSingleton sharedSingleton] groupMessages][groupnumber] = [tempMessages copy];
            
            // Fire a local notification for the message
            UILocalNotification *groupMessageNotification = [[UILocalNotification alloc] init];
            groupMessageNotification.fireDate = [NSDate date];
            groupMessageNotification.alertBody = [NSString stringWithFormat:@"[Group %d][%@]: %@", groupnumber, theirName, theirMessage];
            groupMessageNotification.alertAction = @"show the message";
            groupMessageNotification.timeZone = [NSTimeZone defaultTimeZone];
            groupMessageNotification.applicationIconBadgeNumber = [[UIApplication sharedApplication] applicationIconBadgeNumber] + 1;
            [[UIApplication sharedApplication] scheduleLocalNotification:groupMessageNotification];
            
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationNewMessage object:theMessage];
        }
        
    });
}

void print_nickchange(Tox *m, int friendnumber, uint8_t * string, uint16_t length, void *userdata) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Nick Change from [%d]: %s", friendnumber, string);
        
        uint8_t tempKey[TOX_PUBLIC_KEY_SIZE];
        tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, tempKey, 0); // TODO_BUMP error handling
        
        char convertedKey[(TOX_PUBLIC_KEY_SIZE * 2) + 1];
        int pos = 0;
        for (int i = 0; i < TOX_PUBLIC_KEY_SIZE; ++i, pos += 2) {
            sprintf(&convertedKey[pos] ,"%02X", tempKey[i] & 0xff);
        }
        
        if ([TXCSingleton friendNumber:friendnumber matchesKey:[NSString stringWithUTF8String:convertedKey]]) {
            
        } else {
            return;
        }
        
        
        TXCFriendObject *tempFriend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber];
        [tempFriend setNickname:[NSString stringWithUTF8String:(char *)string]];
        
        //save in user defaults
        [TXCSingleton saveFriendListInUserDefaults];
        
        //for now
        [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
    });
}

void print_statuschange(Tox *m, int friendnumber,  uint8_t * string, uint16_t length, void *userdata) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Status change from [%d]: %s", friendnumber, string);
        
        uint8_t tempKey[TOX_PUBLIC_KEY_SIZE];
        tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, tempKey, 0); // TODO_BUMP error handling
        
        char convertedKey[(TOX_PUBLIC_KEY_SIZE * 2) + 1];
        int pos = 0;
        for (int i = 0; i < TOX_PUBLIC_KEY_SIZE; ++i, pos += 2) {
            sprintf(&convertedKey[pos] ,"%02X", tempKey[i] & 0xff);
        }
        
        if ([TXCSingleton friendNumber:friendnumber matchesKey:[NSString stringWithUTF8String:convertedKey]]) {
            
        } else {
            return;
        }
        
        
        TXCFriendObject *tempFriend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber];
        [tempFriend setStatusMessage:[NSString stringWithUTF8String:(char *)string]];
        
        //save in user defaults
        [TXCSingleton saveFriendListInUserDefaults];
        
        //for now
        [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
    });
}

void print_userstatuschange(Tox *m, int friendnumber, uint8_t kind, void *userdata) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        uint8_t tempKey[TOX_PUBLIC_KEY_SIZE];
        tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, tempKey, 0); // TODO_BUMP error handling
        
        char convertedKey[(TOX_PUBLIC_KEY_SIZE * 2) + 1];
        int pos = 0;
        for (int i = 0; i < TOX_PUBLIC_KEY_SIZE; ++i, pos += 2) {
            sprintf(&convertedKey[pos] ,"%02X", tempKey[i] & 0xff);
        }
        
        if ([TXCSingleton friendNumber:friendnumber matchesKey:[NSString stringWithUTF8String:convertedKey]]) {
            
        } else {
            return;
        }
        
        
        TXCFriendObject *tempFriend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber];
        switch (kind) {
            case TOX_USER_STATUS_AWAY:
            {
                [tempFriend setStatusType:TXCToxFriendUserStatus_Away];
                NSLog(@"User status change: away");
                break;
            }
                
            case TOX_USER_STATUS_BUSY:
            {
                [tempFriend setStatusType:TXCToxFriendUserStatus_Busy];
                NSLog(@"User status change: busy");
                break;
            }
                
            case TOX_USER_STATUS_NONE:
            {
                [tempFriend setStatusType:TXCToxFriendUserStatus_None];
                NSLog(@"User status change: none");
                break;
            }
                
            default:
                break;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendUserStatusChanged object:nil];
    });
}

void print_connectionstatuschange(Tox *m, int friendnumber, uint8_t status, void *userdata) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Friend Status Change: [%d]: %d", friendnumber, (int)status);

        uint8_t tempKey[TOX_PUBLIC_KEY_SIZE];
        tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, tempKey, 0); // TODO_BUMP error handling
        
        char convertedKey[(TOX_PUBLIC_KEY_SIZE * 2) + 1];
        int pos = 0;
        for (int i = 0; i < TOX_PUBLIC_KEY_SIZE; ++i, pos += 2) {
            sprintf(&convertedKey[pos] ,"%02X", tempKey[i] & 0xff);
        }
        
        if ([TXCSingleton friendNumber:friendnumber matchesKey:[NSString stringWithUTF8String:convertedKey]]) {
            
        } else {
            return;
        }
        
        TXCFriendObject *tempFriend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber];
        switch (status) {
            case 0:
                tempFriend.connectionType = TXCToxFriendConnectionStatus_None;
                break;
                
            case 1:
                tempFriend.connectionType = TXCToxFriendConnectionStatus_Online;
                break;
                
            default:
                break;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendUserStatusChanged object:nil];
    });
}

void print_groupnamelistchange(Tox *m, int groupnumber, int peernumber, uint8_t change, void *userdata) {
    /*void (^code_block)(void) = ^void(void) {
        NSLog(@"New names:");
        uint8_t groupPeerList[256][TOX_MAX_NAME_LENGTH];
        int groupPeerCount = tox_group_get_names([[TXCSingleton sharedSingleton] toxCoreInstance], groupnumber, groupPeerList, 256);
        for (int i = 0; i < groupPeerCount; i++) {
            NSLog(@"\t%s", groupPeerList[i]);
        }
    };
    if ([NSThread isMainThread]) {
        code_block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), code_block);
    }*/
    switch (change) {
        case TOX_CHAT_CHANGE_PEER_ADD:
            NSLog(@"GroupChat[%d]: New Peer ([%d])", groupnumber, peernumber);
            break;
        case TOX_CHAT_CHANGE_PEER_NAME:
            NSLog(@"GroupChat[%d]: Peer[%d] -> ", groupnumber, peernumber);
            break;
        case TOX_CHAT_CHANGE_PEER_DEL:
            NSLog(@"GroupChat[%d]: Peer[%d] has left.", groupnumber, peernumber);
            break;
        default:
            break;
    }
}

#pragma mark - End Tox Core Callback Functions

#pragma mark - Thread methods

- (void)killToxThreadInBackground:(BOOL)inBackground {
    if (!inBackground) {
        NSLog(@"Killing main thread");
        if (self.toxMainThreadState != TXCThreadState_killed) {
            self.toxMainThreadState = TXCThreadState_waitingToKill;
        }
            
    } else {
        NSLog(@"Killing background thread");
        if (self.toxBackgroundThreadState != TXCThreadState_killed) {
            self.toxBackgroundThreadState = TXCThreadState_waitingToKill;
        }
    }
}

- (void)startToxThreadInBackground:(BOOL)inBackground {
    if (!inBackground) {
        if (self.toxMainThreadState == TXCThreadState_running) {
            NSLog(@"Trying to start main thread while it's already running.");
            return;
        }
        NSLog(@"Starting main thread");
        self.toxMainThreadState = TXCThreadState_running;
        dispatch_async(self.toxMainThread, ^{
            [self toxCoreLoopInBackground:NO];
        });
    } else {
        if (self.toxBackgroundThreadState == TXCThreadState_running) {
            NSLog(@"Trying to start background thread while it's already running.");
            return;
        }
        NSLog(@"Starting background thread");
        self.toxBackgroundThreadState = TXCThreadState_running;
        dispatch_async(self.toxBackgroundThread, ^{
            [self toxCoreLoopInBackground:YES];
        });
    }
}

- (void)toxCoreLoopInBackground:(BOOL)inBackground {
    
    TXCSingleton *singleton = [TXCSingleton sharedSingleton];
    Tox *toxInstance = [[TXCSingleton sharedSingleton] toxCoreInstance];
    
    //code to check if node connection has changed, if so notify the app
    if (self.on == 0 && tox_self_get_connection_status([[TXCSingleton sharedSingleton] toxCoreInstance]) != TOX_CONNECTION_NONE) {
        NSLog(@"DHT Connected!");
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ToxAppDelegateNotificationDHTConnected object:nil];
        });
        self.on = 1;
    }
    if (self.on == 1 && !tox_self_get_connection_status([[TXCSingleton sharedSingleton] toxCoreInstance]) != TOX_CONNECTION_NONE) {
        NSLog(@"DHT Disconnected!");
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ToxAppDelegateNotificationDHTDisconnected object:nil];
        });
        self.on = 0;
    }
    // If we haven't been connected for over two seconds, bootstrap to another node.
    if (self.on == 0 && singleton.lastAttemptedConnect < time(0)+2) {
        int num = rand() % [singleton.dhtNodeList count];
        unsigned char *binary_string = hex_string_to_bin((char *)[singleton.dhtNodeList[num][@"key"] UTF8String]);
        tox_bootstrap([[TXCSingleton sharedSingleton] toxCoreInstance],
                                   [singleton.dhtNodeList[num][@"ip"] UTF8String],
                                   // TODO_BUMP TOX_ENABLE_IPV6_DEFAULT,
                                   htons(atoi([singleton.dhtNodeList[num][@"port"] UTF8String])),
                                   binary_string, 0); //actual connection // TODO_BUMP error handling
        free(binary_string);
    }
    
    // TODO: Optimized tox_iterate
    
    // Run tox_do
    time_t a = time(0);
    tox_iterate([[TXCSingleton sharedSingleton] toxCoreInstance]);
    if (time(0) - a > 1) {
        NSLog(@"tox_do took more than %lu seconds!", time(0) - a);
    }

    // Keep going
    if (!inBackground) {
        if (self.toxMainThreadState == TXCThreadState_running || self.toxMainThreadState == TXCThreadState_killed) {
            dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(33333 * NSEC_PER_USEC));
            dispatch_after(waitTime, self.toxMainThread, ^{
                [self toxCoreLoopInBackground:NO];
            });
        } else if (self.toxMainThreadState == TXCThreadState_waitingToKill) {
            // Kill ourself
            NSLog(@"Main thread killed");
            self.toxMainThreadState = TXCThreadState_killed;
            return;
        }
    } else {
        if (self.toxBackgroundThreadState == TXCThreadState_running || self.toxBackgroundThreadState == TXCThreadState_killed) {
            dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50000 * NSEC_PER_USEC));
            dispatch_after(waitTime, self.toxBackgroundThread, ^{
                [self toxCoreLoopInBackground:YES];
            });
        } else if (self.toxBackgroundThreadState == TXCThreadState_waitingToKill) {
            // Kill ourself
            NSLog(@"Background thread killed");
            self.toxBackgroundThreadState = TXCThreadState_killed;
            return;
        }
    }
    
    
    
    if (self.on) {
        //print when the number of connected clients changes
        static int lastCount = 0;
        Messenger *m = (Messenger *)[[TXCSingleton sharedSingleton] toxCoreInstance];
        uint32_t i;
        uint64_t temp_time = time(0);
        uint16_t count = 0;
        for(i = 0; i < LCLIENT_LIST; ++i) {
            if (!(m->dht->close_clientlist[i].assoc4.timestamp + 70 <= temp_time) ||
                !(m->dht->close_clientlist[i].assoc6.timestamp + 70 <= temp_time))
                ++count;
            
        }
        if (count != lastCount) {
            NSLog(@"****Nodes connected: %d", count);
        }
        lastCount = count;
    }
}

#pragma mark - End Thread Methods

#pragma mark - Miscellaneous C Functions

unsigned char * hex_string_to_bin(char hex_string[])
{
    size_t len = strlen(hex_string);
    unsigned char *val = malloc(len);
    char *pos = hex_string;
    int i;
    for (i = 0; i < len; ++i, pos+=2)
        sscanf(pos,"%2hhX",&val[i]);
    
    return val;
}

/*
 * Gives the friend number corresponding to
 * the given Tox client ID (32bytes).
 * Returns -1 if not found.
 */
int friendNumForID(NSString *theKey) {
    //Convert key to uint8_t
    uint8_t *newKey = hex_string_to_bin((char *)[theKey UTF8String]);
    
    //Copy the friendlist (kinda) into a variable
    int friendListCount = tox_self_get_friend_list_size([[TXCSingleton sharedSingleton] toxCoreInstance]);
    uint32_t friendList[friendListCount];
    tox_self_get_friend_list([[TXCSingleton sharedSingleton] toxCoreInstance], friendList);
    
    //Loop through, check each key against the inputted key
    if (friendListCount > 0) {
        for (int i = 0; i < friendListCount; i++) {
            uint8_t tempKey[TOX_PUBLIC_KEY_SIZE];
            tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendList[i], tempKey, 0); // TODO_BUMP error handling
            
            if (memcmp(newKey, tempKey, TOX_PUBLIC_KEY_SIZE) == 0) { // True
                free(newKey);
                return i;
            }
        }
    }
    free(newKey);
    return -1;
}

/*
 * Gives the group number corresponding to
 * the given Tox client ID (32 bytes).
 * Returns -1 of not found.
 */
// TODO: UNFINISHED
/*
int groupNumForID(NSString *theKey) {
    //Convert key to uint8_t
    uint8_t *newKey = hex_string_to_bin((char *)[theKey UTF8String]);
    
    //Copy the grouplist (kinda) into a variable
    int groupList[256];
    int groupListCount = tox_get_chatlist([[TXCSingleton sharedSingleton] toxCoreInstance], groupList, 256);
    
    //Loop through, check each key against the inputted key
    if (groupListCount > 0) {
        for (int i = 0; i < groupListCount; i++) {
            uint8_t tempKey[TOX_CLIENT_ID_SIZE];
            
        }
    }
    
}*/

/*
 resolve_addr():
 address should represent IPv4 or a hostname with A record
 
 returns a data in network byte order that can be used to set IP.i or IP_Port.ip.i
 returns 0 on failure
 
 TODO: Fix ipv6 support
 */
uint32_t resolve_addr(const char *address)
{
    struct addrinfo *server = NULL;
    struct addrinfo  hints;
    int              rc;
    uint32_t         addr;
    
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_INET;    // IPv4 only right now.
    hints.ai_socktype = SOCK_DGRAM; // type of socket Tox uses.
    
    rc = getaddrinfo(address, "echo", &hints, &server);
    
    // Lookup failed.
    if (rc != 0) {
        return 0;
    }
    
    // IPv4 records only..
    if (server->ai_family != AF_INET) {
        freeaddrinfo(server);
        return 0;
    }
    
    
    addr = ((struct sockaddr_in *)server->ai_addr)->sin_addr.s_addr;
    
    freeaddrinfo(server);
    return addr;
}

#pragma mark - End Miscellaneous C Functions

#pragma mark - Toxicity Visual Design Methods

- (void)customizeAppearence {
    [[JSBubbleView appearance] setFont:[UIFont systemFontOfSize:16.0f]];

    [self configureNavigationControllerDesign:(UINavigationController *)self.window.rootViewController];
}

- (void)configureNavigationControllerDesign:(UINavigationController *)navController {
    //first, non ios specific stuff:
    
    
    //ios specific stuff
    
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1) {
        // Load resources for iOS 6.1 or earlier
        navController.navigationBar.tintColor = [UIColor colorWithRed:0.3f green:0.37f blue:0.43f alpha:1];
        navController.toolbar.tintColor = [UIColor colorWithRed:0.3f green:0.37f blue:0.43f alpha:1];
    } else {
        // Load resources for iOS 7 or later
        navController.navigationBar.barTintColor = [UIColor colorWithRed:0.3f green:0.37f blue:0.43f alpha:1];
        navController.toolbar.barTintColor = [UIColor colorWithRed:0.3f green:0.37f blue:0.43f alpha:1];
        
        NSDictionary *titleColorsDict = [[NSDictionary alloc] initWithObjectsAndKeys:[UIColor whiteColor], UITextAttributeTextColor, nil];
        [[UIBarButtonItem appearance] setTitleTextAttributes:titleColorsDict forState:UIControlStateNormal];
        
        NSDictionary *pressedTitleColorsDict = [[NSDictionary alloc] initWithObjectsAndKeys:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0f], UITextAttributeTextColor, nil];
        [[UIBarButtonItem appearance] setTitleTextAttributes:pressedTitleColorsDict forState:UIControlStateHighlighted];
    }
}

#pragma mark - End Toxicity Visual Design Methods

@end
