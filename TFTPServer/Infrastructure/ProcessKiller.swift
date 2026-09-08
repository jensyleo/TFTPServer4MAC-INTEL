// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Darwin
import Foundation

/// Bug real encontrado en vivo (2026-09-08): `AppState.trackTransfer` usaba
/// "`NetworkByteMonitor.byteCounts(forPID:)` no devolvió nada" como única
/// señal de que un `tftpd` había terminado. Con `tftpd` corriendo como root
/// (ver `NativeTFTPService.plistContents`), `nettop -p <pid>` puede seguir
/// devolviendo *algo* que pasa el parseo incluso mucho después de que ese
/// PID específico ya no existe (datos obsoletos de una conexión ya cerrada,
/// o un PID recién reciclado por otro proceso completamente distinto) —
/// confirmado en vivo tras una sesión de pruebas con decenas de
/// transferencias rápidas seguidas: dos transferencias quedaron "Detecting"
/// con el contador de tiempo subiendo sin parar (más de 3 minutos) pese a
/// que `ps aux | grep tftpd` no mostraba ningún proceso `tftpd` vivo. Cada
/// una de esas tareas de sondeo huérfanas, al no terminar nunca, seguía
/// lanzando un proceso `nettop` nuevo cada 150ms indefinidamente — con
/// varias acumuladas de toda la sesión, explica el 100% de CPU sostenido y
/// la ventana de la app dejando de responder (el hilo principal, saturado
/// procesando además el aluvión de líneas de log de esas tareas nunca
/// terminadas).
///
/// `kill(pid, 0)` no envía ninguna señal real — solo pregunta al kernel si
/// ese PID existe. Es la fuente de verdad correcta para "¿este proceso
/// sigue vivo?", independiente de si `nettop` logra o no leer sus
/// estadísticas de red.
enum ProcessLiveness {
    static func isAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        // EPERM: el proceso existe pero no tenemos permiso para señalizarlo
        // (esperable ahora que `tftpd` corre como root/`nobody`) — sigue
        // vivo. ESRCH (o cualquier otro errno): ya no existe.
        return errno == EPERM
    }
}

/// El `tftpd` que atiende cada transferencia corre como root (ver
/// NativeTFTPService.plistContents, 2026-09-08: `tftpd` necesita ser root de
/// verdad para poder bajar sus propios privilegios internamente a `nobody`;
/// un intento anterior de correrlo como el usuario de la GUI para evitar
/// pedir autorización aquí rompía las transferencias por completo). Como
/// consecuencia, matarlo sí requiere autorización de administrador — Cancelar
/// vuelve a pedir Touch ID/contraseña, igual que Start/Stop.
///
/// Mata un PID específico, no todos los `tftpd` (2026-09-07): con
/// transferencias simultáneas reales, cancelar una no debe tocar las demás.
enum ProcessKiller {
    static func kill(pid: Int32, privilegedShellRunner: PrivilegedShellRunning = PrivilegedShellRunner()) async {
        try? privilegedShellRunner.runElevated("kill \(pid)")
    }
}
