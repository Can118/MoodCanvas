import SwiftUI

struct WidgetTutorialView: View {
    let onDismiss: () -> Void
    @State private var currentPage = 0

    private let descriptions = [
        "Hold down on any app to edit\nyour home screen",
        "Tap the Edit button in the top\nleft corner",
        "Search for Moodi and add the\nwidget"
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: "FFFCED").ignoresSafeArea()

            VStack(spacing: 0) {
                // Reserve space for skip button
                Color.clear.frame(height: 54)

                // Title — same on every page
                Text("Add the widget to your\nhome screen")
                    .font(Font.custom("EBGaramond-Bold", size: 26))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)

                // Phone illustrations — swipeable
                TabView(selection: $currentPage) {
                    ForEach(0..<3, id: \.self) { page in
                        PhoneIllustration(page: page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 400)

                // Description — fades on page change
                Text(descriptions[currentPage])
                    .font(Font.custom("EBGaramond-Medium", size: 20))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .frame(height: 68, alignment: .top)
                    .animation(.easeInOut(duration: 0.15), value: currentPage)

                // Page dots
                HStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage
                                  ? Color(hex: "665938")
                                  : Color(hex: "BEB89E"))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 16)
                .animation(.easeInOut(duration: 0.15), value: currentPage)

                Spacer()
            }

            // Skip / done button
            Button(currentPage == 2 ? "done" : "skip") {
                onDismiss()
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Color(hex: "837C5A"))
            .padding(.top, 20)
            .padding(.trailing, 26)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Phone illustration

private struct PhoneIllustration: View {
    let page: Int

    private var rotation: Double {
        switch page {
        case 0: return -9.0
        case 1: return -4.0
        default: return  2.0
        }
    }

    var body: some View {
        ZStack {
            phoneMockup
                .rotationEffect(.degrees(rotation))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phoneMockup: some View {
        ZStack(alignment: .top) {
            // Phone shell
            RoundedRectangle(cornerRadius: 42)
                .fill(Color(hex: "EAE6D5"))
                .overlay {
                    RoundedRectangle(cornerRadius: 42)
                        .strokeBorder(Color(hex: "4A4824"), lineWidth: 11)
                }
                .frame(width: 200, height: 376)

            // Screen content
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // App icon grid — top padding shifts down for overlay on page 2
                    appGrid
                        .padding(.horizontal, 18)
                        .padding(.top, page == 2 ? 58 : 44)

                    // Per-page overlay
                    if page == 1 {
                        editBadge
                    } else if page == 2 {
                        searchBar
                    }
                }

                Spacer()

                // Home indicator
                Capsule()
                    .fill(Color(hex: "BEB89E"))
                    .frame(width: 68, height: 5)
                    .padding(.bottom, 18)
            }
            .frame(width: 200, height: 376)
        }
    }

    // MARK: App grid (3 × 4 placeholder icons)

    private var appGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 10
        ) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "C8C4AE"))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    // MARK: "Edit" badge — page 1

    private var editBadge: some View {
        HStack {
            Text("Edit")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: "3C392A"))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: "DEDAD0")))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
    }

    // MARK: Search bar — page 2

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
            Text("Moodi")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color(hex: "797548")))
        .padding(.horizontal, 18)
        .padding(.top, 28)
    }
}
