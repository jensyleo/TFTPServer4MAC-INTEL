// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Valida rutas usadas como TFTP root. Rechaza traversal, rutas del sistema y
/// destinos que no sean directorios reales (PROJECT.md, sección 34).
enum PathValidator {
    private static let disallowedPrefixes = [
        "/etc",
        "/private/etc",
        "/System",
        "/bin",
        "/sbin",
        "/usr/bin",
        "/usr/sbin",
        "/usr/libexec"
    ]

    static func isValidRoot(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let standardizedPath = url.standardizedFileURL.path

        guard !standardizedPath.contains("..") else {
            return false
        }

        // Vulnerabilidad real corregida (2026-09-07, auditoría de seguridad):
        // `NativeTFTPService` interpola esta ruta sin escapar dentro del XML
        // del plist y dentro de un heredoc de shell ejecutado con privilegios
        // de administrador. Una carpeta cuyo nombre contuviera un salto de
        // línea seguido del delimitador exacto del heredoc podría inyectar
        // comandos arbitrarios como root; caracteres de control en general
        // no tienen ninguna razón legítima de aparecer en una ruta de
        // carpeta. Se rechazan aquí, en el único punto de validación común a
        // todo el flujo, en vez de depender solo del escapado en el
        // consumidor.
        guard !standardizedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }

        guard disallowedPrefixes.allSatisfy({ !standardizedPath.hasPrefix($0) }) else {
            return false
        }

        // Bug real encontrado en vivo (2026-09-08): la raíz del servidor
        // terminó siendo literalmente "/" — la lista de prefijos prohibidos
        // de arriba no cubre la raíz del sistema completo ni sus carpetas de
        // primer nivel (`/Users`, `/Applications`, `/Volumes`...), así que
        // nada la rechazaba. Con eso como root, cualquier archivo del disco
        // marcado "legible por todos" queda potencialmente servible por
        // TFTP — exactamente lo que una carpeta raíz acotada debía evitar.
        // Se exige al menos 2 componentes de ruta reales (p. ej.
        // `/Users/nombre`), no solo "no es una ruta prohibida específica".
        let pathComponents = standardizedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.count >= 2 else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        // Deliberadamente NO se revisa `isReadableFile` aquí (bug real
        // encontrado en vivo, 2026-09-08): esta función valida si una ruta
        // es *estructuralmente* segura como root (no es traversal, no es
        // una ruta del sistema, no es "/" ni una carpeta de primer nivel),
        // no si sus permisos están bien ahora mismo. Antes rechazaba
        // cualquier carpeta sin permiso de lectura con el error genérico
        // "carpeta inválida" — eso le ganaba de mano a `PermissionsNeededView`
        // (el popup con el botón "Fix"), que nunca llegaba a mostrarse
        // porque `changeRootDirectory` ya había fallado en este `guard`. Los
        // problemas de lectura son arreglables (botón "Fix"); los
        // estructurales de arriba no lo son — por eso viven en funciones
        // separadas: `isValidRoot` (aquí) decide si la ruta puede aceptarse
        // como configuración; `AppState.refreshPermissions`/`start()` deciden
        // si el servidor puede arrancar de verdad con lo que hay ahí.
        return true
    }

    /// Devuelve el primer ancestro de `url` (empezando por "/" y bajando)
    /// que le falta el bit de ejecución para "otros" — o `nil` si toda la
    /// cadena hasta `url` inclusive lo tiene.
    ///
    /// Bug real encontrado en vivo (2026-09-08), diagnóstico corregido tras
    /// una hipótesis inicial equivocada (TCC — descartada con evidencia:
    /// `log stream` sobre `tccd` durante el intento no mostró ninguna
    /// actividad). La causa real, confirmada con `log stream --level debug`
    /// sobre `tftpd`, es mucho más simple: el propio `tftpd` (corriendo como
    /// root gracias al fix de `NativeTFTPService.plistContents`) baja sus
    /// privilegios internamente a `nobody` por cada petición — visible en el
    /// log como `running as user 'nobody' (-2)` — y para macOS, `nobody` es
    /// simplemente "otro usuario" frente a cualquier carpeta que no le
    /// pertenezca. La carpeta personal de un usuario (`/Users/<usuario>`) es
    /// `750` por defecto en macOS (sin ningún permiso para "otros"), así que
    /// `nobody` no puede ni atravesarla — sin importar los permisos de la
    /// subcarpeta TFTP en sí, que nunca llega a alcanzarse. Confirmado
    /// comparando la cadena completa de permisos: `/`, `/Users`,
    /// `/private`, `/private/tmp` y `/Users/Shared` tienen el bit de
    /// ejecución para "otros" (`755`/`1777`); solo `/Users/<usuario>` (`750`)
    /// no lo tiene — coincide exactamente con qué carpetas funcionan y
    /// cuáles no.
    ///
    /// A diferencia del diagnóstico de TCC (que no tenía arreglo posible
    /// desde la app), este sí es corregible: agregar el bit de ejecución
    /// para "otros" en la carpeta bloqueante NO concede lectura ni listado
    /// — solo permite "pasar a través" de ella para llegar a una ruta ya
    /// conocida, exactamente lo mínimo que `tftpd` necesita.
    static func firstAncestorBlockingOtherTraversal(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var chain: [URL] = []
        var current = url.standardizedFileURL
        while current.path != "/" {
            chain.append(current)
            current = current.deletingLastPathComponent()
        }
        chain.append(current) // "/" en sí también debe tener el bit.

        for ancestor in chain.reversed() {
            guard let attributes = try? fileManager.attributesOfItem(atPath: ancestor.path),
                  let posixPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
                continue
            }
            let otherExecuteBit = 0o001
            if posixPermissions & otherExecuteBit == 0 {
                return ancestor
            }
        }
        return nil
    }
}
