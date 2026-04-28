//  Copyright (c) 2014 James Linnell
//      2026 nilFinx

// Known tags:
// TODO
// TOOD_BUMP
// UNFINISHED
// ERRPRINT (as part of the error printing migration later on)

#import "TXCAppDelegate.h"
#import "TXCFriendAddress.h"
#import "TWMessageBarManager.h"
#import "JSBubbleView.h"
#import <ZBarReaderView.h>

NSString *const TXCToxAppDelegateNotificationFriendAdded				= @"FriendAdded";
NSString *const TXCToxAppDelegateNotificationConferenceAdded			= @"ConferenceAdded";
NSString *const TXCToxAppDelegateNotificationFriendRequestReceived		= @"FriendRequestReceived";
NSString *const TXCToxAppDelegateNotificationConferenceInviteReceived	= @"ConferenceInviteReceived";
NSString *const TXCToxAppDelegateNotificationNewMessage					= @"NewMessage";
NSString *const TXCToxAppDelegateNotificationFriendUserStatusChanged	= @"FriendUserStatusChanged";
NSString *const ToxAppDelegateNotificationDHTConnected					= @"DHTConnected";
NSString *const ToxAppDelegateNotificationDHTDisconnected				= @"DHTDisconnected";

NSString *const TXCToxAppDelegateUserDefaultsToxSave					= @"TXCToxData";

NSString *const TXCToxAppDefaultName						= @"Toxicity User";
NSString *const TXCToxAppDefaultStatus						= @"Toxing on Toxicity";
NSString *const TXCToxAppDefaultFriendRequestMessage		= @"Toxicity user here! Please add me.";

@implementation TXCAppDelegate

