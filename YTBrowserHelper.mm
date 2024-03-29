//
//  YTBrowserHelper.mm
//  YTBrowserHelper
//
//  Created by Kevin Bradley on 12/30/15.
//  Copyright © 2015 nito. All rights reserved.
//

/**
 
 There is entirely too much packed into this "helper" class, I know that, but it works so I don't care ;-P
 
 This helper class and all the other classes contained herein handle file downloads, airplaying, and importing files
 into the iTunes music library. It is definitely a good candidate for MASSIVE refactoring, but since this is a
 free open source project I do for fun, I probably won't spend the time to do said massive refactoring without
 a good reason to do so.
 
 
 */

#import "NSTask.h"
#import "YTBrowserHelper.h"
#import "ipodimport.h"
#import <Foundation/Foundation.h>
#import "AppSupport/CPDistributedMessagingCenter.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CFNetwork/CFHTTPStream.h>

#import <arpa/inet.h>
#import <ifaddrs.h>



/*
 
 NSTask is private on iOS and on top of that, it doesn't appear to have waitUntilExit, so I found
 this code that apple used to use for waitUntilExit in some open source nextstep stuff, seems
 to still work fine.
 
 */

@implementation NSTask (convenience)

- (void) waitUntilExit
{
    NSTimer	*timer = nil;
    
    while ([self isRunning])
    {
        NSDate	*limit;
        
        /*
         *	Poll at 0.1 second intervals.
         */
        limit = [[NSDate alloc] initWithTimeIntervalSinceNow: 0.1];
        if (timer == nil)
        {
            timer = [NSTimer scheduledTimerWithTimeInterval: 0.1
                                                     target: nil
                                                   selector: @selector(class)
                                                   userInfo: nil
                                                    repeats: YES];
        }
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: limit];
        //RELEASE(limit);
    }
    [timer invalidate];
}

@end

/*
 
 the bulk of the airplay code is taken from EtherPlayer on github, some/most of these
 variables are frivolous and should be pruned.
 
 */


const NSUInteger    kAHVideo = 0,
kAHPhoto = 1,
kAHVideoFairPlay = 2,
kAHVideoVolumeControl = 3,
kAHVideoHTTPLiveStreams = 4,
kAHSlideshow = 5,
kAHScreen = 7,
kAHScreenRotate = 8,
kAHAudio = 9,
kAHAudioRedundant = 11,
kAHFPSAPv2pt5_AES_GCM = 12,
kAHPhotoCaching = 13;
const NSUInteger    kAHRequestTagReverse = 1,
kAHRequestTagPlay = 2;
const NSUInteger    kAHPropertyRequestPlaybackAccess = 1,
kAHPropertyRequestPlaybackError = 2,
kAHHeartBeatTag = 10;


const NSUInteger kAHAirplayStatusOffline = 0,
kAHAirplayStatusPlaying = 1,
kAHAirplayStatusPaused= 2;

@interface NSString (TSSAdditions)
- (id)dictionaryValue;
@end

@implementation NSString (TSSAdditions)


