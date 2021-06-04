import Foundation

/// Underlying function signature for validators that can transform the validated subject type
public typealias ValidationT<S, T> = (S) -> Result<T, ValidationErrors>

/// Underlying function signature for validators
public typealias Validation<S> = (S) -> Result<S, ValidationErrors>

/// Function signature for predicates on validated subject types
public typealias Predicate<S> = (S) -> Bool


public typealias Validator<S> = ValidatorT<S, S>

/// A class representing validations that can fail with one or multiple errors
/// and can transforma data in the process.
public class ValidatorT<S, T> {
    let validator: ValidationT<S, T>

    public init(_ validation: @escaping ValidationT<S, T>) {
        self.validator = validation
    }

    public func callAsFunction(_ subject: S) -> Result<T, ValidationErrors> {
        validator(subject)
    }

    /**
     Creates a validator that always succeeds

     List a pure function into the context of a Validator.

     - Parameter value: The value with which this validator should succeed.
     */
    public static func lift(_ function: @escaping (S) -> T) -> ValidatorT {
        ValidatorT { input in
            .success(function(input))
        }
    }

    /**
     Transforms the output of the validator i.e the subject/state being
     validated.

     - Parameter transform: A function that can transform the resulting ouput of the validator.
     - Returns: A validator with the same validation logic of caller but with a potentially different output type and value.
     */
    public func map<O>(_ transform: @escaping (T) -> O) -> ValidatorT<S, O> {
        ValidatorT<S, O> { input in
            let result = self.validator(input)
            return result.map(transform)
        }
    }

    // MARK: Utilities

    /// Calls the validator with a provided subject
    public func verify(_ subject: S) -> Result<T, ValidationErrors> {
        return self.validator(subject)
    }

    /// Runs the validator and collects errors
    public func errors(_ subject: S) -> [Error] {
        return self.validator(subject).failures
    }

    /// Runs the validator collecting errors of specific type
    public func errors<CustomError: Error>(_ subject: S, errorType: CustomError.Type) -> [CustomError] {
        let allErrors = errors(subject)
        return  allErrors as? [CustomError] ?? []
    }