#pragma mark - Application Delegation Methods

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	[ZBarReaderView class];
	
	[self setupTox];
	
	[self customizeAppearence];
	
	self.toxMainThread = dispatch_queue_create("space.recycledplist.Toxicity", DISPATCH_QUEUE_SERIAL);
	self.toxMainThreadState = TXCThreadState_killed;
	self.toxBackgroundThread = dispatch_queue_create("space.recycledplist.ToxicityBG", DISPATCH_QUEUE_SERIAL);
	self.toxBackgroundThreadState = TXCThreadState_killed;
	
	UILocalNotification *locationNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
	if (locationNotification) {
		// TODO: ? Go to most recent chat message
	}
	// TODO: Only reduce badge number when the chats are visited
	application.applicationIconBadgeNumber = 0;
	
	return YES;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
	if ([application applicationState] == UIApplicationStateActive) {
		[[TWMessageBarManager sharedInstance] showMessageWithTitle:@"New Message"
													   description:notification.alertBody
															  type:TWMessageBarMessageTypeInfo];
		application.applicationIconBadgeNumber = 0;
	}
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	// Sent when the application is *about* to move from active to inactive state.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	// Save to be safe.
	
	[TXCSingleton saveToxDataInUserDefaults];
	
	// First and foremost kill our main thread. This is a must.
	[self killToxThreadInBackground:NO];
	while (self.toxMainThreadState != TXCThreadState_killed) { }
	
	// Do nothing on devices that lacks multitasking support.
	if (![[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)]) {
		if (![[UIDevice currentDevice] isMultitaskingSupported]) {
			return;
		}
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
	// Called as part of the transition from the background to the inactive state
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
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
	// Kill any threads present
	[self killToxThreadInBackground:YES];
	[self killToxThreadInBackground:NO];
	
	while (self.toxMainThreadState != TXCThreadState_killed && self.toxBackgroundThreadState != TXCThreadState_killed) {
		// Wait for both threads (only one should be running at a time though) to end
	}
	
	[TXCSingleton saveToxDataInUserDefaults];
	
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

- (void)setupTox
{
	NSLog(@"Running on ToxCore %i.%i.%i", tox_version_major(), tox_version_minor(), tox_version_patch());
	
	// User defaults is the easy way to save info between app launches. Don't have to read a file manually, etc. Basically a plist.
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	
	TOX_ERR_OPTIONS_NEW optNewErr;
	struct Tox_Options* opt = tox_options_new(&optNewErr);
	if (optNewErr != TOX_ERR_OPTIONS_NEW_OK)
	{
		NSLog(@"Failed to initialize Tox options: %i", optNewErr); // ERRPRINT
		exit(1);
	}
	
	// Load save
	if ([prefs objectForKey:TXCToxAppDelegateUserDefaultsToxSave] != nil) {
		NSLog(@"Loading the save");
		NSData *theKey = [prefs objectForKey:TXCToxAppDelegateUserDefaultsToxSave];
		
		uint8_t *data = (uint8_t *)[theKey bytes];
		
		// TODO: Swap for setters
		opt->savedata_type = TOX_SAVEDATA_TYPE_TOX_SAVE;
		opt->savedata_length = [theKey length];
		opt->savedata_data = data;
	}
	
	TOX_ERR_NEW toxNewErr;
	Tox *tox = tox_new(opt, &toxNewErr);
	if (toxNewErr != TOX_ERR_NEW_OK)
	{
		NSLog(@"Failed to initialize Tox: %i", toxNewErr); // ERRPRINT
		exit(1);
	}
	
	[[TXCSingleton sharedSingleton] setToxCoreInstance:tox];
	
	if ([prefs objectForKey:TXCToxAppDelegateUserDefaultsToxSave] == nil) {
		NSLog(@"Saving the new save");
		[TXCSingleton saveToxDataInUserDefaults];
	}
	
	// Callbacks
	tox_callback_friend_name(					tox, callbackFriendName);
	tox_callback_friend_status_message(			tox, callbackFriendStatusMessage);
	tox_callback_friend_status(					tox, callbackFriendStatus);
	tox_callback_friend_connection_status(		tox, callbackFriendConnectionStatus);
	tox_callback_friend_request(				tox, callbackFriendRequest);
	tox_callback_friend_message(				tox, callbackFriendMessage);
	
	tox_callback_conference_invite(				tox, callbackConferenceInvite);
	tox_callback_conference_message(			tox, callbackConferenceMessage);
	tox_callback_conference_peer_list_changed(	tox, callbackConferencePeerListChanged);
	// TODO: peer name change and porentially other conference CBs
	
	// Load nick and status message
	if (tox_self_get_name_size(tox) == 0) {
		[[TXCSingleton sharedSingleton] setUserNick:TXCToxAppDefaultName];
		tox_self_set_name(tox, (uint8_t *)[[[TXCSingleton sharedSingleton] userNick] UTF8String], strlen([[[TXCSingleton sharedSingleton] userNick] UTF8String]), NULL); // TODO_BUMP error handling
	} else {
		uint8_t name[tox_self_get_name_size(tox)];
		tox_self_get_name(tox, name);
		[[TXCSingleton sharedSingleton] setUserNick:[NSString stringWithFormat:@"%s", name]];
	}
	if (tox_self_get_status_message_size(tox) == 0) {
		[[TXCSingleton sharedSingleton] setUserStatusMessage:TXCToxAppDefaultStatus];
		tox_self_set_status_message(tox, (uint8_t *)[[[TXCSingleton sharedSingleton] userStatusMessage] UTF8String], [[[TXCSingleton sharedSingleton] userStatusMessage] length], NULL); // TODO_BUMP error handling
	} else {
		uint8_t status[tox_self_get_status_message_size(tox)];
		tox_self_get_status_message(tox, status);
		[[TXCSingleton sharedSingleton] setUserStatusMessage:[NSString stringWithFormat:@"%s", status]];
	}
	
	size_t size = tox_self_get_friend_list_size(tox);
	if (size != 0) {
		uint32_t friends[size];
		tox_self_get_friend_list(tox, friends);
		for (int i = 0; i < size; i++) {
			uint32_t fid = friends[i];
			
			TXCFriendObject *friend = [[TXCFriendObject alloc] init];
			
			uint8_t pkey[tox_public_key_size()];
			tox_friend_get_public_key(tox, fid, pkey, NULL);
			char *cpkey = bin_to_hex_string(pkey, tox_public_key_size());
			friend.publicKey = [NSString stringWithFormat:@"%s", cpkey];
			free(cpkey);
			
			size_t nameSize = tox_friend_get_name_size(tox, fid, NULL);
			if (nameSize != 0) {
				uint8_t name[nameSize];
				tox_friend_get_name(tox, fid, name, NULL);
				friend.nickname = [[NSString alloc] initWithBytes:name length:nameSize encoding:NSUTF8StringEncoding];
			}
			
			size_t statSize = tox_friend_get_status_message_size(tox, fid, NULL);
			if (statSize != 0) {
				uint8_t stat[statSize];
				tox_friend_get_status_message(tox, fid, stat, NULL);
				friend.statusMessage = [[NSString alloc] initWithBytes:stat length:statSize encoding:NSUTF8StringEncoding];
			}
			
			[[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSArray array] atIndex:fid];
			[[[TXCSingleton sharedSingleton] mainFriendList] insertObject:friend atIndex:fid];
		}
	}
	
	// TODO: Load conferences
	
	// Loads any pending friend requests
	if ([prefs objectForKey:@"pending_requests_list"] != nil)
		[[TXCSingleton sharedSingleton] setPendingFriendRequests:(NSMutableDictionary *)[prefs objectForKey:@"pending_requests_list"]];
	
	// TODO: Load pending conference requests
	
	uint8_t ourAddress1[tox_address_size()];
	tox_self_get_address([[TXCSingleton sharedSingleton] toxCoreInstance], ourAddress1);
	char *convertedAddress = bin_to_hex_string(ourAddress1, tox_address_size());
	NSLog(@"Our Address: %s", convertedAddress);
	free(convertedAddress);
	
	for (id obj in [TXCSingleton sharedSingleton].dhtNodeList) {
		unsigned char *pubkey = hex_string_to_bin((char *)[obj[@"key"] UTF8String]);
		const char *ip = [obj[@"ip"] UTF8String];
		TOX_ERR_BOOTSTRAP err;
		tox_bootstrap(tox, ip, htons(atoi([obj[@"port"] UTF8String])), pubkey, &err);
		free(pubkey);
		if (err != TOX_ERR_BOOTSTRAP_OK)
			NSLog(@"Error bootstrapping to %s: %i", ip, err);
	}
}

#pragma mark - End Application Delegation

#pragma mark - Tox related Methods

- (BOOL)userNickChanged {
	NSString *nick = [[TXCSingleton sharedSingleton] userNick];
	
	__block BOOL returnVar = TRUE;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		TOX_ERR_SET_INFO err;
		tox_self_set_name([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)[nick UTF8String], [nick length], &err);
		if (err != TOX_ERR_SET_INFO_OK)
			quickAlertErr(@"Could not change the nick name", tox_err_set_info_to_string(err));
		returnVar = err == TOX_ERR_SET_INFO_OK;
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW + (100000 * NSEC_PER_USEC));
	return returnVar;
}