- (id)dictionaryValue
{
    NSString *error = nil;
    NSPropertyListFormat format;
    NSData *theData = [self dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    id theDict = [NSPropertyListSerialization propertyListFromData:theData
                                                  mutabilityOption:NSPropertyListImmutable
                                                            format:&format
                                                  errorDescription:&error];
    return theDict;
}


@end

//make things compile and keep it from complaining about undefined methods

@interface JOiTunesImportHelper : NSObject

+ (_Bool)importAudioFileAtPath:(id)arg1 mediaKind:(id)arg2 withMetadata:(id)arg3 serverURL:(id)arg4;
+ (id)downloadManager;

@end

@implementation YTBrowserHelper

@synthesize airplaying, airplayTimer, deviceIP, sessionID, airplayDictionary, operations;

//@synthesize webServer;
/*
 - (void)testRunServer
 {
 self.webServer = [[GCDWebServer alloc] init];
 [self.webServer addGETHandlerForBasePath:@"/" directoryPath:@"/var/mobile/Media/Downloads/" indexFilename:nil cacheAge:0 allowRangeRequests:YES];
 
 if ([self.webServer startWithPort:57287 bonjourName:@""]) {
 
 NSLog(@"started web server on port: %i", self.webServer.port);
 }
 }
 */


+ (id)sharedInstance {
    
    static dispatch_once_t onceToken;
    static YTBrowserHelper *shared;
    if (!shared){
        dispatch_once(&onceToken, ^{
            shared = [YTBrowserHelper new];
            shared.prevInfoRequest = @"/scrub";
            shared.operationQueue = [NSOperationQueue mainQueue];
            shared.downloadQueue = [NSOperationQueue currentQueue];
            shared.operationQueue.name = @"Connection Queue";
            shared.downloadQueue.name = @"Download Queue";
            shared.airplaying = NO;
            shared.paused = YES;
            shared.playbackPosition = 0;
            shared.operations = [NSMutableArray new];
        });
    }
    
    return shared;
    
}

//DASH audio is a weird format, take that aac file and pump out a useable m4a file, with volume adjustment if necessary

- (void)fixAudio:(NSString *)theFile volume:(NSInteger)volume completionBlock:(void(^)(NSString *newFile))completionBlock
{
    //NSLog(@"fix audio: %@", theFile);
    NSString *importOutputFile = [NSString stringWithFormat:@"/var/mobile/Media/Downloads/%@", [[[theFile lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"]];
    NSString *outputFile = [[theFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        @autoreleasepool {
            
            NSTask *afcTask = [NSTask new];
            [afcTask setLaunchPath:@"/usr/bin/ffmpeg"];
            [afcTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];
            [afcTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
            NSMutableArray *args = [NSMutableArray new];
            [args addObject:@"-i"];
            [args addObject:theFile];
            
            if (volume == 0){
                [args addObjectsFromArray:[@"-acodec copy -y" componentsSeparatedByString:@" "]];
            } else {
                [args addObject:@"-vol"];
                [args addObject:[NSString stringWithFormat:@"%ld", (long)volume]];
                [args addObjectsFromArray:[@"-acodec aac -ac 2 -ar 44100 -ab 320K -strict -2 -y" componentsSeparatedByString:@" "]];
            }
            [args addObject:outputFile];
            [afcTask setArguments:args];
            //NSLog(@"mux %@", [args componentsJoinedByString:@" "]);
            [afcTask launch];
            [afcTask waitUntilExit];
            
        }
        
        [[NSFileManager defaultManager] copyItemAtPath:outputFile toPath:importOutputFile error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:theFile error:nil];
        completionBlock(importOutputFile);
    });
    
    
}
- (id)sharedApplication { //keep the compiler happy
    return nil;
}
- (void)startGCDWebServer {} //keep the compiler happy

/*
 
 the music import process is needlessly convoluted to "protect" us, SSDownloads can't be triggered via local files
 JODebox runs a server the open source project GCDWebServer, im pretty sure all it does is just host files from
 /var/mobile/Media/Downloads after preparing them to be compatible to keep SSDownloadManager queues happy in thinking
 the file is coming from a remote source.
 
 */

//this method is never actually called inside YTBrowserHelper, we hook into -(id)init in SpringBoard and add this
//method in YTBrowser.xm

- (NSDictionary *)handleMessageName:(NSString *)name userInfo:(NSDictionary *)userInfo
{
    if ([[name pathExtension] isEqualToString:@"startAirplay"])
    {
        [[YTBrowserHelper sharedInstance] startAirplayFromDictionary:userInfo];
        
    } else if ([[name pathExtension] isEqualToString:@"addDownload"]) {
        
        [[YTBrowserHelper sharedInstance] addDownloadToQueue:userInfo];

        
    } else if ([[name pathExtension] isEqualToString:@"stopDownload"]) {
        
        [[YTBrowserHelper sharedInstance] removeDownloadFromQueue:userInfo];
    }
    
    
    return nil;
}

- (void)removeDownloadFromQueue:(NSDictionary *)downloadInfo
{
    for (YTDownloadOperation *operation in [self operations])
    {
        if ([[operation name] isEqualToString:downloadInfo[@"title"]])
        {
            NSLog(@"found operation, cancel it!");
            [operation cancel];
        }
    }
    [self clearDownload:downloadInfo];
}

//add a download to our NSOperationQueue

- (void)addDownloadToQueue:(NSDictionary *)downloadInfo
{
    YTDownloadOperation *downloadOp = [[YTDownloadOperation alloc] initWithInfo:downloadInfo completed:^(NSString *downloadedFile) {
        
        if (downloadedFile == nil)
        {
            NSLog(@"no downloaded file, either cancelled or failed!");
            return;
        }
        if (![[downloadedFile pathExtension] isEqualToString:[downloadInfo[@"outputFilename"] pathExtension]])
        {
            NSMutableDictionary *mutableCopy = [downloadInfo mutableCopy];
            [mutableCopy setValue:[downloadedFile lastPathComponent] forKey:@"outputFilename"];
            [mutableCopy setValue:[NSNumber numberWithBool:false] forKey:@"inProgress"];
            [self updateDownloadsProgress:mutableCopy];
        } else {
            [self updateDownloadsProgress:downloadInfo];
        }
        
        NSLog(@"download completed!");
        [[self operations] removeObject:downloadOp];
        [self playCompleteSound];
        
    }];
    [[self operations] addObject:downloadOp];
    [self.downloadQueue addOperation:downloadOp];
}

- (void)clearDownload:(NSDictionary *)streamDictionary
{
    NSFileManager *man = [NSFileManager defaultManager];
    NSString *dlplist = [self downloadFile];
    NSMutableArray *currentArray = nil;
    if ([man fileExistsAtPath:dlplist])
    {
        currentArray = [[NSMutableArray alloc] initWithContentsOfFile:dlplist];
        NSMutableDictionary *updateObject = [[currentArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.title == %@", streamDictionary[@"title"]]]lastObject];
        NSInteger objectIndex = [currentArray indexOfObject:updateObject];
        if (objectIndex != NSNotFound)
        {
            [currentArray removeObject:updateObject];
        }
        
    } else {
        currentArray = [NSMutableArray new];
    }
    //[currentArray addObject:streamDictionary];
    [currentArray writeToFile:dlplist atomically:true];
}

//update download progress of whether or not a file is inProgress or not, used to separate downloads in
//UI of tuyu downloads section.

- (void)updateDownloadsProgress:(NSDictionary *)streamDictionary
{
    NSFileManager *man = [NSFileManager defaultManager];
    NSString *dlplist = [self downloadFile];
    NSMutableArray *currentArray = nil;
    if ([man fileExistsAtPath:dlplist])
    {
        currentArray = [[NSMutableArray alloc] initWithContentsOfFile:dlplist];
        NSMutableDictionary *updateObject = [[currentArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.title == %@", streamDictionary[@"title"]]]lastObject];
        NSInteger objectIndex = [currentArray indexOfObject:updateObject];
        if (objectIndex != NSNotFound)
        {
            if ([[streamDictionary[@"outputFilename"]pathExtension] isEqualToString:@"m4a"])
            {
                [currentArray replaceObjectAtIndex:objectIndex withObject:streamDictionary];
                // [currentArray removeObject:updateObject];
                
            } else {
                [updateObject setValue:[NSNumber numberWithBool:false] forKey:@"inProgress"];
                [currentArray replaceObjectAtIndex:objectIndex withObject:updateObject];
                
            }
        }
        
    } else {
        currentArray = [NSMutableArray new];
    }
    //[currentArray addObject:streamDictionary];
    [currentArray writeToFile:dlplist atomically:true];
}

//standard tri-tone completion sound

- (void)playCompleteSound
{
    NSString *thePath = @"/Applications/yourTube.app/complete.aif";
    //NSString *thePath = [[NSBundle mainBundle] pathForResource:@"complete" ofType:@"aif"];
    SystemSoundID soundID;
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath: thePath], &soundID);
    AudioServicesPlaySystemSound (soundID);
}


- (void)startAirplayFromDictionary:(NSDictionary *)airplayDict
{
    CFUUIDRef UUID = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef UUIDString = CFUUIDCreateString(kCFAllocatorDefault,UUID);
    self.sessionID = (__bridge NSString *)UUIDString;
    self.deviceIP = airplayDict[@"deviceIP"];
    NSString *address = [NSString stringWithFormat:@"http://%@", airplayDict[@"deviceIP"]];
    self.baseUrl = [NSURL URLWithString:address];
    [self playRequest:airplayDict[@"videoURL"]];
}

- (void)playRequest:(NSString *)httpFilePath
{
    NSDictionary        *plist = nil;
    NSString            *errDesc = nil;
    NSString            *appName = nil;
    NSError             *error = nil;
    NSData              *outData = nil;
    NSString            *dataLength = nil;
    CFURLRef            myURL;
    CFStringRef         bodyString;
    CFStringRef         requestMethod;
    CFHTTPMessageRef    myRequest;
    CFDataRef           mySerializedRequest;
    
    NSLog(@"/play");
    
    appName = @"MediaControl/1.0";
    
    plist = @{ @"Content-Location" : httpFilePath,
               @"Start-Position" : @0.0f };
    
    outData = [NSPropertyListSerialization dataFromPropertyList:plist
                                                         format:NSPropertyListBinaryFormat_v1_0
                                               errorDescription:&errDesc];
    
    if (outData == nil && errDesc != nil) {
        NSLog(@"Error creating /play info plist: %@", errDesc);
        return;
    }
    
    dataLength = [NSString stringWithFormat:@"%lu", [outData length]];
    
    bodyString = CFSTR("");
    requestMethod = CFSTR("POST");
    myURL = (__bridge CFURLRef)[self.baseUrl URLByAppendingPathComponent:@"play"];
    myRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod,
                                           myURL, kCFHTTPVersion1_1);
    
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("User-Agent"),
                                     (__bridge CFStringRef)appName);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Content-Length"),
                                     (__bridge CFStringRef)dataLength);
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("Content-Type"),
                                     CFSTR("application/x-apple-binary-plist"));
    CFHTTPMessageSetHeaderFieldValue(myRequest, CFSTR("X-Apple-Session-ID"),
                                     (__bridge CFStringRef)self.sessionID);
    mySerializedRequest = CFHTTPMessageCopySerializedMessage(myRequest);
    self.data = [(__bridge NSData *)mySerializedRequest mutableCopy];
    [self.data appendData:outData];
    self.mainSocket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                 delegateQueue:dispatch_get_main_queue()];
    
    NSArray *ipArray = [deviceIP componentsSeparatedByString:@":"];
    NSError *connectError = nil;
    
    [self.mainSocket connectToHost:[ipArray firstObject] onPort:[[ipArray lastObject] integerValue] error:&connectError];
    
    if (connectError != nil)
    {
        NSLog(@"connection error: %@", [connectError localizedDescription]);
    }
    
    if (self.mainSocket != nil) {
        [self.mainSocket writeData:self.data
                       withTimeout:1.0f
                               tag:kAHRequestTagPlay];
        [self.mainSocket readDataToData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                            withTimeout:15.0f
                                    tag:kAHRequestTagPlay];
    } else {
        NSLog(@"Error connecting socket for /play: %@", error);
    }
}

- (void)setCommonHeadersForRequest:(NSMutableURLRequest *)request
{
    [request addValue:@"MediaControl/1.0" forHTTPHeaderField:@"User-Agent"];
    [request addValue:self.sessionID forHTTPHeaderField:@"X-Apple-Session-ID"];
}

- (NSDictionary *)synchronousPlaybackInfo
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/playback-info"
                                                                              relativeToURL:self.baseUrl]];
    [request addValue:@"MediaControl/1.0" forHTTPHeaderField:@"User-Agent"];
    NSURLResponse *theResponse = nil;
    NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:nil];
    NSString *datString = [[NSString alloc] initWithData:returnData  encoding:NSUTF8StringEncoding];
    NSLog(@"return details: %@", datString);
    return [datString dictionaryValue];
}



