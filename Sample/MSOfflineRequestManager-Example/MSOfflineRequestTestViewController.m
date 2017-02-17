//
//  MSOfflineRequestTestViewController.m
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/7/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

#import "MSOfflineRequestTestViewController.h"
#import "MSTestRequest.h"

@interface MSOfflineRequestTestViewController ()

@property (nonatomic) BOOL requestsAllowed;

@end

@implementation MSOfflineRequestTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.requestsAllowed = true;
    
    [OfflineRequestManager manager].delegate = self;
    [self updateLabels];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)toggleRequestsAllowed:(UISwitch *)sender
{
    self.requestsAllowed = sender.on;
}

- (IBAction)queueRequest
{
    [[OfflineRequestManager manager] queueRequest:[MSTestRequest new]];
    [self updateLabels];
}

- (void)updateLabels;
{
    OfflineRequestManager *manager = [OfflineRequestManager manager];
    self.completedRequestsLabel.text = [NSString stringWithFormat:@"%li", (long)manager.currentRequestIndex];
    self.pendingRequestsLabel.text = [NSString stringWithFormat:@"%li", (long)(manager.requestCount - manager.currentRequestIndex)];
    self.totalProgressLabel.text = [NSString stringWithFormat:@"%i%%", (int)(manager.progress * 100)];
}

- (OfflineRequest *)offlineRequestWithDictionary:(NSDictionary<NSString *,id> *)dictionary
{
    return [MSTestRequest new];
}

- (BOOL)offlineRequestManager:(OfflineRequestManager *)manager shouldAttemptRequest:(OfflineRequest *)request
{
    return self.requestsAllowed;
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager didUpdateTo:(double)progress
{
    self.totalProgressLabel.text = [NSString stringWithFormat:@"%i%%", (int)(progress * 100)];
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager didUpdateConnectionStatus:(BOOL)connected
{
    self.connectionStatusLabel.text = connected ? @"Online" : @"Offline";
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager didFinishRequest:(OfflineRequest *)request
{
    [self updateLabels];
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager requestDidFail:(OfflineRequest *)request withError:(NSError *)error
{
    [self updateLabels];
}

@end
