//
//  OfflineRequest.m
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/6/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

#import "OfflineRequest.h"

@implementation OfflineRequest

- (nonnull instancetype)initWithDictionary:(NSDictionary<NSString *, id> * _Nonnull)dictionary {
    self = [super init];
    return self;
}

- (NSDictionary<NSString *, id> * _Nullable)dictionaryRepresentation {
    return nil;
}

- (void)performRequestWithCompletion:(void (^ _Nonnull)(NSError * _Nullable))completion {
    completion(nil);
}

- (BOOL)shouldAttemptResubmissionForError:(NSError * _Nonnull)error {
    return false;
}

@end
