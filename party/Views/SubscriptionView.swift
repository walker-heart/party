import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @StateObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            if storeManager.isSubscribed {
                Text("You are a Premium Member!")
                    .font(.title2)
                    .foregroundColor(.green)
            } else {
                if let subscription = storeManager.subscriptions.first {
                    VStack(spacing: 16) {
                        Text("Upgrade to Premium")
                            .font(.title2)
                            .bold()
                        
                        Text("Get access to all premium features")
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            Task {
                                await purchaseSubscription(subscription)
                            }
                        }) {
                            HStack {
                                Text("Subscribe")
                                Text(subscription.displayPrice)
                                    .bold()
                                Text("/ Month")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isPurchasing)
                    }
                    .padding()
                } else {
                    ProgressView()
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func purchaseSubscription(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            try await storeManager.purchase(product)
        } catch StoreError.userCancelled {
            // User cancelled, no need to show error
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
} 