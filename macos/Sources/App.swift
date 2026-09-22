import SwiftUI
import ServiceManagement

// MARK: - Lectura del sistema

struct PowerState: Equatable {
    var sleepDisabled = false
    var onAC = true
    var batteryPercent: Int? = nil
}

enum Power {

    static func run(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func read() -> PowerState {
        var s = PowerState()

        for line in run("/usr/bin/pmset", ["-g"]).split(separator: "\n")
        where line.contains("SleepDisabled") {
            s.sleepDisabled = line.contains("1")
        }

        let ps = run("/usr/bin/pmset", ["-g", "ps"])
        s.onAC = ps.contains("AC Power")
        if let r = ps.range(of: #"\d+%"#, options: .regularExpression) {
            s.batteryPercent = Int(ps[r].dropLast())
        }
        return s
    }

    /// Diálogo de autenticación nativo de macOS.
    @discardableResult
    static func setSleepDisabled(_ on: Bool) -> Bool {
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(on ? 1 : 0)\""
                   + " with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

// MARK: - Arranque al iniciar sesión

enum LoginItem {
    static let label = "es.marcos.tapadera"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var enabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func set(_ on: Bool) {
        let fm = FileManager.default
        let dir = plistURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if on {
            let exec = Bundle.main.executableURL?.path
                ?? "/Applications/Tapadera.app/Contents/MacOS/Tapadera"
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(label)</string>
              <key>ProgramArguments</key><array><string>\(exec)</string></array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><false/>
              <key>ProcessType</key><string>Interactive</string>
            </dict>
            </plist>
            """
            try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
            _ = Power.run("/bin/launchctl",
                          ["bootstrap", "gui/\(getuid())", plistURL.path])
        } else {
            _ = Power.run("/bin/launchctl",
                          ["bootout", "gui/\(getuid())/\(label)"])
            try? fm.removeItem(at: plistURL)
        }
    }
}

// MARK: - Modelo

@MainActor
final class Model: ObservableObject {
    @Published var state = Power.read()
    @Published var launchAtLogin = LoginItem.enabled
    @Published var working = false

    /// Congelado: usado por el renderizador de imagenes para fijar un estado.
    var frozen = false

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        guard !working, !frozen else { return }
        let fresh = Power.read()
        if fresh != state { state = fresh }
        let li = LoginItem.enabled
        if li != launchAtLogin { launchAtLogin = li }
    }

    func toggle() {
        let target = !state.sleepDisabled
        working = true
        Task.detached {
            let ok = Power.setSleepDisabled(target)
            await MainActor.run {
                self.working = false
                self.state = Power.read()
                if !ok { NSSound.beep() }
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.set(on)
        launchAtLogin = LoginItem.enabled
    }
}

// MARK: - Interruptor

/// Interruptor dibujado a mano. El de AppKit no se puede rasterizar,
/// y asi las imagenes de la documentacion salen del codigo real.
struct Interruptor: ToggleStyle {
    var alto: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        let ancho = alto * 1.72
        let on = configuration.isOn

        return Capsule()
            .fill(on ? Color.green : Color.primary.opacity(0.17))
            .frame(width: ancho, height: alto)
            .overlay(
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.22), radius: 0.8, y: 0.5)
                    .padding(alto * 0.093)
                    .offset(x: on ? (ancho - alto) / 2 : -(ancho - alto) / 2)
            )
            .animation(.snappy(duration: 0.17), value: on)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityRepresentation { Toggle(isOn: .constant(on)) { configuration.label } }
    }
}

// MARK: - Panel

struct Panel: View {
    @ObservedObject var model: Model
    @State private var hoverQuit = false

    var awake: Bool { model.state.sleepDisabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Estado + interruptor
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    Circle()
                        .fill(awake ? Color.green.opacity(0.16) : Color.secondary.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: awake ? "cup.and.saucer.fill" : "moon.zzz.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(awake ? Color.green : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(awake ? "Sigue despierto" : "Se duerme")
                        .font(.system(size: 13, weight: .semibold))
                    Text(awake ? "con la tapa cerrada" : "al cerrar la tapa")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 14)

                if model.working {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(get: { awake }, set: { _ in model.toggle() }))
                        .labelsHidden()
                        .toggleStyle(Interruptor(alto: 16))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 12)

            Divider().padding(.leading, 14)

            // Alimentación
            HStack(spacing: 7) {
                Image(systemName: model.state.onAC ? "powerplug.fill" : batteryIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(powerLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            if awake && !model.state.onAC {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(width: 14)
                    Text("Vas con batería. Enchúfalo antes de cerrar la tapa.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider().padding(.leading, 14)

            // Arranque
            HStack(spacing: 7) {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text("Abrir al iniciar sesión")
                    .font(.system(size: 11.5))
                Spacer(minLength: 10)
                Toggle("", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(Interruptor(alto: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().padding(.leading, 14)

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text("Salir").font(.system(size: 11.5))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hoverQuit ? Color.primary.opacity(0.06) : .clear)
                        .padding(.horizontal, 7)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .onHover { hoverQuit = $0 }
            .padding(.bottom, 6)
            .padding(.top, 2)
        }
        .frame(width: 258)
        .onAppear { model.refresh() }
    }

    var batteryIcon: String {
        guard let p = model.state.batteryPercent else { return "battery.50" }
        switch p {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }

    var powerLine: String {
        var parts = [model.state.onAC ? "Enchufado" : "Batería"]
        if let p = model.state.batteryPercent { parts.append("\(p)%") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - App

#if !SHOTS
@main
struct TapaderaApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            Panel(model: model)
        } label: {
            Image(systemName: model.state.sleepDisabled ? "cup.and.saucer.fill" : "moon.zzz")
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
