//
//  MSOfflineRequestTestViewController.h
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/7/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

#import <UIKit/UIKit.h>
@import MSOfflineRequestManager;

@interface MSOfflineRequestTestViewController : UIViewController<OfflineRequestManagerDelegate>

@property (weak, nonatomic) IBOutlet UILabel *connectionStatusLabel;
@property (weak, nonatomic) IBOutlet UILabel *completedRequestsLabel;
@property (weak, nonatomic) IBOutlet UILabel *pendingRequestsLabel;
@property (weak, nonatomic) IBOutlet UILabel *totalProgressLabel;

@end
