import SwiftUI
import FamilyControls

struct ScreenTimeSettingsView: View {
    @StateObject private var manager = ScreenTimeManager.shared
    @State private var showPicker = false
    @State private var showAuthDeniedAlert = false
    @State private var authErrorText: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { manager.isEnabled },
                    set: { newValue in
                        Task {
                            await manager.setEnabled(newValue)
                            if newValue && manager.authorizationStatus != .approved {
                                showAuthDeniedAlert = true
                            }
                        }
                    }
                )) {
                    Text("Block distracting apps")
                        .foregroundColor(dynamicTextColor)
                }
                .tint(dynamicSecondaryColor)
                .listRowBackground(dynamicSecondaryBackgroundColor)
            } header: {
                Text("Focus Blocker")
                    .foregroundColor(dynamicTextColor)
                    .font(.headline)
            } footer: {
                Text("When enabled, YourDay will soft-block the apps you pick. You can always click through — but skipping your plan or breaking focus during a scheduled task deducts 10% of your garden value (minimum 100 points).")
                    .foregroundColor(dynamicSecondaryTextColor)
            }

            if manager.isEnabled && manager.authorizationStatus == .approved {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text("Choose apps to block")
                                .foregroundColor(dynamicTextColor)
                            Spacer()
                            Text(selectionSummary)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } header: {
                    Text("Apps")
                        .foregroundColor(dynamicTextColor)
                        .font(.headline)
                }
            }

            if manager.isEnabled && manager.authorizationStatus != .approved {
                Section {
                    Text("Screen Time authorization is required. Open iOS Settings → Screen Time to grant access, then toggle again here.")
                        .foregroundColor(dynamicDestructiveColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .navigationTitle("Focus Blocker")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showPicker, selection: Binding(
            get: { manager.selection },
            set: { manager.updateSelection($0) }
        ))
        .alert("Authorization Needed", isPresented: $showAuthDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Grant Screen Time access in iOS Settings → Screen Time to use the focus blocker.")
        }
    }

    private var selectionSummary: String {
        let appsCount = manager.selection.applicationTokens.count
        let categoriesCount = manager.selection.categoryTokens.count
        let webCount = manager.selection.webDomainTokens.count
        let total = appsCount + categoriesCount + webCount
        if total == 0 { return "None selected" }
        var parts: [String] = []
        if appsCount > 0 { parts.append("\(appsCount) app\(appsCount == 1 ? "" : "s")") }
        if categoriesCount > 0 { parts.append("\(categoriesCount) categor\(categoriesCount == 1 ? "y" : "ies")") }
        if webCount > 0 { parts.append("\(webCount) site\(webCount == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}
