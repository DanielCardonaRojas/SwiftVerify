//
//  File.swift
//  
//
//  Created by Daniel Rojas on 18/04/21.
//

import Foundation

struct Pizza {
    let ingredients: [String]
    let size: Int
}

struct UserRegistration {
    let email: String
    let password: String
    let passwordConfirmation: String
}

enum  UserRegistrationError: Error {
    case invalidEmail, invalidPassword, passwordsDontMatch
}

struct FormError<FieldType>: Error {
    enum Reason {
        case invalidFormat, required, needsMatch
    }

    let reason: Reason
    let field: FieldType

    static func required(_ field: FieldType) -> FormError {
        .init(reason: .required, field: field)
    }

    static func badFormat(_ field: FieldType) -> FormError {
        .init(reason: .invalidFormat, field: field)
    }
}

typealias LoginFormError = FormError<LoginField>

enum LoginField {
    case email, password, passwordConfirmation
}

struct FormField<FieldType> {
    var visited = false
    let field: FieldType
    var text = ""
}

struct LoginForm {
    typealias Field = FormField<LoginField>
    var emailField: Field
    var passwordField: Field
    var passwordConfirmationField: Field
}
