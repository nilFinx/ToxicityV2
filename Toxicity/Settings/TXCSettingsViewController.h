//  Copyright (c) 2014 James Linnell
//		2026 nilFinx

#import <UIKit/UIKit.h>


@interface TXCSettingsViewController : UITableViewController

@property (nonatomic, strong) UITextField *statusTextField;
@property (nonatomic, strong) UITextField *nameTextField;

- (IBAction)saveButtonPushed:(id)sender;

@end
