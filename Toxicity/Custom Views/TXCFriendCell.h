//  Copyright (c) 2014 James Linnell
//		2026 nilFinx

#import <UIKit/UIKit.h>
@class TXCFriendObject;
@class TXCConferenceObject;

typedef NS_ENUM(NSUInteger, FriendCellStatusColor) {
    FriendCellStatusColor_Gray,
    FriendCellStatusColor_Green,
    FriendCellStatusColor_Yellow,
    FriendCellStatusColor_Red
};

@interface TXCFriendCell : UITableViewCell

@property (nonatomic, copy) NSString *friendIdentifier;
@property (nonatomic, strong) UILabel *nickLabel;
@property (nonatomic, copy) NSString *messageLabelText;
@property (nonatomic, strong) UIImage *avatarImage;

@property (nonatomic, assign, getter = isShouldShowFriendStatus) BOOL shouldShowFriendStatus;
@property (nonatomic, assign) FriendCellStatusColor statusColor;
@property (nonatomic, strong) TXCFriendObject* friendObject;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, copy) NSString *lastMessage;

- (void)configureCellWithFriendObject:(TXCFriendObject *)friendObject;
- (void)configureCellWithConferenceObject:(TXCConferenceObject *)conferenceObject;
- (void)addNewMessagePin;
- (void)removeNewMessagePin;
@end
