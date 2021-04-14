import XCTest
@testable import Verify

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
        case invalidFormat, required
    }

    let reason: Reason
    let field: FieldType
}

enum LoginField {
    case email, password
}

final class VerifyTests: XCTestCase {
    enum MyError: Error, Equatable {
        case error1, error2
    }

    // MARK: Factory tests
    func testCanEasilyTestStruct() {
        let invalidEmail = UserRegistrationError.invalidEmail
        let invalidPassword = UserRegistrationError.invalidPassword

        let emailValidator = Verify<String>.inOrder {
            Verify.minLength(5, otherwise: invalidEmail)
            Verify.property({ $0.contains("@")}, otherwise: invalidEmail)
        }

        let password = Verify<String>.inOrder {
            Verify<String>.property({ $0.count > 5}, otherwise: invalidPassword)
            Verify.containsSomeOf(CharacterSet.symbols, otherwise: invalidPassword)
        }

        let registrationValidator = Verify<UserRegistration>.atOnce {
            Verify<UserRegistration>.at(\.email, validator: emailValidator)
            Verify<UserRegistration>.at(\.password, validator: password)
            Verify<UserRegistration>.that({ $0.password == $0.passwordConfirmation  }, otherwise: UserRegistrationError.passwordsDontMatch)
        }

        let errors = registrationValidator.errors(UserRegistration(email: "", password: "19d", passwordConfirmation: "12d"))

        XCTAssert(errors.count > 0)

    }

    func testAtOnceEvaluatesAllErrors() {
        let emailValidator = Verify<String>.atOnce {
            Verify.property({ $0.contains("@")}, otherwise: MyError.error1)
            Verify.minLength(5, otherwise: MyError.error2)
        }

        let input = "1"
        let errorCount = emailValidator.errors(input).count
        XCTAssert(errorCount == 2)
    }

    func test_valid_factory_always_succeds() {
        let validator = Verify.valid(3)

        let result = validator(1)

        XCTAssert(try! result.get() == 3)
    }

    func test_can_transform_validor_output() {
        let stringValidator = Verify.valid("123")
        let intValidator = stringValidator.map { Int($0) }
        let result = try? intValidator("").get() ?? 0
        XCTAssert(result == 123)
    }

    func test_error_factory_always_fails() {
        let result = Verify.error(MyError.error1)(3)
        XCTAssert(result.isFailure)
        XCTAssert(result.errorCount == 1)

    }

    func test_property_succeed_on_fulfilled_predicate() {
        let checkCorrectSize = Verify<String>.property({ $0.count == 3}, otherwise: MyError.error1)
        let result = checkCorrectSize("123")
        XCTAssert(result.isSuccess)
    }

    func  test_property_fails_on_unfulfilled_predicate() {
        let checkCorrectSize = Verify<String>.property({ $0.count == 3}, otherwise: MyError.error1)
        let result = checkCorrectSize("12")
        XCTAssert(result.isFailure)
    }

    func test_can_group_field_errors() {
        typealias LoginFormError = FormError<LoginField>

        let validator = Verify<Int>.atOnce {
            Verify<Int>.error(LoginFormError(reason: .invalidFormat, field: .email))
            Verify<Int>.error(LoginFormError(reason: .required, field: .password))
        }

        let groupedErrors: [LoginField: [LoginFormError]] = validator.groupedErrors(0, by: { (error: LoginFormError) in error.field })

        XCTAssert(groupedErrors.values.count > 0)
        XCTAssert(groupedErrors.keys.count == 2)
    }

    func test_can_cast_errors_when_running_validator() {
        let validator = Verify<Int>.atOnce {
            Verify<Int>.error(MyError.error1)
            Verify<Int>.error(MyError.error2)
        }

        let errors = validator.errors(0, errorType: MyError.self)
        XCTAssert(errors.count == 2)
    }

    // MARK: Validator composition

    func test_flatmap_does_not_accumulate_errors() {
        let fail1: Validator<Int> = Verify.error(MyError.error1)
        let fail2: Validator<Int> = Verify.error(MyError.error2)

        let validator = fail1.andThen(fail2)

        XCTAssert(validator(3).errorCount == 1)
    }

    func testSomething() {
        Verify<Pizza>.inOrder(
            Verify.at(\.size, validator: Verify.greaterThanZero(otherwise: MyError.error1))
        )

    }

    func test_flatmap_errors_out_if_caller_fails() {
        let fail1: Validator<Int> = Verify.error(MyError.error1)
        let success = Verify.valid(3)

        let validator = fail1.andThen(success)
        let result = validator(3)

        XCTAssert(result.errorCount == 1)
        XCTAssert(result.getFailure()?.first as? MyError == MyError.error1)

    }

    func test_paralle_validator_sums_errors() {
        let fail1 = Verify<Int>.error(MyError.error1)
        let fail2 = Verify<Int>.error(MyError.error2)

        let validator = fail1.add(fail2, merge: {fst, _ in fst })
        let result = validator(3)

        XCTAssert(result.errorCount == 2)
        XCTAssert(result.getFailure()?.first as? MyError == MyError.error1)
        XCTAssert(result.getFailure()?.last as? MyError == MyError.error2)
    }

    func test_all_composition_accumulates_errors() {
        let fail1 = Verify<Int>.error(MyError.error1)
        let fail2 = Verify<Int>.error(MyError.error2)

        let validator = Verify.atOnce(fail1, fail2, merge: { fst, _ in fst })
        let result = validator(3)

        XCTAssert(result.errorCount == 2)
    }

    func test_flatmap_can_also_transform_input() {
        let validator1 = ValidatorT.lift({ (str: String) in str.count })
        let validator2 = ValidatorT<Int, Int> { (value: Int) in
            .success(value * 2)
        }

        let validator = validator1.andThen(validator2)

        XCTAssert(try! validator("123").get() == 6)
    }

    func test_all_composition_preserves_error_order() {
        let fail1 = Verify<Int>.error(MyError.error1)
        let fail2 = Verify<Int>.error(MyError.error2)

        let validator = Verify<Int>.atOnce(fail1, fail2, merge: { fst, _ in fst })
        let result = validator(3)
        if case .failure(let failures) = result {
            XCTAssert(failures.first as? MyError == MyError.error1)
        }

        XCTAssert(result.errorCount == 2)

    }

    func test_can_add_parallel_check() {
        let fail1 = Verify<Int>.error(MyError.error1)

        let validator = fail1.addCheck({ value in value > 10}, otherwise: MyError.error2)

        let result = validator(2)

        XCTAssert(result.errorCount == 2)
    }

    static var allTests = [
        ("testExample", test_can_add_parallel_check)
    ]
}
