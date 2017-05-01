//
//  BigInt.swift
//  NumberKit
//
//  Created by Matthias Zenger on 12/08/2015.
//  Copyright © 2015-2017 Matthias Zenger. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Darwin


/// Class `BigInt` implements signed, arbitrary-precision integers. `BigInt` objects
/// are immutable, i.e. all operations on `BigInt` objects return result objects.
/// `BigInt` provides all the signed, integer arithmetic operations from Swift and
/// implements the corresponding protocols. To make it easier to define large `BigInt`
/// literals, `String` objects can be used for representing such numbers. They get
/// implicitly coerced into `BigInt`.
///
/// - Note: `BigInt` is internally implemented as a Swift array of UInt32 numbers
///         and a boolean to represent the sign. Due to this overhead, for instance,
///         representing a `UInt64` value as a `BigInt` will result in an object that
///         requires more memory than the corresponding `UInt64` integer.
public struct BigInt: Hashable,
                      CustomStringConvertible,
                      CustomDebugStringConvertible {
  
  // This is an array of `UInt32` words. The lowest significant word comes first in
  // the array.
  internal let words: [UInt32]
  
  // `negative` signals whether the number is positive or negative.
  internal let negative: Bool
  
  // All internal computations are based on 32-bit words; the base of this representation
  // is therefore `UInt32.max + 1`.
  private static let base: UInt64 = UInt64(UInt32.max) + 1
  
  // `hiword` extracts the highest 32-bit value of a `UInt64`.
  private static func hiword(_ num: UInt64) -> UInt32 {
    return UInt32((num >> 32) & 0xffffffff)
  }
  
  // `loword` extracts the lowest 32-bit value of a `UInt64`.
  private static func loword(_ num: UInt64) -> UInt32 {
    return UInt32(num & 0xffffffff)
  }
  
  // `joinwords` combines two words into a `UInt64` value.
  private static func joinwords(_ lword: UInt32, _ hword: UInt32) -> UInt64 {
    return (UInt64(hword) << 32) + UInt64(lword)
  }
  
  /// Class `Base` defines a representation and type for the base used in computing
  /// `String` representations of `BigInt` objects.
  ///
  /// - Note: It is currently not possible to define custom `Base` objects. It needs
  ///         to be figured out first what safety checks need to be put in place.
  public final class Base {
    fileprivate let digitSpace: [Character]
    fileprivate let digitMap: [Character: UInt8]
    
    fileprivate init(digitSpace: [Character], digitMap: [Character: UInt8]) {
      self.digitSpace = digitSpace
      self.digitMap = digitMap
    }
    
    fileprivate var radix: Int {
      return self.digitSpace.count
    }
  }
  
  /// Representing base 2 (binary)
  public static let binBase = Base(
    digitSpace: ["0", "1"],
    digitMap: ["0": 0, "1": 1]
  )
  
  /// Representing base 8 (octal)
  public static let octBase = Base(
    digitSpace: ["0", "1", "2", "3", "4", "5", "6", "7"],
    digitMap: ["0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7]
  )
  
  /// Representing base 10 (decimal)
  public static let decBase = Base(
    digitSpace: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
    digitMap: ["0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9]
  )
  
  /// Representing base 16 (hex)
  public static let hexBase = Base(
    digitSpace: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"],
    digitMap: ["0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
      "A": 10, "B": 11, "C": 12, "D": 13, "E": 14, "F": 15]
  )
  
  /// Maps a radix number to the corresponding `Base` object. Only 2, 8, 10, and 16 are
  /// supported.
  public static func base(of radix: Int) -> Base {
    switch radix {
      case 2:
        return BigInt.binBase
      case 8:
        return BigInt.octBase
      case 10:
        return BigInt.decBase
      case 16:
        return BigInt.hexBase
      default:
        preconditionFailure("unsupported base \(radix)")
    }
  }
  
  /// Internal primary constructor. It removes superfluous words and normalizes the
  /// representation of zero.
  internal init(words: [UInt32], negative: Bool) {
    var words = words
    while words.count > 1 && words[words.count - 1] == 0 {
      words.removeLast()
    }
    self.words = words
    self.negative = words.count == 1 && words[0] == 0 ? false : negative
  }
  
  private static let int64Max = UInt64(Int64.max)
  
  /// Creates a `BigInt` from the given `UInt64` value
  public init(_ value: UInt64) {
    self.init(words: [BigInt.loword(value), BigInt.hiword(value)], negative: false)
  }
  
  /// Creates a `BigInt` from the given `Int64` value
  public init(_ value: Int64) {
    let absvalue = value == Int64.min ? BigInt.int64Max + 1 : UInt64(value < 0 ? -value : value)
    self.init(words: [BigInt.loword(absvalue), BigInt.hiword(absvalue)], negative: value < 0)
  }
  
  /// Creates a `BigInt` from a sequence of digits for a given base. The first digit in the
  /// array of digits is the least significant one. `negative` is used to indicate negative
  /// `BigInt` numbers.
  public init(digits: [UInt8], negative: Bool = false, base: Base = BigInt.decBase) {
    var digits = digits
    var words: [UInt32] = []
    var iterate: Bool
    repeat {
      var sum: UInt64 = 0
      var res: [UInt8] = []
      var j = 0
      while j < digits.count && sum < BigInt.base {
        sum = sum * UInt64(base.radix) + UInt64(digits[j])
        j += 1
      }
      res.append(UInt8(BigInt.hiword(sum)))
      iterate = BigInt.hiword(sum) > 0
      sum = UInt64(BigInt.loword(sum))
      while j < digits.count {
        sum = sum * UInt64(base.radix) + UInt64(digits[j])
        j += 1
        res.append(UInt8(BigInt.hiword(sum)))
        iterate = true
        sum = UInt64(BigInt.loword(sum))
      }
      words.append(BigInt.loword(sum))
      digits = res
    } while iterate
    self.init(words: words, negative: negative)
  }
  
  /// Creates a `BigInt` from a string containing a number using the given base.
  public init?(from str: String, base: Base = BigInt.decBase) {
    var negative = false
    let chars = str.characters
    var i = chars.startIndex
    while i < chars.endIndex && chars[i] == " " {
      i = chars.index(after: i)
    }
    if i < chars.endIndex {
      if chars[i] == "-" {
        negative = true
        i = chars.index(after: i)
      } else if chars[i] == "+" {
        i = chars.index(after: i)
      }
    }
    if i < chars.endIndex && chars[i] == "0" {
      while i < chars.endIndex && chars[i] == "0" {
        i = chars.index(after: i)
      }
      if i == chars.endIndex {
        self.init(0)
        return
      }
    }
    var temp: [UInt8] = []
    while i < chars.endIndex {
      if let digit = base.digitMap[chars[i]] {
        temp.append(digit)
        i = chars.index(after: i)
      } else {
        break
      }
    }
    while i < chars.endIndex && chars[i] == " " {
      i = chars.index(after: i)
    }
    guard i == chars.endIndex else {
      return nil
    }
    self.init(digits: temp, negative: negative, base: base)
  }
  
  /// Converts the `BigInt` object into a string using the given base. `BigInt.DEC` is
  /// used as the default base.
  public func toString(base: Base = BigInt.decBase) -> String {
    // Determine base
    let radix = base.radix
    // Shortcut handling of zero
    if isZero {
      return "0"
    }
    var radixPow: UInt32 = 1
    var digits = 0
    while true {
      let (pow, overflow) = UInt32.multiplyWithOverflow(radixPow, UInt32(radix))
      if !overflow || pow == 0 {
        digits += 1
        radixPow = pow
      }
      if overflow {
        break
      }
    }
    var res = ""
    if radixPow == 0 {
      for i in words.indices.dropLast() {
        BigInt.toString(words[i], prepend: &res, length: digits, base: base)
      }
      BigInt.toString(words.last!, prepend: &res, length: 0, base: base)
    } else {
      var words = self.words
      while words.count > 0 {
        var rem: UInt32 = 0
        for i in words.indices.reversed() {
          let x = BigInt.joinwords(words[i], rem)
          words[i] = UInt32(x / UInt64(radixPow))
          rem = UInt32(x % UInt64(radixPow))
        }
        while words.last == 0 {
          words.removeLast()
        }
        BigInt.toString(rem, prepend: &res, length: words.count > 0 ? digits : 0, base: base)
      }
    }
    if negative {
      res.insert(Character("-"), at: res.startIndex)
    }
    return res
  }
  
  /// Prepends a string representation of `word` to string `prepend` for the given base.
  /// `length` determines the least amount of characters. "0" is used for padding purposes.
  private static func toString(_ word: UInt32, prepend: inout String, length: Int, base: Base) {
    let radix = base.radix
    var (value, n) = (Int(word), 0)
    while n < length || value > 0 {
      prepend.insert(base.digitSpace[value % radix], at: prepend.startIndex)
      value /= radix
      n += 1
    }
  }
  
  /// Returns a string representation of this `BigInt` number using base 10.
  public var description: String {
    return toString()
  }
  
  /// Returns a string representation of this `BigInt` number for debugging purposes.
  public var debugDescription: String {
    var res = "{\(words.count): \(words[0])"
    for i in 1..<words.count {
      res += ", \(words[i])"
    }
    return res + "}"
  }

  /// Returns the `BigInt` as a `Int64` value if this is possible. If the number is outside
  /// the `Int64` range, the property will contain `nil`.
  public var intValue: Int64? {
    guard words.count <= 2 else {
      return nil
    }
    var value: UInt64 = UInt64(words[0])
    if words.count == 2 {
      value += UInt64(words[1]) * BigInt.base
    }
    if negative && value == BigInt.int64Max + 1 {
      return Int64.min
    }
    if value <= BigInt.int64Max {
      return negative ? -Int64(value) : Int64(value)
    }
    return nil
  }
  
  /// Returns the `BigInt` as a `UInt64` value if this is possible. If the number is outside
  /// the `UInt64` range, the property will contain `nil`.
  public var uintValue: UInt64? {
    guard words.count <= 2 && !negative else {
      return nil
    }
    var value: UInt64 = UInt64(words[0])
    if words.count == 2 {
      value += UInt64(words[1]) * BigInt.base
    }
    return value
  }
  
  /// Returns the `BigInt` as a `Double` value. This might lead to a significant loss of
  /// precision, but this operation is always possible.
  public var doubleValue: Double {
    var res: Double = 0.0
    for word in words.reversed() {
      res = res * Double(BigInt.base) + Double(word)
    }
    return self.negative ? -res : res
  }
  
  /// The hash value of this `BigInt` object.
  public var hashValue: Int {
    var hash: Int = 0
    for i in 0..<words.count {
      hash = (31 &* hash) &+ words[i].hashValue
    }
    return hash
  }
  
  /// Returns true if this `BigInt` is negative.
  public var isNegative: Bool {
    return negative
  }
  
  /// Returns true if this `BigInt` represents zero.
  public var isZero: Bool {
    return self.words.count == 1 && self.words[0] == 0
  }
  
  /// Returns true if this `BigInt` represents one.
  public var isOne: Bool {
    return self.words.count == 1 && self.words[0] == 1 && !self.negative
  }
  
  /// Returns a `BigInt` with swapped sign.
  public var negate: BigInt {
    return BigInt(words: words, negative: !negative)
  }
  
  /// Returns the absolute value of this `BigInt`.
  public var abs: BigInt {
    return BigInt(words: words, negative: false)
  }
  
  /// Returns -1 if `self` is less than `rhs`,
  ///          0 if `self` is equals to `rhs`,
  ///         +1 if `self` is greater than `rhs`
  public func compare(to rhs: BigInt) -> Int {
    guard self.negative == rhs.negative else {
      return self.negative ? -1 : 1
    }
    return self.negative ? rhs.compareDigits(with: self) : compareDigits(with: rhs)
  }
  
  private func compareDigits(with rhs: BigInt) -> Int {
    guard words.count == rhs.words.count else {
      return words.count < rhs.words.count ? -1 : 1
    }
    for i in 1...words.count {
      let a = words[words.count - i]
      let b = rhs.words[words.count - i]
      if a != b {
        return a < b ? -1 : 1
      }
    }
    return 0
  }
  
  /// Returns the sum of `self` and `rhs` as a `BigInt`.
  public func plus(_ rhs: BigInt) -> BigInt {
    guard self.negative == rhs.negative else {
      return self.minus(rhs.negate)
    }
    let (b1, b2) = self.words.count < rhs.words.count ? (rhs, self) : (self, rhs)
    var res = [UInt32]()
    res.reserveCapacity(b1.words.count)
    var sum: UInt64 = 0
    for i in 0..<b2.words.count {
      sum += UInt64(b1.words[i])
      sum += UInt64(b2.words[i])
      res.append(BigInt.loword(sum))
      sum = UInt64(BigInt.hiword(sum))
    }
    for i in b2.words.count..<b1.words.count {
      sum += UInt64(b1.words[i])
      res.append(BigInt.loword(sum))
      sum = UInt64(BigInt.hiword(sum))
    }
    if sum > 0 {
      res.append(BigInt.loword(sum))
    }
    return BigInt(words: res, negative: self.negative)
  }
  
  /// Returns the difference between `self` and `rhs` as a `BigInt`.
  public func minus(_ rhs: BigInt) -> BigInt {
    guard self.negative == rhs.negative else {
      return self.plus(rhs.negate)
    }
    let cmp = compareDigits(with: rhs)
    guard cmp != 0 else {
      return 0
    }
    let negative = cmp < 0 ? !self.negative : self.negative
    let (b1, b2) = cmp < 0 ? (rhs, self) : (self, rhs)
    var res = [UInt32]()
    var carry: UInt64 = 0
    for i in 0..<b2.words.count {
      if UInt64(b1.words[i]) < UInt64(b2.words[i]) + carry {
        res.append(UInt32(BigInt.base + UInt64(b1.words[i]) - UInt64(b2.words[i]) - carry))
        carry = 1
      } else {
        res.append(b1.words[i] - b2.words[i] - UInt32(carry))
        carry = 0
      }
    }
    for i in b2.words.count..<b1.words.count {
      if b1.words[i] < UInt32(carry) {
        res.append(UInt32.max)
        carry = 1
      } else {
        res.append(b1.words[i] - UInt32(carry))
        carry = 0
      }
    }
    return BigInt(words: res, negative: negative)
  }
  
  /// Returns the result of mulitplying `self` with `rhs` as a `BigInt`
  public func times(_ rhs: BigInt) -> BigInt {
    let (b1, b2) = self.words.count < rhs.words.count ? (rhs, self) : (self, rhs)
    var res = [UInt32](repeating: 0, count: b1.words.count + b2.words.count)
    for i in 0..<b2.words.count {
      var sum: UInt64 = 0
      for j in 0..<b1.words.count {
        sum += UInt64(res[i + j]) + UInt64(b1.words[j]) * UInt64(b2.words[i])
        res[i + j] = BigInt.loword(sum)
        sum = UInt64(BigInt.hiword(sum))
      }
      res[i + b1.words.count] = BigInt.loword(sum)
    }
    return BigInt(words: res, negative: b1.negative != b2.negative)
  }
  
  private static func multSub(_ approx: UInt32, _ divis: [UInt32],
    _ rem: inout [UInt32], _ from: Int) {
      var sum: UInt64 = 0
      var carry: UInt64 = 0
      for j in 0..<divis.count {
        sum += UInt64(divis[j]) * UInt64(approx)
        let x = UInt64(loword(sum)) + carry
        if UInt64(rem[from + j]) < x {
          rem[from + j] = UInt32(BigInt.base + UInt64(rem[from + j]) - x)
          carry = 1
        } else {
          rem[from + j] = UInt32(UInt64(rem[from + j]) - x)
          carry = 0
        }
        sum = UInt64(hiword(sum))
      }
  }
  
  private static func subIfPossible(divis: [UInt32], rem: inout [UInt32], from: Int) -> Bool {
    var i = divis.count
    while i > 0 && divis[i - 1] >= rem[from + i - 1] {
      if divis[i - 1] > rem[from + i - 1] {
        return false
      }
      i -= 1
    }
    var carry: UInt64 = 0
    for j in 0..<divis.count {
      let x = UInt64(divis[j]) + carry
      if UInt64(rem[from + j]) < x {
        rem[from + j] = UInt32(BigInt.base + UInt64(rem[from + j]) - x)
        carry = 1
      } else {
        rem[from + j] = UInt32(UInt64(rem[from + j]) - x)
        carry = 0
      }
    }
    return true
  }
  
  /// Divides `self` by `rhs` and returns the result as a `BigInt`.
  public func dividedBy(_ rhs: BigInt) -> (quotient: BigInt, remainder: BigInt) {
    guard rhs.words.count <= self.words.count else {
      return (BigInt(0), self.abs)
    }
    let neg = self.negative != rhs.negative
    if rhs.words.count == self.words.count {
      let cmp = compare(to: rhs)
      if cmp == 0 {
        return (BigInt(neg ? -1 : 1), BigInt(0))
      } else if cmp < 0 {
        return (BigInt(0), self.abs)
      }
    }
    var rem = [UInt32](self.words)
    rem.append(0)
    var divis = [UInt32](rhs.words)
    divis.append(0)
    var sizediff = self.words.count - rhs.words.count
    let div = UInt64(rhs.words[rhs.words.count - 1]) + 1
    var res = [UInt32](repeating: 0, count: sizediff + 1)
    var divident = rem.count - 2
    repeat {
      var x = BigInt.joinwords(rem[divident], rem[divident + 1])
      var approx = x / div
      res[sizediff] = 0
      while approx > 0 {
        res[sizediff] += UInt32(approx) // Is this cast ok?
        BigInt.multSub(UInt32(approx), divis, &rem, sizediff)
        x = BigInt.joinwords(rem[divident], rem[divident + 1])
        approx = x / div
      }
      if BigInt.subIfPossible(divis: divis, rem: &rem, from: sizediff) {
        res[sizediff] += 1
      }
      divident -= 1
      sizediff -= 1
    } while sizediff >= 0
    return (BigInt(words: res, negative: neg), BigInt(words: rem, negative: self.negative))
  }
  
  /// Raises this `BigInt` value to the radixPow of `exp`.
  public func toPowerOf(_ exp: BigInt) -> BigInt {
    return pow(exp, self)
  }
  
  /// Computes the square root; this is the largest `BigInt` value `x` such that `x * x` is
  /// smaller than `self`.
  public var sqrt: BigInt {
    guard !self.isNegative else {
      preconditionFailure("cannot compute square root of negative number")
    }
    guard !self.isZero && !self.isOne else {
      return self
    }
    let two = BigInt(2)
    var y = self / two
    var x = self / y
    while y > x {
      y = (x + y) / two
      x = self / y
    }
    return y
  }
  
  /// Computes the bitwise `and` between this value and `rhs`.
  public func and(_ rhs: BigInt) -> BigInt {
    let size = min(self.words.count, rhs.words.count)
    var res = [UInt32]()
    res.reserveCapacity(size)
    for i in 0..<size {
      res.append(self.words[i] & rhs.words[i])
    }
    return BigInt(words: res, negative: self.negative && rhs.negative)
  }
  
  /// Computes the bitwise `or` between this value and `rhs`.
  public func or(_ rhs: BigInt) -> BigInt {
    let size = max(self.words.count, rhs.words.count)
    var res = [UInt32]()
    res.reserveCapacity(size)
    for i in 0..<size {
      let fst = i < self.words.count ? self.words[i] : 0
      let snd = i < rhs.words.count ? rhs.words[i] : 0
      res.append(fst | snd)
    }
    return BigInt(words: res, negative: self.negative || rhs.negative)
  }
  
  /// Computes the bitwise `xor` between this value and `rhs`.
  public func xor(_ rhs: BigInt) -> BigInt {
    let size = max(self.words.count, rhs.words.count)
    var res = [UInt32]()
    res.reserveCapacity(size)
    for i in 0..<size {
      let fst = i < self.words.count ? self.words[i] : 0
      let snd = i < rhs.words.count ? rhs.words[i] : 0
      res.append(fst ^ snd)
    }
    return BigInt(words: res, negative: self.negative || rhs.negative)
  }
  
  /// Inverts the bits in this `BigInt`.
  public var invert: BigInt {
    var res = [UInt32]()
    res.reserveCapacity(self.words.count)
    for word in self.words {
      res.append(~word)
    }
    return BigInt(words: res, negative: !self.negative)
  }
}


/// This extension implements all the boilerplate to make `BigInt` compatible
/// to the applicable Swift 3 protocols. `BigInt` is convertible from integer literals,
/// convertible from Strings, it's a signed number, equatable, comparable, and implements
/// all integer arithmetic functions.
extension BigInt: ExpressibleByIntegerLiteral,
                  ExpressibleByStringLiteral,
                  Equatable,
                  IntegerArithmetic,
                  SignedInteger {
  
  public typealias Distance = BigInt
  
  public init(_ value: UInt) {
    self.init(Int64(value))
  }
  
  public init(_ value: UInt8) {
    self.init(Int64(value))
  }
  
  public init(_ value: UInt16) {
    self.init(Int64(value))
  }
  
  public init(_ value: UInt32) {
    self.init(Int64(value))
  }
  
  public init(_ value: Int) {
    self.init(Int64(value))
  }
  
  public init(_ value: Int8) {
    self.init(Int64(value))
  }
  
  public init(_ value: Int16) {
    self.init(Int64(value))
  }
  
  public init(_ value: Int32) {
    self.init(Int64(value))
  }
  
  public init(integerLiteral value: Int64) {
    self.init(value)
  }
  
  public init(_builtinIntegerLiteral value: _MaxBuiltinIntegerType) {
    self.init(Int64(_builtinIntegerLiteral: value))
  }
  
  public init(stringLiteral value: String) {
    if let bi = BigInt(from: value) {
      self.init(words: bi.words, negative: bi.negative)
    } else {
      self.init(0)
    }
  }
  
  public init(extendedGraphemeClusterLiteral value: String) {
    self.init(stringLiteral: value)
  }
  
  public init(unicodeScalarLiteral value: String) {
    self.init(stringLiteral: String(value))
  }
  
  public static func addWithOverflow(_ lhs: BigInt, _ rhs: BigInt) -> (BigInt, overflow: Bool) {
    return (lhs.plus(rhs), overflow: false)
  }
  
  public static func subtractWithOverflow(_ lhs: BigInt, _ rhs: BigInt) -> (BigInt, overflow: Bool) {
    return (lhs.minus(rhs), overflow: false)
  }
  
  public static func multiplyWithOverflow(_ lhs: BigInt, _ rhs: BigInt) -> (BigInt, overflow: Bool) {
    return (lhs.times(rhs), overflow: false)
  }
  
  public static func divideWithOverflow(_ lhs: BigInt, _ rhs: BigInt) -> (BigInt, overflow: Bool) {
    let res = lhs.dividedBy(rhs)
    return (res.quotient, overflow: false)
  }
  
  public static func remainderWithOverflow(_ lhs: BigInt, _ rhs: BigInt) -> (BigInt, overflow: Bool) {
    let res = lhs.dividedBy(rhs)
    return (res.remainder, overflow: false)
  }
  
  /// The empty bitset.
  public static var allZeros: BigInt {
    return BigInt(0)
  }
  
  /// Returns this number as an `IntMax` number
  public func toIntMax() -> IntMax {
    if let res = self.intValue {
      return res
    }
    preconditionFailure("`BigInt` value cannot be converted to `IntMax`")
  }
  
  /// Adds `n` and returns the result.
  public func advanced(by n: BigInt) -> BigInt {
    return self.plus(n)
  }
  
  /// Computes the distance to `other` and returns the result.
  public func distance(to other: BigInt) -> BigInt {
    return other.minus(self)
  }
}


/// Returns the sum of `lhs` and `rhs`
///
/// - Note: Without this declaration, the compiler complains that `+` is declared
///         multiple times.
public func +(lhs: BigInt, rhs: BigInt) -> BigInt {
  return lhs.plus(rhs)
}

/// Returns the difference between `lhs` and `rhs`
///
/// - Note: Without this declaration, the compiler complains that `+` is declared
///         multiple times.
public func -(lhs: BigInt, rhs: BigInt) -> BigInt {
  return lhs.minus(rhs)
}

/// Adds `rhs` to `lhs` and stores the result in `lhs`.
///
/// - Note: Without this declaration, the compiler complains that `+` is declared
///         multiple times.
public func +=(lhs: inout BigInt, rhs: BigInt) {
  lhs = lhs.plus(rhs)
}

/// Returns true if `lhs` is less than `rhs`, false otherwise.
public func <(lhs: BigInt, rhs: BigInt) -> Bool {
  return lhs.compare(to: rhs) < 0
}

/// Returns true if `lhs` is less than or equals `rhs`, false otherwise.
public func <=(lhs: BigInt, rhs: BigInt) -> Bool {
  return lhs.compare(to: rhs) <= 0
}

/// Returns true if `lhs` is greater or equals `rhs`, false otherwise.
public func >=(lhs: BigInt, rhs: BigInt) -> Bool {
  return lhs.compare(to: rhs) >= 0
}

/// Returns true if `lhs` is greater than equals `rhs`, false otherwise.
public func >(lhs: BigInt, rhs: BigInt) -> Bool {
  return lhs.compare(to: rhs) > 0
}

/// Returns true if `lhs` is equals `rhs`, false otherwise.
public func ==(lhs: BigInt, rhs: BigInt) -> Bool {
  return lhs.compare(to: rhs) == 0
}

/// Returns true if `lhs` is not equals `rhs`, false otherwise.
public func !=(lhs: BigInt, rhs: BigInt) -> Bool {
  return lhs.compare(to: rhs) != 0
}

/// Negates `self`.
public prefix func -(num: BigInt) -> BigInt {
  return num.negate
}

/// Returns the intersection of bits set in `lhs` and `rhs`.
public func &(lhs: BigInt, rhs: BigInt) -> BigInt {
  return lhs.and(rhs)
}

/// Returns the union of bits set in `lhs` and `rhs`.
public func |(lhs: BigInt, rhs: BigInt) -> BigInt {
  return lhs.or(rhs)
}

/// Returns the bits that are set in exactly one of `lhs` and `rhs`.
public func ^(lhs: BigInt, rhs: BigInt) -> BigInt {
  return lhs.xor(rhs)
}

/// Returns the bitwise inverted BigInt
public prefix func ~(x: BigInt) -> BigInt {
  return x.invert
}

/// Returns the maximum of `fst` and `snd`.
public func max(_ fst: BigInt, _ snd: BigInt) -> BigInt {
  return fst.compare(to: snd) >= 0 ? fst : snd
}

/// Returns the minimum of `fst` and `snd`.
public func min(_ fst: BigInt, _ snd: BigInt) -> BigInt {
  return fst.compare(to: snd) <= 0 ? fst : snd
}
