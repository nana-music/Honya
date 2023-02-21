//
//  Input.swift
//  
//
//  Created by hiragram on 2022/08/24.
//

import Foundation

struct Input: Decodable {
    var languages: [String]

    var items: [Item]
}

struct Item: Decodable {
    typealias LanguageCode = String // see: https://ja.wikipedia.org/wiki/ISO_639-1%E3%82%B3%E3%83%BC%E3%83%89%E4%B8%80%E8%A6%A7

    var key: String

    var localizations: [LanguageCode: String]
    var arguments: [Argument]?

    func localizationWithFormattedArguments(_ languageCode: LanguageCode) -> String {
        let raw = localizations[languageCode]!

        let result = argumentsInText(language: languageCode)
            .map({ match -> String in
                let range = match.range
                let startIndex = raw.index(raw.startIndex, offsetBy: range.location)
                let endIndex = raw.index(startIndex, offsetBy: range.length)
                let argumentName = String(raw[startIndex..<endIndex])

                return argumentName
            })
            .reduce(raw) { partialResult, argumentName in
                let argumentOrder = arguments!.firstIndex(where: {
                    $0.name == argumentName
                        .replacingOccurrences(of: "\\(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                })! + 1

                let argument = arguments!.first(where: {
                    $0.name == argumentName
                        .replacingOccurrences(of: "\\(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                })!
                let typeSpecifier = argument.typeSpecifier
                let specifier = "%\(argumentOrder)$\(typeSpecifier)"

                return partialResult.replacingOccurrences(of: argumentName, with: specifier)
            }

        return result
    }

    static let regex: NSRegularExpression = { () in
        let pattern = "\\\\\\(.*?\\)"
        return try! NSRegularExpression(pattern: pattern)
    }()

    func argumentsInText(language: LanguageCode) -> [NSTextCheckingResult] {
        let regex = Self.regex
        let targetText = localizations[language]!
        let matches = regex.matches(in: targetText, range: .init(location: 0, length: targetText.count))

        return matches
    }

    public func getLocalizationKey() -> String {
        let base = "\(key)"
        if let arguments = arguments, !arguments.isEmpty {
            let argumentSpecifiers = arguments
                .map {
                    "%\($0.typeSpecifier)"
                }
                .joined(separator: " ")
            return "\(base) \(argumentSpecifiers)"
        } else {
            return base
        }
    }

    public func getArguments() -> String {
        if let arguments {
            return "[\(arguments.map(\.name).joined(separator: ", "))]"
        } else {
            return "[]"
        }
    }

    struct Argument: Decodable, Equatable {
        var name: String
        var type: String

        var typeSpecifier: String {
            switch type {
            case "String":
                return "@"
            case "Int":
                return "lld"
            case "Double":
                return "lf"
            default:
                fatalError()
            }
        }
    }
}
