import Foundation

typealias ValidatorType<S, T> = (S) -> Result<T, [Error]>
typealias ValidatorType_<S> = (S) -> Result<S, [Error]>
typealias Predicate<S> = (S) -> Bool
typealias Validator_<S> = Validator<S,S>


struct ValidationErrors: Error {
    let errors: [Error]

    init(errors: Error...) {

        self.errors = errors
    }

    var localizedDescription: String {
        errors.first?.localizedDescription ?? ""
    }
}


extension Array: Error where Element: Error {}
/**
 A class representing validations that can fail with one or multiple errors
 and can transforma data in the process.
 */
class Validator<S,T> {
    let validator: ValidatorType<S,T>
    
    init(_ validation: @escaping ValidatorType<S,T>) {
        self.validator = validation
    }

    func callAsFunction(_ subject: S) -> Result<T, [Error]> {
        validator(subject)
    }

    /**
     Creates a validator that always succeeds

     List a pure function into the context of a Validator.

     - Parameter value: The value with which this validator should succeed.
     */
    static func lift(_ function: @escaping (S) -> T) -> Validator {
        Validator { input in
            .success(function(input))
        }
    }

    /**
     Transforms the output of the validator i.e the subject/state being
     validated.

     - Parameter transform: The function to modify the output of result of the validator.
     - Returns: A validator with the same validaiton logic of caller but with coerced output.
     */
    func map<O>(_ transform: @escaping (T) -> O) -> Validator<S,O> {
        Validator<S,O> { [unowned self] input in
            let result = self.validator(input)
            return result.map(transform)
        }
    }
    
    // MARK: Utilities
    func verify(subject: S) -> Result<T, [Error]> {
        return self(subject)
    }

    // MARK: Composition

    /**
     Creates a new validator from caller and supplied validator

    Implementation of flatMap for Validator class.
    Will only run the provided validator if the caller succeeds

     - Parameter check: A validator to compose
     - Returns: A validators that either succeeds or fails with a single error.
     */

    func andThen<O>(_ check: Validator<T, O>) -> Validator<S,O> {
        Validator<S,O> { input in
            self.validator(input).flatMap(check.callAsFunction)
        }
    }
    /**
     Chains a parallel validator to caller
     - Parameter merge: A function to merge or select the final output when both validation succeed.
     - Returns: A validator that will run the caller validation in parallel with the supplied validator.
     */
    func add<T2, O>(_ validator: Validator<S, T2>, merge: @escaping (T, T2) -> O) -> Validator<S, O> {
        Validator<S, O> { input in
            let result1 = self(input)
            let result2 = validator(input)
            switch (result1, result2) {
            case (.success(let output1), .success(let output2)):
                let sum = merge(output1, output2)
                return .success(sum)
            case (.failure(let error1), .failure(let error2)):
                return .failure(error1 + error2)
            case (.success(_), .failure(let error2)):
                return .failure(error2)
            case (.failure(let error1), .success(_)):
                return .failure(error1)
            }
        }
    }


}

// MARK: Utilities
extension Validator {
    /**
     Adds a check to the caller Validator

     - Parameter check: The predicate conforming the agregate validator.
     - Parameter otherwise: The error added to the error list of the caller.
     */
    func addCheck(_ check: @escaping Predicate<S>, otherwise error: Error) -> Validator {
        self.add(Verify.property(check, otherwise: error), merge: { fst, snd in fst })
    }
    /**
     Chaings a validation created from the provided predicate to the caller.

     - Parameter predicate: The predicate to check
     - Returns: Validators that will run a sequential check when caller succeeds.
     */
    func thenCheck(_ predicate: @escaping Predicate<S>, otherwise failure: Error) -> Validator {
        Validator<S,T> { input in
            let result = self(input)
            return result.flatMap({ predicate(input) ? .success($0) : Result.failure([failure]) })
        }
    }

    /**
     Chains a validator that acts on a subfield of the current subject.

     - Parameter keyPath: The property keypath to focus on
     - Parameter check: The validator to apply

     - Returns: Validators that includes checks from caller and the validation on child property.

     */
    func thenOn<F>(_ keyPath: KeyPath<S,F>, check validator: Validator_<F>) -> Validator_<S> {
        Validator<S,S> { (s: S) -> Result<S, [Error]> in
            let subfield = s[keyPath: keyPath]
            return validator(subfield).map({ _ in s })
        }
    }
}


/// Namespace for validator factories.
enum Verify {
    // MARK: Factories

    /**
     Creates a validator that always succeeds

     Const validator that ignores its input.

     - Parameter value: The value with which this validator should succeed.
     */
    static func valid<S>(_ value: S) -> Validator_<S> {
        Validator.lift({ _ in value })
    }

    /**
     Creates a validator that always fails with the provided error

     Will fail no matter what input is provided

     - Parameter error: The error to fail with

     - Returns: Validator
     */
    static func error<S>(_ error: Error) -> Validator_<S>  {
        Validator { _ in .failure([error]) }
    }
    /**
     Creates a Validator from the provided predicate

     - Parameter predicate: Supplied predicate to test the subject against
     - Parameter otherwise: Error in case the subject does not fulfill the predicate.
     */
    static func property<S>(_ predicate: @escaping Predicate<S>, otherwise: Error) -> Validator_<S> {
        Validator { subject in predicate(subject) ? .success(subject) : .failure([otherwise])}
    }

    /**
     Creates a validator composing the provided validators in a parallel way

     - Parameter validators: The list of validators to compose
     - Parameter merge: A function that can sum or select the final output of the resulting validator.
     */
    static func all<S>(_ validators: Validator_<S>..., merge: @escaping (S, S) -> S) -> Validator_<S> {
        Validator<S,S> { input in
            let results = validators.map({ validator in validator(input) })
            let failures = results.compactMap({ $0.getFailure() })
            let succeeds = results.compactMap({ try? $0.get() })

            if failures.count > 0 {
                return .failure(failures)
            }

            let tail = succeeds.suffix(from: 1)
            let state = tail.reduce(succeeds.first!, merge)

            return .success(state)
        }
    }


    /**
     Create a Validator by composing the provided validators in a sequential fashion.

     - Parameter validators: The validators to compose
     - Returns: A validators the will either succeed or fails with exactly one error.
    */

    static func inOrder<S>(_ validators: Validator_<S>...) -> Validator_<S> {
        let initial = validators.first!
        let tail = validators.suffix(from: 1)

        return tail.reduce(initial, { acc, validator in validator.andThen(acc) } )
    }
}

