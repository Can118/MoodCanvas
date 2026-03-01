import SwiftUI

// MARK: - Country model

struct Country: Identifiable {
    let id = UUID()
    let name: String
    let flag: String
    let dialCode: String
}

private let countriesList: [Country] = [
    Country(name: "Afghanistan",          flag: "🇦🇫", dialCode: "+93"),
    Country(name: "Albania",              flag: "🇦🇱", dialCode: "+355"),
    Country(name: "Algeria",              flag: "🇩🇿", dialCode: "+213"),
    Country(name: "Argentina",            flag: "🇦🇷", dialCode: "+54"),
    Country(name: "Armenia",              flag: "🇦🇲", dialCode: "+374"),
    Country(name: "Australia",            flag: "🇦🇺", dialCode: "+61"),
    Country(name: "Austria",              flag: "🇦🇹", dialCode: "+43"),
    Country(name: "Azerbaijan",           flag: "🇦🇿", dialCode: "+994"),
    Country(name: "Bahrain",              flag: "🇧🇭", dialCode: "+973"),
    Country(name: "Bangladesh",           flag: "🇧🇩", dialCode: "+880"),
    Country(name: "Belarus",              flag: "🇧🇾", dialCode: "+375"),
    Country(name: "Belgium",              flag: "🇧🇪", dialCode: "+32"),
    Country(name: "Bolivia",              flag: "🇧🇴", dialCode: "+591"),
    Country(name: "Brazil",               flag: "🇧🇷", dialCode: "+55"),
    Country(name: "Bulgaria",             flag: "🇧🇬", dialCode: "+359"),
    Country(name: "Cambodia",             flag: "🇰🇭", dialCode: "+855"),
    Country(name: "Canada",               flag: "🇨🇦", dialCode: "+1"),
    Country(name: "Chile",                flag: "🇨🇱", dialCode: "+56"),
    Country(name: "China",                flag: "🇨🇳", dialCode: "+86"),
    Country(name: "Colombia",             flag: "🇨🇴", dialCode: "+57"),
    Country(name: "Croatia",              flag: "🇭🇷", dialCode: "+385"),
    Country(name: "Czech Republic",       flag: "🇨🇿", dialCode: "+420"),
    Country(name: "Denmark",              flag: "🇩🇰", dialCode: "+45"),
    Country(name: "Ecuador",              flag: "🇪🇨", dialCode: "+593"),
    Country(name: "Egypt",                flag: "🇪🇬", dialCode: "+20"),
    Country(name: "Estonia",              flag: "🇪🇪", dialCode: "+372"),
    Country(name: "Ethiopia",             flag: "🇪🇹", dialCode: "+251"),
    Country(name: "Finland",              flag: "🇫🇮", dialCode: "+358"),
    Country(name: "France",               flag: "🇫🇷", dialCode: "+33"),
    Country(name: "Georgia",              flag: "🇬🇪", dialCode: "+995"),
    Country(name: "Germany",              flag: "🇩🇪", dialCode: "+49"),
    Country(name: "Ghana",                flag: "🇬🇭", dialCode: "+233"),
    Country(name: "Greece",               flag: "🇬🇷", dialCode: "+30"),
    Country(name: "Guatemala",            flag: "🇬🇹", dialCode: "+502"),
    Country(name: "Hong Kong",            flag: "🇭🇰", dialCode: "+852"),
    Country(name: "Hungary",              flag: "🇭🇺", dialCode: "+36"),
    Country(name: "India",                flag: "🇮🇳", dialCode: "+91"),
    Country(name: "Indonesia",            flag: "🇮🇩", dialCode: "+62"),
    Country(name: "Iran",                 flag: "🇮🇷", dialCode: "+98"),
    Country(name: "Iraq",                 flag: "🇮🇶", dialCode: "+964"),
    Country(name: "Ireland",              flag: "🇮🇪", dialCode: "+353"),
    Country(name: "Israel",               flag: "🇮🇱", dialCode: "+972"),
    Country(name: "Italy",                flag: "🇮🇹", dialCode: "+39"),
    Country(name: "Japan",                flag: "🇯🇵", dialCode: "+81"),
    Country(name: "Jordan",               flag: "🇯🇴", dialCode: "+962"),
    Country(name: "Kazakhstan",           flag: "🇰🇿", dialCode: "+7"),
    Country(name: "Kenya",                flag: "🇰🇪", dialCode: "+254"),
    Country(name: "Kuwait",               flag: "🇰🇼", dialCode: "+965"),
    Country(name: "Kyrgyzstan",           flag: "🇰🇬", dialCode: "+996"),
    Country(name: "Latvia",               flag: "🇱🇻", dialCode: "+371"),
    Country(name: "Lebanon",              flag: "🇱🇧", dialCode: "+961"),
    Country(name: "Libya",                flag: "🇱🇾", dialCode: "+218"),
    Country(name: "Lithuania",            flag: "🇱🇹", dialCode: "+370"),
    Country(name: "Luxembourg",           flag: "🇱🇺", dialCode: "+352"),
    Country(name: "Malaysia",             flag: "🇲🇾", dialCode: "+60"),
    Country(name: "Mexico",               flag: "🇲🇽", dialCode: "+52"),
    Country(name: "Moldova",              flag: "🇲🇩", dialCode: "+373"),
    Country(name: "Morocco",              flag: "🇲🇦", dialCode: "+212"),
    Country(name: "Netherlands",          flag: "🇳🇱", dialCode: "+31"),
    Country(name: "New Zealand",          flag: "🇳🇿", dialCode: "+64"),
    Country(name: "Nigeria",              flag: "🇳🇬", dialCode: "+234"),
    Country(name: "Norway",               flag: "🇳🇴", dialCode: "+47"),
    Country(name: "Pakistan",             flag: "🇵🇰", dialCode: "+92"),
    Country(name: "Paraguay",             flag: "🇵🇾", dialCode: "+595"),
    Country(name: "Peru",                 flag: "🇵🇪", dialCode: "+51"),
    Country(name: "Philippines",          flag: "🇵🇭", dialCode: "+63"),
    Country(name: "Poland",               flag: "🇵🇱", dialCode: "+48"),
    Country(name: "Portugal",             flag: "🇵🇹", dialCode: "+351"),
    Country(name: "Qatar",                flag: "🇶🇦", dialCode: "+974"),
    Country(name: "Romania",              flag: "🇷🇴", dialCode: "+40"),
    Country(name: "Russia",               flag: "🇷🇺", dialCode: "+7"),
    Country(name: "Saudi Arabia",         flag: "🇸🇦", dialCode: "+966"),
    Country(name: "Serbia",               flag: "🇷🇸", dialCode: "+381"),
    Country(name: "Singapore",            flag: "🇸🇬", dialCode: "+65"),
    Country(name: "Slovakia",             flag: "🇸🇰", dialCode: "+421"),
    Country(name: "Slovenia",             flag: "🇸🇮", dialCode: "+386"),
    Country(name: "South Africa",         flag: "🇿🇦", dialCode: "+27"),
    Country(name: "South Korea",          flag: "🇰🇷", dialCode: "+82"),
    Country(name: "Spain",                flag: "🇪🇸", dialCode: "+34"),
    Country(name: "Sri Lanka",            flag: "🇱🇰", dialCode: "+94"),
    Country(name: "Sweden",               flag: "🇸🇪", dialCode: "+46"),
    Country(name: "Switzerland",          flag: "🇨🇭", dialCode: "+41"),
    Country(name: "Taiwan",               flag: "🇹🇼", dialCode: "+886"),
    Country(name: "Thailand",             flag: "🇹🇭", dialCode: "+66"),
    Country(name: "Tunisia",              flag: "🇹🇳", dialCode: "+216"),
    Country(name: "Turkey",               flag: "🇹🇷", dialCode: "+90"),
    Country(name: "Ukraine",              flag: "🇺🇦", dialCode: "+380"),
    Country(name: "United Arab Emirates", flag: "🇦🇪", dialCode: "+971"),
    Country(name: "United Kingdom",       flag: "🇬🇧", dialCode: "+44"),
    Country(name: "United States",        flag: "🇺🇸", dialCode: "+1"),
    Country(name: "Uruguay",              flag: "🇺🇾", dialCode: "+598"),
    Country(name: "Uzbekistan",           flag: "🇺🇿", dialCode: "+998"),
    Country(name: "Venezuela",            flag: "🇻🇪", dialCode: "+58"),
    Country(name: "Vietnam",              flag: "🇻🇳", dialCode: "+84"),
    Country(name: "Yemen",                flag: "🇾🇪", dialCode: "+967"),
]

