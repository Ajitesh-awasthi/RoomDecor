import SwiftUI

public struct WelcomeView: View {
    
    // Action closures — no dependency on Coordinator type
    private let openVirtualAction: () -> Void
    private let openRoomScanAction: () -> Void

    @State private var animate = false
    
    // Public init with default no-op closures so previews/tests don't need Coordinator
    public init(
        openVirtualAction: @escaping () -> Void = {},
        openRoomScanAction: @escaping () -> Void = {}
    ) {
        self.openVirtualAction = openVirtualAction
        self.openRoomScanAction = openRoomScanAction
    }
    
    public var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 32) {
                
                // --- TOP LOGO WITH BEAUTIFUL BLUE CIRCLE GLOW ---
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 220, height: 220)
                        .blur(radius: 20)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 160, height: 160)
                        .blur(radius: 12)

                    Image(systemName: "house.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 85)
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.3), radius: 10)
                        .scaleEffect(animate ? 1 : 0.8)
                        .animation(.spring(response: 0.6, dampingFraction: 0.65), value: animate)
                }
                .padding(.top, 40)
                
                // TITLE
                Text("SmartDecor")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.blue)
                    .opacity(animate ? 1 : 0)
                    .animation(.easeIn(duration: 0.5).delay(0.1), value: animate)
                
                // SUBTITLE
                Text("Choose how you want to continue")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
                    .opacity(animate ? 1 : 0)
                    .animation(.easeIn(duration: 0.5).delay(0.2), value: animate)
                
                // BUTTONS (MODERN FLOATING CARDS)
                VStack(spacing: 20) {
                    ModernOptionButton(
                        title: "Live Preview",
                        subtitle: "Try live in your space",
                        icon: "eye.fill",
                        action: openVirtualAction
                    )
                    
                    ModernOptionButton(
                        title: "Design my room",
                        subtitle: "AI recommended setup",
                        icon: "sparkles",
                        action: openRoomScanAction
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .opacity(animate ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.3), value: animate)
                
                Spacer()
            }
        }
        .onAppear { animate = true }
    }
}

struct ModernOptionButton: View {
    
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue.opacity(0.7))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
            )
        }
    }
}

#Preview {
    // Preview works without Coordinator now
    WelcomeView()
}
