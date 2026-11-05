import SwiftUI

/// Phone number, then the WhatsApp code. Email + password is the quiet fallback (also what the
/// App Review account uses).
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    private enum Step { case phone, code }
    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var cooldown = 0
    @State private var showEmail = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("Fox").resizable().scaledToFit().frame(height: 150).padding(.top, 36)
                VStack(spacing: 6) {
                    Text("לוגיפוד למורים").font(.largeTitle.bold())
                    Text(step == .phone ? "הכניסו את מספר הטלפון ונשלח קוד בוואטסאפ" : "שלחנו קוד בן 6 ספרות ל-\(Phone.format(phone))")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                if let notice = auth.notice {
                    Label(notice, systemImage: "info.circle.fill").font(.footnote).foregroundStyle(.orange)
                }

                if step == .phone { phoneStep } else { codeStep }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Button("כניסה עם אימייל וסיסמה") { showEmail = true }
                    .font(.footnote).padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showEmail) { EmailLoginView().environment(\.layoutDirection, .rightToLeft) }
        .onAppear { focused = true }
    }

    private var phoneStep: some View {
        VStack(spacing: 14) {
            TextField("050-123-4567", text: $phone)
                .keyboardType(.numberPad).textContentType(.telephoneNumber)
                .font(.title2.monospacedDigit()).multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .padding(14).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                .focused($focused)
                .onChange(of: phone) { _, new in
                    let f = Phone.format(new)
                    if f != new { phone = f }
                }
            primaryButton("שלחו לי קוד", enabled: Phone.isValid(phone)) { await sendCode() }
        }
    }

    private var codeStep: some View {
        VStack(spacing: 14) {
            TextField("••••••", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.system(size: 32, weight: .semibold, design: .monospaced)).kerning(8)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .padding(14).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                .focused($focused)
                .onChange(of: code) { _, new in
                    let d = String(new.filter(\.isNumber).prefix(6))
                    if d != new { code = d }
                    if d.count == 6 { Task { await verify() } }
                }
            primaryButton("כניסה", enabled: code.count == 6) { await verify() }
            HStack(spacing: 18) {
                Button("מספר אחר") { step = .phone; code = ""; error = nil }
                Button(cooldown > 0 ? "שליחה חוזרת (\(cooldown))" : "שליחה חוזרת") { Task { await sendCode() } }
                    .disabled(cooldown > 0 || busy)
            }
            .font(.footnote)
        }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(!enabled || busy)
    }

    private func sendCode() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await auth.requestCode(phone: Phone.digits(phone))
            step = .code; code = ""; focused = true
            startCooldown()
        } catch { self.error = error.localizedDescription }
    }

    private func verify() async {
        guard !busy, code.count == 6 else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await auth.verify(phone: phone, code: code) } catch {
            self.error = "הקוד שגוי או שפג תוקפו. בדקו ונסו שוב."
            code = ""
        }
    }

    private func startCooldown() {
        cooldown = 30
        Task {
            while cooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                cooldown -= 1
            }
        }
    }
}

struct EmailLoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("אימייל", text: $email)
                        .keyboardType(.emailAddress).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    SecureField("סיסמה", text: $password).textContentType(.password)
                        .environment(\.layoutDirection, .leftToRight)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack { if busy { ProgressView() }; Text("כניסה").bold() }.frame(maxWidth: .infinity)
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("כניסה עם אימייל")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } } }
        }
    }

    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            dismiss()
        } catch { self.error = "האימייל או הסיסמה שגויים." }
    }
}
