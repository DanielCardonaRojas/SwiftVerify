# SwiftVerify

![Swift Tests](https://github.com/DanielCardonaRojas/SwiftVerify/workflows/Swift%20Tests/badge.svg)
![GitHub release](https://img.shields.io/github/v/tag/DanielCardonaRojas/SwiftVerify)

A flexible state validation solution.


## Features

- Function builder composition API
- Easy composition of small validators into more complex ones.

## Usage

### Creating validators

**Create simple validators from predicates**

```swift
let validateEmail = Verify<String>.property({ $0.contains("@") }, otherwise: .myError)
```

A simpler way is to use some of the built in helpers.

```swift
```

### Easily extensible

You can easily create validators on any type via extensions: 

```swift
extension Validate where Subject == Int {
    public static func greaterThenZero(otherwise error: Error) -> Validator_<Subject> {
        Verify<Int>.property({ $0  >  0}, otherwise: error)
    }
}

extension Validate where Subject == String {
    public static func minLength(_ value: Int, otherwise error: Error) -> Validator_<Subject> {
    Validate.property({ (string: String) in string.count >= value }, otherwise: error)
    }
}
```

Having created these extensions they will become avaiable like this: 

```swift
Verify<String>.minLength(10, otherwise: .myError)
Verify<Int>.greaterThenZero(otherwise: .myOtherError)
```

### Composition

Verify has to flavors of composition, a senquenced or in order composition, or an eager / parallel composition.

**Sequenced composition**

```swift
let emailValidator = Verify<String>.inSequence {
    Validate.property({ $0.contains("@")}, otherwise: invalidEmail)
    Validate.minLength(5, otherwise: invalidEmail)
}

let input = "1"
emailValidator.errors(input).count == 1
```

Notice that even the input "1" fails both the validations only one error will be accumulated.
This is usually the desired behavour  since we want to validate one condition at a time.

**Parallel composition**

```swift
let emailValidator = Verify<String>.atOnce {
    Validate.property({ $0.contains("@")}, otherwise: invalidEmail)
    Validate.minLength(5, otherwise: invalidEmail)
}

let input = "1"
emailValidator.errors(input).count == 2
```

The  previous example will acumulate both errors.

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

let emailValidator = Verify<String>.inSequence {
    Validate.minLength(5, otherwise: invalidEmail)
    Validate.property({ $0.contains("@")}, otherwise: invalidEmail)
}

let password = Verify<String>.inSequence {
    Verify<String>.property({ $0.count > 5}, otherwise: invalidPassword)
    Validate.containsSomeOf(CharacterSet.symbols, otherwise: invalidPassword)
}

let registrationValidator = Verify<UserRegistration>.atOnce {
    Verify<UserRegistration>.at(\.email, validator: emailValidator)
    Verify<UserRegistration>.at(\.password, validator: password)
    Verify<UserRegistration>.property({ $0.password == $0.passwordConfirmation  }, otherwise: UserRegistrationError.passwordsDontMatch)
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



