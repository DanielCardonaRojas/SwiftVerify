import Foundation

typealias ValidatorType<S, T> = (S) -> Result<T, ValidationErrors>
typealias ValidatorType_<S> = (S) -> Result<S, ValidationErrors>
public typealias Predicate<S> = (S) -> Bool
public typealias Validator_<S> = Validator<S, S>

public struct ValidationErrors: Error, LocalizedError {
    public var errors: [Error]

    public subscript(_ index: Int) -> Error {
        return errors[index]
    }

    public var first: Error? {
        errors.first
    }

    public var last: Error? {
        errors.last
    }

    public init(_ errors: Error...) {
        self.errors = errors
    }

    init(fromList: [Error]) {
        self.errors = fromList
    }

}

// MARK: - Function Builders
/// A validation function builder
@_functionBuilder
public struct ValidationSequencedBuilder<Subject> {
    public static func buildBlock(_ validators: Validator_<Subject>...) -> Validator_<Subject> {
        composeSequential(validators)
    }
}

@_functionBuilder
public struct ValidationParallelBuilder<Subject> {

    public static func buildBlock(_ validators: Validator_<Subject>...) -> Validator_<Subject> {
        composeAll(validators, merge: { fst, snd in fst })
    }
}

extension Verify {
    public static func inSequence(@ValidationSequencedBuilder<Subject> _ content: () -> Validator_<Subject>)
        -> Validator_<Subject>
    {
        content()
    }

    public static func atOnce(@ValidationParallelBuilder<Subject> _ content: () -> Validator_<Subject>)
        -> Validator_<Subject>
    {
        content()
    }
}
/// A class representing validations that can fail with one or multiple errors
/// and can transforma data in the process.
public class Validator<S, T> {
    let validator: ValidatorType<S, T>

    init(_ validation: @escaping ValidatorType<S, T>) {
        self.validator = validation
    }

    func callAsFunction(_ subject: S) -> Result<T, ValidationErrors> {
        validator(subject)
    }

