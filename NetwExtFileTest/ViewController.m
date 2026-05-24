// ViewController.m
#import "ViewController.h"
#import <NetworkExtension/NetworkExtension.h>

static NSString *const kAppGroupID = @"group.YC.NetwExtFileTest";
static NSString *const kTunnelDescription = @"MyTunnel";
static NSString *const kCommandFile = @"command.txt";
static NSString *const kResponseFile = @"response.txt";
static NSString *const kLogFileName = @"50mb_log.txt";

@interface ViewController ()
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, strong) UIButton *stopBtn;
@property (nonatomic, strong) UIButton *sendLogBtn;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *logStatusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NETunnelProviderManager *currentManager;
@property (nonatomic, assign) BOOL isCheckingStatus;
@property (nonatomic, strong) dispatch_source_t fileWatcher;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self setupUI];
    [self startFileWatcher];
    [self checkAppGroupAccess];
    [self performSelector:@selector(checkStatus) withObject:nil afterDelay:0.5];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(vpnStatusChanged:)
                                                 name:NEVPNStatusDidChangeNotification
                                               object:nil];
}

- (void)setupUI {
    // Start Button
    self.startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startBtn.frame = CGRectMake(100, 120, 200, 50);
    [self.startBtn setTitle:@"Start VPN" forState:UIControlStateNormal];
    self.startBtn.backgroundColor = [UIColor systemGreenColor];
    [self.startBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startBtn.layer.cornerRadius = 8;
    [self.startBtn addTarget:self action:@selector(startVPN) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startBtn];
    
    // Stop Button
    self.stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopBtn.frame = CGRectMake(100, 185, 200, 50);
    [self.stopBtn setTitle:@"Stop VPN" forState:UIControlStateNormal];
    self.stopBtn.backgroundColor = [UIColor systemRedColor];
    [self.stopBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.stopBtn.layer.cornerRadius = 8;
    self.stopBtn.enabled = NO;
    self.stopBtn.alpha = 0.6;
    [self.stopBtn addTarget:self action:@selector(stopVPN) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopBtn];
    
    // Send Log Button
    self.sendLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendLogBtn.frame = CGRectMake(100, 250, 200, 50);
    [self.sendLogBtn setTitle:@"Generate & Share 50MB Log" forState:UIControlStateNormal];
    self.sendLogBtn.backgroundColor = [UIColor systemOrangeColor];
    [self.sendLogBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.sendLogBtn.layer.cornerRadius = 8;
    self.sendLogBtn.enabled = NO;
    self.sendLogBtn.alpha = 0.6;
    [self.sendLogBtn addTarget:self action:@selector(sendLogCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendLogBtn];
    
    // Status Label
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 330, self.view.bounds.size.width - 40, 40)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.text = @"VPN: Checking...";
    [self.view addSubview:self.statusLabel];
    
    // Progress View
    self.progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(40, 390, self.view.bounds.size.width - 80, 10)];
    self.progressView.progress = 0;
    self.progressView.hidden = YES;
    [self.view addSubview:self.progressView];
    
    // Log Status Label
    self.logStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 410, self.view.bounds.size.width - 40, 50)];
    self.logStatusLabel.textAlignment = NSTextAlignmentCenter;
    self.logStatusLabel.font = [UIFont systemFontOfSize:12];
    self.logStatusLabel.textColor = [UIColor grayColor];
    self.logStatusLabel.text = @"Log: Not generated";
    self.logStatusLabel.numberOfLines = 0;
    [self.view addSubview:self.logStatusLabel];
    
    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2, 480);
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
}

#pragma mark - App Groups Helpers

- (void)checkAppGroupAccess {
    NSURL *container = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kAppGroupID];
    if (container) {
        NSLog(@"[App] ✅ App Groups container: %@", container.path);
        
        // Write test file
        NSString *testPath = [container.path stringByAppendingPathComponent:@"app_test.txt"];
        [@"app_test" writeToFile:testPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[App] Test file written: %@", testPath);
        
        self.logStatusLabel.text = @"App Groups: OK";
    } else {
        NSLog(@"[App] ❌ No App Groups container! Check entitlements.");
        self.logStatusLabel.text = @"App Groups: NOT configured!";
        self.logStatusLabel.textColor = [UIColor redColor];
    }
}

- (NSURL *)getAppGroupContainer {
    return [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kAppGroupID];
}

#pragma mark - File Watcher

- (void)startFileWatcher {
    NSURL *container = [self getAppGroupContainer];
    if (!container) {
        NSLog(@"[App] ❌ No App Groups container");
        return;
    }
    
    NSURL *responseURL = [container URLByAppendingPathComponent:kResponseFile];
    NSURL *logURL = [container URLByAppendingPathComponent:kLogFileName];
    
    int dirFd = open(container.path.UTF8String, O_EVTONLY);
    if (dirFd == -1) {
        NSLog(@"[App] ❌ Failed to open directory");
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, dirFd,
                                                      DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
    
    dispatch_source_set_event_handler(source, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:responseURL.path] &&
            [[NSFileManager defaultManager] fileExistsAtPath:logURL.path]) {
            
            // Clear response marker
            [[NSFileManager defaultManager] removeItemAtURL:responseURL error:nil];
            
            // Read the log file
            [strongSelf readLogFileFromAppGroups:logURL];
        }
    });
    
    dispatch_source_set_cancel_handler(source, ^{
        close(dirFd);
    });
    
    dispatch_resume(source);
    self.fileWatcher = source;
    
    NSLog(@"[App] File watcher started");
}

