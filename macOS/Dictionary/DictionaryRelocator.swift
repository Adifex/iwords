//
//  DictionaryRelocator.swift
//  iWords (macOS)
//
//  Created by Dan Weiner on 2/6/22.
//

import Foundation

extension NSNotification.Name {
    static let dictionaryRelocationComplete = NSNotification.Name("dictionaryRelocationComplete")
}

enum DictionaryRelocator {

    // MARK: Properties

    /// Will be non-nil if migration has been performed.
    static var dictionarySupportURL: URL?

    // MARK: Private properties

    private static let _dictionarySupportURL: URL? = {
        let fileManager = FileManager.default

        let appSupportURL = try? fileManager.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true)

        return appSupportURL?
            .appendingPathComponent("iWords",
                                    isDirectory: true)
            .appendingPathComponent("Dictionary Support",
                                    isDirectory: true)
            .appendingPathComponent("Engine-1f2f0fb-arm64-v1", isDirectory: true)
    }()

    private static let fileNamesToMigrate = [
        "WORD.MDV",
        "ADDONS.LAT",
        "CHECKEWD.",
        "DICTFILE.GEN",
        "DICTLINE.GEN",
        "EWDSFILE.GEN",
        "EWDSLIST.GEN",
        "INDXFILE.GEN",
        "INFLECTS.LAT",
        "INFLECTS.SEC",
        "STEMFILE.GEN",
        "STEMLIST.GEN",
        "UNIQUES.LAT"
    ]

    // MARK: Methods

    static func relocateDictionaryToApplicationSupport() throws {
        try _relocate()
    }

    static func initialize() {
        if wasRelocationPerformed() {
            dictionarySupportURL = _dictionarySupportURL
        } else if let destination = _dictionarySupportURL,
                  FileManager.default.fileExists(atPath: destination.deletingLastPathComponent()
                    .appendingPathComponent("WORD.MDV").path) {
            // Never load generated Intel-era data into the rebuilt engine.
            do {
                try _relocate()
                try migrateLegacyPreferences(to: destination)
            } catch {
                dictionarySupportURL = nil
                NSLog("Dictionary migration failed; using bundled defaults: %@", error.localizedDescription)
            }
        }
    }

    static func uninstall() throws {
        guard let dictionarySupportURL = dictionarySupportURL else {
            throw DWError("Unable to get dictionary support path.", recoverySuggestion: nil)
        }

        let fileManager = FileManager.default

        try fileManager.removeItem(at: dictionarySupportURL)

        Self.dictionarySupportURL = nil

        NotificationCenter.default.post(name: .dictionaryRelocationComplete, object: nil)
    }

    private static func migrateLegacyPreferences(to destination: URL) throws {
        let file = destination.appendingPathComponent("WORD.MDV")
        let legacyFile = destination.deletingLastPathComponent().appendingPathComponent("WORD.MDV")
        let legacy = try String(contentsOf: legacyFile, encoding: .utf8)
        let keys: Set<String> = ["DO_MEDIEVAL_TRICKS", "DO_TWO_WORDS", "OMIT_ARCHAIC", "OMIT_MEDIEVAL", "OMIT_UNCOMMON"]
        var values: [String: String] = [:]
        for line in legacy.split(whereSeparator: \.isNewline) {
            let pair = line.split(whereSeparator: \.isWhitespace)
            if pair.count == 2, keys.contains(String(pair[0])), ["Y", "N"].contains(String(pair[1])) {
                values[String(pair[0])] = String(pair[1])
            }
        }
        let defaults = try String(contentsOf: file, encoding: .utf8)
        let merged = defaults.split(whereSeparator: \.isNewline).map { line -> String in
            guard let key = line.split(whereSeparator: \.isWhitespace).first,
                  let value = values[String(key)] else { return String(line) }
            return String(key).padding(toLength: 33, withPad: " ", startingAt: 0) + value
        }.joined(separator: "\n") + "\n"
        try merged.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: Private methods

    private static func wasRelocationPerformed() -> Bool {
        do {
            guard let dictionarySupportURL = _dictionarySupportURL else {
                throw DWError("Unable to get dictionary support path.", recoverySuggestion: nil)
            }
            return fileNamesToMigrate
                .allSatisfy {
                    let dstURL = dictionarySupportURL.appendingPathComponent($0, isDirectory: false)
                    return FileManager.default.fileExists(atPath: dstURL.path)
                }
        } catch {
            return false
        }
    }

    // Migrate dictionary to local user storage if necessary.
    private static func _relocate() throws {
        guard let dictionarySupportURL = _dictionarySupportURL else {
            throw DWError("Unable to get dictionary support path.", recoverySuggestion: nil)
        }

        let fileManager = FileManager.default

        try fileManager.createDirectory(at: dictionarySupportURL, withIntermediateDirectories: true)

        for file in fileNamesToMigrate {
            guard let srcURL = Bundle.main.url(forResource: file, withExtension: nil) else {
                throw DWError("Unable to get URL for dictionary file \(file)")
            }

            let dstURL = dictionarySupportURL.appendingPathComponent(file, isDirectory: false)



            do {
                try fileManager.copyItem(at: srcURL, to: dstURL)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                print("Not migrating \(file) because it already exists in destination")
            }
        }

        Self.dictionarySupportURL = _dictionarySupportURL

        NotificationCenter.default.post(name: .dictionaryRelocationComplete, object: nil)
    }

}
