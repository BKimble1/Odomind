import SwiftUI
import StoreKit
import OdomindCore

/// Odomind Pro.
///
/// Never shown during first setup, and never as a wall between the owner and
/// something they already had. It lists only what is actually built, states
/// the total price and the period it buys, and says plainly what happens if
/// the subscription ends.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String?
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    header
                    features
                    plans
                    footerNotes
                }
                .padding(Theme.Spacing.large)
            }
            .background(Theme.Palette.page)
            .navigationTitle("Odomind Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("paywall.dismiss")
                }
            }
            .task {
                if model.entitlements.products.isEmpty {
                    await model.entitlements.loadProducts()
                }
                selectedProductID = selectedProductID ?? defaultSelection
            }
        }
    }

    private var entitlements: EntitlementService { model.entitlements }

    private var defaultSelection: String? {
        entitlements.products.first(where: { $0.id == ProProduct.yearly })?.id
            ?? entitlements.products.first?.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            if model.isPro {
                Label("You have Odomind Pro", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
            } else {
                Text("Keep it all up to date")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
            }
            Text("Odomind works without a subscription, and always will. Pro adds the parts that save you time month after month.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(spacing: 0) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                    Image(systemName: feature.symbolName)
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text(feature.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if feature != ProFeature.allCases.last {
                    Divider().overlay(Theme.Palette.separator)
                }
            }
        }
        .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder
    private var plans: some View {
        if model.isPro {
            VStack(spacing: Theme.Spacing.small) {
                manageLink
            }
        } else if let failure = entitlements.loadFailure {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    // No price is invented here. If the App Store did not
                    // answer, the screen says so and offers to try again.
                    Label("Subscription details unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Colors.caution)
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Button("Try again") {
                        Task { await entitlements.loadProducts() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityIdentifier("paywall.retry")
                }
            }
        } else if entitlements.products.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Theme.Spacing.medium) {
                ForEach(entitlements.products, id: \.id) { product in
                    PlanRow(
                        product: product,
                        isSelected: selectedProductID == product.id
                    ) {
                        selectedProductID = product.id
                    }
                }

                PrimaryActionButton(title: subscribeTitle) {
                    Task { await buy() }
                }
                .disabled(selectedProductID == nil || isWorking || entitlements.isPurchasing)
                .accessibilityIdentifier("paywall.subscribe")

                Button("Restore purchases") {
                    Task { await restore() }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.accent)
                .frame(minHeight: Theme.minimumTapTarget)
                .accessibilityIdentifier("paywall.restore")
            }
        }
    }

    private var subscribeTitle: String {
        guard let id = selectedProductID,
              let product = entitlements.products.first(where: { $0.id == id })
        else { return "Subscribe" }
        return "Subscribe · \(product.displayPrice)"
    }

    private var manageLink: some View {
        VStack(spacing: Theme.Spacing.small) {
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                Link("Manage subscription", destination: url)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(minHeight: Theme.minimumTapTarget)
                    .accessibilityIdentifier("paywall.manage")
            }
            Button("Restore purchases") { Task { await restore() } }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.accent)
                .frame(minHeight: Theme.minimumTapTarget)
        }
    }

    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            if let message {
                QuietNote(text: message, symbolName: "info.circle")
            }
            QuietNote(text: ProPolicy.lapsePromise, symbolName: "lock.open")
            Text("Payment is charged to your Apple Account at confirmation. A subscription renews automatically unless you turn renewal off at least 24 hours before the period ends. You can manage or cancel it in your Apple Account settings.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.large) {
                Link("Privacy", destination: SupportLinks.privacy)
                Link("Terms", destination: SupportLinks.terms)
            }
            .font(.caption)
            .foregroundStyle(Theme.Palette.accent)
        }
    }

    private func buy() async {
        guard let id = selectedProductID,
              let product = entitlements.products.first(where: { $0.id == id })
        else { return }
        isWorking = true
        defer { isWorking = false }

        switch await entitlements.purchase(product) {
        case .purchased:
            message = nil
            dismiss()
        case .pending:
            message = "This purchase is waiting for approval. Odomind will unlock Pro as soon as it goes through."
        case .cancelled:
            message = nil
        case .failed(let reason):
            message = reason
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        switch await entitlements.restore() {
        case .purchased:
            message = nil
            dismiss()
        case .failed(let reason):
            message = reason
        case .pending, .cancelled:
            message = nil
        }
    }
}

/// One purchasable plan.
///
/// The total and the period it buys are the headline. Any per-month equivalent
/// of the annual plan is secondary and marked as an equivalent, because the
/// amount actually charged is the yearly one.
private struct PlanRow: View {
    let product: Product
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.primaryText)
                    if let equivalent { 
                        Text(equivalent)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
            }
            .padding(Theme.Spacing.medium)
            .frame(minHeight: Theme.minimumTapTarget)
            .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .strokeBorder(isSelected ? Theme.Palette.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text("\(periodTitle), \(product.displayPrice)"))
        .accessibilityIdentifier("paywall.plan.\(product.id)")
    }

    private var periodTitle: String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayName }
        switch period.unit {
        case .month where period.value == 1: return "Monthly"
        case .year where period.value == 1: return "Yearly"
        default: return product.displayName
        }
    }

    /// Only for the yearly plan, and only ever as "about £x a month", never as
    /// the price being charged.
    private var equivalent: String? {
        guard let period = product.subscription?.subscriptionPeriod,
              period.unit == .year, period.value == 1
        else { return nil }
        // Formatted with the product's own style, so the currency and its
        // conventions come from the storefront rather than being assumed.
        let monthly = product.price / 12
        return "Billed once a year · about \(monthly.formatted(product.priceFormatStyle)) a month"
    }
}

/// Where the legal links point.
///
/// Apple's standard EULA is the terms unless a custom agreement is filed, and
/// that is what this points at.
enum SupportLinks {
    static let privacy = URL(string: "https://idlery.com/odomind/privacy")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "https://idlery.com/odomind/support")!
}
