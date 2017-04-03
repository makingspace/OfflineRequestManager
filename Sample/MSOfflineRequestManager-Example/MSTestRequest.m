//
//  MSTestRequest.m
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/6/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

#import "MSTestRequest.h"

@implementation MSTestRequest

- (instancetype)initWithDictionary:(NSDictionary<NSString *,id> *)dictionary
{
    self = [super init];
    return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation
{
    return @{};
}

- (void)performWithCompletion:(void (^)(NSError * _Nullable))completion
{
    NSURLSessionConfiguration *defaultConfigObject = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration: defaultConfigObject delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    
    NSURL *url = [NSURL URLWithString: @"https://s3.amazonaws.com/fast-image-cache/demo-images/FICDDemoImage004.jpg"];
    NSURLSessionDownloadTask *task = [defaultSession downloadTaskWithURL:url];
    
    self.completion = completion;
    
    [task resume];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (self.completion) {
        self.completion(error);
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    [self.requestDelegate request:self didUpdateTo:((float)totalBytesWritten / (float)totalBytesExpectedToWrite)];
}

@end
