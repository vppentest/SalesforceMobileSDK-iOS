//
//  NativeLoginManager.swift
//  SalesforceSDKCore
//
//  Created by Brandon Page on 12/13/23.
//  Copyright (c) 2023-present, salesforce.com, inc. All rights reserved.
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

import CryptoKit

/// Global Constants
let maximumUsernameLength = 80
let minimumPasswordLength = 8
let maximumPasswordLengthInBytes = 16000

///
/// This class is internal to the Mobile SDK - don't instantiate in your application code!
///
/// It's only public to be visible from the obj-c code when the library is compiled as a framework.
/// See https://developer.apple.com/documentation/swift/importing-swift-into-objective-c#Import-Code-Within-a-Framework-Target
@objc(SFNativeLoginManagerInternal)
public class NativeLoginManagerInternal: NSObject, NativeLoginManager {
    
    static let errorDomain = "com.salesforce.security.nativeLoginException"
    
    @objc public let clientId: String
    @objc public let redirectUri: String
    @objc public let loginUrl: String
    let scene: UIScene?
    
    /// A structure for the Headless Identity API's authorization endpoint response
    private struct AuthorizationResponseBody: Codable {
        let sfdc_community_url: String
        let sfdc_community_id: String
        let code: String
    }
    
    @objc public init(clientId: String, redirectUri: String, loginUrl: String, scene: UIScene?) {
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.loginUrl = loginUrl
        self.scene = scene
    }
    
    public func login(
        username: String,
        password: String
    ) async throws -> NativeLoginResult
    {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !isValidUsername(username: trimmedUsername) {
            return .invalidUsername
        }
        
        if !isValidPassword(password: trimmedPassword) {
            return .invalidPassword
        }
        let credentials = try generateColonConcatinatedBase64String(
            value1: trimmedUsername,
            value2: trimmedPassword)
        let authRequest = RestRequest(method: .POST, baseURL: loginUrl, path: kSFOAuthEndPointAuthorize, queryParams: nil)
        let customHeaders: NSMutableDictionary = [kSFOAuthRequestTypeParamName: kSFOAuthRequestTypeNamedUser,
                                                  kHttpHeaderContentType: kHttpPostContentType,
                                                  kSFOAuthAuthorizationTypeParamName: "\(kSFOAuthAuthorizationTypeBasic) \(credentials)"]
        
        let codeVerifier = generateCodeVerifier()
        guard let challenge = generateChallenge(codeVerifier: codeVerifier) else { return .unknownError }
        let authRequestBody = generateAuthorizationRequestBody(
            codeChallenge: challenge)
        authRequest.customHeaders = customHeaders
        authRequest.setCustomRequestBodyString(authRequestBody, contentType: kHttpPostContentType)
        authRequest.requiresAuthentication = false
        authRequest.endpoint = ""
   
        // First REST Call - Authorization
        let authorizationResponse = await withCheckedContinuation { continuation in
            RestClient.sharedGlobal.send(request: authRequest) { result in
                continuation.resume(returning: result)
            }
        }

        // Second REST Call - Access token request with code verifier
        return await submitAccessTokenRequest(
            authorizationResponse: authorizationResponse,
            codeVerifier: codeVerifier)
    }
    
    public func fallbackToWebAuthentication() {
        UserAccountManager.shared.shouldFallbackToWebAuthentication = true
        UserAccountManager.shared.switchToNewUserAccount { _ in
            UserAccountManager.shared.shouldFallbackToWebAuthentication = false
        }
    }
    
    public func shouldShowBackButton() -> Bool {
        if (SalesforceManager.shared.biometricAuthenticationManager().locked) {
            return false
        }
        
        guard let totalAccounts = UserAccountManager.shared.userAccounts()?.count else { return false }
        return (totalAccounts > 0 && UserAccountManager.shared.currentUserAccount != nil)
    }
    
    public func cancelAuthentication() {
        if (shouldShowBackButton()) {
            UserAccountManager.shared.stopCurrentAuthentication()
            SFSDKWindowManager.shared().authWindow(nil).viewController?.presentedViewController?.dismiss(animated: false, completion: {
                SFSDKWindowManager.shared().authWindow(nil).dismissWindow()
            })
        }
    }
    
    public func biometricAuthenticationSuccess() {
        let bioAuthMgr = BiometricAuthenticationManagerInternal.shared
        
        if bioAuthMgr.enabled && bioAuthMgr.locked {
            SFSDKCoreLogger.i(classForCoder, message: "Native Login biometric authentication success.")
            bioAuthMgr.unlockPostProcessing()
            UserAccountManager.shared.stopCurrentAuthentication()
        }
    }
    
    public func getBiometricAuthenticationUsername() -> String? {
        if BiometricAuthenticationManagerInternal.shared.locked {
            return UserAccountManager.shared.currentUserAccount?.idData.username
        }
        
        return nil
    }
    