//  alternates /scrub and /playback-info
- (void)infoRequest
{
    [self writeOK];
    NSString                *nextRequest = @"/playback-info";
    NSMutableURLRequest     *request = nil;
    
    if (self.airplaying) {
        if ([self.prevInfoRequest isEqualToString:@"/playback-info"]) {
            nextRequest = @"/scrub";
            self.prevInfoRequest = @"/scrub";
            
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                                 relativeToURL:self.baseUrl]];
            [self setCommonHeadersForRequest:request];
            [NSURLConnection sendAsynchronousRequest:request
                                               queue:self.operationQueue
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                       //  update our position in the file after /scrub
                                       NSString    *responseString = [[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding];
                                       NSRange     cachedDurationRange = [responseString rangeOfString:@"position: "];
                                       NSUInteger  cachedDurationEnd;
                                       
                                       if (cachedDurationRange.location != NSNotFound) {
                                           cachedDurationEnd = cachedDurationRange.location + cachedDurationRange.length;
                                           self.playbackPosition = [[responseString substringFromIndex:cachedDurationEnd] doubleValue];
                                           //[self.delegate positionUpdated:self.playbackPosition];
                                       }
                                   }];
        } else {
            nextRequest = @"/playback-info";
            self.prevInfoRequest = @"/playback-info";
            
            request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nextRequest
                                                                 relativeToURL:self.baseUrl]];
            [self setCommonHeadersForRequest:request];
            [NSURLConnection sendAsynchronousRequest:request
                                               queue:self.operationQueue
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                       //  update our playback status and position after /playback-info
                                       NSDictionary            *playbackInfo = nil;
                                       NSString                *errDesc = nil;
                                       NSNumber                *readyToPlay = nil;
                                       NSPropertyListFormat    format;
                                       
                                       if (!self.airplaying) {
                                           return;
                                       }
                                       
                                       playbackInfo = [NSPropertyListSerialization propertyListFromData:data
                                                                                       mutabilityOption:NSPropertyListImmutable
                                                                                                 format:&format
                                                                                       errorDescription:&errDesc];
                                       
                                       //  NSLog(@"playbackInfo: %@", playbackInfo );
                                       
                                       if ([[playbackInfo allKeys] count] == 0 || playbackInfo == nil)
                                       {
                                           [self stopPlayback];
                                           
                                       }
                                       
                                       if ((readyToPlay = [playbackInfo objectForKey:@"readyToPlay"])
                                           && ([readyToPlay boolValue] == NO)) {
                                           NSDictionary    *userInfo = nil;
                                           NSString        *bundleIdentifier = nil;
                                           NSError         *error = nil;
                                           
                                           userInfo = @{ NSLocalizedDescriptionKey : @"Target AirPlay server not ready.  "
                                                         "Check if it is on and idle." };
                                           
                                           bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
                                           error = [NSError errorWithDomain:bundleIdentifier
                                                                       code:100
                                                                   userInfo:userInfo];
                                           
                                           NSLog(@"Error: %@", [error description]);
                                           [self stoppedWithError:error];
                                       } else if ([playbackInfo objectForKey:@"position"]) {
                                           self.playbackPosition = [[playbackInfo objectForKey:@"position"] doubleValue];
                                           self.paused = [[playbackInfo objectForKey:@"rate"] doubleValue] < 0.5f ? YES : NO;
                                           
                                           //[self.delegate setPaused:self.paused];
                                           //[self.delegate positionUpdated:self.playbackPosition];
                                       } else if (playbackInfo != nil) {
                                           [self getPropertyRequest:kAHPropertyRequestPlaybackError];
                                       } else {
                                           NSLog(@"Error parsing /playback-info response: %@", errDesc);
                                       }
                                   }];
        }
    }
}