    /**
        Runs the validator and collects error, such that they are arranged by a field type. This is useful for forms
     
            - Parameter fieldSelector: A function that will convert an error to a specific field
     */
    public func groupedErrors<ErrorType, Field>(_ subject: S, by fieldSelector: (ErrorType) -> Field) -> [Field: [ErrorType]] {
        guard let fieldErrors = self.errors(subject) as? [ErrorType] else {
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

    public func andThen<O>(_ check: ValidatorT<T, O>) -> ValidatorT<S, O> {
        ValidatorT<S, O> { input in
            self.validator(input).flatMap(check.validator)
        }
    }
    /**
     Chains a parallel validator to caller
     - Parameter merge: A function to merge or select the final output when both validation succeed.
     - Returns: A validator that will run the caller validation in parallel with the supplied validator.
     */
    public func add<T2, O>(_ validator: ValidatorT<S, T2>, merge: @escaping (T, T2) -> O)
        -> ValidatorT<S, O> {
        ValidatorT<S, O> { input in
            let result1 = self.validator(input)
            let result2 = validator.verify(input)
            switch (result1, result2) {
            case (.success(let output1), .success(let output2)):
                let sum = merge(output1, output2)
                return .success(sum)
            case (.failure(let error1), .failure(let error2)):

                return .failure(ValidationErrors(fromList: error1.errors + error2.errors))
            case (.success, .failure(let error2)):
                return .failure(error2)
            case (.failure(let error1), .success):
                return .failure(error1)
            }
        }
    }

}

// MARK: Utilities
extension ValidatorT {

    /**
     Convert validator to a validator on optionals

     */
    public func optional() -> ValidatorT<S?, T?> {
        Verify.optional(self)
    }

    /**
     Adds a check to the caller Validator

     - Parameter check: The predicate conforming the agregate validator.
     - Parameter otherwise: The error added to the error list of the caller.
     */
    public func addCheck(_ check: @escaping Predicate<S>, otherwise error: Error) -> ValidatorT {
        add(Verify.that(check, otherwise: error), merge: { fst, _ in fst })
    }

    /**
       Chains a validator created from a predicate
     
        Note the validator will only run after the current validator succeeds
     
        - Parameter predicate: A predicate to test when the calling validator succeeds
        - Parameter failure: The error associated with this validator
     
     This is a shorthand for `andThen(Verify.that(...))`
     
     */
    public func andThat(_ predicate: @escaping Predicate<S>, otherwise failure: Error) -> ValidatorT {
        ValidatorT<S, T> { input in
            let result = self.validator(input)
            return result.flatMap({
                predicate(input) ? .success($0) : Result.failure(ValidationErrors(failure))
            })
        }
    }

    /**
     Chaings a validation created from the provided predicate to the caller.

     - Parameter predicate: The predicate to check
     - Returns: Validators that will run a sequential check when the caller succeeds.
     */
    public func thenCheck(_ predicate: @escaping Predicate<S>, otherwise failure: Error)
        -> ValidatorT {
        ValidatorT<S, T> { input in
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
    public func thenOn<F>(_ keyPath: KeyPath<S, F>, check validator: Validator<F>) -> Validator<S> {
        ValidatorT<S, S> { (s: S) in
            let subfield = s[keyPath: keyPath]
            return validator.validator(subfield).map({ _ in s })
        }
    }
}

// MARK: - Validator methods
extension ValidatorT where S == T {

    /**
     Bypass the validator when a certain condition holds true
     
     - Parameter predicate: A predicate determining if should bypass or not
     */
    public func ignore(when predicate: @escaping Predicate<S>) -> ValidatorT {
        ValidatorT { input in
            if predicate(input) { return .success(input) }
            return self.validator(input)
        }
    }

}
// MARK: - Factories

public enum Verify<Subject> {

    /**
     Create a Validator from a predicate
     
     ```
     e.g Verify<String>.that({ !$0.isEmpty }, otherwise: .requiredField)
     or  Verify.that({ (String input) in !input.isEmpty }, otherwise: .requiredField)
     ```
     */
    public static func that(_ predicate: @escaping Predicate<Subject>, otherwise error: Error)
        -> Validator<Subject> {
        ValidatorT { subject in
            predicate(subject) ? .success(subject) : .failure(ValidationErrors(error))
        }
    }

    /**
         Create a validator that acts on a specific property of the validated subject. Useful for validating structs and other composite types.
     
     - Parameter keyPath: A keypath selecting the property or attribue of the subject.
     */
    public static func at<F>(_ keyPath: KeyPath<Subject, F>, validator: Validator<F>)
        -> Validator<Subject> {
        ValidatorT.lift({ $0 }).thenOn(keyPath, check: validator)
    }

    /**
     Creates a validator on optional from a validator

     Note will only run the  provided  validator if  the input is Optional.some
     */
    public static func optional<T>(_ validator: ValidatorT<Subject, T>) -> ValidatorT<Subject?, T?> {
        ValidatorT<Subject?, T?> { input in
            guard let value = input else {
                return .success(.none)
            }

            return validator.verify(value).map({ Optional.some($0) })
        }
    }

    // MARK: Main composing functions

    /**
     Creates a validator composing the provided validators in a parallel way

     - Parameter validators: The list of validators to compose
     - Parameter merge: A function that can sum or select the final output of the resulting validator.
     
         Note: Tipically subjects won't be mutated of transformed in validating functions so output will be the same.
     */
    public static func atOnce(_ validators: Validator<Subject>..., merge: ((Subject, Subject) -> Subject)? = nil)
        -> Validator<Subject> {
        composeAll(validators, merge: merge ?? { fst, _ in fst })
    }

    /**
     Creates a validator composing the provided validators in a parallel way

     - Parameter validators: The list of validators to compose
     - Parameter merge: A function that can sum or select the final output of the resulting validator.
     
         Note: Tipically subjects won't be mutated of transformed in validating functions so output will be the same.
     */
    public static func atOnce(@ValidationParallelBuilder<Subject> _ content: () -> Validator<Subject>)
    -> Validator<Subject> {
        content()
    }

    /**
     Create a Validator by composing the provided validators in a sequential fashion.

     - Parameter validators: The validators to compose
     - Returns: A validators the will either succeed or fails with exactly one error.
     */

    public static func inOrder(_ validators: Validator<Subject>...) -> Validator<Subject> {
        composeSequential(validators)
    }

    /**
     Create a Validator by composing the provided validators in a sequential fashion.
     
        Note: This is essential the same as `inOrder` but using a function builder and not having to
        seperate items by commas.

     - Parameter content: The function builder body
     - Returns: A validators the will either succeed or fails with exactly one error.
     */
    public static func inOrder(@ValidationSequencedBuilder<Subject> _ content: () -> Validator<Subject>)
    -> Validator<Subject> {
        content()
    }

    // MARK: Constant validators
    /**
     Creates a validator that always succeeds

     Const validator that ignores its input.

     - Parameter value: The value with which this validator should succeed.
     */
    public static func valid(_ value: Subject) -> Validator<Subject> {
        ValidatorT.lift({ _ in value })
    }

    /**
     Creates a validator that always fails with the provided error

     Will fail no matter what input is provided

     - Parameter error: The error to fail with

     - Returns: Validator
     */
    public static func error(_ error: Error) -> Validator<Subject> {
        ValidatorT { _ in .failure(ValidationErrors(error)) }
    }
}

// MARK: - Composition functions
func composeSequential<S>(_ validators: [Validator<S>]) -> Validator<S> {
    let initial = validators.first!
    let tail = validators.suffix(from: 1)
    return tail.reduce(initial, { acc, validator in acc.andThen(validator) })
}

func composeAll<S>(_ validators: [Validator<S>], merge: @escaping (S, S) -> S) -> Validator<S> {
    ValidatorT<S, S> { input in
        let results = validators.map({ validator in validator.validator(input) })
        let failure = results.compactMap({ $0.getFailure() })
            .reduce(
                ValidationErrors(fromList: []), { acc, errors in
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

// MARK: - Function Builders
/// A validation function builder
@_functionBuilder
public struct ValidationSequencedBuilder<Subject> {
    public static func buildBlock(_ validators: Validator<Subject>...) -> Validator<Subject> {
        composeSequential(validators)
    }
}

@_functionBuilder
public struct ValidationParallelBuilder<Subject> {

    public static func buildBlock(_ validators: Validator<Subject>...) -> Validator<Subject> {
        composeAll(validators, merge: { fst, _ in fst })
    }
}

// MARK: - ValidationErrors

/// Represents the list of errors of a validation
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
