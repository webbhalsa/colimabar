import SwiftUI

struct NewProfileSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var name: String = ""
    @State private var options = ProfileStartOptions(cpu: 4, memoryGB: 8, diskGB: 100, runtime: "docker")

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var existingNames: Set<String> { Set(appState.profiles.map { $0.name }) }

    private var validationError: String? {
        if trimmedName.isEmpty { return nil }
        if existingNames.contains(trimmedName) { return "A profile named \"\(trimmedName)\" already exists." }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        if trimmedName.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use only letters, digits, dashes, or underscores."
        }
        return nil
    }

    private var canCreate: Bool { !trimmedName.isEmpty && validationError == nil }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Profile")
                .font(.title2.bold())
                .padding(.top, 16)
                .padding(.bottom, 4)

            Form {
                Section("Name") {
                    TextField("Profile name", text: $name, prompt: Text("my-profile"))
                    if let err = validationError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Resources") {
                    Stepper(value: $options.cpu, in: 1...16) {
                        LabeledContent("CPU", value: "\(options.cpu) cores")
                    }
                    Stepper(value: $options.memoryGB, in: 1...64) {
                        LabeledContent("Memory", value: "\(options.memoryGB) GB")
                    }
                    Stepper(value: $options.diskGB, in: 20...500, step: 10) {
                        LabeledContent("Disk", value: "\(options.diskGB) GB")
                    }
                    Picker("Runtime", selection: $options.runtime) {
                        ForEach(ProfileStartOptions.runtimes, id: \.self) { rt in
                            Text(rt.capitalized).tag(rt)
                        }
                    }
                }

                Section {
                    Label("The new profile will start automatically after creation.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    appState.beginCreate(name: trimmedName, options: options)
                    openWindow(id: WindowID.progress.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
            .padding(16)
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 460)
    }
}
