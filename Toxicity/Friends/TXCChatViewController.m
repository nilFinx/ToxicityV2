//  Copyright (c) 2014 James Linnell
//		2026 nilFinx

#import "TXCChatViewController.h"
#import "UIColor+ToxicityColors.h"


@implementation TXCChatViewController

#pragma mark - View controller lifecycle

- (void)viewDidLoad {
    self.delegate = self;
    self.dataSource = self;
    [super viewDidLoad];

    self.backgroundColor = [UIColor toxicityBackgroundLightColor];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self scrollToBottomAnimated:NO];
}

@end