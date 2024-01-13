//
//  NativeLoginManagerTests.swift
//  SalesforceSDKCore
//
//  Created by Brandon Page on 1/12/24.
//  Copyright (c) 2024-present, salesforce.com, inc. All rights reserved.
// 
//  Redistribution and use of this software in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//  * Redistributions of source code must retain the above copyright notice, this list of conditions
//  and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice, this list of
//  conditions and the following disclaimer in the documentation and/or other materials provided
//  with the distribution.
//  * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
//  endorse or promote products derived from this software without specific prior written
//  permission of salesforce.com, inc.
// 
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
//  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
//  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
//  WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import XCTest
@testable import SalesforceSDKCore

final class NativeLoginManagerTests: XCTestCase {
    let nativeLoginManager = NativeLoginManagerInternal(clientId: "", redirectUri: "", loginUrl: "")
    
    func testUsername() async {
        var result = await nativeLoginManager.login(username: "", password: "")
        XCTAssertEqual(.invalidUsername, result, "Should not allow empty username.")
        result = await nativeLoginManager.login(username: "test@c", password: "")
        XCTAssertEqual(.invalidUsername, result, "Should not allow invalid username.")
        // success
        result = await nativeLoginManager.login(username: "test@c.co   ", password: "")
        XCTAssertEqual(.invalidPassword, result, "Should allow username.")
    }
    
    func testPassword() async {
        var result = await nativeLoginManager.login(username: "bpage@salesforce.com", password: "")
        XCTAssertEqual(.invalidPassword, result, "Should not allow invalid password.")
        result = await nativeLoginManager.login(username: "bpage@salesforce.com", password: "test123")
        XCTAssertEqual(.invalidPassword, result, "Should not allow password shorter than 7 chars.")
        result = await nativeLoginManager.login(username: "bpage@salesforce.com", password: "123456789")
        XCTAssertEqual(.invalidPassword, result, "Should not allow password without any letter chars.")
        result = await nativeLoginManager.login(username: "bpage@salesforce.com", password: "abcdefghi")
        XCTAssertEqual(.invalidPassword, result, "Should not allow password without any numbers.")
        result = await nativeLoginManager.login(username: "user@name.com", password: "passuser@name.comword")
        XCTAssertEqual(.invalidPassword, result, "Should not allow password that contains username.")
        // success
        result = await nativeLoginManager.login(username: "bpage@salesforce.com", password: "mypass12")
        XCTAssertEqual(.invalidCredentials, result, "Should not allow password without any numbers.")
    }
    
    func testShouldShowBackButton() {
        let accountManager = UserAccountManager.shared
        XCTAssertNil(accountManager.currentUserAccount)
        XCTAssertFalse(nativeLoginManager.shouldShowBackButton(), "Should not show back button by default.")
    }
    
    private func createUser(index: Int) -> UserAccount {
        let credentials = OAuthCredentials(identifier: "identifier-\(index)", clientId: "fakeClientIdForTesting", encrypted: true)!
        let user = UserAccount(credentials: credentials)
        user.idData = IdentityData(jsonDict: [ "user_id": "\(index)" ])
        UserAccountManager.shared.currentUserAccount = user
        
        return user
    }
}
