//
//  File.swift
//  
//
//  Created by Daniel Cardona Rojas on 12/06/20.
//

import Foundation
extension Verify where Subject == Int {
    public static func greaterThenZero(otherwise error: Error) -> Validator_<Subject> {
        Verify<Int>.property({ $0  >  0}, otherwise: error)
    }
}


extension Verify where Subject == String {
    public static func property(_ predicate: @escaping Predicate<Subject>, otherwise error: Error)
        -> Validator_<Subject>
    {
        Validator { subject in
            predicate(subject) ? .success(subject) : .failure(ValidationErrors(error))
        }
    }
    /**
     Create a validator on String testing its length to be greater or equal to a value.

     - Parameter value: Integer representing the minimum length this string should have
     - Parameter error: The error in case length criteria not fulfilled.
     */
    public static func minLength(_ value: Int, otherwise error: Error) -> Validator_<Subject> {
        Verify.property({ (string: String) in string.count >= value }, otherwise: error)
    }

    /**
     Create a validator on String testing its length to be less than or equal to a value.

     - Parameter value: Integer representing the minimum length this string should have
     - Parameter error: The error in case length criteria not fulfilled.
     */
    public static func maxLength(_ value: Int, otherwise error: Error) -> Validator_<Subject> {
        Verify.property({ (string: String) in string.count <= value }, otherwise: error)
    }

    /**
     Creates a validator that ensures no overlap between the tested string and the provided
     CharacterSet

     - Parameter set: Character set to test the string against
     - Parameter error: The error in case the string is not disjoint with the set.
     */
    public static func dissallowedCharacterSet(_ set: CharacterSet, otherwise error: Error)
        -> Validator_<Subject>
    {
        Verify.property(
            { (string: String) in
                CharacterSet(charactersIn: string).isDisjoint(with: set)
            }, otherwise: error)
    }

    /**
     Creates a validator that ensures input is a subset of the provided CharacterSet.

     - Parameter set: Character set to test the string against
     - Parameter error: The error in case the string is not disjoint with the set.
     */
    public static func fromCharacterSet(_ set: CharacterSet, otherwise error: Error) -> Validator_<
        Subject
    > {
        Verify.property(
            { (string: String) in
                CharacterSet(charactersIn: string).isSubset(of: set)
            }, otherwise: error)
    }

    /**
     Creates a validator that ensures input is a subset of the provided CharacterSet.

     - Parameter set: Character set to test the string against
     - Parameter error: The error in case the string is not disjoint with the set.
     */
    public static func containsSomeOf(_ set: CharacterSet, otherwise error: Error) -> Validator_<
        Subject
        > {
            Verify.property(
                { (string: String) in
                    !CharacterSet(charactersIn: string).isDisjoint(with: set)
            }, otherwise: error)
    }
    /**
     Creates a validator from a regular expression

     Note the regex should have exactly one match and it should be over the range of
     the complete string.

     - Parameter regex: Regular expression to test the string against.
     - Parameter error: Failure to if string does not match.

     */
    public static func matchesRegex(_ regex: NSRegularExpression, otherwise error: Error)
        -> Validator_<Subject>
    {
        Verify.property(
            { (string: String) in
                let matches = regex.numberOfMatches(
                    in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)
                )
                return matches == 1
            }, otherwise: error)

    }
}
