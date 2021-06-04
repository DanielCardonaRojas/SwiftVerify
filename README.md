# SwiftVerify

![Swift Tests](https://github.com/DanielCardonaRojas/SwiftVerify/workflows/Swift%20Tests/badge.svg)
![GitHub release](https://img.shields.io/github/v/tag/DanielCardonaRojas/SwiftVerify)
[![codecov](https://codecov.io/gh/DanielCardonaRojas/SwiftVerify/branch/master/graph/badge.svg?token=9MK1R8PV24)](https://codecov.io/gh/DanielCardonaRojas/SwiftVerify)

A flexible state validation solution.

## Features

- Function builder composition API
- Easy composition of small validators into more complex ones.
- Easily extensible
- Documented [here](https://danielcardonarojas.github.io/SwiftVerify)

## Usage

### Creating validators

**Create simple validators from predicates**

```swift
let validateEmail = Verify<String>.that({ $0.contains("@") }, otherwise: .myError)
```

### Extend and reuse validators

You can easily create validators on any type via extensions:

```swift
extension Verify where Subject == Int {
    public static func greaterThanZero(otherwise error: Error) -> Validator_<Subject> {
        Verify<Int>.that({ $0  >  0}, otherwise: error)
    }
}

extension Verify where Subject == String {
    public static func minLength(_ value: Int, otherwise error: Error) -> Validator_<Subject> {
    Verify.that({ (string: String) in string.count >= value }, otherwise: error)
    }
}
```

Having created these extensions they will become avaiable like this:

```swift
Verify<String>.minLength(10, otherwise: .myError)
Verify<Int>.greaterThanZero(otherwise: .myOtherError)
```

### Composition

Verify has two flavors of composition, a senquenced or in order composition, or a parallel composition.

**Sequenced composition**

In sequence composition only one a validator is ran at a time and will accumulate
at most one error since the next validator in the chain will only
be applied when the previous succeeds.

```swift
let emailValidator = Verify<String>.inOrder {
    Verify.that({ $0.contains("@")}, otherwise: invalidEmail)
    Verify.minLength(5, otherwise: invalidEmail)
}

let input = "1"
emailValidator.errors(input).count == 1
```

Notice that even the input "1" fails both the validations only one error will be accumulated.
This is usually the desired behavour since we want to validate one condition at a time.

Also can be written as:

```swift
let emailValidator = Verify<String>
    .that({ $0.contains("@")}, otherwise: invalidEmail)
    .andThat({ $0.count >= 5}, otherwise: invalidEmail)

let input = "1"
emailValidator.errors(input).count == 1
```

**Parallel composition**

In parallel composition we run all validators at once and accumulate all errors.

```swift
let emailValidator = Verify<String>.atOnce {
    Verify.that({ $0.contains("@")}, otherwise: invalidEmail)
    Verify.minLength(5, otherwise: invalidEmail)
}

let input = "1"
emailValidator.errors(input).count == 2
```

The previous example will acumulate both errors.

### Cheat sheet

**Factories**

| Method       |                    Signature                    | Description                               |
| :----------- | :---------------------------------------------: | :---------------------------------------- |
| Verify.that  |        `(Predicate<S>) -> Validator<S>`         | Validates with predicate                  |
| Verify.at    | `(KeyPath<S, P>, Predicate<P>) -> Validator<S>` | Validates the property focused by keypath |
| Verify.error |            `(Error) -> Validator<S>`            | Always fails with specified error         |

**Composition**

| Method              |            Signature             | Accumulates errors |
| :------------------ | :------------------------------: | :----------------: |
| andThen             | `(Validator<S>) -> Validator<S>` |         No         |
| andThat / thenCheck |    `(Predicate) -> Validator`    |         No         |
| add                 | `(Validator<S>) -> Validator<S>` |        Yes         |
| addCheck            | `(Predicate<S>) -> Validator<S>` |        Yes         |

**Utilities**

| Method |            Signature             | Description                                             |
| :----- | :------------------------------: | :------------------------------------------------------ |
| ignore | `(Predicate<S>) -> Validator<S>` | Bypass validator when the provided predicate holds true |

## Examples

### Field validations

Given a model, for instance a UserRegistration struct:

```swift
struct UserRegistration {
    let email: String
    let password: String
    let passwordConfirmation: String
}
```

we can apply validation to specific properties with keypaths.

```swift
let invalidEmail = UserRegistrationError.invalidEmail
let invalidPassword = UserRegistrationError.invalidPassword

let emailValidator = Verify<String>.inOrder {
    Verify.minLength(5, otherwise: invalidEmail)
    Verify.that({ $0.contains("@")}, otherwise: invalidEmail)
}

let password = Verify<String>.inOrder {
    Verify<String>.that({ $0.count > 5}, otherwise: invalidPassword)
    Verify.containsSomeOf(CharacterSet.symbols, otherwise: invalidPassword)
}

let registrationValidator = Verify<UserRegistration>.atOnce {
    Verify<UserRegistration>.at(\.email, validator: emailValidator)
    Verify<UserRegistration>.at(\.password, validator: password)
    Verify<UserRegistration>.that({ $0.password == $0.passwordConfirmation  }, otherwise: UserRegistrationError.passwordsDontMatch)
}

let errors = registrationValidator.errors(UserRegistration(email: "", password: "19d", passwordConfirmation: "12d"))

```

### Run a validator

Running a validator is a simple as passing in a parameter since its just a function.
To be a bit more eloquent a `verify` method is provided, this method is special because besides
forwarding the argument to the calling validator it can also be used to filter the error list and
have it cast to a specific error type. Just supply a specific type parameter.

### Form validation

Often times you will have modeled your error type similar to:

```swift
struct FormError<FieldType>: Error {
    enum Reason {
        case invalidFormat, required
    }

    let reason: Reason
    let field:  FieldType
}

enum LoginField {
    case email, password
}
```

In these scenarios its convenient to be able to group errors by field.

```swift
typealias LoginFormError = FormError<LoginField>

let validator = Verify<Int>.atOnce {
    Verify<Int>.error(LoginFormError(reason: .invalidFormat, field: .email))
    Verify<Int>.error(LoginFormError(reason: .required, field: .password))
}

let groupedErrors: [LoginField: [LoginFormError]] = validator.groupedErrors(0, by: { (error:  LoginFormError) in error.field })

//  Or even

let fieldErrors: [LoginField: [LoginFormError.Reason]] = groupedErrors.mapValues({  $0.map({ $0.reason })})
```
