import SwiftUI

struct WidgetTutorialView: View {
    let onDismiss: () -> Void
    @State private var currentPage = 0

    private let images       = ["step1_iphone", "step2_iphone", "step3_iphone"]
    private let descriptions = [
        "Hold down on any app to edit your home screen",
        "Tap the Edit button in the top left corner",
        "Search for Moodi and add the widget"
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: "FFFCED").ignoresSafeArea()

            VStack(spacing: 0) {
                // Space for skip button
                Color.clear.frame(height: 52)

                Spacer().frame(height: 48)

                // Title — same on every step
                Text("Add the widget to your home screen")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "665938"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)

                Spacer().frame(height: 36)

                // Swipeable phone illustrations using real assets
                TabView(selection: $currentPage) {
                    ForEach(0..<3, id: \.self) { page in
                        Image(images[page])
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, 16)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 440)

                Spacer().frame(height: 24)

                // Step description
                Text(descriptions[currentPage])
                    .font(Font.custom("EBGaramond-Medium", size: 24))
                    .foregroundStyle(Color(hex: "665938"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                    .frame(height: 76, alignment: .top)
                    .id(currentPage)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: currentPage)

                Spacer().frame(height: 20)

                // Page dots
                HStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage
                                  ? Color(hex: "665938")
                                  : Color(hex: "665938").opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: currentPage)

                Spacer()
            }

            // Skip — always ends the tutorial immediately
            Button("skip") { onDismiss() }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "B69F83"))
                .padding(.top, 18)
                .padding(.trailing, 26)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
