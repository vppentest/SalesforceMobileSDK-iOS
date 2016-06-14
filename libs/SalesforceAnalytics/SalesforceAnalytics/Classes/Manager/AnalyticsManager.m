/*
 AnalyticsManager.m
 SalesforceAnalytics
 
 Created by Bharath Hariharan on 6/5/16.
 
 Copyright (c) 2016, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "AnalyticsManager+Internal.h"

static NSMutableDictionary *analyticsManagerList = nil;

@interface AnalyticsManager ()

@property (nonatomic, readwrite, strong) NSString *uniqueId;
@property (nonatomic, readwrite, strong) EventStoreManager *storeManager;
@property (nonatomic, readwrite, strong) DeviceAppAttributes *deviceAttributes;

@end

@implementation AnalyticsManager

+ (id) sharedInstance:(NSString *) uniqueId dataEncryptorBlock:(DataEncryptorBlock) dataEncryptorBlock dataDecryptorBlock:(DataDecryptorBlock) dataDecryptorBlock deviceAttributes:(DeviceAppAttributes *) deviceAttributes {
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        analyticsManagerList = [[NSMutableDictionary alloc] init];
    });
    @synchronized ([AnalyticsManager class]) {
        if (!uniqueId) {
            return nil;
        }
        id analyticsMgr = [analyticsManagerList objectForKey:uniqueId];
        if (!analyticsMgr) {
            analyticsMgr = [[AnalyticsManager alloc] init:uniqueId dataEncryptorBlock:dataEncryptorBlock dataDecryptorBlock:dataDecryptorBlock deviceAttributes:deviceAttributes];
            [analyticsManagerList setObject:analyticsMgr forKey:uniqueId];
        }
        return analyticsMgr;
    }
}

+ (void) removeSharedInstance:(NSString *) uniqueId {
    @synchronized ([AnalyticsManager class]) {
        if (uniqueId) {
            [analyticsManagerList removeObjectForKey:uniqueId];
        }
    }

    /*
     * TODO: Call this method and cleanup for StoreManager from logout in SalesforceSDKManager.
     */
}

- (id) init:(NSString *) uniqueId dataEncryptorBlock:(DataEncryptorBlock) dataEncryptorBlock dataDecryptorBlock:(DataDecryptorBlock) dataDecryptorBlock deviceAttributes:(DeviceAppAttributes *) deviceAttributes {
    self = [super init];
    if (self) {
        self.uniqueId = uniqueId;
        self.deviceAttributes = deviceAttributes;
        self.globalSequenceId = 0;
        self.storeManager = [[EventStoreManager alloc] init:uniqueId dataEncryptorBlock:dataEncryptorBlock dataDecryptorBlock:dataDecryptorBlock];
    }
    return self;
}

/*
 * TODO: Handle 'changePasscode' in SalesforceSDKManager when the passcode changes (maybe irrelevant if encryption block is used).
 */

@end
