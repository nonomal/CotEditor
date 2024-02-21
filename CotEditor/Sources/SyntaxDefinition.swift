//
//  SyntaxDefinition.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2023-01-19.
//
//  ---------------------------------------------------------------------------
//
//  © 2023-2024 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

final class SyntaxDefinition: ObservableObject {
    
    struct Highlight: Identifiable, EmptyInitializable {
        
        let id = UUID()
        
        var begin: String = ""
        var end: String?
        var isRegularExpression: Bool = false
        var ignoreCase: Bool = false
        var description: String?
    }
    
    
    struct Outline: Identifiable, EmptyInitializable {
        
        let id = UUID()
        
        var pattern: String = ""
        var template: String = ""
        var ignoreCase: Bool = false
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var description: String?
    }
    
    
    struct KeyString: Identifiable, EmptyInitializable {
        
        let id = UUID()
        
        var string: String = ""
    }
    
    
    struct Comment: Equatable, Codable {
        
        var inline: String?
        var blockBegin: String?
        var blockEnd: String?
        
        
        var blockPair: Pair<String>? {
            
            if let begin = self.blockBegin, let end = self.blockEnd { Pair(begin, end) } else { nil }
        }
    }
    
    
    struct Metadata: Equatable, Codable {
        
        var version: String?
        var lastModified: String?
        var distributionURL: String?
        var author: String?
        var license: String?
        var description: String?
    }
    
    @Published var kind: Syntax.Kind = .general
    
    @Published var keywords: [Highlight] = []
    @Published var commands: [Highlight] = []
    @Published var types: [Highlight] = []
    @Published var attributes: [Highlight] = []
    @Published var variables: [Highlight] = []
    @Published var values: [Highlight] = []
    @Published var numbers: [Highlight] = []
    @Published var strings: [Highlight] = []
    @Published var characters: [Highlight] = []
    @Published var comments: [Highlight] = []
    
    @Published var commentDelimiters: Comment = Comment()
    @Published var outlines: [Outline] = []
    @Published var completions: [KeyString] = []
    
    @Published var filenames: [KeyString] = []
    @Published var extensions: [KeyString] = []
    @Published var interpreters: [KeyString] = []
    
    @Published var metadata: Metadata = Metadata()
    
    
    static func highlightKeyPath(for type: SyntaxType) -> ReferenceWritableKeyPath<SyntaxDefinition, [Highlight]> {
        
        switch type {
            case .keywords: \.keywords
            case .commands: \.commands
            case .types: \.types
            case .attributes: \.attributes
            case .variables: \.variables
            case .values: \.values
            case .numbers: \.numbers
            case .strings: \.strings
            case .characters: \.characters
            case .comments: \.comments
        }
    }
}



// MARK: Equatable

extension SyntaxDefinition: Equatable {
    
    static func == (lhs: SyntaxDefinition, rhs: SyntaxDefinition) -> Bool {
        
        SyntaxType.allCases.map(Self.highlightKeyPath(for:)).allSatisfy({ lhs[keyPath: $0] == rhs[keyPath: $0] }) &&
        lhs.kind == rhs.kind &&
        lhs.commentDelimiters == rhs.commentDelimiters &&
        lhs.outlines == rhs.outlines &&
        lhs.completions == rhs.completions &&
        lhs.filenames == rhs.filenames &&
        lhs.extensions == rhs.extensions &&
        lhs.interpreters == rhs.interpreters &&
        lhs.metadata == rhs.metadata
    }
}


extension SyntaxDefinition.Highlight: Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        
        lhs.begin == rhs.begin &&
        lhs.end == rhs.end &&
        lhs.isRegularExpression == rhs.isRegularExpression &&
        lhs.ignoreCase == rhs.ignoreCase &&
        lhs.description == rhs.description
    }
}


extension SyntaxDefinition.Outline: Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        
        lhs.pattern == rhs.pattern &&
        lhs.template == rhs.template &&
        lhs.ignoreCase == rhs.ignoreCase &&
        lhs.bold == rhs.bold &&
        lhs.italic == rhs.italic &&
        lhs.underline == rhs.underline &&
        lhs.description == rhs.description
    }
}


extension SyntaxDefinition.KeyString: Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        
        lhs.string == rhs.string
    }
}