- (BOOL)userStatusChanged {
	NSString *status = [[TXCSingleton sharedSingleton] userStatusMessage];
	
	__block BOOL returnVar = TRUE;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		TOX_ERR_SET_INFO err;
		tox_self_set_status_message([[TXCSingleton sharedSingleton] toxCoreInstance], (uint8_t *)[status UTF8String], [status length], &err);
		if (err != TOX_ERR_SET_INFO_OK)
			quickAlertErr(@"Could not change the user status", tox_err_set_info_to_string(err));
		returnVar = err == TOX_ERR_SET_INFO_OK;
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW + (100000 * NSEC_PER_USEC));
	return returnVar;
}

- (void)userStatusTypeChanged {
	TOX_USER_STATUS statusType;
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

- (BOOL)sendMessage:(TXCMessageObject *)message {
	Tox *tox = [[TXCSingleton sharedSingleton] toxCoreInstance];
	
	// Organize our message data
	__block uint32_t friendNum = -1;
	if (message.isConferenceMessage)
		friendNum = tox_conference_by_id(tox, (uint8_t *)[message.recipientKey UTF8String], NULL);
	else
		friendNum = friendNumForID(message.recipientKey);
	if (friendNum == -1) {
		// In case something data-wise messed up, and the friend no longer exists, or the key got messed up.
		quickAlert(@"Error",
			@"Uh oh, something went wrong! The friend key you're trying to send a message to doesn't seem to be in your friend list. \
			Try restarting the app and send a bug report!");
		return FALSE;
	}
	
	NSLog(@"Sending Message %@", message);
	
	__block BOOL returnVar = TRUE;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		uint32_t num;
		const char *error;
		// TODO_BUMP error handling here
		NSString *msg = message.isActionMessage ? [message.message substringFromIndex:2] : message.message;
		if (!message.conferenceMessage) {
			TOX_ERR_FRIEND_SEND_MESSAGE err;
			num = tox_friend_send_message(tox, friendNum, message.isActionMessage ? TOX_MESSAGE_TYPE_ACTION : TOX_MESSAGE_TYPE_NORMAL,
				(uint8_t *)[msg UTF8String], [msg length], &err);
			if (err != TOX_ERR_FRIEND_SEND_MESSAGE_OK)
			{
				error = tox_err_friend_send_message_to_string(err);
				returnVar = FALSE;
			}
		} else {
			TOX_ERR_CONFERENCE_SEND_MESSAGE err;
			num = tox_conference_send_message(tox, friendNum, message.isActionMessage ? TOX_MESSAGE_TYPE_ACTION : TOX_MESSAGE_TYPE_NORMAL,
				(uint8_t *)[msg UTF8String], [msg length], &err);
			if (err != TOX_ERR_FRIEND_SEND_MESSAGE_OK)
			{
				error = tox_err_conference_send_message_to_string(err);
				returnVar = FALSE;
			}
		}
		
		if (!returnVar)
			quickAlertErr(@"Error sending a message", error);
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW + (100000 * NSEC_PER_USEC));
	return returnVar;
}

