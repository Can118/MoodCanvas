import SwiftUI
import StoreKit
import os

private let paywallLog = Logger(subsystem: "com.huseyinturkay.moodcanvas.app", category: "paywall")

// MARK: - ViewModel

@MainActor
final class PaywallViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var selectedProduct: Product?
    @Published var isPurchasing = false
    @Published var purchaseError: String?

    private static let productIDs: [String] = [
        "com.huseyinturkay.moodcanvas.app.weekly",
        "com.huseyinturkay.moodcanvas.app.yearly",
        "com.huseyinturkay.moodcanvas.app.lifetime",
    ]

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted {
                let order = Self.productIDs
                return (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99)
            }
            selectedProduct = products.first { $0.id.hasSuffix("yearly") }
            paywallLog.info("Loaded \(self.products.count) product(s)")
        } catch {
            paywallLog.error("Product load failed: \(error.localizedDescription)")
        }
    }

    func purchase() async -> Bool {
        guard let product = selectedProduct else { return false }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                paywallLog.info("Purchase complete: \(product.id)")
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            paywallLog.error("Purchase error: \(error.localizedDescription)")
            return false
        }
    }

    func restore() async -> Bool {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified = result { return true }
            }
            return false
        } catch {
            paywallLog.error("Restore failed: \(error.localizedDescription)")
            return false
        }
    }

    func weeklyEquivalent(for product: Product) -> String? {
        guard product.id.hasSuffix("yearly") else { return nil }
        return (product.price / 52).formatted(product.priceFormatStyle)
    }

    func isLifetime(_ p: Product) -> Bool { p.id.hasSuffix("lifetime") }
    func isYearly(_ p: Product)   -> Bool { p.id.hasSuffix("yearly") }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let e): throw e
        case .verified(let v): return v
        }
    }
}

// MARK: - PaywallView

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isPremium") private var isPremium = false
    @StateObject private var vm = PaywallViewModel()

    @State private var headerVisible = false
    @State private var perksVisible  = false
    @State private var plansVisible  = false
    @State private var ctaVisible    = false
    @State private var ctaPulse      = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "FFFCED").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    closeRow
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    headerSection
                        .padding(.top, 8)
                        .opacity(headerVisible ? 1 : 0)
                        .offset(y: headerVisible ? 0 : 22)

                    perksSection
                        .padding(.top, 20)
                        .opacity(perksVisible ? 1 : 0)
                        .offset(y: perksVisible ? 0 : 22)

                    planCardsSection
                        .padding(.top, 16)
                        .opacity(plansVisible ? 1 : 0)
                        .offset(y: plansVisible ? 0 : 22)

                    ctaSection
                        .padding(.top, 20)
                        .opacity(ctaVisible ? 1 : 0)
                        .offset(y: ctaVisible ? 0 : 22)

                    footerSection
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
            }

            if let msg = toastMessage {
                Text(msg)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(hex: "3C392A")))
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: toastMessage)
        .task {
            await vm.loadProducts()
            withAnimation(.easeOut(duration: 0.45))                     { headerVisible = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.08))         { perksVisible  = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.16))         { plansVisible  = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.24))         { ctaVisible    = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.7)) {
                ctaPulse = true
            }
        }
    }

    // MARK: - Close

    private var closeRow: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.45))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(hex: "3C392A").opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: -16) {
                FloatingMoodIcon(imageName: "tired_mood", delay: 0.5, size: 62)
                FloatingMoodIcon(imageName: "happy_mood", delay: 0.0, size: 80)
                FloatingMoodIcon(imageName: "sad_mood",   delay: 1.0, size: 62)
            }
            Text("Upgrade to Moodi Pro")
                .font(Font.custom("EBGaramond-Bold", size: 30))
                .foregroundStyle(Color(hex: "3C392A"))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Perks

    private let perks: [(String, String)] = [
        ("person.3.fill",  "Create unlimited groups"),
        ("widget.small",   "Real-time widget sync"),
        ("sparkles",       "All upcoming features included"),
    ]

    private var perksSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(perks.enumerated()), id: \.offset) { idx, perk in
                PerkRow(icon: perk.0, text: perk.1)
                    .padding(.vertical, 12)
                if idx < perks.count - 1 {
                    Rectangle()
                        .fill(Color(hex: "3C392A").opacity(0.07))
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "F5EEDC"))
                .shadow(color: Color(hex: "3C392A").opacity(0.05), radius: 16, y: 6)
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Plan Cards

    private var planCardsSection: some View {
        VStack(spacing: 10) {
            if vm.products.isEmpty {
                ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
            } else {
                ForEach(vm.products, id: \.id) { product in
                    PlanCard(
                        product: product,
                        isSelected: vm.selectedProduct?.id == product.id,
                        weeklyEquivalent: vm.weeklyEquivalent(for: product),
                        isLifetime: vm.isLifetime(product),
                        isYearly: vm.isYearly(product)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            vm.selectedProduct = product
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    let ok = await vm.purchase()
                    if ok {
                        isPremium = true
                        dismiss()
                    }
                }
            } label: {
                Group {
                    if vm.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    Capsule()
                        .fill(Color(hex: "B8721C"))
                        .scaleEffect(ctaPulse ? 1.015 : 1.0)
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.isPurchasing || vm.selectedProduct == nil)
            .padding(.horizontal, 24)

            if let error = vm.purchaseError {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(hex: "B8721C"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let p = vm.selectedProduct, p.subscription != nil {
                Text("Cancel anytime in your iPhone Settings")
                    .font(Font.custom("EBGaramond-Regular", size: 14))
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.38))
            }
        }
    }

    private var ctaTitle: String {
        guard let p = vm.selectedProduct else { return "Get Moodi Pro" }
        if vm.isLifetime(p) { return "Get Lifetime Access — \(p.displayPrice)" }
        return "Continue — \(p.displayPrice)"
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    let ok = await vm.restore()
                    let msg = ok ? "Purchases restored!" : "No active subscriptions found."
                    if ok { isPremium = true }
                    withAnimation { toastMessage = msg }
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { toastMessage = nil }
                    if ok { dismiss() }
                }
            } label: {
                Text("Restore purchases")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.45))
                    .underline()
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                Link("Privacy Policy",
                     destination: URL(string: "https://nocap.bio/moodi/privacy")!)
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.35))
                Text("·")
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.25))
                Link("Terms of Use",
                     destination: URL(string: "https://nocap.bio/moodi/terms")!)
                    .foregroundStyle(Color(hex: "3C392A").opacity(0.35))
            }
            .font(.system(.caption, design: .rounded))
        }
    }
}