- (void)readLogFileFromAppGroups:(NSURL *)logURL {
    NSLog(@"[App] Reading log file...");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressView.hidden = NO;
        self.progressView.progress = 0;
        self.logStatusLabel.text = @"Receiving 50MB log...";
        self.logStatusLabel.textColor = [UIColor orangeColor];
    });
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:logURL.path];
        if (!fileHandle) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.logStatusLabel.text = @"Failed to open file";
                self.logStatusLabel.textColor = [UIColor redColor];
            });
            return;
        }
        
        const NSUInteger chunkSize = 64 * 1024; // 64 KB
        NSUInteger totalBytes = 0;
        NSUInteger lastPercent = 0;
        const NSUInteger expectedSize = 50 * 1024 * 1024;
        
        // Optional: Save to app's local documents
        NSURL *documentsURL = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *savedLogURL = [documentsURL URLByAppendingPathComponent:@"received_log.txt"];
        [[NSFileManager defaultManager] createFileAtPath:savedLogURL.path contents:nil attributes:nil];
        NSFileHandle *saveHandle = [NSFileHandle fileHandleForWritingToURL:savedLogURL error:nil];
        
        while (YES) {
            @autoreleasepool {
                NSData *chunk = [fileHandle readDataOfLength:chunkSize];
                if (chunk.length == 0) break;
                totalBytes += chunk.length;
                
                // Save chunk to local file
                [saveHandle writeData:chunk];
                
                NSUInteger percent = (totalBytes * 100) / expectedSize;
                if (percent >= lastPercent + 5) {
                    lastPercent = percent;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.progressView.progress = (float)percent / 100.0;
                        self.logStatusLabel.text = [NSString stringWithFormat:@"Receiving: %lu%% (%lu MB)",
                                                    (unsigned long)percent,
                                                    (unsigned long)(totalBytes / 1024 / 1024)];
                    });
                    NSLog(@"[App] Received: %lu%%", (unsigned long)percent);
                }
            }
        }
        
        [saveHandle closeFile];
        [fileHandle closeFile];
        
        // Delete the shared log file after reading
        [[NSFileManager defaultManager] removeItemAtURL:logURL error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.progressView.hidden = YES;
            self.sendLogBtn.enabled = YES;
            self.sendLogBtn.alpha = 1.0;
            
            NSString *sizeStr = [NSString stringWithFormat:@"%.2f MB", (float)totalBytes / 1024 / 1024];
            self.logStatusLabel.text = [NSString stringWithFormat:@"✅ Received %@ log!\nSaved to Documents/received_log.txt", sizeStr];
            self.logStatusLabel.textColor = [UIColor greenColor];
            
            // Share file action
            [self showShareSheetForFile:savedLogURL];
        });
        
        NSLog(@"[App] ✅ Successfully received %lu bytes", (unsigned long)totalBytes);
    });
}

- (void)showShareSheetForFile:(NSURL *)fileURL {
    NSArray *itemsToShare = @[fileURL];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:itemsToShare applicationActivities:nil];
    
    // For iPad
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.sendLogBtn;
        activityVC.popoverPresentationController.sourceRect = self.sendLogBtn.bounds;
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

#pragma mark - Send Command

- (void)sendLogCommand {
    if (!self.currentManager || self.currentManager.connection.status != NEVPNStatusConnected) {
        self.logStatusLabel.text = @"VPN not connected";
        self.logStatusLabel.textColor = [UIColor redColor];
        return;
    }
    
    self.sendLogBtn.enabled = NO;
    self.sendLogBtn.alpha = 0.6;
    [self.spinner startAnimating];
    self.logStatusLabel.text = @"Sending command to extension...";
    self.logStatusLabel.textColor = [UIColor orangeColor];
    self.progressView.hidden = YES;
    self.progressView.progress = 0;
    
    NSURL *container = [self getAppGroupContainer];
    if (!container) {
        self.logStatusLabel.text = @"No App Groups container";
        [self.spinner stopAnimating];
        self.sendLogBtn.enabled = YES;
        return;
    }
    
    // Delete old response and log files
    NSURL *responseURL = [container URLByAppendingPathComponent:kResponseFile];
    NSURL *logURL = [container URLByAppendingPathComponent:kLogFileName];
    [[NSFileManager defaultManager] removeItemAtURL:responseURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:logURL error:nil];
    
    // Write command file
    NSURL *commandURL = [container URLByAppendingPathComponent:kCommandFile];
    NSString *command = @"GENERATE_50MB_LOG";
    NSError *error = nil;
    [command writeToFile:commandURL.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        self.logStatusLabel.text = [NSString stringWithFormat:@"Write error: %@", error.localizedDescription];
        [self.spinner stopAnimating];
        self.sendLogBtn.enabled = YES;
        return;
    }
    
    self.logStatusLabel.text = @"Command sent, waiting for log...";
    self.logStatusLabel.textColor = [UIColor orangeColor];
}

