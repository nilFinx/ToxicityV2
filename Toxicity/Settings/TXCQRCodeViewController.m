//  Copyright (c) 2014 Виктор Шаманов
//		2014 James Linnell
//      2026 nilFinx

#import "TXCQRCodeViewController.h"
#import "QREncoder/QREncoder.h"

@interface TXCQRCodeViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *qrImageView;

@end

@implementation TXCQRCodeViewController

#pragma mark - View controller lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIImage *qrCode = [QREncoder encode:self.code size:4 correctionLevel:QRCorrectionLevelLow scaleFactor:10];
    self.qrImageView.image = qrCode;
}

@end