- (void)togglePaused
{
    if (self.airplaying) {
        self.paused = !self.paused;
        [self changePlaybackStatus];
    }
}

- (void)getPropertyRequest:(NSUInteger)property
{
    NSMutableURLRequest *request = nil;
    NSString *reqType = nil;
    NSString *urlString = @"/getProperty?%@";
    if (property == kAHPropertyRequestPlaybackAccess) {
        reqType = @"playbackAccessLog";
    } else {
        reqType = @"playbackErrorLog";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:urlString, reqType]
                                                         relativeToURL:self.baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    [request setValue:@"application/x-apple-binary-plist" forHTTPHeaderField:@"Content-Type"];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               //  get the PLIST from the response and log it
                               NSDictionary            *propertyPlist = nil;
                               NSString                *errDesc = nil;
                               NSPropertyListFormat    format;
                               
                               propertyPlist = [NSPropertyListSerialization propertyListFromData:data
                                                                                mutabilityOption:NSPropertyListImmutable
                                                                                          format:&format
                                                                                errorDescription:&errDesc];
                               
                               [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                   NSLog(@"%@: %@", reqType, propertyPlist);
                               }];
                           }];
}

- (void)stopRequest
{
    NSMutableURLRequest *request = nil;
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/stop"
                                                         relativeToURL:self.baseUrl]];
    
    [self setCommonHeadersForRequest:request];
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               [self stoppedWithError:nil];
                               [self.mainSocket disconnectAfterReadingAndWriting];
                           }];
}

