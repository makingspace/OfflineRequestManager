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
    
    [OfflineRequestManager defaultManager].delegate = self;
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
    [[OfflineRequestManager defaultManager] queueRequest:[MSTestRequest new]];
    [self updateLabels];
}

- (void)updateLabels;
{
    OfflineRequestManager *manager = [OfflineRequestManager defaultManager];
    self.completedRequestsLabel.text = [NSString stringWithFormat:@"%li", (long)manager.completedRequestCount];
    self.pendingRequestsLabel.text = [NSString stringWithFormat:@"%li", (long)(manager.totalRequestCount - manager.completedRequestCount)];
    self.totalProgressLabel.text = [NSString stringWithFormat:@"%i%%", (int)(manager.progress * 100)];
}

- (id<OfflineRequest>)offlineRequestWithDictionary:(NSDictionary<NSString *,id> *)dictionary
{
    return [[MSTestRequest alloc] initWithDictionary:dictionary];
}

- (BOOL)offlineRequestManager:(OfflineRequestManager *)manager shouldAttemptRequest:(id<OfflineRequest>)request
{
    return self.requestsAllowed;
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager didUpdateProgress:(double)progress
{
    self.totalProgressLabel.text = [NSString stringWithFormat:@"%i%%", (int)(progress * 100)];
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager didUpdateConnectionStatus:(BOOL)connected
{
    self.connectionStatusLabel.text = connected ? @"Online" : @"Offline";
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager didFinishRequest:(id<OfflineRequest>)request
{
    [self updateLabels];
}

- (void)offlineRequestManager:(OfflineRequestManager *)manager requestDidFail:(id<OfflineRequest>)request withError:(NSError *)error
{
    [self updateLabels];
}

@end
