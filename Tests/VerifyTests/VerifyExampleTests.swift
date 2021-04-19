//
//  File.swift
//  
//
//  Created by Daniel Rojas on 18/04/21.
//

import Foundation

import XCTest
@testable import Verify

final class VerifyExampleTests: XCTestCase {

    func testLoginFormExample() {
        let emailValidator = Verify<LoginForm.Field>
            .that({ !$0.text.isEmpty}, otherwise: LoginFormError.required(.email))
            .andThat({ $0.text.contains("@")}, otherwise: LoginFormError.badFormat(.email))
            .ignore(when: { !$0.visited})

        Verify<LoginForm>.atOnce(
            Verify.at(\.emailField, validator: emailValidator),
            Verify.that({ $0.passwordField.text == $0.passwordConfirmationField.text}, otherwise: LoginFormError(reason: .needsMatch, field: .passwordConfirmation))
        )
    }

}
