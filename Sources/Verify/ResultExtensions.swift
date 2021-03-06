//
//  File.swift
//  
//
//  Created by Daniel Cardona Rojas on 11/06/20.
//

import Foundation

extension Result {

    var isFailure: Bool {
        switch self {
        case .failure:
            return true
        case .success:
            return false
        }
    }

    var isSuccess: Bool {
        !isFailure
    }

    func withDefault(_ value: Success) -> Success {
        (try? self.get()) ?? value
    }

    static func ??(_ lhs: Result, _ rhs: Success) -> Success {
        return lhs.withDefault(rhs)
    }

    func getFailure() -> Failure? {
        switch self {
        case .failure(let fail):
            return fail
        case .success:
            return nil
        }
    }
}

extension Result where Failure == ValidationErrors {
    var errorCount: Int {
        getFailure()?.errors.count ?? 0
    }

    var failures: [Error] {
        switch self {
        case .failure(let fail):
            return fail.errors
        case .success:
            return []
        }
    }
}
