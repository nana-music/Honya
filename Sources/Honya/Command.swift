//
//  Command.swift
//  
//
//  Created by hiragram on 2022/08/24.
//

import Foundation
import ArgumentParser
import Yams
import Darwin

struct Honya: ParsableCommand {
    @Option var yml: String = "honya.yml"
    @Option var stringsOutputDirectory: String = "."
    @Option var swiftOutputDirectory: String = "."

    mutating func run() throws {
        do {
            try execute()
        } catch let error {
            Self.exit(withError: error)
        }
    }

    private func execute() throws {
        let decoder = YAMLDecoder()

        let filePointer = FileManager.default.fileSystemRepresentation(withPath: NSString(string: yml).expandingTildeInPath as String)
        let yamlURL = URL(fileURLWithFileSystemRepresentation: filePointer, isDirectory: false, relativeTo: nil)
        let yamlData = try Data(contentsOf: yamlURL)

        let input = try decoder.decode(Input.self, from: yamlData)

        try validate(input: input)

        try output(input: input)
    }

    private func validate(input: Input) throws {
        let projectLanguages = input.languages

        try projectLanguages.forEach { projectLanguage in
            try input.items.forEach { item in
                guard item.localizations.keys.contains(projectLanguage) else {
                    throw ValidationError.itemDoesNotContainProjectLanguage(key: item.key, missingLanguage: projectLanguage)
                }
            }
        }

        try input.items.forEach { item in
            try item.localizations.keys.forEach { localizedLanguage in
                guard projectLanguages.contains(localizedLanguage) else {
                    throw ValidationError.itemHasALanguageNotIncludedInProjectLanguage(key: item.key, unnecessaryLanguage: localizedLanguage)
                }
            }
        }

        let pattern = "\\\\\\(.*?\\)"
        let regex = try! NSRegularExpression(pattern: pattern)
        try input.items.forEach { item in
            try (item.arguments ?? []).forEach({ argument in
                guard ["String", "Int", "Double"].contains(where: { $0 == argument.type }) else {
                    throw ValidationError.argumentTypeIsNotSupported(key: item.key, argumentName: argument.name, argumentType: argument.type)
                }
            })

            try item.localizations.keys.forEach { localizedLanguage in
                let targetText = item.localizations[localizedLanguage]!
                let matches = item.argumentsInText(language: localizedLanguage)

                try matches.forEach { result in
                    try (0..<result.numberOfRanges).forEach { i in
                        let startIndex = targetText.index(targetText.startIndex, offsetBy: result.range(at: i).location)
                        let endIndex = targetText.index(startIndex, offsetBy: result.range(at: i).length)
                        let argumentName = String(targetText[startIndex..<endIndex])
                            .replacingOccurrences(of: "\\(", with: "")
                            .replacingOccurrences(of: ")", with: "")

                        guard (item.arguments ?? []).contains(where: { argument in
                            argument.name == argumentName
                        }) else {
                            throw ValidationError.undefinedArgument(key: item.key, undefinedArgumentName: argumentName)
                        }
                    }
                }
            }
        }

        // TODO: カテゴリ名に記号を含まないようにする
        // TODO: カテゴリ名はアルファベットで始まるようにする
        // TODO: キーにドット以外の記号を使えなくする
    }

    private func output(input: Input) throws {
        try outputStringsFile(input: input)
        try outputSwiftFile(input: input)
    }

    private func outputSwiftFile(input: Input) throws {
        let swiftSourcePath = URL(fileURLWithPath: swiftOutputDirectory).appendingPathComponent("Localization.swift")
        try? FileManager.default.removeItem(at: swiftSourcePath)

        let swiftSourceOutput = SwiftSourceOutput(input: input)

        try swiftSourceOutput.output.write(to: swiftSourcePath, atomically: true, encoding: .utf8)
    }

    private func outputStringsFile(input: Input) throws {
        try input.languages.forEach { language in
            let languageDirectory = URL(fileURLWithPath: stringsOutputDirectory).appendingPathComponent("\(language).lproj")
            let localizableStringsPath = languageDirectory.appendingPathComponent("Localizable.strings")

            try FileManager.default.createDirectory(at: languageDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: localizableStringsPath)
            let categoryLines = input.items.map { item -> String in
                "\"\(item.getLocalizationKey())\" = \"\(item.localizationWithFormattedArguments(language))\";"
            }.joined(separator: "\n")

            try categoryLines.write(to: localizableStringsPath, atomically: true, encoding: .utf8)
        }
    }
}

enum ValidationError: LocalizedError {
    case itemDoesNotContainProjectLanguage(key: String, missingLanguage: String)
    case itemHasALanguageNotIncludedInProjectLanguage(key: String, unnecessaryLanguage: String)
    case undefinedArgument(key: String, undefinedArgumentName: String)
    case argumentTypeIsNotSupported(key: String, argumentName: String, argumentType: String)

    var errorDescription: String? {
        switch self {
        case .itemDoesNotContainProjectLanguage(key: let key, missingLanguage: let language):
            return "Item which has a key \"\(key)\" does not have localization for \"\(language)\"."
        case .itemHasALanguageNotIncludedInProjectLanguage(key: let key, unnecessaryLanguage: let language):
            return "Item which has a key \"\(key)\" has unnecessary localization for \"\(language)\"."
        case .undefinedArgument(key: let key, undefinedArgumentName: let argumentName):
            return "Item which has a key \"\(key)\" includes undefined argument named \"\(argumentName)\"."
        case .argumentTypeIsNotSupported(key: let key, argumentName: let argumentName, argumentType: let argumentType):
            return "Type of an argument named \"\(argumentName)\" in key \"\(key)\" is not supported: \"\(argumentType)\"."
        }
    }
}
