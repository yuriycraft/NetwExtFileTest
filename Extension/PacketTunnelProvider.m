// PacketTunnelProvider.m
#import "PacketTunnelProvider.h"

static NSString *const kAppGroupID = @"group.YC.NetwExtFileTest";
static NSString *const kLogFileName = @"50mb_log.txt";
static NSString *const kCommandFile = @"command.txt";
static NSString *const kResponseFile = @"response.txt";

@interface PacketTunnelProvider ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) dispatch_source_t fileWatcher;
@end

@implementation PacketTunnelProvider

- (void)startTunnelWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))handler {
    NSLog(@"[Extension] ========== STARTING TUNNEL ==========");
    
    // Setup network settings
    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"198.18.0.1"];
    
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[@"198.18.0.1"] subnetMasks:@[@"255.255.255.0"]];
    NEIPv4Route *defaultRoute = [[NEIPv4Route alloc] initWithDestinationAddress:@"0.0.0.0" subnetMask:@"0.0.0.0"];
    defaultRoute.gatewayAddress = @"198.18.0.1";
    ipv4.includedRoutes = @[defaultRoute];
    settings.IPv4Settings = ipv4;
    
    __weak typeof(self) weakSelf = self;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            NSLog(@"[Extension] Failed to set settings: %@", error);
            handler(error);
            return;
        }
        
        NSLog(@"[Extension] ✅ Tunnel settings applied");
        strongSelf.isRunning = YES;
        
        // Start watching for commands from app
        [strongSelf startWatchingForCommands];
        
        handler(nil);
    }];
}

#pragma mark - Watch for Commands

- (void)startWatchingForCommands {
    NSURL *container = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kAppGroupID];
    if (!container) {
        NSLog(@"[Extension] ❌ No App Groups container");
        return;
    }
    
    NSURL *commandURL = [container URLByAppendingPathComponent:kCommandFile];
    
    // Create directory if needed
    [[NSFileManager defaultManager] createDirectoryAtURL:container
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    
    int dirFd = open(container.path.UTF8String, O_EVTONLY);
    if (dirFd == -1) {
        NSLog(@"[Extension] ❌ Failed to open directory");
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, dirFd,
                                                      DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
    
    dispatch_source_set_event_handler(source, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:commandURL.path]) {
            NSError *error = nil;
            NSString *command = [NSString stringWithContentsOfFile:commandURL.path
                                                          encoding:NSUTF8StringEncoding
                                                             error:&error];
            if (command && [command isEqualToString:@"GENERATE_50MB_LOG"]) {
                NSLog(@"[Extension] Received GENERATE command");
                [strongSelf generate50MBLogToFile];
            }
            // Delete command after processing
            [[NSFileManager defaultManager] removeItemAtURL:commandURL error:nil];
        }
    });
    
    dispatch_source_set_cancel_handler(source, ^{
        close(dirFd);
    });
    
    dispatch_resume(source);
    self.fileWatcher = source;
    
    NSLog(@"[Extension] Watching for commands at: %@", container.path);
}

#pragma mark - Generate 50MB Log

- (void)generate50MBLogToFile {
    NSLog(@"[Extension] Starting to generate 50MB log...");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *container = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kAppGroupID];
        if (!container) {
            NSLog(@"[Extension] ❌ No App Groups container");
            return;
        }
        
        NSURL *logURL = [container URLByAppendingPathComponent:kLogFileName];
        
        // Delete old file
        [[NSFileManager defaultManager] removeItemAtURL:logURL error:nil];
        
        // Create new file
        [[NSFileManager defaultManager] createFileAtPath:logURL.path contents:nil attributes:nil];
        
        NSError *error = nil;
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingToURL:logURL error:&error];
        if (!fileHandle) {
            NSLog(@"[Extension] ❌ Failed to open file: %@", error);
            return;
        }
        
        const NSUInteger totalSize = 50 * 1024 * 1024; // 50 MB
        const NSUInteger chunkSize = 64 * 1024; // 64 KB
        NSMutableData *chunk = [NSMutableData dataWithLength:chunkSize];
        
        // Fill chunk with test pattern
        for (NSUInteger i = 0; i < chunkSize; i++) {
            ((uint8_t *)chunk.mutableBytes)[i] = i & 0xFF;
        }
        
        NSUInteger written = 0;
        NSUInteger lastPercent = 0;
        
        while (written < totalSize) {
            @autoreleasepool {
                [fileHandle writeData:chunk];
                [fileHandle synchronizeFile]; // Force flush to disk
                written += chunkSize;
                
                NSUInteger percent = (written * 100) / totalSize;
                if (percent >= lastPercent + 10) {
                    lastPercent = percent;
                    NSLog(@"[Extension] Generation progress: %lu%%", (unsigned long)percent);
                }
            }
        }
        
        [fileHandle closeFile];
        NSLog(@"[Extension] ✅ Successfully generated 50MB log file at: %@", logURL.path);
        
        // Write response marker
        NSURL *responseURL = [container URLByAppendingPathComponent:kResponseFile];
        [@"READY" writeToFile:responseURL.path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[Extension] Response marker written");
    });
}

#pragma mark - Packet Handling

- (void)readPackets {
    if (!self.isRunning) return;
    
    __weak typeof(self) weakSelf = self;
    [self.packetFlow readPacketsWithCompletionHandler:^(NSArray<NSData *> *packets, NSArray<NSNumber *> *protocols) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.isRunning) return;
        
        // Just pass packets through
        [strongSelf.packetFlow writePackets:packets withProtocols:protocols];
        [strongSelf readPackets];
    }];
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))handler {
    NSLog(@"[Extension] Stopping tunnel, reason: %ld", (long)reason);
    self.isRunning = NO;
    
    if (self.fileWatcher) {
        dispatch_source_cancel(self.fileWatcher);
        self.fileWatcher = nil;
    }
    
    handler();
}

@end
