//
//  MSTestRequest.h
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/6/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

@import MSOfflineRequestManager;

@interface MSTestRequest : NSObject<OfflineRequest, NSURLSessionDownloadDelegate>

@property (copy, nonatomic, nullable) void (^completion) (NSError * _Nullable);

@property (nonatomic, weak) id <OfflineRequestDelegate> _Nullable requestDelegate;

- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> * _Nonnull)dictionary;
- (void)performWithCompletion:(void (^ _Nonnull)(NSError * _Nullable))completion;

@end
