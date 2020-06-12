import XCTest
@testable import Verify



struct Pizza {
    let ingredients: [String]
    let size: Int
}

final class VerifyTests: XCTestCase {
    enum MyError: Error, Equatable {
        case error1, error2
    }

    // MARK: Factory tests

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
        let checkCorrectSize = Verify.property({ (str: String) in str.count == 3}, otherwise: MyError.error1)
        let result = checkCorrectSize("123")
        XCTAssert(result.isSuccess)
    }

    func  test_property_fails_on_unfulfilled_predicate() {
        let checkCorrectSize = Verify.property({ (str: String) in str.count == 3}, otherwise: MyError.error1)
        let result = checkCorrectSize("12")
        XCTAssert(result.isFailure)
    }

    // MARK: Validator composition

    func test_flatmap_does_not_accumulate_errors() {
        let fail1: Validator_<Int> = Verify.error(MyError.error1)
        let fail2: Validator_<Int> = Verify.error(MyError.error2)

        let validator = fail1.andThen(fail2)

        XCTAssert(validator(3).errorCount == 1)
    }


    func test_flatmap_errors_out_if_caller_fails() {
        let fail1: Validator_<Int> = Verify.error(MyError.error1)
        let success = Verify.valid(3)

        let validator = fail1.andThen(success)
        let result = validator(3)

        XCTAssert(result.errorCount == 1)
        XCTAssert(result.getFailure()?.first as? MyError == MyError.error1)

    }

    func test_paralle_validator_sums_errors() {
        let fail1: Validator_<Int> = Verify.error(MyError.error1)
        let fail2: Validator_<Int> = Verify.error(MyError.error2)

        let validator = fail1.add(fail2, merge: {fst, snd in fst })
        let result = validator(3)

        XCTAssert(result.errorCount == 2)
        XCTAssert(result.getFailure()?.first as? MyError == MyError.error1)
        XCTAssert(result.getFailure()?.last as? MyError == MyError.error2)
    }


    func test_all_composition_accumulates_errors() {
        let fail1: Validator_<Int> = Verify.error(MyError.error1)
        let fail2: Validator_<Int> = Verify.error(MyError.error2)

        let validator = Verify.all(fail1, fail2, merge: { fst, snd in fst })
        let result = validator(3)

        XCTAssert(result.errorCount == 2)
    }

    func test_flatmap_can_also_transform_input() {
        let validator1 = Validator.lift({ (str: String) in str.count })
        let validator2 = Validator<Int, Int> { (value: Int) in
            .success(value * 2)
        }

        let validator = validator1.andThen(validator2)

        XCTAssert(try! validator("123").get() == 6)
    }

//    func test_all_composition_preserves_error_order() {
//        let fail1: Validator_<Int> = Verify.error(MyError.error1)
//        let fail2: Validator_<Int> = Verify.error(MyError.error2)
//
//        let validator = Verify.all(fail1, fail2, merge: { fst, snd in fst })
//        let result = validator(3)
//        if case .failure(let failures) = result {
////            let error = result?.getFailure()?.first as? MyError
//            XCTAssert(failures.first as? MyError == MyError.error1)
//        }
//
//
////        XCTAssert(result.errorCount == 2)
//
//    }

    func test_can_add_parallel_check() {
        let fail1: Validator_<Int> = Verify.error(MyError.error1)

        let validator = fail1.addCheck({ value in value > 10}, otherwise: MyError.error2)

        let result = validator(2)

        XCTAssert(result.errorCount == 2)
    }



    static var allTests = [
        ("testExample", test_can_add_parallel_check),
    ]
}
