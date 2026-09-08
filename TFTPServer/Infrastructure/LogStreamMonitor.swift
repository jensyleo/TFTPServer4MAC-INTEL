// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Transmite en vivo el log unificado de macOS para el proceso `tftpd`.
///
/// `--level debug` es obligatorio: por defecto `log stream`/`log show`
/// ocultan los mensajes de nivel debug/info, que es exactamente el nivel que
/// usa `tftpd -d` (confirmado en vivo — sin este flag, el stream nunca
/// mostraba nada aunque el daemon sí estaba logueando). Ver
/// TransferActivityParser para por qué el formato exacto de esas líneas
/// varía según la versión de macOS.
@MainActor
final class LogStreamMonitor {
    private var process: Process?
    private var pipe: Pipe?

    /// Bug real encontrado en vivo (2026-09-08): esto entregaba las líneas
    /// una por una (`lines.forEach(onLine)`), y cada línea terminaba
    /// mutando por separado el arreglo `@Published` de `AppState.logEntries`
    /// (un `append` + a veces un `removeFirst`). Con `-d` (debug) ya
    /// arreglado (ver `NativeTFTPService.plistContents`) — antes `-d15`
    /// estaba roto y casi no producía nada — `tftpd` genera muchísimas más
    /// líneas por petición de las que producía antes. Durante una sesión
    /// larga de pruebas, el `readabilityHandler` puede entregar cientos o
    /// miles de líneas acumuladas en una sola lectura del pipe; mutar el
    /// arreglo una vez POR LÍNEA en ese caso (en vez de una sola vez para
    /// todo el lote) fue lo que saturó el hilo principal — confirmado con
    /// `sample`: la CPU se quedaba al 30%+ sostenido mucho después de que
    /// las transferencias de la prueba habían terminado, con la pila
    /// apuntando exactamente a `AppState.log(_:_:)` decenas de miles de
    /// veces. Entregar el lote completo de una vez permite a quien consume
    /// esto (`AppState`) hacer UNA sola mutación del arreglo por lote en vez
    /// de una por línea.
    func start(onLines: @escaping @MainActor @Sendable ([String]) -> Void) {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--level", "debug",
            "--style", "compact",
            "--predicate", "process == \"tftpd\""
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n").map(String.init)
            guard !lines.isEmpty else { return }
            Task { @MainActor in
                onLines(lines)
            }
        }

        do {
            try process.run()
            self.process = process
            self.pipe = pipe
        } catch {
            onLines(["Could not start log streaming: \(error.localizedDescription)"])
        }
    }

    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        pipe = nil
    }
}