- (NSDictionary *)airplayState
{
    if (self.mainSocket == nil || [self.mainSocket isDisconnected] == true) {
        return @{@"playbackState": [NSNumber numberWithUnsignedInteger:kAHAirplayStatusOffline]};
    }
    
    if (airplaying && self.paused)
    {
        return @{@"playbackState": [NSNumber numberWithUnsignedInteger:kAHAirplayStatusPaused]};
    }
    if (airplaying && !self.paused)
    {
        return @{@"playbackState": [NSNumber numberWithUnsignedInteger:kAHAirplayStatusPlaying]};
    }
    
    return @{@"playbackState": [NSNumber numberWithUnsignedInteger:kAHAirplayStatusOffline]};
}

- (void)stopPlayback
{
    NSLog(@"stop playback");
    if (self.airplaying) {
        [self stopRequest];
        // [self.videoManager stop];
    }
}

- (void)changePlaybackStatus
{
    NSMutableURLRequest *request = nil;
    NSString            *rateString = @"/rate?value=1.00000";
    
    if (self.paused) {
        rateString = @"/rate?value=0.00000";
    }
    
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:rateString
                                                         relativeToURL:self.baseUrl]];
    request.HTTPMethod = @"POST";
    [self setCommonHeadersForRequest:request];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               //   Do nothing on completion
                           }];
}