- (BOOL)addFriend:(NSString *)address {
	Tox *tox = [[TXCSingleton sharedSingleton] toxCoreInstance];
	NSLog(@"Adding: %@", address);
	
	uint8_t *binID = hex_string_to_bin((char *)[address UTF8String]);
	__block uint32_t fid;
	__block TOX_ERR_FRIEND_ADD err;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		fid = tox_friend_add(tox, binID, (uint8_t *)[TXCToxAppDefaultFriendRequestMessage UTF8String], [TXCToxAppDefaultFriendRequestMessage length], &err);
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	free(binID);
	
	switch (err) {
		case TOX_ERR_FRIEND_ADD_OK: {
			// Add friend to the singleton array, for use throughout the app.
			TXCFriendObject *friend = [[TXCFriendObject alloc] init];
			[friend setPublicKey:[address substringToIndex:(tox_public_key_size() * 2)]];
			[friend setStatusMessage:@"Waiting for request..."];
			
			[[[TXCSingleton sharedSingleton] mainFriendList] insertObject:friend atIndex:fid];
			[[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSArray array] atIndex:fid];
			
			[TXCSingleton saveToxDataInUserDefaults];
			
			break;
		}
		default:
			quickAlertErr(@"Error adding friend", tox_err_friend_add_to_string(err));
	}
	return err == TOX_ERR_FRIEND_ADD_OK;
}

- (void)acceptFriendRequests:(NSArray *)keysToAccept {
	__block TOX_ERR_FRIEND_ADD err;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		[keysToAccept enumerateObjectsUsingBlock:^(NSString* arrayKey, NSUInteger idx, BOOL *stop) {
			NSData *data = [[[[TXCSingleton sharedSingleton] pendingFriendRequests] objectForKey:arrayKey] copy];
			
			uint8_t *key = (uint8_t *)[data bytes];
			int num = tox_friend_add_norequest([[TXCSingleton sharedSingleton] toxCoreInstance], key, &err);
			free(key);
			
			switch (err) {
				case TOX_ERR_FRIEND_ADD_OK: {
					TXCFriendObject *friend = [[TXCFriendObject alloc] init];
					[friend setPublicKey:[arrayKey substringToIndex:(tox_public_key_size() * 2)]];
					NSLog(@"Accepted request from %@", [friend publicKey]);
					[friend setNickname:@"Unnamed user"];
					[friend setStatusMessage:@""];
					
					[[[TXCSingleton sharedSingleton] mainFriendList] insertObject:friend atIndex:num];
					[[[TXCSingleton sharedSingleton] mainFriendMessages] insertObject:[NSArray array] atIndex:num];
					
					[TXCSingleton saveToxDataInUserDefaults];
					
					// Remove from the pending requests
					[[[TXCSingleton sharedSingleton] pendingFriendRequests] removeObjectForKey:arrayKey];
					
					[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
					
					break;
				}
				default:
					quickAlertErr(@"Error accepting friend request", tox_err_friend_add_to_string(err));
			}
		}];
		
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	[[NSUserDefaults standardUserDefaults] setObject:[[TXCSingleton sharedSingleton] pendingFriendRequests] forKey:@"pending_requests_list"];
}

- (void)acceptConferenceInvites:(NSArray *)keysToAccept {
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		for (NSString *arrayKey in keysToAccept) {
			
			NSData *data = [[[[TXCSingleton sharedSingleton] pendingConferenceInvites] objectForKey:arrayKey] copy];
			uint32_t cid = [[[[TXCSingleton sharedSingleton] pendingConferenceInviteFriendNumbers] objectForKey:arrayKey] unsignedIntValue];
			
			TOX_ERR_CONFERENCE_JOIN err;
			int num = tox_conference_join([[TXCSingleton sharedSingleton] toxCoreInstance], cid, (uint8_t *)[data bytes], [data length], &err);
			
			switch (err) {
				case TOX_ERR_CONFERENCE_JOIN_OK: {
					TXCConferenceObject *conference = [[TXCConferenceObject alloc] init];
					[conference setPublicKey:arrayKey];
					[[[TXCSingleton sharedSingleton] conferenceList] insertObject:conference atIndex:num];
					[[[TXCSingleton sharedSingleton] conferenceMessages] insertObject:[NSArray array] atIndex:num];
					
					[TXCSingleton saveToxDataInUserDefaults];
					
					[[[TXCSingleton sharedSingleton] pendingConferenceInvites] removeObjectForKey:arrayKey];
					[[[TXCSingleton sharedSingleton] pendingConferenceInviteFriendNumbers] removeObjectForKey:arrayKey];
					[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationConferenceAdded object:nil];
					
					break;
				}
				default:
					quickAlertErr(@"Error joining the conference", tox_err_conference_join_to_string(err));
			}
		}
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
}

- (BOOL)deleteFriend:(NSString*)friendKey {
	int friendNum = friendNumForID(friendKey);
	if (friendNum == -1) {
		return FALSE;
	}
	
	__block TOX_ERR_FRIEND_DELETE err;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		tox_friend_delete([[TXCSingleton sharedSingleton] toxCoreInstance], friendNum, &err);
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	switch (err) {
		case TOX_ERR_FRIEND_DELETE_OK: {
			[TXCSingleton saveToxDataInUserDefaults];
			break;
		}
		default: {
			quickAlertErr(@"Deleting the friend failed", tox_err_friend_delete_to_string(err));
			return -1;
		}
	}
	
	return err == TOX_ERR_FRIEND_DELETE_OK;
}

- (BOOL)deleteConference:(uint32_t)cid {
	__block TOX_ERR_CONFERENCE_DELETE err;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(self.toxMainThread, ^{
		tox_conference_delete([[TXCSingleton sharedSingleton] toxCoreInstance], cid, &err);
		dispatch_semaphore_signal(semaphore);
	});
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	switch (err) {
		case TOX_ERR_FRIEND_DELETE_OK: {
			[TXCSingleton saveToxDataInUserDefaults];
			break;
		}
		default: {
			quickAlertErr(@"Deleting the conference failed", tox_err_conference_delete_to_string(err));
			return -1;
		}
	}
	
	return err == TOX_ERR_FRIEND_DELETE_OK;
}

#pragma mark - End Tox related Methods

#pragma mark - Tox Core Callback Functions

void callbackFriendName(Tox *m, Tox_Friend_Number friendnumber, const uint8_t * name, size_t length, void *userdata) {
	dispatch_sync(dispatch_get_main_queue(), ^{
		NSLog(@"Name change from %d: %s", friendnumber, name);
		
		uint8_t pkey[tox_public_key_size()];
		TOX_ERR_FRIEND_GET_PUBLIC_KEY err;
		tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, pkey, &err);
		char *convertedKey = bin_to_hex_string(pkey, tox_public_key_size());
		if (err != TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK || ![TXCSingleton friendNumber:friendnumber matchesKey:[NSString stringWithUTF8String:convertedKey]])
			return;
		
		free(convertedKey);
		
		TXCFriendObject *tempFriend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber];
		[tempFriend setNickname:[NSString stringWithUTF8String:(char *)name]];
		
		[TXCSingleton saveToxDataInUserDefaults];
		
		// TODO: Change to a different notification
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
	});
}

