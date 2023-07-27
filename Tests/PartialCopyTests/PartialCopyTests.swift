import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(PartialCopyMacros)
import PartialCopyMacros

let testMacros: [String: Macro.Type] = [
    "PartialCopyable": PartialCopyableMacro.self,
]
#endif

final class PartialCopyTests: XCTestCase {
    func testMacroImplicitMemberwiseInit() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String
                let lastName: String
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String
                let lastName: String
                internal func with(firstName: String? = nil, lastName: String? = nil) -> Self {
                    Self.init(firstName: firstName ?? self.firstName, lastName: lastName ?? self.lastName)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroMemberwiseInit() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init(firstName: String, lastName: String) {
                    self.firstName = firstName
                    self.lastName = lastName
                }
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init(firstName: String, lastName: String) {
                    self.firstName = firstName
                    self.lastName = lastName
                }
                internal func with(firstName: String? = nil, lastName: String? = nil) -> Self {
                    Self.init(firstName: firstName ?? self.firstName, lastName: lastName ?? self.lastName)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroPartialMemberwiseInit() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init(firstName: String) {
                    self.firstName = firstName
                    self.lastName = firstName
                }
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init(firstName: String) {
                    self.firstName = firstName
                    self.lastName = firstName
                }
                internal func with(firstName: String? = nil) -> Self {
                    Self.init(firstName: firstName ?? self.firstName)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroFailableInit() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init?(firstName: String, lastName: String) {
                    self.firstName = firstName
                    self.lastName = lastName
                }
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init?(firstName: String, lastName: String) {
                    self.firstName = firstName
                    self.lastName = lastName
                }
                internal func with(firstName: String? = nil, lastName: String? = nil) -> Self? {
                    Self.init(firstName: firstName ?? self.firstName, lastName: lastName ?? self.lastName)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroAsyncThrowingInit() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init(firstName: String, lastName: String) async throws {
                    self.firstName = firstName
                    self.lastName = lastName
                }
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String
                let lastName: String
            
                internal init(firstName: String, lastName: String) async throws {
                    self.firstName = firstName
                    self.lastName = lastName
                }
                internal func with(firstName: String? = nil, lastName: String? = nil) async throws -> Self {
                    try await Self.init(firstName: firstName ?? self.firstName, lastName: lastName ?? self.lastName)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroOptionalProps() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String?
                let lastName: String?
            
                internal init(firstName: String?, lastName: String?) {
                    self.firstName = firstName
                    self.lastName = lastName
                }
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String?
                let lastName: String?
            
                internal init(firstName: String?, lastName: String?) {
                    self.firstName = firstName
                    self.lastName = lastName
                }
                internal func with(firstName: String?? = nil, lastName: String?? = nil) -> Self {
                    Self.init(firstName: firstName ?? self.firstName, lastName: lastName ?? self.lastName)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroNotAStruct() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            class Person {
            }
            """,
            expandedSource: """
            class Person {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@PartialCopyable can only be applied to structs", line: 1, column: 1)
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroNoStoredProps() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
            }
            """,
            expandedSource: """
            struct Person {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@PartialCopyable has no effect on types without any stored properties", line: 1, column: 1, severity: .warning)
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroNoValidInits() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                let firstName: String
                let lastName: String
            
                init() {
                    self.firstName = "John"
                    self.lastName = "Doe"
                }
            
                init(fullName: String) {
                    let parts = fullName.split(separator: " ")
                    self.firstName = String(parts[0])
                    self.lastName = String(parts[1])
                }
            }
            """,
            expandedSource: """
            struct Person {
                let firstName: String
                let lastName: String
            
                init() {
                    self.firstName = "John"
                    self.lastName = "Doe"
                }
            
                init(fullName: String) {
                    let parts = fullName.split(separator: " ")
                    self.firstName = String(parts[0])
                    self.lastName = String(parts[1])
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@PartialCopyable requires at least one initializer that only references stored properties (including the compiler-generated memberwise init)", line: 1, column: 1, notes: [
                    .init(message: "Initializer has no parameters", line: 6, column: 5),
                    .init(message: "Initializer has parameters that do not match any stored properties", line: 11, column: 5)
                ])
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacroNoTypeAnnotation() throws {
        #if canImport(PartialCopyMacros)
        assertMacroExpansion(
            """
            @PartialCopyable
            struct Person {
                var firstName: String = "John"
                var lastName = "Doe"
            }
            """,
            expandedSource: """
            struct Person {
                var firstName: String = "John"
                var lastName = "Doe"
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@PartialCopyable requires stored properties provide explicit type annotations", line: 4, column: 9, fixIts: [
                    .init(message: "Add an explicit type annotation")
                ])
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
