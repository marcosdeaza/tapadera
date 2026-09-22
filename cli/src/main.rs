//! Tapadera - mantiene el ordenador trabajando con la tapa cerrada.
//!
//! Un solo concepto, tres sistemas:
//!   macOS    pmset disablesleep
//!   Windows  powercfg, accion al cerrar la tapa
//!   Linux    systemd-logind, HandleLidSwitch
//!
//! Sin dependencias: solo la biblioteca estandar.

use std::process::{Command, ExitCode};

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() -> ExitCode {
    let arg = std::env::args().nth(1).unwrap_or_else(|| "status".into());

    match arg.as_str() {
        "on" => apply(true),
        "off" => apply(false),
        "toggle" => match backend::is_on() {
            Ok(cur) => apply(!cur),
            Err(e) => fail(&e),
        },
        "status" => match backend::is_on() {
            Ok(true) => {
                println!("activo    el equipo sigue despierto con la tapa cerrada");
                ExitCode::SUCCESS
            }
            Ok(false) => {
                println!("inactivo  el equipo se duerme al cerrar la tapa");
                ExitCode::from(1)
            }
            Err(e) => fail(&e),
        },
        "-v" | "--version" | "version" => {
            println!("tapadera {VERSION} ({})", backend::NAME);
            ExitCode::SUCCESS
        }
        "-h" | "--help" | "help" => {
            help();
            ExitCode::SUCCESS
        }
        other => {
            eprintln!("orden desconocida: {other}\n");
            help();
            ExitCode::from(2)
        }
    }
}

fn apply(on: bool) -> ExitCode {
    match backend::set(on) {
        Ok(()) => {
            println!(
                "{}",
                if on {
                    "activo    ya puedes cerrar la tapa"
                } else {
                    "inactivo  el equipo vuelve a dormirse al cerrar la tapa"
                }
            );
            if on {
                if let Some(aviso) = battery_warning() {
                    eprintln!("{aviso}");
                }
            }
            ExitCode::SUCCESS
        }
        Err(e) => fail(&e),
    }
}

fn fail(msg: &str) -> ExitCode {
    eprintln!("error: {msg}");
    ExitCode::from(1)
}

fn help() {
    println!(
        "tapadera {VERSION}\n\
         Mantiene el ordenador trabajando con la tapa cerrada.\n\n\
         USO\n  \
           tapadera <orden>\n\n\
         ORDENES\n  \
           on        no dormir al cerrar la tapa\n  \
           off       volver al comportamiento normal\n  \
           toggle    alternar entre los dos\n  \
           status    mostrar el estado (codigo 0 activo, 1 inactivo)\n  \
           version   version y sistema detectado\n\n\
         NOTAS\n  \
           Cambiar el estado toca la configuracion de energia del sistema\n  \
           y necesita privilegios de administrador.\n  \
           En macOS hay ademas una app de barra de menus: Tapadera.app"
    );
}

/// Aviso si se activa yendo con bateria. Nunca bloquea la operacion.
fn battery_warning() -> Option<String> {
    let pct = backend::battery_percent()?;
    Some(format!(
        "aviso: vas con bateria ({pct}%). Enchufalo antes de cerrar la tapa."
    ))
}