void callbackFriendStatusMessage(Tox *m, Tox_Friend_Number friendnumber, const uint8_t * string, size_t length, void *userdata) {
	dispatch_sync(dispatch_get_main_queue(), ^{
		NSLog(@"Status message change from %d: %s", friendnumber, string);
		
		uint8_t pkey[tox_public_key_size()];
		TOX_ERR_FRIEND_GET_PUBLIC_KEY err;
		tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendnumber, pkey, &err);
		char *convertedKey = bin_to_hex_string(pkey, tox_public_key_size());
		if (err != TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK || ![TXCSingleton friendNumber:friendnumber matchesKey:[NSString stringWithUTF8String:convertedKey]])
			return;
		
		
		TXCFriendObject *tempFriend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber];
		[tempFriend setStatusMessage:[NSString stringWithUTF8String:(char *)string]];
		
		[TXCSingleton saveToxDataInUserDefaults];
		
		// TODO: Change to a different notification
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendAdded object:nil];
	});
}

void callbackFriendStatus(Tox *m, Tox_Friend_Number fid, TOX_USER_STATUS status, void *userdata) {
	dispatch_sync(dispatch_get_main_queue(), ^{
		
		uint8_t pkey[tox_public_key_size()];
		TOX_ERR_FRIEND_GET_PUBLIC_KEY err;
		tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], fid, pkey, &err);
		char *convertedKey = bin_to_hex_string(pkey, tox_public_key_size());
		if (err != TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK || ![TXCSingleton friendNumber:fid matchesKey:[NSString stringWithUTF8String:convertedKey]])
			return;
		
		
		TXCFriendObject *friend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:fid];
		switch (status) {
			case TOX_USER_STATUS_AWAY:
			{
				[friend setStatusType:TXCToxFriendUserStatus_Away];
				NSLog(@"Status change from %d: away", fid);
				break;
			}
			case TOX_USER_STATUS_BUSY:
			{
				[friend setStatusType:TXCToxFriendUserStatus_Busy];
				NSLog(@"Status change from %d: busy", fid);
				break;
			}
			case TOX_USER_STATUS_NONE:
			{
				[friend setStatusType:TXCToxFriendUserStatus_None];
				NSLog(@"Status change from %d: none", fid);
				break;
			}
			default:
				break;
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendUserStatusChanged object:nil];
	});
}

void callbackFriendConnectionStatus(Tox *m, Tox_Friend_Number fid, TOX_CONNECTION status, void *userdata) {
	dispatch_sync(dispatch_get_main_queue(), ^{
		
		uint8_t tempKey[tox_public_key_size()];
		tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], fid, tempKey, 0); // TODO_BUMP error handling
		
		char convertedKey[(tox_public_key_size() * 2) + 1];
		int pos = 0;
		for (int i = 0; i < tox_public_key_size(); ++i, pos += 2) {
			sprintf(&convertedKey[pos] ,"%02X", tempKey[i] & 0xff);
		}
		
		if ([TXCSingleton friendNumber:fid matchesKey:[NSString stringWithUTF8String:convertedKey]]) {
			
		} else {
			return;
		}
		
		TXCFriendObject *friend = [[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:fid];
		switch (status) {
			case TOX_CONNECTION_NONE:
				friend.connectionType = TXCToxFriendConnectionStatus_None;
				NSLog(@"Status change from %d: None", fid);
				break;
			case TOX_CONNECTION_TCP:
				NSLog(@"Status change from %d: TCP", fid);
			case TOX_CONNECTION_UDP:
				NSLog(@"Status change from %d: UDP", fid);
			default:
				friend.connectionType = TXCToxFriendConnectionStatus_Online;
				break;
		}
		// TODO: Separate this from the user presence?
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendUserStatusChanged object:nil];
	});
}

