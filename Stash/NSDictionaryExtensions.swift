//
//  NSDictionaryExtensions.swift
//  Stash
//
//  Created by Daniel Tomlinson on 16/12/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

extension Dictionary {
    @warn_unused_result func keysSortedByValues(@noescape comparator: (Value, Value) -> Bool) -> [Key] {
        return lazy.sort { comparator($0.0.1, $0.1.1) }.map { $0.0 }
    }
}
