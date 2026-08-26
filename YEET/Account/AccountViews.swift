import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AccountSheet: View {
    @ObservedObject var appModel: YEETAppModel
    var onShowTutorial: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var isEditingHandle = false
    @State private var isConfirmingDeletion = false
    @State private var isReauthorizingDeletion = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    accountContent
                    Divider().opacity(0.55)
                    accountButton("HOW TO PLAY", symbol: "hand.point.up.left.fill") {
                        dismiss()
                        onShowTutorial()
                    }
                    if let error = localError ?? appModel.accountActionError {
                        Text(error)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("yeet.account.error")
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(YEETTheme.paper.ignoresSafeArea())
            .navigationTitle("ACCOUNT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("DONE") { dismiss() }
                        .font(.subheadline.weight(.black))
                }
            }
        }
        .interactiveDismissDisabled(appModel.isAccountWorking)
        .alert("Delete account?", isPresented: $isConfirmingDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                isReauthorizingDeletion = true
            }
        } message: {
            Text("You’ll confirm with Apple next. Your profile and every saved score will be permanently deleted.")
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        switch appModel.accountState {
        case .unavailable:
            accountHeader(symbol: "bolt.slash.fill", title: "BACKEND UNAVAILABLE")
            Text("Tossing still works. Add your Supabase configuration to enable accounts and rankings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(YEETTheme.muted)

        case .checking:
            ProgressView("Checking account…")
                .tint(YEETTheme.ink)
            if appModel.accountActionError != nil {
                accountButton("RETRY", symbol: "arrow.clockwise") {
                    appModel.retryAccountCheck()
                }
            }

        case .signedOut:
            accountHeader(symbol: "person.crop.circle.badge.plus", title: "CLAIM YOUR YEETS")
            Text("Sign in only when you want to save a score. Playing never requires an account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(YEETTheme.muted)
            AppleSignInControl(appModel: appModel, localError: $localError)
                .frame(height: 52)

        case .needsHandle:
            accountHeader(symbol: "at", title: "CHOOSE YOUR HANDLE")
            HandleForm(
                initialHandle: "",
                isWorking: appModel.isAccountWorking,
                buttonTitle: "SAVE HANDLE"
            ) { handle in
                await appModel.saveHandle(handle)
            }

        case let .signedIn(_, handle):
            accountHeader(symbol: "person.crop.circle.fill", title: "@\(handle)")

            if isEditingHandle {
                HandleForm(
                    initialHandle: handle,
                    isWorking: appModel.isAccountWorking,
                    buttonTitle: "UPDATE HANDLE"
                ) { proposedHandle in
                    let didSave = await appModel.saveHandle(proposedHandle)
                    if didSave { isEditingHandle = false }
                    return didSave
                }
            } else if isReauthorizingDeletion {
                VStack(spacing: 12) {
                    Text("CONFIRM DELETION WITH APPLE")
                        .font(.caption.weight(.black))
                    AppleDeletionControl(appModel: appModel, localError: $localError)
                        .frame(height: 52)
                    Button("CANCEL") { isReauthorizingDeletion = false }
                        .font(.caption.weight(.black))
                        .foregroundStyle(YEETTheme.muted)
                }
            } else {
                accountButton("EDIT HANDLE", symbol: "pencil") {
                    isEditingHandle = true
                }
                accountButton("SIGN OUT", symbol: "rectangle.portrait.and.arrow.right") {
                    Task { await appModel.signOut() }
                }
                accountButton("DELETE ACCOUNT", symbol: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
            }
        }
    }

    private func accountHeader(symbol: String, title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(YEETTheme.ink)
                .frame(width: 72, height: 72)
                .background(YEETTheme.yellow, in: Circle())
            Text(title)
                .font(.title2.weight(.black))
                .fontWidth(.compressed)
                .multilineTextAlignment(.center)
        }
    }

    private func accountButton(
        _ title: String,
        symbol: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(YEETTheme.ink.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : YEETTheme.ink)
        .disabled(appModel.isAccountWorking)
    }
}

private struct HandleForm: View {
    @State private var handle: String
    @State private var validationMessage: String?
    let isWorking: Bool
    let buttonTitle: String
    let onSave: (String) async -> Bool

    init(
        initialHandle: String,
        isWorking: Bool,
        buttonTitle: String,
        onSave: @escaping (String) async -> Bool
    ) {
        _handle = State(initialValue: initialHandle)
        self.isWorking = isWorking
        self.buttonTitle = buttonTitle
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                Text("@")
                    .font(.title3.weight(.black))
                TextField("handle", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityIdentifier("yeet.account.handle")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(YEETTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

            Text(validationMessage ?? "3–20 lowercase letters, numbers, or underscores")
                .font(.caption)
                .foregroundStyle(validationMessage == nil ? YEETTheme.muted : Color.red)

            Button(action: save) {
                Group {
                    if isWorking {
                        ProgressView().tint(YEETTheme.ink)
                    } else {
                        Text(buttonTitle)
                    }
                }
                .font(.subheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(YEETTheme.yellow, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }

    private func save() {
        let normalized = HandleValidator.normalize(handle)
        guard HandleValidator.isValid(normalized) else {
            validationMessage = BackendError.invalidHandle.localizedDescription
            return
        }
        validationMessage = nil
        handle = normalized
        Task { _ = await onSave(normalized) }
    }
}

private struct AppleSignInControl: View {
    @ObservedObject var appModel: YEETAppModel
    @Binding var localError: String?
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            localError = nil
            do {
                let nonce = try AppleNonce.make()
                rawNonce = nonce
                request.nonce = AppleNonce.sha256(nonce)
                request.requestedScopes = []
            } catch {
                localError = "Couldn’t prepare Apple sign in."
            }
        } onCompletion: { result in
            switch result {
            case let .failure(error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    localError = "Apple sign in failed. Please try again."
                }
            case let .success(authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let token = String(data: tokenData, encoding: .utf8),
                    let rawNonce
                else {
                    localError = BackendError.invalidAppleCredential.localizedDescription
                    return
                }
                Task { await appModel.completeAppleSignIn(idToken: token, rawNonce: rawNonce) }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .disabled(appModel.isAccountWorking)
        .accessibilityIdentifier("yeet.account.signInWithApple")
    }
}

private struct AppleDeletionControl: View {
    @ObservedObject var appModel: YEETAppModel
    @Binding var localError: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            localError = nil
            request.requestedScopes = []
        } onCompletion: { result in
            switch result {
            case let .failure(error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    localError = "Apple confirmation failed. Please try again."
                }
            case let .success(authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let codeData = credential.authorizationCode,
                    let code = String(data: codeData, encoding: .utf8)
                else {
                    localError = BackendError.invalidAppleCredential.localizedDescription
                    return
                }
                Task { _ = await appModel.deleteAccount(authorizationCode: code) }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .disabled(appModel.isAccountWorking)
        .accessibilityIdentifier("yeet.account.confirmDeletionWithApple")
    }
}

private enum AppleNonce {
    static func make(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else {
                throw BackendError.message("Secure random generation failed.")
            }
            if Int(random) < characters.count {
                result.append(characters[Int(random)])
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
