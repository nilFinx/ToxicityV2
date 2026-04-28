//  Copyright (c) 2014 James Linnell
//		2026 nilFinx

#import <UIKit/UIKit.h>


@interface TXCFriendsListTableViewController : UITableViewController <UIAlertViewDelegate>

@property (nonatomic, copy) NSString* lastMessage;
@property (nonatomic, assign) NSUInteger numberOfLastMessageAuthor;

@end