void callbackFriendRequest(Tox *tox, const uint8_t *public_key, const uint8_t *data, size_t length, void *userdata) {
	dispatch_sync(dispatch_get_main_queue(), ^{
		NSLog(@"Friend Request! From: ");
		char *pkey = bin_to_hex_string((uint8_t *)public_key, tox_public_key_size());
		printf("%s\n", pkey);
		NSString *strpk = [NSString stringWithUTF8String:pkey];
		
		// Check to see if this person is already on our friends list
		for (TXCFriendObject *tempFriend in [[TXCSingleton sharedSingleton] mainFriendList]) {
			// If they're on our friends list, just auto accept.
			if ([tempFriend.publicKey isEqualToString:strpk]) {
				NSLog(@"The friend request we got is one of a friend we already have, calling add_no_request: %@ %@", tempFriend.nickname, tempFriend.publicKey);
				dispatch_async(((TXCAppDelegate *)[[UIApplication sharedApplication] delegate]).toxMainThread, ^{
					tox_friend_add_norequest([[TXCSingleton sharedSingleton] toxCoreInstance], public_key, NULL);
					// What do we even to if this fails? I have zero clue. TODO: Maybe think about this.
				});
				return;
			}
		}
		
		// We got a friend request, so we have to store it!
		[[[TXCSingleton sharedSingleton] pendingFriendRequests] setObject:[NSData dataWithBytes:public_key length:tox_public_key_size()] forKey:strpk];
		[[NSUserDefaults standardUserDefaults] setObject:[[TXCSingleton sharedSingleton] pendingFriendRequests] forKey:@"pending_requests_list"];
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationFriendRequestReceived object:nil];
		free(pkey);
		[TXCSingleton saveToxDataInUserDefaults];
	});
}

