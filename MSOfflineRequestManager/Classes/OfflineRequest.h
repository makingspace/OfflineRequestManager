//
//  OfflineRequest.h
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/6/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol OfflineRequestDelegate;

@interface OfflineRequest : NSObject

@property (nonatomic, assign, nullable) id<OfflineRequestDelegate> delegate;

- (nonnull instancetype)initWithDictionary:(NSDictionary<NSString *, id> * _Nonnull)dictionary;
- (NSDictionary<NSString *, id> * _Nullable)dictionaryRepresentation;
- (void)performRequestWithCompletion:(void (^ _Nonnull)(NSError * _Nullable))completion;
- (BOOL)shouldAttemptResubmissionForError:(NSError * _Nonnull)error;

@end