- (void)stoppedWithError:(NSError *)error
{
    self.paused = NO;
    self.airplaying = NO;
    [self.infoTimer invalidate];
    self.playbackPosition = 0;

}

#pragma mark -
#pragma mark GCDAsyncSocket methods

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    NSLog(@"socket:didConnectToHost:port: called");
}

- (void)socket:(GCDAsyncSocket *)sock didWritePartialDataOfLength:(NSUInteger)partialLength
           tag:(long)tag
{
    NSLog(@"socket:didWritePartialDataOfLength:tag: called");
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if (tag == kAHRequestTagReverse) {
        //  /reverse request data written
    } else if (tag == kAHRequestTagPlay) {
        //  /play request data written
        self.airplaying = YES;
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSString    *replyString = nil;
    NSRange     range;
    
    replyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // NSLog(@"socket:didReadData:withTag: data:\r\n%@", replyString);
    
    if (tag == kAHRequestTagPlay) {
        //  /play request reply received and read
        range = [replyString rangeOfString:@"HTTP/1.1 200 OK"];
        
        if (range.location != NSNotFound) {
            self.airplaying = YES;
            self.paused = NO;
            // [self.delegate setPaused:self.paused];
            // [self.delegate durationUpdated:self.videoManager.duration];
            
            self.infoTimer = [NSTimer scheduledTimerWithTimeInterval:3.0f
                                                              target:self
                                                            selector:@selector(infoRequest)
                                                            userInfo:nil
                                                             repeats:YES];
        }
        
       // NSLog(@"read data for /play reply");
    }
}

- (void)writeOK
{
    NSData *okData = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
    [self.mainSocket writeData:okData withTimeout:10.0f tag:kAHHeartBeatTag];
}


/*
 
 +[<JOiTunesImportHelper: 0x106aacf10> importAudioFileAtPath:/var/mobile/Media/Downloads/Drake - Friends with Money (Produced by Tommy Gunnz) [0p].m4a mediaKind:song withMetadata:{
 albumName = "Unknown Album 2";
 artist = "Unknown Artist";
 duration = 247734;
 software = "Lavf56.40.101";
 title = "Drake - Friends with Money (Produced by Tommy Gunnz) [0p]";
 type = Music;
 year = 2016;
	} serverURL:http://localhost:52387/Media/Downloads]
 
 */

- (void)importFileWithJO:(NSString *)theFile duration:(NSInteger)duration
{
    //since this isnt being called through messages anymore we need to make sure we start the GCD server ourselves.
    id sbInstance = [NSClassFromString(@"SpringBoard") sharedApplication];
    [sbInstance startGCDWebServer];
    
    // NSLog(@"importFileWithJO: %@", theFile);
    //[self testRunServer];
    //NSData *imageData = [NSData dataWithContentsOfFile:@"/var/mobile/Library/Preferences/imageTest.png"];
    NSString *dlPath = @"/var/mobile/Library/Application Support/tuyu/Downloads";
    NSString *jpegFile = [dlPath stringByAppendingPathComponent:[[[theFile lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"] ];
    NSData *imageData = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:jpegFile])
    {
        NSLog(@"file exists: %@", jpegFile);
        imageData = [NSData dataWithContentsOfFile:jpegFile];
    } else {
        imageData = [NSData dataWithContentsOfFile:@"/Applications/yourTube.app/GenericArtwork.png"];
    }
    //NSData *imageData = [NSData dataWithContentsOfFile:@"/Applications/yourTube.app/GenericArtwork.png"];
    NSDictionary *theDict = @{@"albumName": @"tuyu downloads", @"artist": @"Unknown Artist", @"duration": [NSNumber numberWithInteger:duration], @"imageData":imageData, @"type": @"Music", @"software": @"Lavf56.40.101", @"title": [[theFile lastPathComponent] stringByDeletingPathExtension], @"year": @2016};
    Class joitih = NSClassFromString(@"JOiTunesImportHelper");
    [joitih importAudioFileAtPath:theFile mediaKind:@"song" withMetadata:theDict serverURL:@"http://localhost:52387/Media/Downloads"];
    
    //[self importFile:theFile withData:theDict serverURL:@"http://localhost:57287/Media/Downloads"];
}


//a failed attempt to replicate what JODebox does to import files into the library.

- (void)importFile:(NSString *)filePath withData:(NSDictionary *)inputDict serverURL:(NSString *)serverURL
{
    NSLog(@"importFile: %@", filePath);
    SSDownloadMetadata *metad = [[SSDownloadMetadata alloc] initWithKind:@"song"]; //r10
    NSString *downloads = @"/var/mobile/Media/Downloads"; //r6
    // NSString *serverArg = @"http://localhost:port/Media/Downloads"; //var_3C
    NSNumber *duration = inputDict[@"duration"];//get duration from input data
    
    
    NSString *fileServerPath = [filePath stringByReplacingOccurrencesOfString:downloads withString:serverURL]; //r4
    NSLog(@"fileServerPath: %@", fileServerPath);
    NSString *escapedPath = [fileServerPath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; //r5
    NSLog(@"escapedPath: %@", escapedPath);
    NSURL *urlString = [NSURL URLWithString:escapedPath]; //var_5C
    NSLog(@"urlString: %@", urlString);
    NSURLRequest *fileURLRequest = [NSURLRequest requestWithURL:urlString];
    double durationDouble = [duration doubleValue]; //r6
    NSNumber *updatedDuration = [NSNumber numberWithDouble:durationDouble*1000];
    [metad setDurationInMilliseconds:updatedDuration];
    
    [metad setArtistName:@"Unknown"];
    [metad setGenre:@"Unknown"];
    [metad setReleaseYear:@2016];
    [metad setPurchaseDate:[NSDate date]];
    [metad setShortDescription:@"This is a test"];
    [metad setLongDescription:@"This is a long test"];
    [metad setBundleIdentifier:@"com.nito.itunesimport"];
    [metad setComposerName:@"youTube Browser"];
    [metad setCopyright:@"© 2016 youTube Browser"];
    NSString *transID = [filePath lastPathComponent];
    [metad setTransactionIdentifier:transID];
    [metad setTitle:transID];
    NSData *imageData = inputDict[@"imageData"];
    NSURL *imageURL = nil;
    NSURLRequest *imageURLRequest = nil;
    if (imageData != nil){
        
        NSString *imageFile = [[filePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpeg"];
        [imageData writeToFile:imageFile atomically:YES];
        imageURL = [NSURL fileURLWithPath:imageFile];
        imageURLRequest = [NSURLRequest requestWithURL:imageURL];
    }
    
    
    
    SSDownload *fileDownload = [[SSDownload alloc] initWithDownloadMetadata:metad];
    if (imageURLRequest != nil)
    {
        SSDownloadAsset *imageAsset = [[SSDownloadAsset alloc] initWithURLRequest:imageURLRequest];
        [fileDownload addAsset:imageAsset forType:@"artwork"];
    }
    
    if (fileURLRequest != nil) //it better not be!
    {
        SSDownloadAsset *fileAsset = [[SSDownloadAsset alloc] initWithURLRequest:fileURLRequest];
        [fileDownload addAsset:fileAsset forType:@"media"];
    }
    
    SSDownloadQueue *dlQueue = [[SSDownloadQueue alloc] initWithDownloadKinds:[SSDownloadQueue mediaDownloadKinds]];
    SSDownloadManager *manager = [dlQueue downloadManager];
    [manager addDownloads:@[fileDownload] completionBlock:nil];
}


@end

