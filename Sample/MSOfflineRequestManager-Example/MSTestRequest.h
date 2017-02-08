//
//  MSTestRequest.h
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/6/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

@import MSOfflineRequestManager;

@interface MSTestRequest : OfflineRequest<NSURLSessionDownloadDelegate>

@property (copy, nonatomic, nullable) void (^completion) (NSError * _Nullable);

@end