void callbackFriendMessage(Tox *m, uint32_t friendnumber, TOX_MESSAGE_TYPE type, const uint8_t * string, size_t length, void *userdata) {
	// TODO: Action messages
	dispatch_sync(dispatch_get_main_queue(), ^{
		NSLog(@"Message from %d: %s", friendnumber, string);
		
		TXCMessageObject *theMessage = [[TXCMessageObject alloc] init];
		theMessage.message = [NSString stringWithUTF8String:(char *)string];
		theMessage.senderName = [[TXCSingleton sharedSingleton] userNick];
		theMessage.origin = MessageLocation_Them;
		theMessage.didFailToSend = NO;
		theMessage.ConferenceMessage = NO;
		theMessage.actionMessage = NO;
		[theMessage setSenderKey:[[[[TXCSingleton sharedSingleton] mainFriendList] objectAtIndex:friendnumber] publicKey]];
		
		
		// If the message coming through is not to the currently opened chat window, then fire a notification.
		if ((
				friendnumber != [[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] row] &&
				[[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] section] != 1
			) || [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
			NSMutableArray *tempMessages = [[[[TXCSingleton sharedSingleton] mainFriendMessages] objectAtIndex:friendnumber] mutableCopy];
			[tempMessages addObject:theMessage];
			
			// Add message to singleton
			[[TXCSingleton sharedSingleton] mainFriendMessages][friendnumber] = [tempMessages copy];
			
			// Fire a local notification for the message
			UILocalNotification *friendMessageNotification = [[UILocalNotification alloc] init];
			friendMessageNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
			friendMessageNotification.alertBody = [NSString stringWithFormat:@"[%@]: %@", theMessage.senderName, theMessage.message];
			friendMessageNotification.alertAction = @"Show the message";
			friendMessageNotification.timeZone = [NSTimeZone defaultTimeZone];
			friendMessageNotification.applicationIconBadgeNumber = [[UIApplication sharedApplication] applicationIconBadgeNumber] + 1;
			[[UIApplication sharedApplication] scheduleLocalNotification:friendMessageNotification];
			NSLog(@"Sent UILocalNotification for the new message");
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationNewMessage object:theMessage];
	});
}

void callbackConferenceInvite(Tox *tox, Tox_Friend_Number fid, Tox_Conference_Type ctype, const uint8_t *cookie, size_t length, void *userdata) {
	// TODO: ctype stuff
	dispatch_sync(dispatch_get_main_queue(), ^{
		const char *convertedKey = bin_to_hex_string((uint8_t *)cookie, length);
		NSLog(@"Conference invite from friend %d, cookie: %s", fid, convertedKey);
		
		BOOL alreadyInThisConference = NO;
		for (TXCConferenceObject *tempConference in [[TXCSingleton sharedSingleton] conferenceList]) {
			if ([[NSString stringWithUTF8String:convertedKey] isEqualToString:[tempConference publicKey]]) {
				NSLog(@"The Conference we were invited to is one we're already in! %@", [tempConference publicKey]);
				alreadyInThisConference = YES;
				break;
			}
		}
		
		if (alreadyInThisConference == NO) {
			[[[TXCSingleton sharedSingleton] pendingConferenceInvites]
			 	setObject:[NSData dataWithBytes:cookie length:length] forKey:[NSString stringWithUTF8String:(char *)cookie]];
			[[[TXCSingleton sharedSingleton] pendingConferenceInviteFriendNumbers]
				setObject:[NSNumber numberWithInt:fid] forKey:[NSString stringWithUTF8String:(char *)cookie]];
			[[NSUserDefaults standardUserDefaults] setObject:[[TXCSingleton sharedSingleton] pendingConferenceInvites] forKey:@"pending_invites_list"];
			[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationConferenceInviteReceived object:nil];
			[TXCSingleton saveToxDataInUserDefaults];
		} else {
			TXCAppDelegate *tempAppDelegate = (TXCAppDelegate *)[[UIApplication sharedApplication] delegate];
			dispatch_async(tempAppDelegate.toxMainThread, ^{
				tox_conference_join([[TXCSingleton sharedSingleton] toxCoreInstance], fid, cookie, length, NULL);
			});
		}
		
	});
}

// connected

void callbackConferenceMessage(Tox *tox, Tox_Conference_Number cid, Tox_Conference_Peer_Number pid, Tox_Message_Type type, uint8_t * message, size_t length, void *userdata) {
	// TODO: Action messages
	NSLog(@"Conference message received from Conference %d, Peer %d: %s", cid, pid, message);
	dispatch_sync(dispatch_get_main_queue(), ^{
		Tox *tox = [[TXCSingleton sharedSingleton] toxCoreInstance];
		
		char *peerName[tox_conference_peer_get_name_size(tox, cid, pid, NULL)];
		tox_conference_peer_get_name(tox, cid, pid, (uint8_t *)peerName, NULL);
		NSString *speerName = [NSString stringWithUTF8String:(const char *)peerName];
		
		NSString *theirMessage = [NSString stringWithUTF8String:(const char *)message];
		
		TXCMessageObject *theMessage = [[TXCMessageObject alloc] init];
		theMessage.message = theirMessage;
		theMessage.senderName = speerName;
		theMessage.origin = [speerName isEqualToString:[[TXCSingleton sharedSingleton] userNick]] ? MessageLocation_Me : MessageLocation_Them;
		theMessage.didFailToSend = NO;
		theMessage.actionMessage = NO;
		theMessage.ConferenceMessage = YES;
		theMessage.senderKey = [[[[TXCSingleton sharedSingleton] conferenceList] objectAtIndex:cid] publicKey];
		
		// If the message coming through is not to the currently opened chat window, notify
		if ((
			cid != [[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] row] &&
			[[[TXCSingleton sharedSingleton] currentlyOpenedFriendNumber] section] != 0)
			|| [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
			NSMutableArray *tempMessages = [[[[TXCSingleton sharedSingleton] conferenceMessages] objectAtIndex:cid] mutableCopy];
			[tempMessages addObject:theMessage];
			
			[[TXCSingleton sharedSingleton] conferenceMessages][cid] = [tempMessages copy];
			
			// Fire a local notification for the message
			UILocalNotification *ConferenceMessageNotification = [[UILocalNotification alloc] init];
			ConferenceMessageNotification.fireDate = [NSDate date];
			// TODO: Conference name
			ConferenceMessageNotification.alertBody = [NSString stringWithFormat:@"[Conference %d][%@]: %@", cid, speerName, theirMessage];
			ConferenceMessageNotification.alertAction = @"Show the message";
			ConferenceMessageNotification.timeZone = [NSTimeZone defaultTimeZone];
			ConferenceMessageNotification.applicationIconBadgeNumber = [[UIApplication sharedApplication] applicationIconBadgeNumber] + 1;
			[[UIApplication sharedApplication] scheduleLocalNotification:ConferenceMessageNotification];
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:TXCToxAppDelegateNotificationNewMessage object:theMessage];
	});
}

// title

// peerName

void callbackConferencePeerListChanged(Tox *m, Tox_Conference_Peer_Number Conferencenumber, void *userdata) {
	// TODO: Restore
	/*void (^code_block)(void) = ^void(void) {
	 NSLog(@"New names:");
	 uint8_t ConferencePeerList[256][TOX_MAX_NAME_LENGTH];
	 int ConferencePeerCount = tox_Conference_get_names([[TXCSingleton sharedSingleton] toxCoreInstance], Conferencenumber, ConferencePeerList, 256);
	 for (int i = 0; i < ConferencePeerCount; i++) {
	 NSLog(@"\t%s", ConferencePeerList[i]);
	 }
	 };
	 if ([NSThread isMainThread]) {
	 code_block();
	 } else {
	 dispatch_sync(dispatch_get_main_queue(), code_block);
	 }
	 switch (change) {
	 case TOX_CHAT_CHANGE_PEER_ADD:
	 NSLog(@"ConferenceChat[%d]: New Peer ([%d])", Conferencenumber, peernumber);
	 break;
	 case :
	 NSLog(@"ConferenceChat[%d]: Peer[%d] -> ", Conferencenumber, peernumber);
	 break;
	 case TOX_CHAT_CHANGE_PEER_DEL:
	 NSLog(@"ConferenceChat[%d]: Peer[%d] has left.", Conferencenumber, peernumber);
	 break;
	 default:
	 break;
	 }*/
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
	Tox *tox = [[TXCSingleton sharedSingleton] toxCoreInstance];
	
	//code to check if node connection has changed, if so notify the app
	if (self.on == 0 && tox_self_get_connection_status(tox) != TOX_CONNECTION_NONE) {
		NSLog(@"DHT Connected!");
		dispatch_sync(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:ToxAppDelegateNotificationDHTConnected object:nil];
		});
		self.on = 1;
	}
	if (self.on == 1 && tox_self_get_connection_status(tox) == TOX_CONNECTION_NONE) {
		NSLog(@"DHT Disconnected!");
		dispatch_sync(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:ToxAppDelegateNotificationDHTDisconnected object:nil];
		});
		self.on = 0;
	}
	
	// TODO: Optimized tox_iterate
	
	// Run tox_do
	time_t a = time(0);
	tox_iterate(tox, NULL);
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

