import SwiftUI

struct SettingsView: View {
    @AppStorage("disableAnimations") private var disableAnimations = false
    @AppStorage("crossfadeDuration") private var crossfadeDuration = 0.0
    @AppStorage("defaultTab") private var defaultTab = "Library"
    @AppStorage("appTheme") private var appTheme = 0 // 0: System, 1: Light, 2: Dark

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    VStack(alignment: .leading) {
                        Text("Crossfade Duration")
                        HStack {
                            Slider(value: $crossfadeDuration, in: 0...12, step: 1)
                                .tint(.accentColor)
                            Text("\(Int(crossfadeDuration))s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Appearance & Behavior") {
                    Picker("Theme", selection: $appTheme) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    
                    Picker("Default Tab", selection: $defaultTab) {
                        Text("Library").tag("Library")
                        Text("Artists").tag("Artists")
                    }

                    Toggle("Reduce Animations", isOn: $disableAnimations)
                        .tint(.accentColor)
                }

                Section("Data Cache") {
                    Button(role: .destructive) {
                        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                             try? FileManager.default.removeItem(at: docs.appendingPathComponent("Artwork"))
                             try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
                        }
                    } label: {
                        Text("Clear Artwork Cache")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                    Link("Source Code on GitHub", destination: URL(string: "https://github.com/sidharthify/kanade/")!)
                }

                Section("Support") {
                    Text("Thanks for listening with Kanade. Made by sidharthify.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
