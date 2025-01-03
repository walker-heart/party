import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import GoogleSignInSwift
import FirebaseCore
import UIKit
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var activeParties: [Party] = []
    
    private let auth: Auth
    private let db: Firestore
    private let usersCollection = "users"
    private let partiesCollection = "party"
    private var partyManager: PartyManager?
    
    private var appleSignInDelegate: SignInWithAppleDelegate?
    
    init(auth: Auth = Auth.auth(), db: Firestore = Firestore.firestore()) {
        self.auth = auth
        self.db = db
        
        // Set up auth state listener
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                if let user = user {
                    do {
                        try await self?.fetchUserData(userId: user.uid)
                    } catch {
                        print("Error fetching user data:", error.localizedDescription)
                        self?.resetState()
                    }
                } else {
                    self?.removeAllPartyListeners()
                    self?.resetState()
                }
            }
        }
    }
    
    func setPartyManager(_ partyManager: PartyManager) {
        self.partyManager = partyManager
    }
    
    private func removeAllPartyListeners() {
        for party in activeParties {
            partyManager?.removeListener(for: party.id)
        }
    }
    
    private func fetchUserData(userId: String) async throws {
        let document = try await db.collection(usersCollection).document(userId).getDocument()
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User data not found"])
        }
        
        // Create user from raw data to handle missing fields
        let user = User(
            id: userId,
            email: data["email"] as? String ?? auth.currentUser?.email ?? "",
            firstName: data["firstName"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            isAdmin: data["isAdmin"] as? Bool ?? false,
            activeParties: data["activeParties"] as? [String] ?? [],
            authProviders: data["authProviders"] as? [String] ?? []
        )
        
        // Update user data to ensure it has all fields and current provider
        var updatedUser = user
        
        // Get current providers from Firebase Auth
        if let currentUser = auth.currentUser {
            let currentProviders = Set(currentUser.providerData.map { $0.providerID })
            let storedProviders = Set(user.authProviders)
            
            // If providers don't match, update Firestore to match Firebase Auth
            if currentProviders != storedProviders {
                // Only keep providers that exist in Firebase Auth
                updatedUser.authProviders = Array(currentProviders)
                try await saveUserData(updatedUser)
                print("Synced providers: Firebase Auth has \(currentProviders), updated Firestore from \(storedProviders)")
            }
        }
        
        self.currentUser = updatedUser
        self.isAuthenticated = true
        
        // Remove existing listeners
        removeAllPartyListeners()
        
        // If user is admin, fetch all parties, otherwise fetch active parties
        if updatedUser.isAdmin {
            let snapshot = try await db.collection(partiesCollection).getDocuments()
            var parties: [Party] = []
            for document in snapshot.documents {
                if let party = try? await fetchParty(partyId: document.documentID) {
                    parties.append(party)
                    partyManager?.listenToParty(id: party.id)
                }
            }
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            // Get all parties from Firestore
            let snapshot = try await db.collection(partiesCollection).getDocuments()
            var parties: [Party] = []
            
            // Get current date and date 3 days ago
            let currentDate = Date()
            let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: currentDate) ?? currentDate
            
            for document in snapshot.documents {
                if let party = try? await fetchParty(partyId: document.documentID) {
                    // Include party if:
                    // 1. User is an editor
                    // 2. Party was joined in the last 3 days
                    if party.editors.contains(user.id) || 
                       (party.updatedAt >= threeDaysAgo && user.activeParties.contains(party.id)) {
                        parties.append(party)
                        partyManager?.listenToParty(id: party.id)
                    }
                }
            }
            
            // Sort by most recently updated
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    private func resetState() {
        self.currentUser = nil
        self.isAuthenticated = false
        self.activeParties = []
    }
    
    func signOut() async throws {
        // Sign out from Firebase
        try auth.signOut()
        
        // Sign out from Google
        GIDSignIn.sharedInstance.signOut()
        
        // Clear Apple session (if needed)
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: currentUser?.id ?? "") { (credentialState, error) in
            if credentialState == .authorized {
                // Clear keychain items if needed
                // Note: Apple doesn't provide direct sign out, but we can clear local state
            }
        }
        
        // Remove all party listeners
        removeAllPartyListeners()
        
        // Reset local state
        resetState()
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            
            // Check if user exists in Firestore
            if let existingUser = try? await getUserById(result.user.uid) {
                // Update providers if needed
                var updatedUser = existingUser
                if !existingUser.authProviders.contains("password") {
                    updatedUser.authProviders.append("password")
                    try await saveUserData(updatedUser)
                }
            } else {
                // Create new user if doesn't exist
                let newUser = User(
                    id: result.user.uid,
                    email: email,
                    authProviders: ["password"]
                )
                try await saveUserData(newUser)
            }
            
            try await fetchUserData(userId: result.user.uid)
        } catch let error as NSError {
            // First check if the email exists with a different provider
            if let userId = try? await getUserIdByEmail(email),
               let user = try? await getUserById(userId) {
                if !user.authProviders.contains("password") {
                    let providerNames = user.authProviders.map { $0 == "google.com" ? "Google" : "Email/Password" }
                        .joined(separator: " or ")
                    throw NSError(
                        domain: "",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "This email is registered with \(providerNames). Please sign in using that method instead."]
                    )
                }
            }
            
            // If we get here, either the email doesn't exist or it's a genuine wrong password
            if error.code == AuthErrorCode.userNotFound.rawValue {
                throw NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No account found with this email. Please check your email or sign up."]
                )
            } else if error.code == AuthErrorCode.wrongPassword.rawValue {
                throw NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Incorrect password. Please try again."]
                )
            }
            
            throw error
        }
    }
    
    func signUp(email: String, password: String, firstName: String = "", lastName: String = "") async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        let user = User(
            id: result.user.uid,
            email: email,
            firstName: firstName,
            lastName: lastName,
            authProviders: ["password"]
        )
        try await saveUserData(user)
        self.currentUser = user
        self.isAuthenticated = true
    }
    
    private func saveUserData(_ user: User) async throws {
        guard !user.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        var updatedUser = user
        
        // Always sync with Firebase Auth providers
        if let currentUser = auth.currentUser {
            let currentProviders = Set(currentUser.providerData.map { $0.providerID })
            // Only save providers that actually exist in Firebase Auth
            updatedUser.authProviders = Array(currentProviders)
        }
        
        let data = try Firestore.Encoder().encode(updatedUser)
        try await db.collection(usersCollection).document(user.id).setData(data)
    }
    
    func addPartyToActive(_ partyId: String) async throws {
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        guard var user = currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if !user.activeParties.contains(partyId) {
            user.activeParties.append(partyId)
            try await saveUserData(user)
            self.currentUser = user
            
            if let party = try? await fetchParty(partyId: partyId) {
                if !activeParties.contains(where: { $0.id == partyId }) {
                    activeParties.append(party)
                    activeParties.sort { $0.updatedAt > $1.updatedAt }
                }
            }
        }
    }
    
    func removePartyFromActive(_ partyId: String) async {
        activeParties.removeAll { $0.id == partyId }
        
        if let user = currentUser, !user.isAdmin {
            var updatedUser = user
            updatedUser.activeParties.removeAll { $0 == partyId }
            do {
                try await saveUserData(updatedUser)
                self.currentUser = updatedUser
            } catch {
                print("Error updating user data:", error.localizedDescription)
            }
        }
    }
    
    func fetchParty(partyId: String) async throws -> Party {
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        let document = try await db.collection(partiesCollection).document(partyId).getDocument()
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        let name = data["name"] as? String ?? ""
        let passcode = data["passcode"] as? String ?? ""
        let creatorId = data["creatorId"] as? String ?? ""
        let editors = data["editors"] as? [String] ?? [creatorId]
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        
        let people = (data["people"] as? [[String: Any]] ?? []).compactMap { personData -> Attendee? in
            guard let id = personData["id"] as? String,
                  let firstName = personData["firstName"] as? String,
                  let lastName = personData["lastName"] as? String,
                  let isPresent = personData["isPresent"] as? Bool,
                  let createdAt = (personData["createdAt"] as? Timestamp)?.dateValue(),
                  let updatedAt = (personData["updatedAt"] as? Timestamp)?.dateValue(),
                  let addMethod = personData["addMethod"] as? String
            else { return nil }
            
            let updatedBy = personData["updatedBy"] as? String
            
            return Attendee(
                id: id,
                firstName: firstName,
                lastName: lastName,
                isPresent: isPresent,
                createdAt: createdAt,
                updatedAt: updatedAt,
                addMethod: addMethod,
                updatedBy: updatedBy
            )
        }
        
        return Party(
            id: document.documentID,
            name: name,
            passcode: passcode,
            creatorId: creatorId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            attendees: people,
            editors: editors
        )
    }
    
    func getUserIdByEmail(_ email: String) async throws -> String? {
        let snapshot = try await db.collection(usersCollection)
            .whereField("email", isEqualTo: email)
            .getDocuments()
        
        return snapshot.documents.first?.documentID
    }
    
    func getUserById(_ userId: String) async throws -> User? {
        guard !userId.isEmpty else { return nil }
        
        let document = try await db.collection(usersCollection).document(userId).getDocument()
        guard let data = document.data() else { return nil }
        
        return User(
            id: userId,
            email: data["email"] as? String ?? "",
            firstName: data["firstName"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            isAdmin: data["isAdmin"] as? Bool ?? false,
            activeParties: data["activeParties"] as? [String] ?? [],
            authProviders: data["authProviders"] as? [String] ?? []
        )
    }
    
    func refreshParty(_ partyId: String) async throws {
        let party = try await fetchParty(partyId: partyId)
        refreshParty(party)
    }
    
    func refreshParty(_ party: Party?) {
        guard let party = party else { return }
        if let index = activeParties.firstIndex(where: { $0.id == party.id }) {
            activeParties[index] = party
            // Sort by most recently updated
            activeParties.sort { $0.updatedAt > $1.updatedAt }
        }
    }
    
    func signInWithGoogle() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get root view controller"])
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString,
              let email = result.user.profile?.email else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get Google ID token or email"])
        }
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        
        // Check if email exists
        if let existingUserId = try? await getUserIdByEmail(email) {
            // Email exists, try to sign in
            do {
                try await auth.signIn(with: credential)
                // Update Firestore user data if needed
                if var user = try? await getUserById(existingUserId) {
                    if !user.authProviders.contains("google.com") {
                        user.authProviders.append("google.com")
                        try await saveUserData(user)
                    }
                }
            } catch {
                // If sign-in fails, it might be because we need to link instead
                if let currentUser = auth.currentUser {
                    if currentUser.uid == existingUserId {
                        // Same user, just link the Google provider
                        try await currentUser.link(with: credential)
                        // Update Firestore user data
                        if var user = self.currentUser {
                            if !user.authProviders.contains("google.com") {
                                user.authProviders.append("google.com")
                                try await saveUserData(user)
                            }
                        }
                    } else {
                        throw NSError(
                            domain: "",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "This Google account is linked to a different account. Please sign out first."]
                        )
                    }
                } else {
                    throw error
                }
            }
        } else {
            // New user, create account
            let authResult = try await auth.signIn(with: credential)
            let newUser = User(
                id: authResult.user.uid,
                email: email,
                firstName: result.user.profile?.givenName ?? "",
                lastName: result.user.profile?.familyName ?? "",
                authProviders: ["google.com"]
            )
            try await saveUserData(newUser)
        }
        
        try await fetchUserData(userId: auth.currentUser?.uid ?? "")
    }
    
    func handleGoogleSignIn(user: GIDGoogleUser?) async throws {
        guard let googleUser = user,
              let idToken = googleUser.idToken?.tokenString,
              let email = googleUser.profile?.email else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get Google sign in information"])
        }
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )
        
        // Check if email exists
        if let existingUserId = try? await getUserIdByEmail(email) {
            // Email exists, try to sign in
            do {
                try await auth.signIn(with: credential)
                // Update Firestore user data if needed
                if var user = try? await getUserById(existingUserId) {
                    if !user.authProviders.contains("google.com") {
                        user.authProviders.append("google.com")
                        try await saveUserData(user)
                    }
                }
            } catch {
                // If sign-in fails, it might be because we need to link instead
                if let currentUser = auth.currentUser {
                    if currentUser.uid == existingUserId {
                        // Same user, just link the Google provider
                        try await currentUser.link(with: credential)
                        // Update Firestore user data
                        if var user = self.currentUser {
                            if !user.authProviders.contains("google.com") {
                                user.authProviders.append("google.com")
                                try await saveUserData(user)
                            }
                        }
                    } else {
                        throw NSError(
                            domain: "",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "This Google account is linked to a different account. Please sign out first."]
                        )
                    }
                } else {
                    throw error
                }
            }
        } else {
            // New user, create account
            let authResult = try await auth.signIn(with: credential)
            let newUser = User(
                id: authResult.user.uid,
                email: email,
                firstName: googleUser.profile?.givenName ?? "",
                lastName: googleUser.profile?.familyName ?? "",
                authProviders: ["google.com"]
            )
            try await saveUserData(newUser)
        }
        
        try await fetchUserData(userId: auth.currentUser?.uid ?? "")
    }
    
    func updateUserProfile(firstName: String, lastName: String) async throws {
        guard let user = currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Create updated user with new name
        let updatedUser = User(
            id: user.id,
            email: user.email,
            firstName: firstName,
            lastName: lastName,
            isAdmin: user.isAdmin,
            activeParties: user.activeParties,
            authProviders: user.authProviders
        )
        
        // Save to Firestore
        try await saveUserData(updatedUser)
        
        // Update local state
        self.currentUser = updatedUser
    }
    
    func sendPasswordResetEmail() async throws {
        guard let user = currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        guard user.authProviders.contains("password") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Email/password authentication is not enabled for this account"])
        }
        
        // Send reset email
        try await auth.sendPasswordReset(withEmail: user.email)
        
        // Remove all other auth providers except password
        var updatedUser = user
        updatedUser.authProviders = ["password"]
        
        // Remove providers from Firebase Auth
        if let currentUser = auth.currentUser {
            for provider in currentUser.providerData {
                if provider.providerID != "password" {
                    try await currentUser.unlink(fromProvider: provider.providerID)
                }
            }
        }
        
        // Update Firestore with only password provider
        try await saveUserData(updatedUser)
        self.currentUser = updatedUser
    }
    
    func linkEmailPassword(email: String, password: String) async throws {
        guard let currentUser = auth.currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        // If the user already has an email (from Google), use that instead of the provided one
        let emailToUse = currentUser.email ?? email
        
        // Verify this is the same email if provided
        if email != emailToUse {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please use your existing email (\(emailToUse)) to add password authentication"])
        }
        
        // Create email credential
        let credential = EmailAuthProvider.credential(withEmail: emailToUse, password: password)
        
        // Link the credential to the current user
        _ = try await currentUser.link(with: credential)
        
        // Update the user's auth providers in Firestore
        if var user = self.currentUser, !user.authProviders.contains("password") {
            user.authProviders.append("password")
            try await saveUserData(user)
            self.currentUser = user
        }
    }
    
    func linkGoogleAccount() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get root view controller"])
        }
        
        // Sign in with Google
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        
        guard let idToken = result.user.idToken?.tokenString,
              let email = result.user.profile?.email else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get Google sign in information"])
        }
        
        // Create Google credential
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        
        // Get current user
        guard let currentUser = auth.currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        // Verify the email matches
        if currentUser.email != email {
            throw NSError(
                domain: "",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "The Google account email does not match your current account email"]
            )
        }
        
        do {
            // Check if the provider is already linked
            if currentUser.providerData.contains(where: { $0.providerID == "google.com" }) {
                throw NSError(
                    domain: "",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Google account is already linked to this account"]
                )
            }
            
            // Link the credential
            try await currentUser.link(with: credential)
            
            // Update Firestore after successful linking
            if var user = self.currentUser, !user.authProviders.contains("google.com") {
                user.authProviders.append("google.com")
                try await saveUserData(user)
                self.currentUser = user
            }
        } catch let error as NSError {
            if error.domain == AuthErrorDomain {
                switch error.code {
                case AuthErrorCode.providerAlreadyLinked.rawValue:
                    throw NSError(
                        domain: "",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "This Google account is already linked to this account"]
                    )
                case AuthErrorCode.credentialAlreadyInUse.rawValue:
                    throw NSError(
                        domain: "",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "This Google account is already linked to another account"]
                    )
                default:
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    func removeAuthProvider(_ provider: String, password: String? = nil) async throws {
        guard let currentUser = auth.currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let user = self.currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User data not found"])
        }
        
        // Ensure at least one provider remains
        guard user.authProviders.count > 1 else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot remove the only sign-in method"])
        }
        
        // Remove the provider
        switch provider {
        case "password":
            guard let password = password else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Password is required to remove email/password authentication"])
            }
            
            // Create email credential and reauthenticate
            let credential = EmailAuthProvider.credential(withEmail: user.email, password: password)
            try await currentUser.reauthenticate(with: credential)
            
            // If reauthentication successful, unlink password provider
            _ = try await currentUser.unlink(fromProvider: "password")
            
            // Update Firestore
            var updatedUser = user
            updatedUser.authProviders.removeAll { $0 == "password" }
            try await saveUserData(updatedUser)
            self.currentUser = updatedUser
            
        case "google.com":
            _ = try await currentUser.unlink(fromProvider: "google.com")
            
            // Update Firestore
            var updatedUser = user
            updatedUser.authProviders.removeAll { $0 == "google.com" }
            try await saveUserData(updatedUser)
            self.currentUser = updatedUser
            
        case "apple.com":
            _ = try await currentUser.unlink(fromProvider: "apple.com")
            
            // Update Firestore
            var updatedUser = user
            updatedUser.authProviders.removeAll { $0 == "apple.com" }
            try await saveUserData(updatedUser)
            self.currentUser = updatedUser
            
        default:
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported authentication provider"])
        }
    }
    
    func signInWithApple() async throws {
        let nonce = randomNonceString()
        
        return try await withCheckedThrowingContinuation { continuation in
            let signInDelegate = SignInWithAppleDelegate { [weak self] result in
                Task { @MainActor [weak self] in
                    do {
                        guard let self = self else {
                            continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Auth manager was deallocated"]))
                            return
                        }
                        
                        switch result {
                        case .success(let authorization):
                            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let appleIDToken = appleIDCredential.identityToken,
                                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get Apple ID token"])
                            }
                            
                            let credential = OAuthProvider.appleCredential(
                                withIDToken: idTokenString,
                                rawNonce: nonce,
                                fullName: appleIDCredential.fullName
                            )
                            
                            // Check if user exists with this email
                            if let email = appleIDCredential.email ?? auth.currentUser?.email,
                               let existingUserId = try? await self.getUserIdByEmail(email) {
                                // Email exists, check if user is signed in
                                if let currentUser = self.auth.currentUser {
                                    if currentUser.uid == existingUserId {
                                        // Same user, just link Apple provider
                                        try await currentUser.link(with: credential)
                                        if var user = self.currentUser {
                                            if !user.authProviders.contains("apple.com") {
                                                user.authProviders.append("apple.com")
                                                try await self.saveUserData(user)
                                            }
                                        }
                                    } else {
                                        // Different user, try to sign in
                                        try await self.auth.signIn(with: credential)
                                        if var user = try? await self.getUserById(existingUserId) {
                                            if !user.authProviders.contains("apple.com") {
                                                // Preserve existing providers and add apple.com
                                                user.authProviders.append("apple.com")
                                                try await self.saveUserData(user)
                                            }
                                        }
                                    }
                                } else {
                                    // Not signed in, sign in to existing account
                                    try await self.auth.signIn(with: credential)
                                    if var user = try? await self.getUserById(existingUserId) {
                                        if !user.authProviders.contains("apple.com") {
                                            // Preserve existing providers and add apple.com
                                            user.authProviders.append("apple.com")
                                            try await self.saveUserData(user)
                                        }
                                    }
                                }
                            } else {
                                // New user, create account
                                let authResult = try await self.auth.signIn(with: credential)
                                
                                // Only create new user data if it doesn't exist
                                if try await self.getUserById(authResult.user.uid) == nil {
                                    let newUser = User(
                                        id: authResult.user.uid,
                                        email: appleIDCredential.email ?? authResult.user.email ?? "",
                                        firstName: appleIDCredential.fullName?.givenName ?? "",
                                        lastName: appleIDCredential.fullName?.familyName ?? "",
                                        authProviders: ["apple.com"]
                                    )
                                    try await self.saveUserData(newUser)
                                }
                            }
                            
                            try await self.fetchUserData(userId: self.auth.currentUser?.uid ?? "")
                            continuation.resume()
                            
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Store delegate as a property to prevent deallocation
            self.appleSignInDelegate = signInDelegate
            
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = signInDelegate
            controller.presentationContextProvider = signInDelegate
            
            // Start the sign-in flow
            controller.performRequests()
        }
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    func deleteAccount() async throws {
        guard let currentUser = auth.currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
        }
        
        guard let user = self.currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User data not found"])
        }
        
        // Clean up user data
        // 1. Remove user from all party editor lists
        let partiesSnapshot = try await db.collection(partiesCollection).whereField("editors", arrayContains: user.id).getDocuments()
        for document in partiesSnapshot.documents {
            // Update the editors array directly in Firestore
            try await db.collection(partiesCollection).document(document.documentID).updateData([
                "editors": FieldValue.arrayRemove([user.id])
            ])
        }
        
        // 2. Delete user document from Firestore
        try await db.collection(usersCollection).document(user.id).delete()
        
        // 3. Delete Firebase Auth account
        try await currentUser.delete()
        
        // 4. Reset local state
        resetState()
    }
    
    private func getUserByEmail(_ email: String) async throws -> User? {
        let snapshot = try await db.collection(usersCollection)
            .whereField("email", isEqualTo: email)
            .getDocuments()
        
        guard let document = snapshot.documents.first,
              let data = try? Firestore.Decoder().decode(User.self, from: document.data()) else {
            return nil
        }
        
        return data
    }
}

// Helper class to handle Apple Sign In delegate methods
private class SignInWithAppleDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var handler: (Result<ASAuthorization, Error>) -> Void
    private weak var window: UIWindow?
    
    init(handler: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.handler = handler
        super.init()
        
        // Store window reference
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            self.window = window
        }
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = self.window {
            return window
        }
        
        // Fallback to getting a new window reference if the stored one is nil
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            self.window = window
            return window
        }
        
        fatalError("No window found for Apple Sign In presentation")
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        handler(.success(authorization))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        handler(.failure(error))
    }
}