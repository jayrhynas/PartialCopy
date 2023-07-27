import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct PartialCopyableMacro: MemberMacro {
    fileprivate struct InitializerInfo {
        var accessModifier: String
        var isFailable = false
        var isAsync    = false
        var isThrowing = false
        var params: [(name: TokenSyntax, type: TypeSyntax)]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic.notAStruct(for: declaration))
            return []
        }

        // Gather initializers and stored properties
        var initializers: [InitializerDeclSyntax] = []
        var storedProperties: [PatternBindingSyntax] = []
        
        var anyMissingType = false
        
        for member in structDecl.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                initializers.append(initializer)
            }
            else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    // skip let bindings with initialized values
                    if varDecl.bindingKeyword == .keyword(.let), binding.initializer != nil {
                        continue
                    }
                    // skip computed properties
                    if binding.accessor?.is(CodeBlockSyntax.self) == true {
                        continue
                    }
                    // skip (and error) on properties with no type annotation
                    if binding.typeAnnotation == nil {
                        context.diagnose(Diagnostic.noTypeAnnotation(for: binding))
                        anyMissingType = true
                        continue
                    }
                    
                    storedProperties.append(binding)
                }
            }
        }
        
        if anyMissingType {
            return []
        }
        
        // warn and exit if no stored properties
        guard !storedProperties.isEmpty else {
            context.diagnose(Diagnostic.noStoredProps(for: structDecl))
            return []
        }
        
        let validInitializers = initializers.isEmpty
        // if there are no initializers, assume the generated memberwise initializer
        ? [InitializerInfo(accessModifier: "internal", params: storedProperties.map {
            ($0.identifier!, $0.typeAnnotation!.type)
        })]
        // otherwise, look for initializers that only have parameters matching stored property names and types
        : initializers.compactMap { initializer in
            if initializer.signature.input.parameterList.isEmpty {
                return nil
            }
            for param in initializer.signature.input.parameterList {
                let hasStoredProp = storedProperties.contains { prop in
                    prop.identifier?.text == param.firstName.text
                    && prop.typeAnnotation?.type.description == param.type.description
                }
                if !hasStoredProp {
                    return nil
                }
            }
            
            return InitializerInfo(
                accessModifier: initializer.modifiers?.compactMap { $0.as(DeclModifierSyntax.self) }.first?.name.text ?? "internal",
                isFailable: initializer.optionalMark != nil,
                isAsync: initializer.signature.effectSpecifiers?.asyncSpecifier != nil,
                isThrowing: initializer.signature.effectSpecifiers?.throwsSpecifier != nil,
                params: initializer.signature.input.parameterList.map { ($0.firstName, $0.type) }
            )
        }
        
        // if there were initializers written by the user, but none of them were valid, this is an error
        if validInitializers.isEmpty {
            context.diagnose(Diagnostic.noInitializers(for: structDecl, invalidInitializers: initializers))
            return []
        }
        
        // generate a `with` method for each initializer
        return validInitializers.map { initializer in
            let paramList = initializer.params.map { "\($0.name): \($0.type)? = nil" }.joined(separator: ", ")
            let callList  = initializer.params.map { "\($0.name): \($0.name) ?? self.\($0.name)" }.joined(separator: ", ")
            
            return """
            \(raw: initializer.accessModifier) func with(\(raw: paramList)) \(raw: initializer.isAsync ? "async " : "")\(raw: initializer.isThrowing ? "throws " : "")-> Self\(raw: initializer.isFailable ? "?" : "") {
                \(raw: initializer.isThrowing ? "try " : "")\(raw: initializer.isAsync ? "await " : "")Self.init(\(raw: callList))
            }
            """
        }
    }
}


// MARK: Syntax Helpers

extension PatternBindingSyntax {
    fileprivate var identifier: TokenSyntax? {
        self.pattern.as(IdentifierPatternSyntax.self)?.identifier
    }
    
    func withTypeAnnotation(_ type: TypeSyntax) -> PatternBindingSyntax {
        var copy = self
        copy.pattern.trailingTrivia = []
        copy.typeAnnotation = .init(colon: .colonToken(trailingTrivia: .space), type: type as TypeSyntax, trailingTrivia: .space)
        return copy
    }
}


// MARK: Diagnostics

extension PartialCopyableMacro {
    enum Diagnostic {
        static func notAStruct(for syntax: some SyntaxProtocol) -> SwiftDiagnostics.Diagnostic {
            .init(node: Syntax(syntax), message: Error.notAStruct)
        }
        
        static func noStoredProps(for syntax: some SyntaxProtocol) -> SwiftDiagnostics.Diagnostic {
            .init(node: Syntax(syntax), message: Error.noStoredProps)
        }
        
        static func noInitializers(for syntax: some SyntaxProtocol, invalidInitializers: [InitializerDeclSyntax]) -> SwiftDiagnostics.Diagnostic {
            .init(
                node: Syntax(syntax),
                message: Error.noInitializers,
                notes: invalidInitializers.map {
                    Note(node: Syntax($0.initKeyword), message: $0.signature.input.parameterList.isEmpty ? Message.initNoParams : Message.initParamMismatch)
                }
            )
        }
        
        static func noTypeAnnotation(for binding: PatternBindingSyntax) -> SwiftDiagnostics.Diagnostic {
            .init(
                node: Syntax(binding),
                message: Error.noTypeAnnotation,
                fixIts: [
                    .init(message: Message.addTypeAnnotation, changes: [
                        .replace(oldNode: Syntax(binding), newNode: Syntax(binding.withTypeAnnotation("<\("#")Type#>")))
                    ])
                ]
            )
        }
    }
    
    struct Error: Swift.Error, DiagnosticMessage {
        let diagnosticID: MessageID
        let message: String
        let severity: DiagnosticSeverity
        
        init(id: String, message: String, severity: DiagnosticSeverity = .error) {
            self.diagnosticID = .init(domain: "com.jayrhynas.PartialCopyableMacro", id: id)
            self.message = message
            self.severity = severity
        }
        
        static let notAStruct       = Error(id: "notAStruct",       message: "@PartialCopyable can only be applied to structs")
        static let noStoredProps    = Error(id: "noStoredProps",    message: "@PartialCopyable has no effect on types without any stored properties", severity: .warning)
        static let noInitializers   = Error(id: "noInitializers",   message: "@PartialCopyable requires at least one initializer that only references stored properties (including the compiler-generated memberwise init)")
        static let noTypeAnnotation = Error(id: "noTypeAnnotation", message: "@PartialCopyable requires stored properties provide explicit type annotations")
    }
    
    struct Message: FixItMessage, NoteMessage {
        let fixItID: MessageID
        let message: String
        
        init(id: String, message: String) {
            self.fixItID = .init(domain: "com.jayrhynas.PartialCopyableMacro", id: id)
            self.message = message
        }
        
        static let addTypeAnnotation = Message(id: "addTypeAnnotation", message: "Add an explicit type annotation")
        static let initNoParams      = Message(id: "initNoParams",      message: "Initializer has no parameters")
        static let initParamMismatch = Message(id: "initParamMismatch", message: "Initializer has parameters that do not match any stored properties")
        
    }
}


// MARK: - Plugin Definition

@main
struct PartialCopyPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PartialCopyableMacro.self,
    ]
}