// MARK: - FloatingMoodIcon

private struct FloatingMoodIcon: View {
    let imageName: String
    let delay: Double
    let size: CGFloat

    @State private var floatY: CGFloat = 0

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            .offset(y: floatY)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) { floatY = -10 }
            }
    }
}

// MARK: - PerkRow

private struct PerkRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "B8721C"))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(hex: "B8721C").opacity(0.12)))
            Text(text)
                .font(Font.custom("EBGaramond-Regular", size: 17))
                .foregroundStyle(Color(hex: "3C392A"))
            Spacer()
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let weeklyEquivalent: String?
    let isLifetime: Bool
    let isYearly: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? Color(hex: "B8721C") : Color(hex: "3C392A").opacity(0.2),
                        lineWidth: isSelected ? 2 : 1.5
                    )
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .fill(Color(hex: "B8721C"))
                        .frame(width: 12, height: 12)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(planTitle)
                        .font(Font.custom("EBGaramond-SemiBold", size: 18))
                        .foregroundStyle(Color(hex: "3C392A"))
                    if isYearly {
                        Text("Best Value")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: "B8721C")))
                    }
                    if isLifetime {
                        Text("One-time")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: "3C392A").opacity(0.6))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: "3C392A").opacity(0.1)))
                    }
                }
                if let wk = weeklyEquivalent {
                    Text("≈ \(wk) / week")
                        .font(Font.custom("EBGaramond-Regular", size: 14))
                        .foregroundStyle(Color(hex: "3C392A").opacity(0.45))
                }
            }

            Spacer()

            Text(product.displayPrice)
                .font(Font.custom("EBGaramond-SemiBold", size: 18))
                .foregroundStyle(isSelected ? Color(hex: "B8721C") : Color(hex: "3C392A").opacity(0.65))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color(hex: "B8721C").opacity(0.07) : Color(hex: "EDE8D8"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isSelected ? Color(hex: "B8721C") : Color.clear,
                            lineWidth: 1.5
                        )
                )
        )
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }

    private var planTitle: String {
        if isLifetime { return "Lifetime" }
        if isYearly   { return "Yearly" }
        return "Weekly"
    }
}

// MARK: - SkeletonCard

private struct SkeletonCard: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(hex: "EDE8D8"))
            .frame(height: 68)
            .opacity(pulse ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .padding(.horizontal, 0)
    }
}

#Preview {
    PaywallView()
}