fn output(cmd: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(cmd)
        .args(args)
        .output()
        .map_err(|e| format!("no se pudo ejecutar {cmd}: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(if err.is_empty() {
            format!("{cmd} fallo con codigo {:?}", out.status.code())
        } else {
            err
        });
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

// ---------------------------------------------------------------- macOS

#[cfg(target_os = "macos")]
mod backend {
    use super::output;

    pub const NAME: &str = "macos/pmset";

    pub fn is_on() -> Result<bool, String> {
        Ok(output("/usr/bin/pmset", &["-g"])?
            .lines()
            .find(|l| l.contains("SleepDisabled"))
            .map(|l| l.contains('1'))
            .unwrap_or(false))
    }

    pub fn set(on: bool) -> Result<(), String> {
        output(
            "/usr/bin/pmset",
            &["-a", "disablesleep", if on { "1" } else { "0" }],
        )
        .map(|_| ())
        .map_err(|e| {
            if e.contains("not permitted") || e.contains("denied") {
                "hace falta sudo: sudo tapadera on".into()
            } else {
                e
            }
        })
    }

    pub fn battery_percent() -> Option<u8> {
        let ps = output("/usr/bin/pmset", &["-g", "ps"]).ok()?;
        if ps.contains("AC Power") {
            return None;
        }
        let i = ps.find('%')?;
        ps[..i]
            .rsplit(|c: char| !c.is_ascii_digit())
            .next()?
            .parse()
            .ok()
    }
}

// -------------------------------------------------------------- Windows

#[cfg(target_os = "windows")]
mod backend {
    use super::output;

    pub const NAME: &str = "windows/powercfg";

    // Subgrupo "Botones de inicio/apagado y tapa" y ajuste "Accion al cerrar la tapa".
    const SUB_BUTTONS: &str = "4f971e89-eebd-4455-a8de-9e59040e7347";
    const LID_ACTION: &str = "5ca83367-6e45-459f-a27b-476b1d01c936";

    pub fn is_on() -> Result<bool, String> {
        let q = output(
            "powercfg",
            &["/query", "SCHEME_CURRENT", SUB_BUTTONS, LID_ACTION],
        )?;
        // 0x00000000 = no hacer nada. Miramos el valor de corriente alterna.
        let ac = q
            .lines()
            .find(|l| l.contains("Current AC Power Setting Index"))
            .or_else(|| q.lines().find(|l| l.contains("de corriente alterna")))
            .ok_or("no se pudo leer la configuracion de la tapa")?;
        Ok(ac.trim().ends_with('0'))
    }

    pub fn set(on: bool) -> Result<(), String> {
        let v = if on { "0" } else { "1" }; // 0 = nada, 1 = suspender
        output(
            "powercfg",
            &["/setacvalueindex", "SCHEME_CURRENT", SUB_BUTTONS, LID_ACTION, v],
        )?;
        output(
            "powercfg",
            &["/setdcvalueindex", "SCHEME_CURRENT", SUB_BUTTONS, LID_ACTION, v],
        )?;
        output("powercfg", &["/setactive", "SCHEME_CURRENT"])?;
        Ok(())
    }

    pub fn battery_percent() -> Option<u8> {
        let out = output(
            "wmic",
            &["path", "Win32_Battery", "get", "EstimatedChargeRemaining"],
        )
        .ok()?;
        out.lines()
            .filter_map(|l| l.trim().parse::<u8>().ok())
            .next()
    }
}

// ---------------------------------------------------------------- Linux

#[cfg(target_os = "linux")]
mod backend {
    use super::output;
    use std::fs;
    use std::path::Path;

    pub const NAME: &str = "linux/systemd-logind";

    const DROPIN: &str = "/etc/systemd/logind.conf.d/99-tapadera.conf";

    const CONTENT: &str = "# Escrito por tapadera.\n\
        [Login]\n\
        HandleLidSwitch=ignore\n\
        HandleLidSwitchDocked=ignore\n\
        HandleLidSwitchExternalPower=ignore\n";

    pub fn is_on() -> Result<bool, String> {
        Ok(Path::new(DROPIN).exists())
    }

    pub fn set(on: bool) -> Result<(), String> {
        let dir = Path::new(DROPIN).parent().unwrap();
        if on {
            fs::create_dir_all(dir).map_err(permiso)?;
            fs::write(DROPIN, CONTENT).map_err(permiso)?;
        } else if Path::new(DROPIN).exists() {
            fs::remove_file(DROPIN).map_err(permiso)?;
        }
        // Recargar logind para que el cambio surta efecto ya.
        let _ = output("systemctl", &["kill", "-s", "HUP", "systemd-logind"]);
        Ok(())
    }

    fn permiso(e: std::io::Error) -> String {
        if e.kind() == std::io::ErrorKind::PermissionDenied {
            "hace falta sudo: sudo tapadera on".into()
        } else {
            e.to_string()
        }
    }

    pub fn battery_percent() -> Option<u8> {
        let base = Path::new("/sys/class/power_supply");
        for entry in fs::read_dir(base).ok()? {
            let p = entry.ok()?.path();
            if fs::read_to_string(p.join("type")).ok()?.trim() != "Battery" {
                continue;
            }
            // Si esta enchufado no avisamos.
            if let Ok(s) = fs::read_to_string(p.join("status")) {
                if s.trim() == "Charging" || s.trim() == "Full" {
                    return None;
                }
            }
            return fs::read_to_string(p.join("capacity")).ok()?.trim().parse().ok();
        }
        None
    }
}