    /**
     Creates a validator that always succeeds

     List a pure function into the context of a Validator.

     - Parameter value: The value with which this validator should succeed.
     */
    public static func lift(_ function: @escaping (S) -> T) -> Validator {
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
    public func map<O>(_ transform: @escaping (T) -> O) -> Validator<S, O> {
        Validator<S, O> { input in
            let result = self.validator(input)
            return result.map(transform)
        }
    }

    // MARK: Utilities
    public func verify(_ subject: S) -> Result<T, ValidationErrors> {
        return self.validator(subject)
    }

    public func errors(_ subject: S) -> [Error] {
        return self.validator(subject).failures
    }

    public func errors<CustomError: Error>(_ subject: S, errorType: CustomError.Type) -> [CustomError] {
        let allErrors = errors(subject)
        return  allErrors as? [CustomError] ?? []
    }

    public func groupedErrors<ErrorType, Field>(_ subject: S, by fieldSelector: (ErrorType) -> Field) -> [Field: [ErrorType]] {
        guard let fieldErrors = self.errors(subject) as? [ErrorType] else  {
            return [:]
        }

        return Dictionary.init(grouping: fieldErrors, by: fieldSelector)
    }

    // MARK: Composition

    /**
     Creates a new validator from caller and supplied validator

    Implementation of flatMap for Validator class.
    Will only run the provided validator if the caller succeeds

     - Parameter check: A validator to compose
     - Returns: A validators that either succeeds or fails with a single error.
     */

    public func andThen<O>(_ check: Validator<T, O>) -> Validator<S, O> {
        Validator<S, O> { input in
            self.validator(input).flatMap(check.validator)
        }
    }
    /**
     Chains a parallel validator to caller
     - Parameter merge: A function to merge or select the final output when both validation succeed.
     - Returns: A validator that will run the caller validation in parallel with the supplied validator.
     */
    public func add<T2, O>(_ validator: Validator<S, T2>, merge: @escaping (T, T2) -> O)
        -> Validator<S, O>
    {
        Validator<S, O> { input in
            let result1 = self.validator(input)
            let result2 = validator.verify(input)
            switch (result1, result2) {
            case (.success(let output1), .success(let output2)):
                let sum = merge(output1, output2)
                return .success(sum)
            case (.failure(let error1), .failure(let error2)):

                return .failure(ValidationErrors(fromList: error1.errors + error2.errors))
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
     Convert validator to a validator on optionals

     */
    public func optional() -> Validator<S?, T?> {
        Verify.optional(self)
    }

    /**
     Adds a check to the caller Validator

     - Parameter check: The predicate conforming the agregate validator.
     - Parameter otherwise: The error added to the error list of the caller.
     */
    public func addCheck(_ check: @escaping Predicate<S>, otherwise error: Error) -> Validator {
        self.add(Verify.property(check, otherwise: error), merge: { fst, snd in fst })
    }
    /**
     Chaings a validation created from the provided predicate to the caller.

     - Parameter predicate: The predicate to check
     - Returns: Validators that will run a sequential check when caller succeeds.
     */
    public func thenCheck(_ predicate: @escaping Predicate<S>, otherwise failure: Error)
        -> Validator
    {
        Validator<S, T> { input in
            let result = self.validator(input)
            return result.flatMap({
                predicate(input) ? .success($0) : Result.failure(ValidationErrors(failure))
            })
        }
    }

    /**
     Chains a validator that acts on a subfield of the current subject.

     - Parameter keyPath: The property keypath to focus on
     - Parameter check: The validator to apply

     - Returns: Validators that includes checks from caller and the validation on child property.

     */
    public func thenOn<F>(_ keyPath: KeyPath<S, F>, check validator: Validator_<F>) -> Validator_<S>
    {
        Validator<S, S> { (s: S) in
            let subfield = s[keyPath: keyPath]
            return validator.validator(subfield).map({ _ in s })
        }
    }
}

extension Validator where S == T {

    public func ignore(when predicate: @escaping Predicate<S>) -> Validator {
        Validator { input in
            if predicate(input) { return .success(input) }
            return self.validator(input)
        }
    }

}
// MARK: - Factories

public enum Verify<Subject> {
    public static func property(_ predicate: @escaping Predicate<Subject>, otherwise error: Error)
        -> Validator_<Subject>
    {
        Validator { subject in
            predicate(subject) ? .success(subject) : .failure(ValidationErrors(error))
        }
    }

    public static func at<F>(_ keyPath: KeyPath<Subject, F>, validator: Validator_<F>)
        -> Validator_<Subject>
    {
        Validator.lift({ $0 }).thenOn(keyPath, check: validator)
    }

    /**
     Creates a validator on optional from a validator

     Note will only runt the  provided  validator if  the input is Optional.some
     */
    public static func optional<T>(_ validator: Validator<Subject, T>) -> Validator<Subject?, T?> {
        Validator<Subject?, T?> { input in
            guard let value = input else {
                return .success(.none)
            }

            return validator.verify(value).map({ Optional.some($0) })
        }
    }

    /**
     Creates a validator composing the provided validators in a parallel way

     - Parameter validators: The list of validators to compose
     - Parameter merge: A function that can sum or select the final output of the resulting validator.
     */
    public static func all(_ validators: Validator_<Subject>..., merge: @escaping (Subject, Subject) -> Subject)
        -> Validator_<Subject>
    {
        composeAll(validators, merge: merge)
    }

    /**
     Create a Validator by composing the provided validators in a sequential fashion.

     - Parameter validators: The validators to compose
     - Returns: A validators the will either succeed or fails with exactly one error.
     */

    public static func inOrder(_ validators: Validator_<Subject>...) -> Validator_<Subject> {
        composeSequential(validators)
    }
    /**
     Creates a validator that always succeeds

     Const validator that ignores its input.

     - Parameter value: The value with which this validator should succeed.
     */
    public static func valid(_ value: Subject) -> Validator_<Subject> {
        Validator.lift({ _ in value })
    }

    /**
     Creates a validator that always fails with the provided error

     Will fail no matter what input is provided

     - Parameter error: The error to fail with

     - Returns: Validator
     */
    public static func error(_ error: Error) -> Validator_<Subject> {
        Validator { _ in .failure(ValidationErrors(error)) }
    }
}


// MARK: - Composition functions
func composeSequential<S>(_ validators: [Validator_<S>]) -> Validator_<S> {
    let initial = validators.first!
    let tail = validators.suffix(from: 1)
    return tail.reduce(initial, { acc, validator in acc.andThen(validator) })
}

func composeAll<S>(_ validators: [Validator_<S>], merge: @escaping (S, S) -> S) -> Validator_<S> {
    Validator<S, S> { input in
        let results = validators.map({ validator in validator.validator(input) })
        let failure = results.compactMap({ $0.getFailure() })
            .reduce(
                ValidationErrors(fromList: []),
                { acc, errors in
                    ValidationErrors(fromList: acc.errors + errors.errors)
                })

        let succeeds = results.compactMap({ try? $0.get() })

        if failure.errors.count > 0 {
            return .failure(failure)
        }

        let tail = succeeds.suffix(from: 1)
        let state = tail.reduce(succeeds.first!, merge)

        return .success(state)
    }
}
