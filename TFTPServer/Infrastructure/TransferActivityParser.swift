// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

enum TransferEvent {
    case filenameDetected(pid: Int32, filename: String)
}

/// Interpreta las líneas de debug del `tftpd` real (activado con `-l -d`,
/// visibles solo con `log stream --level debug`, ver LogStreamMonitor) en
/// eventos estructurados.
///
/// El formato real de esta línea **depende de la versión de macOS** (bug real
/// encontrado en vivo, 2026-09-08, probando en macOS 13.7.8 Ventura después
/// de que el formato de abajo se investigara originalmente en macOS Tahoe
/// 26.6.2): el `tftpd` de Ventura es un build mucho más antiguo (basado en
/// `FreeBSD src/libexec/tftpd/tftpd.c,v 1.38 2007`, confirmado con `strings`
/// sobre el binario) y jamás produce una línea `Filename: 'x'` — en vez de
/// eso, loguea `<IP>: read request for <ruta absoluta>: success` (descarga) o
/// `<IP>: write request for <ruta absoluta>: success` (subida). Con el
/// regex viejo (solo `Filename: 'x'`), la app nunca detectaba ninguna
/// transferencia en Ventura — sin barra de progreso, sin importar cuánto
/// durara la transferencia. Este parser prueba ambos formatos, así que sigue
/// funcionando en la versión de macOS donde se descubrió el primero.
///
/// Investigado en vivo en macOS Tahoe 26.6.2 (2026-09-04): tanto RRQ como WRQ
/// producen exactamente la misma línea `Filename: 'x'` seguida de
/// `Mode: 'octet'` — no hay ninguna línea que distinga lectura de escritura,
/// ni progreso por bloque (`"%s block %d..."`, `"Received %d bytes..."` del
/// binario nunca aparecieron en el log real pese al debug level; deben usar
/// una ruta de impresión que no pasa por syslog cuando corre sin tty). El
/// formato de Ventura sí distingue lectura/escritura en la propia línea, pero
/// por consistencia con Tahoe (donde no se puede saber aquí) `AppState` sigue
/// infiriendo la dirección observando si el archivo crece en disco en vez de
/// depender de esto.
///
/// El log en formato `--style compact` sí incluye el PID del proceso en
/// ambos formatos (`tftpd[PID:TID] ...`) — verificado en vivo con dos
/// transferencias simultáneas (2026-09-07). Se usa ese PID, no `pgrep`, para
/// distinguir transferencias concurrentes correctamente: `pgrep -f` no puede
/// diferenciar cuál de varios procesos `tftpd` corresponde a cuál archivo.
enum TransferActivityParser {
    nonisolated(unsafe) private static let tahoeFilenamePattern = /tftpd\[(\d+):[^\]]*\].*Filename: '(.+)'/
    nonisolated(unsafe) private static let venturaRequestPattern = /tftpd\[(\d+):[^\]]*\].*(?:read|write) request for (.+): success/

    /// Bug real encontrado en vivo (2026-09-08): el motor nativo de `Regex`
    /// de Swift no es barato — con `tftpd -d` generando mucho volumen de
    /// líneas por sesión (ver `LogStreamMonitor`), correr AMBOS regex sobre
    /// CADA línea (la inmensa mayoría de las cuales no es ninguna de las dos
    /// cosas, p. ej. "Retrieve User by Name") se volvió, junto con el costo
    /// de `@Published logEntries`, uno de los puntos que saturaba el hilo
    /// principal (confirmado con `sample`: la pila se quedaba minutos en
    /// `Regex.firstMatch`). Un chequeo de substring — barato, sin motor de
    /// regex — descarta la inmensa mayoría de líneas antes de intentar
    /// siquiera compilar/ejecutar el patrón correspondiente.
    static func parse(line: String) -> TransferEvent? {
        if line.contains("Filename: '"), let match = line.firstMatch(of: tahoeFilenamePattern), let pid = Int32(match.1) {
            return .filenameDetected(pid: pid, filename: String(match.2))
        }
        if line.contains("request for"), let match = line.firstMatch(of: venturaRequestPattern), let pid = Int32(match.1) {
            // El formato de Ventura loguea la ruta absoluta ya resuelta
            // (post directory-search), no el nombre relativo que pidió el
            // cliente — se usa solo el último componente para que
            // `AppState` la trate igual que el nombre relativo de Tahoe.
            let absolutePath = String(match.2)
            let filename = (absolutePath as NSString).lastPathComponent
            return .filenameDetected(pid: pid, filename: filename)
        }
        return nil
    }
}
