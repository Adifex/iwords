//
//  Dictionary.swift
//  iWords (macOS)
//
//  Created by Dan Weiner on 1/9/22.
//

import Foundation

struct DWError: LocalizedError, Identifiable, CustomNSError {
    let id = UUID()

    let description: String

    var errorDescription: String? {
        description
    }

    let _recoverySuggestion: String?

    var recoverySuggestion: String {
        _recoverySuggestion ?? ""
    }

    static var errorDomain: String {
        "org.iwords.iwords.errorDomain"
    }

    var errorCode: Int {
        return 1
    }

    var errorUserInfo: [String : Any] {
        [NSLocalizedRecoverySuggestionErrorKey: recoverySuggestion as Any]
    }

    init(_ description: String, recoverySuggestion: String? = nil) {
        self.description = description
        self._recoverySuggestion = recoverySuggestion
    }
}

protocol DictionaryDelegate: AnyObject {
    /// - note: 0 <= progress <= 1
    func dictionary(_ dictionary: Dictionary, progressChangedTo progress: Double)
}

class Dictionary {

    // MARK: - Types

    @objc
    enum Direction: Int, CustomStringConvertible, CustomDebugStringConvertible, Codable, CaseIterable {
        // Do not change. Reflected in tags in interface builder.
        case latinToEnglish = 0
        case englishToLatin = 1

        var debugDescription: String {
            switch self {
            case .latinToEnglish: return "Ltn->Eng"
            case .englishToLatin: return "Eng->Ltn"
            }
        }

        var description: String {
            switch self {
            case .latinToEnglish: return "Latin → English"
            case .englishToLatin: return "English → Latin"
            }
        }

        mutating func toggle() {
            switch self {
            case .latinToEnglish: self = .englishToLatin
            case .englishToLatin: self = .latinToEnglish
            }
        }
    }

    struct Options: OptionSet {
        let rawValue: Int
        static let diagnosticMode = Options(rawValue: 1 << 0)
    }

    weak var delegate: DictionaryDelegate?

    // MARK: - Private vars