#pragma mark - VPN Management

- (void)vpnStatusChanged:(NSNotification *)notification {
    [self checkStatus];
}

- (void)checkStatus {
    if (self.isCheckingStatus) return;
    self.isCheckingStatus = YES;
    
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isCheckingStatus = NO;
            
            if (error) {
                self.statusLabel.text = @"VPN: Error";
                return;
            }
            
            NETunnelProviderManager *foundManager = nil;
            for (NETunnelProviderManager *m in managers) {
                if ([m.localizedDescription isEqualToString:kTunnelDescription]) {
                    foundManager = m;
                    break;
                }
            }
            
            if (foundManager) {
                self.currentManager = foundManager;
                [self updateUIWithStatus:foundManager.connection.status];
            } else {
                self.currentManager = nil;
                self.statusLabel.text = @"VPN: Not configured";
                self.startBtn.enabled = YES;
                self.stopBtn.enabled = NO;
                self.sendLogBtn.enabled = NO;
            }
        });
    }];
}

- (void)updateUIWithStatus:(NEVPNStatus)status {
    BOOL isConnected = (status == NEVPNStatusConnected);
    
    self.startBtn.enabled = !isConnected;
    self.startBtn.alpha = !isConnected ? 1.0 : 0.6;
    self.stopBtn.enabled = isConnected;
    self.stopBtn.alpha = isConnected ? 1.0 : 0.6;
    self.sendLogBtn.enabled = isConnected;
    self.sendLogBtn.alpha = isConnected ? 1.0 : 0.6;
    
    NSString *statusText = @"";
    switch (status) {
        case NEVPNStatusDisconnected: statusText = @"VPN: Disconnected"; break;
        case NEVPNStatusConnecting: statusText = @"VPN: Connecting..."; break;
        case NEVPNStatusConnected: statusText = @"VPN: Connected ✓"; break;
        case NEVPNStatusDisconnecting: statusText = @"VPN: Disconnecting..."; break;
        default: statusText = @"VPN: Unknown"; break;
    }
    self.statusLabel.text = statusText;
}

- (void)startVPN {
    if (!self.startBtn.enabled) return;
    
    [self.spinner startAnimating];
    self.startBtn.enabled = NO;
    self.statusLabel.text = @"Starting VPN...";
    
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        NETunnelProviderManager *manager = nil;
        
        for (NETunnelProviderManager *m in managers) {
            if ([m.localizedDescription isEqualToString:kTunnelDescription]) {
                manager = m;
                break;
            }
        }
        
        if (!manager) {
            manager = [[NETunnelProviderManager alloc] init];
        }
        
        NETunnelProviderProtocol *protocol = [[NETunnelProviderProtocol alloc] init];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        protocol.providerBundleIdentifier = [bundleID stringByAppendingString:@".NetworkExt"];
        protocol.serverAddress = @"198.18.0.1";
        protocol.disconnectOnSleep = NO;
        
        manager.protocolConfiguration = protocol;
        manager.localizedDescription = kTunnelDescription;
        manager.enabled = YES;
        
        [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
            if (saveError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.spinner stopAnimating];
                    self.startBtn.enabled = YES;
                    self.statusLabel.text = [NSString stringWithFormat:@"Save error: %@", saveError.localizedDescription];
                });
                return;
            }
            
            [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
                if (loadError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.spinner stopAnimating];
                        self.startBtn.enabled = YES;
                        self.statusLabel.text = [NSString stringWithFormat:@"Load error: %@", loadError.localizedDescription];
                    });
                    return;
                }
                
                NSError *startError = nil;
                BOOL started = [manager.connection startVPNTunnelWithOptions:nil andReturnError:&startError];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.spinner stopAnimating];
                    if (startError) {
                        self.statusLabel.text = [NSString stringWithFormat:@"Start error: %@", startError.localizedDescription];
                        self.startBtn.enabled = YES;
                    } else if (started) {
                        self.currentManager = manager;
                    } else {
                        self.statusLabel.text = @"Failed to start VPN";
                        self.startBtn.enabled = YES;
                    }
                });
            }];
        }];
    }];
}

- (void)stopVPN {
    if (!self.stopBtn.enabled) return;
    
    self.stopBtn.enabled = NO;
    self.statusLabel.text = @"Stopping VPN...";
    
    if (self.currentManager) {
        [self.currentManager.connection stopVPNTunnel];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.fileWatcher) {
        dispatch_source_cancel(self.fileWatcher);
    }
}

@end
