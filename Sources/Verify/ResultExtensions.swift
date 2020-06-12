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
        case .failure(_):
            return true
        case .success(_):
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
        case .success(_):
            return nil
        }
    }
}

extension Result where Failure == [Error] {
    var errorCount: Int {
        getFailure()?.count ?? 0
    }

    var failures: [Error] {
        switch self {
        case .failure(let fail):
            return fail
        case .success(_):
            return []
        }
    }
}
