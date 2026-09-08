// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

struct FileSystemService: Sendable {
    func listEntries(in directory: URL) -> [FileEntry] {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
            let size = (values?.isDirectory == true) ? nil : values?.fileSize.map(Int64.init)
            return FileEntry(
                id: url.path,
                name: url.lastPathComponent,
                modificationDate: values?.contentModificationDate,
                sizeInBytes: size
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func fileSize(at url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
    }

    /// Verifica permisos de la carpeta raíz y de su carpeta padre por separado,
    /// como en la referencia histórica (PROJECT.md, sección 61).
    func hasAppropriatePermissions(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isReadableFile(atPath: directory.path)
    }

    /// Agrega lectura+ejecución para el dueño (necesarias para listar y
    /// atravesar el directorio) sin tocar el resto de los bits existentes —
    /// deliberadamente no fuerza `0o755`, que sobrescribiría permisos de
    /// grupo/otros que el usuario pudo haber configurado a propósito. Falla
    /// (y no hace nada) si el directorio no existe o pertenece a otro
    /// usuario — esta app corre como el usuario actual, sin privilegios para
    /// tocar archivos ajenos, y no debe pedir autorización solo para esto.
    func repairPermissions(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let attributes = try? fileManager.attributesOfItem(atPath: directory.path)
        let currentMode = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let repairedMode = currentMode | 0o500
        do {
            try fileManager.setAttributes([.posixPermissions: repairedMode], ofItemAtPath: directory.path)
        } catch {
            return false
        }
        return fileManager.isReadableFile(atPath: directory.path)
    }

    /// Agrega SOLO el bit de ejecución para "otros" (`o+x`, octal `0o001`) —
    /// nunca lectura ni escritura — sin tocar el resto de los bits
    /// existentes. Ver `PathValidator.firstAncestorBlockingOtherTraversal`
    /// para el bug real que esto arregla: `tftpd`, corriendo como `nobody`
    /// tras bajar sus propios privilegios, no puede atravesar una carpeta
    /// personal (`750` por defecto) para llegar a la carpeta TFTP elegida,
    /// sin importar los permisos de esa subcarpeta. Este bit por sí solo
    /// permite "pasar a través" de `directory` hacia una ruta ya conocida —
    /// NO permite listar su contenido (`ls`) ni leer archivos sueltos que
    /// estén directamente dentro de ella, salvo que esos archivos/carpetas
    /// tengan además sus propios permisos de lectura para "otros". Falla (y
    /// no hace nada) si la carpeta no existe o pertenece a otro usuario —
    /// esta app corre como el usuario actual, sin privilegios para tocar
    /// carpetas ajenas, y no debe pedir autorización solo para esto.
    func repairOtherTraversal(on directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let attributes = try? fileManager.attributesOfItem(atPath: directory.path)
        let currentMode = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let repairedMode = currentMode | 0o001
        do {
            try fileManager.setAttributes([.posixPermissions: repairedMode], ofItemAtPath: directory.path)
        } catch {
            return false
        }
        let updatedAttributes = try? fileManager.attributesOfItem(atPath: directory.path)
        let updatedMode = (updatedAttributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return updatedMode & 0o001 != 0
    }
}
