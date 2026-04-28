//  Copyright (c) 2014 James Linnell
//		2026 nilFinx

#import "TXCConferenceViewController.h"
#import "JSMessage.h"
#import "JSBubbleImageViewFactory.h"
#import "TXCSingleton.h"
#import "TXCAppDelegate.h"
#import "UIColor+ToxicityColors.h"

static NSString *const kSenderMe = @"Me";
extern NSString *const TXCToxAppDelegateNotificationNewMessage;

@interface TXCConferenceChatViewController ()

@property (nonatomic, strong) NSMutableArray *mainConferenceList;
@property (nonatomic, strong) NSMutableArray *mainConferenceMessages;
@property (nonatomic, strong) TXCConferenceObject *conferenceInfo;
@property (nonatomic, strong) NSMutableArray *messages;
@property (nonatomic, strong) NSIndexPath *friendIndex;
@property (nonatomic, strong) UIImageView *statusNavBarImageView;

@end

@implementation TXCConferenceChatViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (id)initWithFriendIndex:(NSIndexPath *)theIndex {
    
    self = [super init];
    if (self) {
        self.friendIndex = theIndex;
        
        self.mainConferenceList = [[TXCSingleton sharedSingleton] conferenceList];
        self.mainConferenceMessages = [[TXCSingleton sharedSingleton] conferenceMessages];
        
        self.messages = [[self.mainConferenceMessages objectAtIndex:self.friendIndex.row] mutableCopy];
        
        self.ConferenceInfo = [self.mainConferenceList objectAtIndex:self.friendIndex.row];
        
        [[TXCSingleton sharedSingleton] setCurrentlyOpenedFriendNumber:self.friendIndex];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.messageInputView.textView.placeHolder = @"";
    self.sender = kSenderMe;

    if (!self.conferenceInfo.name.length) {
        self.title = self.conferenceInfo.publicKey;
    } else {
        self.title = self.conferenceInfo.name;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(newMessage:)
                                                 name:TXCToxAppDelegateNotificationNewMessage
                                               object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    NSLog(@"view Did Appear");
    [super viewDidAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    NSLog(@"view did disappear");
    [super viewDidDisappear:animated];
    [TXCSingleton sharedSingleton].conferenceMessages[self.friendIndex.row] = self.messages.mutableCopy;
    [[TXCSingleton sharedSingleton] setCurrentlyOpenedFriendNumber:[NSIndexPath indexPathForItem:-1 inSection:-1]];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications Center stuff

- (void)updateUserInfo {
    if (!self.conferenceInfo.name.length)
        self.title = self.conferenceInfo.publicKey;
    else
        self.title = self.conferenceInfo.name;
    
    //todo: status (where to display?) and status type
}

- (void)newMessage:(NSNotification *)notification {
    TXCMessageObject *receivedMessage = [notification object];
    
    if ([receivedMessage.senderKey isEqualToString:self.conferenceInfo.publicKey]) {
        [self.tableView beginUpdates];
        
        [self.messages addObject:receivedMessage];
        
        [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForItem:(self.messages.count - 1) inSection:0]] withRowAnimation:UITableViewRowAnimationBottom];
        [self.tableView endUpdates];
        
        [self scrollToBottomAnimated:YES];
        [JSMessageSoundEffect playMessageReceivedSound];
    }
}

#pragma mark - Table view data source
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.messages.count;
}

#pragma mark - Messages view delegate
- (void)didSendText:(NSString *)text fromSender:(NSString *)sender onDate:(NSDate *)date
{
    TXCMessageObject *tempMessage = [[TXCMessageObject alloc] init];
    tempMessage.recipientKey = self.conferenceInfo.publicKey;
    
    if ([text length] >= 5) {
        //only check for the "/me " if the message is 5 or more characters in length.
        //5 because we can't send a blank action
        //text:"/me " the action would be ""
        //text:"/me h" the action would be "h"
        if ([[text substringToIndex:4] isEqualToString:@"/me "]) {
            tempMessage.message = [[NSString alloc] initWithFormat:@"* %@", [text substringFromIndex:4]];
            tempMessage.actionMessage = YES;
        } else {
            tempMessage.message = [text copy];
            tempMessage.actionMessage = NO;
        }
    } else {
        tempMessage.message = [text copy];
    }
    tempMessage.origin = MessageLocation_Me;
    tempMessage.didFailToSend = NO;
    tempMessage.ConferenceMessage = YES;
    
    TXCAppDelegate *ourDelegate = (TXCAppDelegate *)[[UIApplication sharedApplication] delegate];
    BOOL success = [ourDelegate sendMessage:tempMessage];
    if (!success) {
        tempMessage.didFailToSend = YES;
    }
    
    //add the message after we know if it failed or not
//    [messages addObject:tempMessage];
    
    [self finishSend];
}

- (JSBubbleMessageType)messageTypeForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TXCMessageObject *tempMessage = [self.messages objectAtIndex:indexPath.row];
    return tempMessage.origin == MessageLocation_Me ? JSBubbleMessageTypeOutgoing : JSBubbleMessageTypeIncoming;
}

- (UIImageView *)bubbleImageViewWithType:(JSBubbleMessageType)type forRowAtIndexPath:(NSIndexPath *)indexPath
{
    TXCMessageObject *tempMessage = [self.messages objectAtIndex:indexPath.row];
    if (tempMessage.origin == MessageLocation_Me) {
        return [JSBubbleImageViewFactory bubbleImageViewForType:type color:[UIColor js_bubbleBlueColor]];
    } else {
        return [JSBubbleImageViewFactory bubbleImageViewForType:type color:[UIColor js_bubbleLightGrayColor]];
    }
}

- (JSMessageInputViewStyle)inputViewStyle {
    return JSMessageInputViewStyleFlat;
}

- (BOOL)shouldPreventScrollToBottomWhileUserScrolling
{
    return YES;
}

- (BOOL)shouldDisplayTimestampForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)allowsPanToDismissKeyboard {
    return YES;
}

- (BOOL)hasTimestampForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (JSMessage *)messageForRowAtIndexPath:(NSIndexPath *)indexPath {
    TXCMessageObject *tempMessage = [self.messages objectAtIndex:indexPath.row];
    return [[JSMessage alloc] initWithText:tempMessage.message
                                    sender:tempMessage.origin == MessageLocation_Me ? kSenderMe : tempMessage.senderName
                                      date:nil];
}

- (UIImageView *)avatarImageViewForRowAtIndexPath:(NSIndexPath *)indexPath sender:(NSString *)sender
{
    return nil;
}

- (void)configureCell:(JSBubbleMessageCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    TXCMessageObject *tempMessage = [self.messages objectAtIndex:indexPath.row];
    if (cell.subtitleLabel && tempMessage.origin == MessageLocation_Them) {
        cell.subtitleLabel.text = [tempMessage senderName];
    }

    if (cell.messageType == JSBubbleMessageTypeOutgoing) {
        cell.bubbleView.textView.textColor = [UIColor whiteColor];
    }
}


@end
