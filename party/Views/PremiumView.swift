import SwiftUI
import StoreKit

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Crown Icon
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    // Title
                    Text("Upgrade to Premium")
                        .font(.system(size: 32, weight: .bold))
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Premium Features")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            PremiumFeatureRow(text: "Unlimited party creation")
                            PremiumFeatureRow(text: "Advanced party management tools")
                            PremiumFeatureRow(text: "Priority support")
                            PremiumFeatureRow(text: "Early access to new features")
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Subscription Button Section
                    VStack(spacing: 16) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(1.2)
                        } else if let subscription = storeManager.subscriptions.first {
                            Button(action: {
                                Task {
                                    await purchaseSubscription(subscription)
                                }
                            }) {
                                if isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("\(subscription.displayPrice) / Month")
                                        .bold()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .disabled(isPurchasing)
                        } else {
                            Button(action: {
                                Task {
                                    isLoading = true
                                    await storeManager.loadProducts()
                                    isLoading = false
                                }
                            }) {
                                Text("Retry Loading Subscription")
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Terms Text
                    Text("Subscription will automatically renew unless canceled at least 24 hours before the end of the current period. You can manage your subscription in your App Store account settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            isLoading = true
            await storeManager.loadProducts()
            isLoading = false
        }
    }
    
    private func purchaseSubscription(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            try await storeManager.purchase(product)
            dismiss()
        } catch StoreError.userCancelled {
            // User cancelled, no need to show error
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct PremiumFeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.purple)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

#Preview {
    PremiumView()
} 