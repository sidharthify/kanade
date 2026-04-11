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
                
                Section(header: Text("Appearance")) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        Text("Theme")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Choose app appearance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Theme", selection: $appTheme) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        Text("Default Tab")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Tab to show on launch")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Default Tab", selection: $defaultTab) {
                            Text("Library").tag("Library")
                            Text("Artists").tag("Artists")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Playback")) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        Text("Crossfade")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Overlap duration between tracks")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Slider(value: $crossfadeDuration, in: 0...12, step: 1)
                                .tint(.accentColor)
                            Text("\(Int(crossfadeDuration))s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Performance")) {
                    Toggle(isOn: $disableAnimations) {
                        VStack(alignment: .leading) {
                            Text("Reduce Animations")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Disable heavy UI transitions")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.accentColor)
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Storage")) {
                    Button(action: {
                        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                             try? FileManager.default.removeItem(at: docs.appendingPathComponent("Artwork"))
                             try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text("Clear Image Cache")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text("Frees up local storage")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("About")) {
                    LabeledContent {
                        Text(appVersion)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Version")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Build \(buildNumber)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if let url = URL(string: "https://github.com/sidharthify/kanade/") {
                        Link(destination: url) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Kanade OSS")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("View Source on GitHub")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