    private lazy var executableURL: URL = {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "words") else {
            fatalError("Could not find words program file in bundle.")
        }
        return url
    }()
    private lazy var executablePath = executableURL.path
    private lazy var bundleWorkingDir = Bundle.main.url(forResource: "DICTFILE", withExtension: "GEN")!
        .deletingLastPathComponent()
    private var workingDir: URL {
        DictionaryRelocator.dictionarySupportURL ?? bundleWorkingDir
    }

    private var activeCompletionHandler: ((Result<String?, DWError>) -> Void)?
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?

    private var timer: Timer?

    // MARK: - Init

    init() {
        startProcess()
    }

    deinit {
        timer?.invalidate()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }

    static func sanitize(input: String) -> String? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(["#", "!", "@", "~"]))
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Methods

    func getDefinitions(_ inputs: [String],
                        direction: Direction,
                        options: Options,
                        completion: @escaping (Result<[(String, String?)], DWError>) -> Void) {
        guard !inputs.isEmpty else {
            completion(.success([]))
            return
        }

        var results: [(String, String?)] = []
        let totalCount = Double(inputs.count)
        var completedCount: Double = 0

        func processInput(at i: Int) {
            getDefinition(inputs[i], direction: direction, options: options) { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let result):
                    results.append((inputs[i], result))
                    completedCount += 1
                    let progress = completedCount / totalCount
                    DispatchQueue.main.async {
                        self.delegate?.dictionary(self, progressChangedTo: progress)
                    }
                    if inputs.indices.contains(i + 1) {
                        processInput(at: i + 1)
                    } else {
                        completion(.success(results))
                    }
                }
            }
        }
        processInput(at: 0)
    }

    func getDefinition(_ input: String,
                       direction: Direction,
                       options: Options,
                       completion: @escaping (Result<String?, DWError>) -> Void) {
        guard let input = Self.sanitize(input: input) else {
            completion(.success(nil))
            return
        }
        guard activeCompletionHandler == nil else {
            completion(.failure(DWError("Lookup already in progress")))
            return
        }

        guard !input.contains(where: \.isNewline) else {
            completion(.failure(DWError("Please look up one word at a time.")))
            return
        }
        if process?.isRunning != true { startProcess() }
        guard let process, process.isRunning, let inputPipe else {
            completion(.failure(DWError("Could not start the dictionary engine.")))
            return
        }
        self.activeCompletionHandler = completion
        let command = direction == .latinToEnglish ? "~L" : "~E"
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data("\(command)\n\(input)\n".utf8))
        } catch {
            complete(with: .failure(DWError("Could not send the lookup: \(error.localizedDescription)")))
            return
        }

        timer = .scheduledTimer(withTimeInterval: 5, repeats: false, block: { [weak self] timer in
            guard let self = self else {
                return
            }
            guard self.activeCompletionHandler != nil else {
                return
            }

            self.complete(with: .failure(DWError("The operation timed out. Please try again.")))
            self.restartProcess()
        })
    }

    // MARK: - Private methods

    private var tempData = Data()
    private func handleNewData(_ newData: Data) {
        precondition(Thread.isMainThread)
        tempData += newData
        guard tempData.count <= 4 * 1024 * 1024 else {
            complete(with: .failure(DWError("Dictionary output exceeded its size limit.")))
            restartProcess()
            return
        }

        // Always prefix of an English-to-Latin result
        let englishToLatinPrefix = "Language changed to ENGLISH_TO_LATIN\nInput a single English word (+ part of speech - N, ADJ, V, PREP, . .. )\n\n=>"
        // Always prefix of a Latin-to-English result
        let latinToEnglishPrefix = "Language changed to LATIN_TO_ENGLISH\n\n=>"

        // A pipe read may end in the middle of a UTF-8 character.
        guard let tempDataString = String(data: tempData, encoding: .utf8) else { return }

        if case let cmp = tempDataString.components(separatedBy: englishToLatinPrefix),
           cmp.count > 1,
           let lastCmp = cmp.last,
           lastCmp.hasSuffix("\n=>") {
            tempData.removeAll()
            handleDefinitionResult(lastCmp)
        } else if case let cmp = tempDataString.components(separatedBy: latinToEnglishPrefix),
                  cmp.count > 1,
                  let lastCmp = cmp.last,
                  lastCmp.hasSuffix("\n=>") {
            tempData.removeAll()
            handleDefinitionResult(lastCmp)
        }
    }

    private func handleDefinitionResult(_ str: String) {
        assert(Thread.current.isMainThread)

        var str = str
        str = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.suffix(2) == "=>" {
            str = String(str.dropLast(2))
        }
        str = str.trimmingCharacters(in: .whitespacesAndNewlines)

        complete(with: .success(str))
    }

    /// - Precondition: is main thread
    private func complete(with result: Result<String?, DWError>) {
        precondition(Thread.isMainThread)

        timer?.invalidate()
        timer = nil

        let handler = activeCompletionHandler
        activeCompletionHandler = nil

        if needsRestart {
            needsRestart = false
            restartProcess()
        }

        handler?(result)
    }

    private var needsRestart = false

    func setNeedsRestart() {
        if activeCompletionHandler != nil {
            needsRestart = true
        } else {
            restartProcess()
        }
    }

    private func restartProcess() {
        complete(with: .failure(DWError("Process restarted")))

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        tempData.removeAll()
        startProcess()
    }

    private func startProcess() {
        guard process?.isRunning != true else { return }
        tempData.removeAll()

        let p = Process()
        p.currentDirectoryURL = workingDir
        p.executableURL = executableURL
        p.arguments = []
        outputPipe = Pipe()
        errorPipe = Pipe()
        inputPipe = Pipe()
        p.standardOutput = outputPipe
        p.standardError = errorPipe
        p.standardInput = inputPipe

        let outputFileHandle = outputPipe!.fileHandleForReading

        outputFileHandle.readabilityHandler = { [weak self, weak p] fh in
            let data = fh.availableData
            if data.isEmpty { fh.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, let p, self.process === p else { return }
                self.handleNewData(data)
            }
        }
        // Drain stderr so a diagnostic cannot fill the pipe and stall WORDS.
        errorPipe?.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { fh.readabilityHandler = nil }
        }

        process = p

        p.terminationHandler = { [weak self] endedProcess in
            DispatchQueue.main.async {
                guard let self, self.process === endedProcess else { return }
                self.process = nil
                self.complete(with: .failure(DWError("Dictionary engine exited (\(endedProcess.terminationStatus)).")))
            }
        }

        do {
            try p.run()
        } catch {
            process = nil
            NSLog("Dictionary engine launch failed: %@", error.localizedDescription)
        }
    }
}
