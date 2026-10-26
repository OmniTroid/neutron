import NeutronKit
import SwiftUI

/// Answers DepotDownloader's login prompts.
struct LoginSheet: View {
    @Environment(AppModel.self) private var model
    let prompt: PendingPrompt
    @State private var text = ""

    private var isPassword: Bool { prompt.prompt == .password }

    private var message: String {
        switch prompt.prompt {
        case .password: "Enter the password for \(model.config.user ?? "your Steam account"). Neutron signs in once and remembers it."
        case .guardCode: "Enter the Steam Guard code from your authenticator app."
        case .emailCode(let email): "Enter the Steam Guard code sent to \(email)."
        case .mobileConfirmation: "Approve the sign-in in the Steam Mobile app."
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isPassword ? "person.badge.key.fill" : "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
                .padding(.top, 6)

            VStack(spacing: 6) {
                Text(isPassword ? "Sign in to Steam" : "Steam Guard")
                    .font(.title2.weight(.semibold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if isPassword {
                    SecureField("Password", text: $text)
                } else {
                    TextField("Code", text: $text)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .onSubmit(submit)

            HStack {
                Button("Cancel Download", role: .cancel) { model.answer(prompt, with: nil) }
                Spacer()
                Button(isPassword ? "Sign In" : "Continue", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 380)
    }

    private func submit() {
        guard !text.isEmpty else { return }
        model.answer(prompt, with: isPassword ? text : text.uppercased())
    }
}

/// Asks for the Steam account name the first time something is installed.
struct AccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var user = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            VStack(spacing: 6) {
                Text("Which Steam account?")
                    .font(.title2.weight(.semibold))
                Text("Use the account name you sign in with, the same account as the Mac Steam client.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Account name", text: $user)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit(submit)
            HStack {
                Button("Cancel", role: .cancel) {
                    model.accountRequestFor = nil
                    dismiss()
                }
                Spacer()
                Button("Continue", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(user.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 380)
    }

    private func submit() {
        let user = user.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty else { return }
        model.setAccount(user)
    }
}