    private func isValidUsername(username: String) -> Bool {
        if (username.count > maximumUsernameLength) {
            return false
        }
        
        let emailStyleRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailStyleRegex)
        return predicate.evaluate(with: username)
    }
    
    /// Validation of the weakest possible password requrements.
    /// Rules derived from: https://help.salesforce.com/s/articleView?id=sf.admin_password.htm&type=5
    private func isValidPassword(password: String) -> Bool {
        let containsNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        let containsLetter = password.rangeOfCharacter(from: .letters) != nil
        
        return containsNumber && containsLetter && password.count >= minimumPasswordLength && password.utf8.count <= maximumPasswordLengthInBytes
    }
 
    private func urlSafeBase64Encode(data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeVerifier() -> String {
        let randomData = SFSDKCryptoUtils.randomByteData(withLength: kSFOAuthCodeVerifierByteLength)
        return urlSafeBase64Encode(data: randomData)
    }
    
    private func generateChallenge(codeVerifier: String) -> String? {
        guard let data = codeVerifier.data(using: .utf8) else { return nil }
        let hash = SHA256.hash(data: data)
        return urlSafeBase64Encode(data: hash.dataRepresentation)
    }
    
    // MARK: Headless, Password-Less Login Via One-Time-Passcode
    
    public func submitOtpRequest(
        username: String,
        reCaptchaToken: String,
        reCaptchaSiteKeyId: String?,
        googleCloudProjectId: String?,
        isReCaptchaEnterprise: Bool,
        otpVerificationMethod: OtpVerificationMethod) async throws -> OtpRequestResult
    {
        
        // Validate parameters.
        if !isValidUsername(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            return OtpRequestResult(nativeLoginResult: .invalidUsername)
        }
        
        /*
         * Create the OTP request body with the provided parameters. Note: The
         * `emailtemplate` parameter isn't supported here, but could be added in
         * the future.
         */
        // Determine the reCAPTCHA parameter for non-enterprise reCAPTCHA
        let reCaptchaParameter: String? = if (isReCaptchaEnterprise) {
            nil
        } else {
            reCaptchaToken
        }
        // Determine the reCAPTCHA "event" parameter for enterprise reCAPTCHA
        let reCaptchaEventParameter: OtpRequestBodyReCaptchaEvent? = if (isReCaptchaEnterprise) {
            OtpRequestBodyReCaptchaEvent(
                token: reCaptchaToken,
                siteKey: try reCaptchaSiteKeyId ?? { throw NSError(
                    domain:NativeLoginManagerInternal.errorDomain,
                    code:-1,
                    userInfo: [NSLocalizedDescriptionKey: "A reCAPTCHA site key wasn't and must be provided when using enterprise reCAPATCHA."])}(),
                projectId: try googleCloudProjectId ?? { throw NSError(
                    domain:NativeLoginManagerInternal.errorDomain,
                    code:-1,
                    userInfo: [NSLocalizedDescriptionKey: "A Google Cloud project id wasn't and must be provided when using enterprise reCAPATCHA."])}()
            )
        } else {
            nil
        }
        // Determine the OTP verification method.
        let otpVerificationMethodString = generateVerificationTypeHeaderValue(
            otpVerificationMethod: otpVerificationMethod)
        // Generate the OTP request body.
        let requestBodyString = try {
            do { return String(
                data: try JSONEncoder().encode(
                    OtpRequestBody(
                        recaptcha: reCaptchaParameter,
                        recaptchaevent: reCaptchaEventParameter,
                        username: username,
                        verificationMethod: otpVerificationMethodString)
                ),
                encoding: .utf8)!
            } catch let error {
                throw NativeLoginError.encodingError(underlyingError: error)
            }}()
        
        // Create the OTP request.
        let otpRequest = RestRequest(
            method: .POST,
            baseURL: loginUrl,
            path: kSFOAuthEndPointHeadlessInitPasswordlessLogin,
            queryParams: nil)
        otpRequest.endpoint = ""
        otpRequest.requiresAuthentication = false
        otpRequest.setCustomRequestBodyString(
            requestBodyString,
            contentType: kHttpPostApplicationJsonContentType
        )
        
        // Submit the OTP request and fetch the OTP response.
        let otpResponse = await withCheckedContinuation { continuation in
            RestClient.sharedGlobal.send(
                request: otpRequest
            ) { result in
                continuation.resume(returning: result)
            }
        }
        
        // React to the OTP response.
        switch otpResponse {
            
        case .success(let otpResponse):
            // Decode the OTP response to obtain the OTP email and identifier.
            let otpResponseBody = try {
                do {
                    return try otpResponse.asDecodable(type: OtpResponseBody.self)
                } catch let error {
                    throw NativeLoginError.decodingError(underlyingError: error)
                }}()
            return OtpRequestResult(
                nativeLoginResult: .success,
                otpIdentifier: otpResponseBody.identifier)
            
        case .failure(let error):
            SFSDKCoreLogger().e(
                classForCoder,
                message: "OTP request failure with description '\(error.localizedDescription)'.")
            return OtpRequestResult(nativeLoginResult: .unknownError)
        }
    }
    
    public func submitPasswordlessAuthorizationRequest(
        otp: String,
        otpIdentifier: String,
        otpVerificationMethod: OtpVerificationMethod
    ) async throws -> NativeLoginResult
    {
        // Validate parameters.
        let trimmedOtp = otp.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Generate code verifier and code challenge.
        let codeVerifier = generateCodeVerifier()
        guard let codeChallenge = generateChallenge(
            codeVerifier: codeVerifier
        ) else {
            throw NSError(
                domain:NativeLoginManagerInternal.errorDomain,
                code:-1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot generate code verifier due to a nil result."])
        }
        
        // Determine the OTP verification method.
        let otpVerificationMethodString = generateVerificationTypeHeaderValue(otpVerificationMethod: otpVerificationMethod)
        // Generate the authorization.
        let authorization = try generateColonConcatinatedBase64String(
            value1: otpIdentifier,
            value2: otp)
        // Generate the authorization request headers.
        // TODO: Evaluate use of `Uvid-Hint` header. ECJ20240306
        let authorizationRequestHeaders: NSMutableDictionary = [
            kSFOAuthRequestTypeParamName: kSFOAuthRequestTypePasswordlessLogin,
            kSFOAuthAuthVerificationTypeParamName: otpVerificationMethodString,
            kHttpHeaderContentType: kHttpPostContentType,
            kSFOAuthAuthorizationTypeParamName: "\(kSFOAuthAuthorizationTypeBasic) \(authorization)"]
        
        // Generate the authorization request body.
        let authorizationRequestBodyString = generateAuthorizationRequestBody(codeChallenge: codeChallenge)
            
        // Create the authorization request.
        let authorizationRequest = RestRequest(
            method: .POST,
            baseURL: loginUrl,
            path: kSFOAuthEndPointAuthorize,
            queryParams: nil)
        authorizationRequest.customHeaders = authorizationRequestHeaders
        authorizationRequest.endpoint = ""
        authorizationRequest.requiresAuthentication = false
        authorizationRequest.setCustomRequestBodyString(
            authorizationRequestBodyString,
            contentType: kHttpPostContentType)
        
        // Submit the authorization request and fetch the authorization response.
        let authorizationResponse = await withCheckedContinuation { continuation in
            RestClient.sharedGlobal.send(
                request: authorizationRequest
            ) { result in
                continuation.resume(returning: result)
            }
        }
        
        // React to the authorization response.
        return await submitAccessTokenRequest(
            authorizationResponse: authorizationResponse,
            codeVerifier: codeVerifier)
    }
    
    /// Resolves a Headless Identity API headless, password-less one-time-passcode verification type
    /// header value from the provided OTP verification method.
    /// - Parameters:
    ///   - otpVerificationMethod: An OTP verification method
    private func generateVerificationTypeHeaderValue(
        otpVerificationMethod: OtpVerificationMethod
    ) -> String
    {
        
        return switch (otpVerificationMethod) {
        case .email: kSFOAuthAuthVerificationTypeEmail
        case .sms: kSFOAuthAuthVerificationTypeSms
        }
    }
    
    /// Error cases for native login.
    public enum NativeLoginError: Error {
        case invalidParameter
        case encodingError(underlyingError: Error)
        case decodingError(underlyingError: Error)
    }
    
    /// A structure for the OTP request body.
    private struct OtpRequestBody: Codable {
        
        /// The reCAPTCHA token provided by the reCAPTCHA iOS SDK.  This is not used with reCAPTCHA Enterprise
        let recaptcha: String?
        
        /// The reCAPTCHA parameters for use with reCAPTCHA Enterprise
        let recaptchaevent: OtpRequestBodyReCaptchaEvent?
        
        /// The Salesforce username
        let username: String
        
        /// The OTP verification code's delivery method in "email" or "sms"
        let verificationMethod: String
        
        enum CodingKeys: String, CodingKey {
            case recaptcha = "recaptcha"
            case recaptchaevent = "recaptchaevent"
            case verificationMethod = "verificationmethod"
            case username = "username"
        }
    }
    
    /// A structure for the OTP request response body.
    private struct OtpResponseBody: Codable {
        let status: String
        let identifier: String
    }
    
    /// A structure for the OTP request body's reCAPTCHA event parameter.
    private struct OtpRequestBodyReCaptchaEvent: Codable {
        
        /// The reCAPTCHA token provided by the reCAPTCHA iOS SDK.  This is used only with reCAPTCHA Enterprise
        let token: String
        
        /// The Google Cloud project reCAPTCHA Key's "Id" as shown in Google Cloud Console under "Products & Solutions", "Security" and "reCAPTCHA Enterprise"
        let siteKey: String
        
        /// The user-inittiated "Action Name" for the reCAPTCHA event.  A specific value is not required by Google though it is used in reCAPTCHA Metrics.  "login" is a recommended value from Google documentation.
        var expectedAction = "login"
        
        /// The Google Cloud project's "Id" as shown in Google Cloud Console
        let projectId: String
    }
    
    // MARK: Private Implementation
    
    /// Generates a Base64 encoded value by concatinated the provided values with a colon, which is
    /// commonly used in the Headless Identity API request headers.
    /// - Parameters:
    ///   - value1: The left-side value
    ///   - value2: The right-side value
    private func generateColonConcatinatedBase64String(
        value1: String,
        value2: String
    ) throws -> String {
        guard let valuesUtf8EncodedData = "\(value1):\(value2)".data(
            using: .utf8
        ) else {
            throw NSError(
                domain:NativeLoginManagerInternal.errorDomain,
                code:-1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to UTF-8 encode colon-concatinated string with values '\(value1)' and '\(value2)' due to a nil encoding result."])
        }
        return urlSafeBase64Encode(data: valuesUtf8EncodedData)
    }
    
    /// Generates a request body for the Headless Identity API authorization request.
    /// - Parameters:
    ///   - codeChallenge: The authorization code challenge
    private func generateAuthorizationRequestBody(
        codeChallenge: String
    ) -> String {
        return "\(kSFOAuthResponseType)=\(kSFOAuthCodeCredentialsParamName)&\(kSFOAuthClientId)=\(clientId)&\(kSFOAuthRedirectUri)=\(redirectUri)&\(kSFOAuthCodeChallengeParamName)=\(codeChallenge)"
    }
    
    /// Reacts to a response from the Headless Identity API's authorization endpoint to initiate the token
    /// exchange, request a granted access token and create the user's session.
    /// - Parameters:
    ///   - authResult: The result from the Headless Identity API's authorization endpoint
    ///   - codeVerifier: The code verifier
    private func submitAccessTokenRequest(
        authorizationResponse: Result<RestResponse, RestClientError>,
        codeVerifier: String
    ) async -> NativeLoginResult {
        
        switch authorizationResponse {

        case .success(let successfulResponse): // Authorization success.
            do {
                // Decode the authorization response.
                let authorizationResponseBody = try successfulResponse.asDecodable(
                    type: AuthorizationResponseBody.self)

                // Generate the access token request body.
                let tokenRequestBody = "\(kSFOAuthResponseTypeCode)=\(authorizationResponseBody.code)&\(kSFOAuthGrantType)=\(kSFOAuthGrantTypeAuthorizationCode)&\(kSFOAuthClientId)=\(clientId)&\(kSFOAuthRedirectUri)=\(redirectUri)&\(kSFOAuthCodeVerifierParamName)=\(codeVerifier)"
                
                // Create the access token request.
                let tokenRequest = RestRequest(
                    method: .POST,
                    baseURL: authorizationResponseBody.sfdc_community_url,
                    path: kSFOAuthEndPointToken,
                    queryParams: nil)
                tokenRequest.endpoint = ""
                tokenRequest.requiresAuthentication = false
                tokenRequest.setCustomRequestBodyString(
                    tokenRequestBody,
                    contentType: kHttpPostContentType)
                
                // Submit the access token request.
                let tokenResponse = await withCheckedContinuation { continuation in
                    RestClient.sharedGlobal.send(
                        request: tokenRequest
                    ) { tokenResponse in
                        continuation.resume(returning: tokenResponse)
                    }
                }
                
                // React to the token response.
                switch(tokenResponse) {
                    
                case .success(let tokenResponse): // Access token success.
                    // Create the successfully authorized user's session.
                    UserAccountManager.shared.createNativeUserAccount(
                        with: tokenResponse.asData(),
                        scene:scene)
                    return .success
                    
                case .failure(let error): // Access token failure.
                    SFSDKCoreLogger().e(
                        classForCoder,
                        message: "error: \(error)")
                    return .unknownError
                }
            } catch {
                SFSDKCoreLogger().e(classForCoder, message: "error: \(error)")
                return .unknownError
            }
            
        case .failure(let error): // Authorization failure.
            // You will catch the error here in the event of auth failure or if the user cannot login this way.
            SFSDKCoreLogger().e(classForCoder, message: "authentication error: \(error)")
            return .invalidCredentials
        }
    }
}