// MARK: - Country Picker Sheet

struct CountryPickerSheet: View {
    @Binding var selected: Country
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Country] {
        search.isEmpty
            ? countriesList
            : countriesList.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { country in
                Button {
                    selected = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.title2)
                        Text(country.name)
                            .foregroundStyle(Color(hex: "3C392A"))
                        Spacer()
                        Text(country.dialCode)
                            .foregroundStyle(Color(hex: "837C5A"))
                            .font(.system(size: 14, design: .rounded))
                    }
                }
            }
            .searchable(text: $search, prompt: "Search country")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - Phone Number View

struct PhoneNumberView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var phoneDigits = ""
    @State private var isLoading = false
    @State private var navigateToVerification = false
    @State private var selectedCountry = countriesList.first(where: { $0.dialCode == "+1" && $0.name == "United States" }) ?? countriesList[0]
    @State private var showCountryPicker = false
    @FocusState private var isFocused: Bool

    private var rawDigits: String { phoneDigits.filter(\.isNumber) }
    private var isValid: Bool { rawDigits.count == 10 }
    private var fullNumber: String { "\(selectedCountry.dialCode)\(rawDigits)" }

    var body: some View {
        ZStack {
            Color(hex: "FFFCED").ignoresSafeArea()

            // Back button
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "3C392A"))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer().frame(height: 120)

                // Title
                Text("What's your number?")
                    .font(Font.custom("EBGaramond-Medium", size: 28))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer().frame(height: 28)

                // Phone input
                HStack(spacing: 0) {
                    // Tappable country code
                    Button { showCountryPicker = true } label: {
                        HStack(spacing: 6) {
                            Text(selectedCountry.flag)
                                .font(.system(size: 20))
                            Text(selectedCountry.dialCode)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "837C5A"))
                        }
                        .padding(.leading, 18)
                        .padding(.trailing, 14)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color(hex: "3C392A").opacity(0.12))
                        .frame(width: 1, height: 28)

                    TextField("", text: $phoneDigits)
                        .keyboardType(.numberPad)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "3C392A"))
                        .multilineTextAlignment(.leading)
                        .focused($isFocused)
                        .tint(Color(hex: "B8721C"))
                        .padding(.leading, 14)
                        .padding(.trailing, 14)
                        .onChange(of: phoneDigits) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(10))
                            var formatted = ""
                            for (i, char) in digits.enumerated() {
                                if i == 3 || i == 6 { formatted += "-" }
                                formatted.append(char)
                            }
                            if phoneDigits != formatted { phoneDigits = formatted }
                        }
                }
                .frame(height: 60)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "FFFBE5")))
                .shadow(color: Color(hex: "3C392A").opacity(0.10), radius: 12, x: 0, y: 5)
                .padding(.horizontal, 28)

                Spacer()

                // Terms / error
                Group {
                    if let error = authService.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    } else {
                        Text("By tapping Next, you are agreeing to our Terms\nand Privacy.")
                            .foregroundStyle(Color(hex: "837C5A"))
                    }
                }
                .font(.system(size: 12, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

                Spacer().frame(height: 16)

                // Next button
                Button {
                    Task {
                        isLoading = true
                        await authService.sendVerificationCode(to: fullNumber)
                        isLoading = false
                        if authService.errorMessage == nil {
                            navigateToVerification = true
                        }
                    }
                } label: {
                    nextButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isLoading)
                .opacity(isValid ? 1 : 0.5)
                .padding(.horizontal, 40)

                Spacer().frame(height: 24)
            }
        }
        .navigationDestination(isPresented: $navigateToVerification) {
            VerificationView(phoneNumber: fullNumber)
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $selectedCountry)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear { isFocused = true }
    }

    private var nextButtonLabel: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Next")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .black))
                        .padding(.trailing, 26)
                }
                .foregroundStyle(.white)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            Capsule()
                .fill(Color(hex: "B8721C"))
                .overlay {
                    Capsule()
                        .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
                }
        }
    }
}

#Preview {
    NavigationStack {
        PhoneNumberView()
            .environmentObject(AuthService())
    }
}
