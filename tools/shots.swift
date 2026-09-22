import SwiftUI
import AppKit

// Renderiza las imagenes del README a partir de las vistas reales de la app.
// Se compila junto a macos/Sources/App.swift con -DSHOTS.

@MainActor
func model(sleepDisabled: Bool, onAC: Bool, battery: Int?, login: Bool = true) -> Model {
    let m = Model()
    m.frozen = true
    m.state = PowerState(sleepDisabled: sleepDisabled, onAC: onAC, batteryPercent: battery)
    m.launchAtLogin = login
    return m
}

/// Ventana flotante con la sombra y el radio del popover del sistema.
struct Floating<Content: View>: View {
    var dark: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(dark ? Color(white: 0.13) : Color(white: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09),
                                  lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(dark ? 0.55 : 0.20), radius: 22, y: 9)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct Lienzo<Content: View>: View {
    var dark: Bool
    var pad: CGFloat = 34
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(pad)
            .background(dark ? Color(white: 0.09) : Color(white: 0.945))
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// Franja derecha de la barra de menus con el icono de Tapadera.
struct BarraMenus: View {
    var activo: Bool
    var dark: Bool

    var body: some View {
        HStack(spacing: 17) {
            Image(systemName: activo ? "cup.and.saucer.fill" : "moon.zzz")
                .font(.system(size: 14))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(activo ? Color.primary.opacity(0.10) : .clear)
                )
            Image(systemName: "wifi").font(.system(size: 14))
            Image(systemName: "battery.75").font(.system(size: 14))
            Image(systemName: "magnifyingglass").font(.system(size: 13))
            Image(systemName: "switch.2").font(.system(size: 13))
            Text("mar 22 sep  18:42").font(.system(size: 12.5))
        }
        .foregroundStyle(dark ? Color.white.opacity(0.92) : Color.black.opacity(0.85))
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(dark ? Color(white: 0.17) : Color(white: 0.99))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

@MainActor
func write<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) {
    let r = ImageRenderer(content: view)
    r.scale = scale
    guard let img = r.nsImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("fallo al renderizar \(name)\n".utf8))
        return
    }
    let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
    let url = URL(fileURLWithPath: "\(dir)/\(name).png")
    try? png.write(to: url)
    print("· \(name).png  \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

@main
struct Shots {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            // Los dos estados, uno al lado del otro.
            write(Lienzo(dark: false, pad: 38) {
                HStack(alignment: .top, spacing: 26) {
                    Floating(dark: false) {
                        Panel(model: model(sleepDisabled: true, onAC: true, battery: 82))
                    }
                    Floating(dark: false) {
                        Panel(model: model(sleepDisabled: false, onAC: true, battery: 82))
                    }
                }
            }, "hero")

            // Modo oscuro, con el aviso de bateria.
            write(Lienzo(dark: true, pad: 34) {
                Floating(dark: true) {
                    Panel(model: model(sleepDisabled: true, onAC: false, battery: 41))
                }
            }, "aviso-bateria")

            // Modo claro, estado en reposo.
            write(Lienzo(dark: false, pad: 34) {
                Floating(dark: false) {
                    Panel(model: model(sleepDisabled: false, onAC: false, battery: 41))
                }
            }, "reposo")

            // La barra de menus.
            write(Lienzo(dark: false, pad: 24) {
                VStack(spacing: 14) {
                    BarraMenus(activo: true, dark: false)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    BarraMenus(activo: false, dark: false)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }, "barra-menus")
        }
        exit(0)
    }
}