char * bin_to_hex_string(uint8_t bin[], size_t len)
{
	char *hexString = malloc(len * 2 + 1);
	int pos = 0;
	for (int i = 0; i < len; ++i, pos += 2) {
		sprintf(&hexString[pos] ,"%02X", bin[i] & 0xff);
	}
	return hexString;
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
	size_t friendListCount = tox_self_get_friend_list_size([[TXCSingleton sharedSingleton] toxCoreInstance]);
	uint32_t friendList[friendListCount];
	tox_self_get_friend_list([[TXCSingleton sharedSingleton] toxCoreInstance], friendList);
	
	//Loop through, check each key against the inputted key
	if (friendListCount > 0) {
		for (int i = 0; i < friendListCount; i++) {
			uint8_t tempKey[tox_public_key_size()];
			tox_friend_get_public_key([[TXCSingleton sharedSingleton] toxCoreInstance], friendList[i], tempKey, 0); // TODO_BUMP error handling
			
			if (memcmp(newKey, tempKey, tox_public_key_size()) == 0) { // True
				free(newKey);
				return i;
			}
		}
	}
	free(newKey);
	return -1;
}

/*
 * Gives the Conference number corresponding to
 * the given Tox client ID (32 bytes).
 * Returns -1 of not found.
 */
// TODO: UNFINISHED
/*
 int ConferenceNumForID(NSString *theKey) {
 //Convert key to uint8_t
 uint8_t *newKey = hex_string_to_bin((char *)[theKey UTF8String]);
 
 //Copy the Conferencelist (kinda) into a variable
 int ConferenceList[256];
 int ConferenceListCount = tox_get_chatlist([[TXCSingleton sharedSingleton] toxCoreInstance], ConferenceList, 256);
 
 //Loop through, check each key against the inputted key
 if (ConferenceListCount > 0) {
 for (int i = 0; i < ConferenceListCount; i++) {
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

void quickAlert(NSString *title, NSString *body) {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertView *alertView = [[UIAlertView alloc]
			initWithTitle:title
			message:body
			delegate:nil
			cancelButtonTitle:@"Okay"
			otherButtonTitles:nil];
		[alertView show];
	});
}

void quickAlertLog(NSString *title, NSString *body) {
	NSLog(@"%@: %@", title, body);
	quickAlert(title, body);
}

void quickAlertErr(NSString *title, const char *error) {
	NSLog(@"%@: %s", title, error);
	quickAlert(title, [NSString stringWithFormat:@"Error Code: %s", error]);
}

- (void)customizeAppearence {
	[[JSBubbleView appearance] setFont:[UIFont systemFontOfSize:16.0f]];
	
	[self configureNavigationControllerDesign:(UINavigationController *)self.window.rootViewController];
}

- (void)configureNavigationControllerDesign:(UINavigationController *)navController {
	if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1) {
		// iOS 6.1 or earlier
		navController.navigationBar.tintColor = [UIColor colorWithRed:0.3f green:0.37f blue:0.43f alpha:1];
		navController.toolbar.tintColor = [UIColor colorWithRed:0.3f green:0.37f blue:0.43f alpha:1];
	} else {
		// iOS 7 or later
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
