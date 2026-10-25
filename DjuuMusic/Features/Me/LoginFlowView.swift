import SwiftUI

/// 手机号 + 短信验证码登录（复刻站点 /user/mlogin 流程）。
/// 获取验证码前需通过滑块拼图验证码，换取 token 后调用 /code/sendSms。
struct LoginFlowView: View {
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mobile = ""
    @State private var smsCode = ""
    @State private var agreed = false
    @State private var showCaptcha = false
    @State private var countdown = 0
    @State private var countdownTimer: Timer?
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var showToast = false
    @State private var toastText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 20)

                VStack(spacing: 14) {
                    phoneField
                    codeField
                    agreementRow
                    loginButton
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("手机号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showCaptcha) {
                SliderCaptchaView { token in
                    Task { await requestSms(token: token) }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } })) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .overlay {
                if showToast {
                    VStack {
                        Text(toastText)
                            .font(.footnote)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .transition(.opacity)
                }
            }
            .onDisappear { countdownTimer?.invalidate() }
        }
    }

    // MARK: - Fields

    private var phoneField: some View {
        HStack {
            Text("+86")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("手机号码", text: $mobile)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private var codeField: some View {
        HStack(spacing: 10) {
            TextField("验证码", text: $smsCode)
                .keyboardType(.numberPad)
            // 不用 glassEffect：嵌在外层输入框的玻璃内会产生文字叠影，改实底胶囊。
            Button {
                guard validatePhone() else { return }
                showCaptcha = true
            } label: {
                Text(countdown > 0 ? "\(countdown)秒" : "获取验证码")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(countdown > 0 ? Color.secondary : Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(countdown > 0 ? Color.gray.opacity(0.35) : Color.accentColor,
                                in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(countdown > 0)
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .padding(.trailing, 4)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private var agreementRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                agreed.toggle()
            } label: {
                Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(agreed ? Color.accentColor : .secondary)
            }
            Text("我已阅读并同意《用户服务协议》与《隐私政策》")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var loginButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("登录").bold()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .disabled(isSubmitting)
    }

    // MARK: - Actions

    private func validatePhone() -> Bool {
        let trimmed = mobile.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 11, trimmed.hasPrefix("1"),
              let _ = Int(trimmed) else {
            alertMessage = "请输入正确的手机号码"
            return false
        }
        mobile = trimmed
        return true
    }

    private func requestSms(token: String) async {
        do {
            let message = try await DjuuAPI.sendSms(mobile: mobile, token: token)
            toastText = message
            withAnimation { showToast = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showToast = false }
            startCountdown()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdown = 60
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 { timer.invalidate() }
            }
        }
    }

    private func submit() async {
        guard validatePhone() else { return }
        guard smsCode.count == 4 else {
            alertMessage = "验证码不正确"
            return
        }
        guard agreed else {
            alertMessage = "您需要阅读并同意《用户服务协议》与《隐私政策》才能继续"
            return
        }
        isSubmitting = true
        do {
            let profile = try await DjuuAPI.login(mobile: mobile, smsCode: smsCode)
            LocalStore.profile = profile
            onSuccess()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
