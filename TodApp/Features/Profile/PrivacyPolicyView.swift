import SwiftUI

/// The privacy policy (`PrivacyPolicy`), readable in the app.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Stand: \(PrivacyPolicy.updated)")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
                ForEach(PrivacyPolicy.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.todBody(16, weight: .bold))
                            .foregroundStyle(Color.todText)
                        Text(section.body)
                            .font(.todBody(14))
                            .foregroundStyle(Color.todTextDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.todBackground)
        .navigationTitle("Datenschutz")
        .navigationBarTitleDisplayMode(.inline)
    }
}
