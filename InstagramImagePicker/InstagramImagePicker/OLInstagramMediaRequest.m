//
//  InstagramMediaRequest.m
//  Ps
//
//  Created by Deon Botha on 09/12/2013.
//  Copyright (c) 2013 dbotha. All rights reserved.
//

#import "OLInstagramMediaRequest.h"
#import "OLInstagramImagePickerConstants.h"
#import <NXOAuth2Client/NXOAuth2.h>

@interface OLInstagramMediaRequest ()
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation OLInstagramMediaRequest

- (id)init {
    return [self initWithBaseURL:@"https://api.instagram.com/v1/users/self/media/recent"];
}

- (id)initWithBaseURL:(NSString *)baseURL {
    if (self = [super init]) {
        _baseURL = baseURL;
    }
    
    return self;
}

- (void)cancel {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    self.cancelled = YES;
}

- (void)fetchMediaWithCompletionHandler:(InstagramMediaRequestCompletionHandler)completionHandler filter:(InstagramMediaFilter)filter {
    NXOAuth2Account *account = [[[NXOAuth2AccountStore sharedStore] accounts] lastObject];
    [self fetchMediaForAccount:account completionHandler:completionHandler filter:filter];
}

- (void)fetchMediaForAccount:(NXOAuth2Account *)account completionHandler:(InstagramMediaRequestCompletionHandler)completionHandler filter:(InstagramMediaFilter)filter {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    if ([self.baseURL rangeOfString:@"access_token"].location == NSNotFound) {
        _baseURL = [self.baseURL stringByAppendingFormat:@"?access_token=%@", account.accessToken.accessToken];
    }
    
    NSURL *url = [NSURL URLWithString:[self.baseURL stringByAppendingString:@"&count=100"]];

    [NXOAuth2Request performMethod:@"GET"
                        onResource:url
                   usingParameters:nil
                       withAccount:account
               sendProgressHandler:^(unsigned long long bytesSend, unsigned long long bytesTotal) { }
                   responseHandler:^(NSURLResponse *response, NSData *responseData, NSError *error) {
                       [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                       if (self.cancelled) {
                           return;
                       }
                       
                       NSAssert([NSThread isMainThread], @"Oops not calling back on main thread");
                       
                       NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                       if (httpResponse.statusCode == 400 || httpResponse.statusCode == 401) {
                           // Kill all accounts and force the user to login again.
                           NSArray *accounts = [[NXOAuth2AccountStore sharedStore] accounts];
                           for (NXOAuth2Account *account in accounts) {
                               [[NXOAuth2AccountStore sharedStore] removeAccount:account];
                           }
                           
                           NSError *error = [NSError errorWithDomain:kOLInstagramImagePickerErrorDomain code:kOLInstagramImagePickerErrorCodeOAuthTokenInvalid userInfo:@{NSLocalizedDescriptionKey: @"Instagram authorization token has expired. You'll need to log in again."}];
                           if (completionHandler) completionHandler(error, nil, nil);
                       } else {
                           NSError *error;
                           NSDictionary *json = responseData == nil ? nil : [NSJSONSerialization JSONObjectWithData:responseData options:kNilOptions error:&error];
                           if (error) {
                               if (completionHandler) completionHandler(error, nil, nil);
                               return;
                           }
                           
                           if (httpResponse.statusCode != 200) {
                               // TODO: real error handling here based on response json error message!!!!
                                NSError *error = [NSError errorWithDomain:kOLInstagramImagePickerErrorDomain code:kOLInstagramImagePickerErrorCodeBadResponse userInfo:@{NSLocalizedDescriptionKey: @"Failed to reach Instagram. Please check your internet connectivity and try again."}];
                               if (completionHandler) completionHandler(error, nil, nil);
                           } else {
                               
                               NSError *error = [NSError errorWithDomain:kOLInstagramImagePickerErrorDomain code:kOLInstagramImagePickerErrorCodeBadResponse userInfo:@{NSLocalizedDescriptionKey: @"Received a bad response from Instagram. Please try again."}];
                               
                               id pagination = [json objectForKey:@"pagination"];
                               id data = [json objectForKey:@"data"];
                               if (![pagination isKindOfClass:[NSDictionary class]] || ![data isKindOfClass:[NSArray class]]) {
                                   if (completionHandler) completionHandler(error, nil, nil);
                                   return;
                               }
                               
                               NSString *nextURL = [pagination objectForKey:@"next_url"];
                               if (nextURL && ![nextURL isKindOfClass:[NSString class]]) {
                                   if (completionHandler) completionHandler(error, nil, nil);
                                   return;
                               }
                               
                               NSMutableArray *media = [[NSMutableArray alloc] init];
                               
                               for (id d in data) {
                                   if (![d isKindOfClass:[NSDictionary class]]) {
                                       continue;
                                   }
                                   
                                   OLInstagramMediaType type = OLInstagramMediaTypeImage;
                                   id type_val = [d valueForKey:@"type"];
                                   if ([type_val isEqualToString:@"video"]) {
                                       type = OLInstagramMediaTypeVideo;
                                   }
                                   
                                   id images = [d objectForKey:@"images"];
                                   if (![images isKindOfClass:[NSDictionary class]]) {
                                       continue;
                                   }
                                   
                                   id thumbnailResolutionImage = [images objectForKey:@"thumbnail"];
                                   id standardResolutionImage = [images objectForKey:@"standard_resolution"];
                                   if (![thumbnailResolutionImage isKindOfClass:[NSDictionary class]] || ![standardResolutionImage isKindOfClass:[NSDictionary class]]) {
                                       continue;
                                   }
                                   
                                   id thumbnailResolutionImageURLStr = [thumbnailResolutionImage objectForKey:@"url"];
                                   id standardResolutionMediaURLStr = [standardResolutionImage objectForKey:@"url"];
                                   if (![thumbnailResolutionImageURLStr isKindOfClass:[NSString class]] || ![standardResolutionMediaURLStr isKindOfClass:[NSString class]]) {
                                       continue;
                                   }
                                   
                                   if (type == OLInstagramMediaTypeVideo) {
                                       id videos = [d objectForKey:@"videos"];
                                       if (![videos isKindOfClass:[NSDictionary class]]) {
                                           continue;
                                       }

                                       id standardResolutionVideo = [videos objectForKey:@"standard_resolution"];
                                       if (![standardResolutionVideo isKindOfClass:[NSDictionary class]]) {
                                           continue;
                                       }

                                       standardResolutionMediaURLStr = [standardResolutionVideo objectForKey:@"url"];
                                       if (![standardResolutionMediaURLStr isKindOfClass:[NSString class]]) {
                                           continue;
                                       }
                                   }
                                   
                                   NSRange range = [thumbnailResolutionImageURLStr rangeOfString:@"http://"];
                                   if (range.location == 0) {
                                       thumbnailResolutionImageURLStr = [thumbnailResolutionImageURLStr stringByReplacingCharactersInRange:range withString:@"https://"];
                                   }
                                   
                                   range = [standardResolutionMediaURLStr rangeOfString:@"http://"];
                                   if (range.location == 0) {
                                       standardResolutionMediaURLStr = [standardResolutionMediaURLStr stringByReplacingCharactersInRange:range withString:@"https://"];
                                   }
                                   
                                   NSDictionary *location = [d valueForKey:@"location"];
                                   NSNumber *lat = nil;
                                   NSNumber *lon = nil;
                                   if (location != (id)[NSNull null]) {
                                       lat = [location valueForKey:@"latitude"];
                                       lon = [location valueForKey:@"longitude"];
                                   }
                                   
                                   OLInstagramMedia *im = [[OLInstagramMedia alloc] initWithThumbURL:[NSURL URLWithString:thumbnailResolutionImageURLStr]
                                                                                             fullURL:[NSURL URLWithString:standardResolutionMediaURLStr]
                                                                                           mediaType:type
                                                                                             caption:[[d valueForKey:@"caption"] valueForKey:@"text"]
                                                                                            latitude:lat
                                                                                           longitude:lon];
                                   if (filter(im) == TRUE) {
                                       [media addObject:im];
                                   }
                                   
                               }
                               
                               OLInstagramMediaRequest *nextPageRequest = nil;
                               if (nextURL) {
                                   nextPageRequest = [[OLInstagramMediaRequest alloc] initWithBaseURL:nextURL];
                               }
                               
                               if (completionHandler) completionHandler(nil, media, nextPageRequest);
                           }
                           
                       }
                       
                   }];

}

@end
