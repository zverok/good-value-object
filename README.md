# Good Value Object convertion for Ruby

> In computer science, a **value object** is a small object that represents a _simple_ entity whose equality is not based on identity: i.e. two value objects are _equal_ when they have the same _value_, not necessarily being the _same object_. [→](https://en.wikipedia.org/wiki/Value_object)

Creating good, reusable and idiomatic value objects for Ruby is not that simple.

**This repository** provides a checklist for a good value object design. Currently it is in "RFC" (request for comments) state, gathering experience, agreements and convention. In future, it will also have _automated tests_, so you can just

```ruby
# in RSpec
it_behaves_like "good value object",
  arithmetic: false,
  ordered: false,
  sample_values: [
    {lat: 1, lng: 2},
    {lat: 50, lng: 40}
    ...
  ]
```

## Examples

We are using imaginary, yet real-life-alike `Quantity { amount: Numeric, unit: String }` type for most of the examples. And, eventually, other types that demonstrate some points better.

## Definitions

We can think about most value objects as a Struct (not Ruby's particular implementation, but generic programming concept: group of named fields). The fields of this structure we further will call **structured elements**. It is logical concept rather than implementational.

**Example**: for `Date` value type, "structural" values are probably `(year, month, day of month)` (maybe `calendar` too, depending of fancyness of your date). That does _not_ imply that `Date` instance stores them in instance variables, neither the fact that it is the only instance variables:

* Date may be internally represented by one integer value, and calculate components back and force on construction and parts accessors;
* Date may have _weekday_ as an accessor and instance variable. But it is probably derived value, because it indeed can be derived from year, month and day, and there are _almost_ no situations where it can be used to specify the date (e.g. `2018, March, Monday` is ambiguous, and `2018, March, 5th` doesn't need weekday to be specific).

> **Note**: `2018, 10th week, Monday` _is_ a thing in some business contexts, but probably it is better to have specialized constructor or even type for it.

## Construction

* `#initialize` should have type's structural parts as an arguments, the `TypeName.new(...)` should be the most straightforward ("just validate and store in instance variables") way to construct value; all other ways to construct should go to specialized class methods
  ```ruby
  # Bad
  Quantity.new('10 m')
  # Good
  Quantity.new(10, 'm')
  Quantity.parse('10 m')
  ```
  * See also "Conversion to and from other types"

* It is acceptable to have structural elements converted or wrapped on construction
  ```ruby
  q = Quantity.new(10, 'm')
  q.amount # => #<BigDecimal 10>
  q.unit # => #<Quantity::Unit m>
  ```

* Consider using keyword arguments instead of positional ones, especially if there are more than 2 arguments for constructor, or order is not obvious (is it `GeoPoint.new(lat, lng)` or `GeoPoint.new(lng, lat)`?)
  * (Obvious yet mandatory: please, use real keyword arguments, not pre-Ruby 2.1 `params = {}` hack)
* Value construction options could be provided by keyword arguments, but it is undesirable to have both main argument and options as keyword arguments, or having both as positional arguments
  ```ruby
  # OK
  Quantity.new(10, 'm')
  Quantity.new(amount: 10, unit: 'm')
  Quantity.new(10, 'm', system: Quantity::SI)
  # Questionable
  Quantity.new(amount: 10, unit: 'm', system: Quantity::SI)
  Quantity.new(10, 'm', Quantity::SI)
  ```

* Sometimes it is useful (but not required) to provide construction method synonymous with the type name, e.g. `Quantity(amount, unit)`; it brings no additional functionality yet emphasizes the fact that value "just exists", and we are referencing to existing concept of "10 meters", not constructing it (which "new" implies)
* If there are expected to be a lot of similar objects created during the lifecycle of the application, consider caching objects (having exactly one object for one value). `Type.new` can be redefined for this purpose:
  ```ruby
  10.times.map { Quantity.new(10, 'm') }.map(&:object_id).uniq.count # => 1
  ```
  Another approach seen in use is making `Type.new` private, and making `Type(...)` or `Type.[]` (with caching inside) the primary construction method.

* Avoid redefining `.new` for other purposes, especially to return value of type different from requested:
  ```ruby
  # Really bad
  Quantity.new(10, 'm') # => #<Quantity::Physics::Length 10 m>
  # Something like this would be better
  Quantity.coerce(10, 'm') # => #<Quantity::Physics::Length 10 m>
  # or even
  Quantity['m'].new(10)
  ```

## Basic properties

* All structural elements of the value should be exposed as `attr_reader`s (or methods with the same behavior)
* Value object **should** be absolutely immutable, no `attr_setter`s and no other way to change value of the object
  * It is wise to `freeze` all structural elements that belong to mutable Ruby types, to prevent code like this:
    ```ruby
    q = Quantity.new(10, 'm')
    q.unit.upcase!
    # Or, more believable:
    q = Quantity.new(10, 'm')
    u = q.unit
    # ...later...
    u.upcase! # => Unexpectedly makes q to have unit == 'M'
    ```

* As immutability makes this code impossible:
  ```ruby
  new_value = value.dup
  new_value.property = x
  ```
  consider providing some _reasonable_ methods to "produce a value like this, with some parts changed"
  * Consider (but mindfully) `merge(property: value, property: value)` interface for it
    ```ruby
    # Good
    FancyDate.now.merge(month: 12) # produces new FancyDate: "same day, but in December"
    # Not really useful
    Quantity.new(10, 'm').merge(unit: 's') # what's the semantics of "same value but in seconds"?..
    # Probably better
    Quantity.new(10, 'm').unit.create(20) # => Quantity(20, 'm')
    ```

* **No global option** should change behavior of value objects. Consider providing "context" or "environment" to constructor or instance method:

  ```ruby
  # Unforgivable bad
  Quantity.new(10, 'm').normalize # => Quantity.new(32.8, 'feet')
  Quantity.system = Quantity::SI
  Quantity.new(10, 'm').normalize # => Quantity.new(10, 'm')

  # Still pretty questionable
  Quantity.new(10, 'm').normalize # => Quantity.new(32.8, 'feet')
  Quantity.new(10, 'm', system: Quantity::SI).normalize # => Quantity.new(10, 'm')

  # Good
  Quantity.new(10, 'm').normalize # => Quantity.new(32.8, 'feet')
  Quantity.new(10, 'm').normalize(system: Quantity::SI) # => Quantity.new(10, 'm')

  # Best ;)
  Quantity.new(10, 'm').normalize # => Quantity.new(10, 'm')
  Quantity.new(10, 'm').normalize(system: Quantity::IMPERIAL) # => Quantity.new(32.8, 'feet')
  ```

### `#inspect` and `#pp`

* You should implement `#inspect` for your types, it is really helpful for debugging
* By convention, `#inspect` for value types should look like `#<TypeName value representation>`
* Value representation should be full (without loosing important details) yet concise (without variable names and unimportant clarifications)
  ```ruby
  # Good
  Quantity.new(10, 'm').inspect # => "#<Quantity 10 m>" or #<Quantity(10 m)>`
  # Bad
  Quantity.new(10, 'm').inspect # => "#<Quantity(m)>"
  Quantity.new(10, 'm').inspect # => "10 m" - it is unhelpful to not be able to distinguish from string while debugging
  Quantity.new(10, 'm').inspect # => "#<Quantity amount=10 unit=\"m\">" - unnecessary verbosity
  # Also bad: Ruby's stdlib Date
  Date.today.inspect # => "#<Date: 2018-03-04 ((2458182j,0s,0n),+0s,2299161j)>" -- ((2458182j,0s,0n),+0s,2299161j) anybody?
  ```
* If it can be created, it **should** be possible to inspect; `#inspect` should try hard to never raise and never return anything except string
  ```ruby
  # Good
  Quantity.new(INFINITY, 'm') # => ArgumentError on attempt to create, no problems with inspect
  # Acceptable
  Quantity.new(INFINITY, 'm').inspect # => "#<Quantity [UNREPRESENTABLE]>"
  # Bad
  Quantity.new(INFINITY, 'm').inspect # => ArgumentError or nil
  ```
* If it is known beforehand about some possible basic values the value object will try to represent, it is advisable to try providing nicer inspects, immediately readable
  ```ruby
  # Not really helpful
  Quantity.new(10_000_000, 'm').inspect # => #<Quantity 10000000 m>
  # Good
  Quantity.new(10_000_000, 'm').inspect # => #<Quantity 10,000,000 m>
  # Could be acceptable in some contexts
  Quantity.new(10_000_000, 'm').inspect # => #<Quantity 1e7 m>
  ```
* As since Ruby 2.5.0 `pp` is required by default, consider implementing multiline `#pretty_print` for the value, especially if it contains lots of data that is reasonable to print in multiple lines
  * Documentation on implementing `#pretty_print` (pretty terse, yet enough to start) could be found [here](https://docs.ruby-lang.org/en/2.5.0/PP.html#class-PP-label-Output+Customization)

## Comparison

* Provide `==` method for values
  * Values should be equal if, and only if, all of their structural elements are equal
  * `==` should NOT raise on attempt to compare with incompatible type: in Ruby, `1 == "1"` is just `false`, not a deadly sin punished by exception
  * Do not be too generous on equality: `Quantity.new(10, 'm') == 10` may seem like a good idea in some context, yet it will eventually lead to a lot of hidden bugs
* See "Behavior in hashes" about overriding `#eql?`
* **Never** override `#equal?`
* Provide order comparison for values (`<`, `>` and so on) if, and only if, order on all acceptable values is defined and unambiguous
  * It is strongly advised to provide those methods by implementing `<=>` and including `Comparable` (and it will give you `==` for free)
  * `<=>` should NOT raise on attempt to compare with incompatible type, just return `nil`, `Comparable`s implementation of other method will behave the most reasonable way: `==` will return `false` and `<` and other similar methods would raise `ArgumentError`
  * if implementing `<` and `>` by yourself, don't forget about `<=` and `>=`; and make them raise `ArgumentError` on incompatible types
* Consider providing `positive?`, `negative?` and `zero?` for the value if, and only if, their meaning is clear and semantically unambiguous
* If the order on values is strictly defined, consider providing `Type::INFINITY` constant or class method, for using in expressions like:
  ```ruby
  ranges = {
    Quantity.new(1, 'm')...Quantity.new(10, 'm') => 'near',
    Quantity.new(10, 'm')...Quantity.new(100, 'm') => 'far',
    Quantity.new(100, 'm')...Quantity::INFINITY => 'nowhere'
  }
  ranges.select { |r, _| r.cover?(value) }....
  # and this
  value.clamp(Quantity.new(100, 'm'), Quantity::INFINITY) # "not lower the 100" one-side clamp
  ```
  Possible infinity concept interfaces:
  ```ruby
  # Probably OK if used rarely, and constructor should not fail on this
  Quantity.new(Float::INFINITY, 'm')
  # Pretty clear yet no explicit type, can be hard to implement <=>
  Quantity::INFINITY
  # Also clear and typed, needs mindful implementation
  Quantity.infinity('m')
  ```
  * See also "Behavior in ranges" for notes about Range implementation quirks

## Other operators

* Consider providing a subset of math operators (`+`, `-`, `*`, `/` and so on) if their meaning is obvious and unambiguous
* Try to follow "natural" intuition of mathematical operators (`a + b == b + a`, `a - b = a + (-b)` and so on)
  * Note that Ruby's intuition also redefines some of operators base qualities, when acceptable, for example, using `+` for _concatenation_ (of strings and arrays), which is not commutative
* Don't override operators just because it is cool: using, say `~Quantity.new(10, 'm')` to say "something about this quantity" (for example, producing range `Quantity.new(9.5, 'm')..Quantity.new(10.5, 'm')`) is cool for play yet leads to unguessable code
* Consider implementing `|` and `&` if:
  * value object is some kind of pattern, for this operators to mean "or" and "and"
  * value object represents some kind of range(s), for this operators to mean "union" and "intersection"
  ```ruby
  Dates::Period.parse('2017-02') | Dates::Period.parse('2016-12')
  # => #<Dates::Period Dec 1-31 2016, Feb 1-28 2017>
  Dates::Period.parse_range('2017-01-30'..'2017-02-12') & Dates::Period.parse('2017-01')
  # => #<Dates::Period Jan 30-31 2017>
  ```
* Consider implementing `===` if value can be used as some kind of pattern
  ```ruby
  # Messy
  if quantity.unit == 'm'
  elsif quantity.unit == 's'
  else ...

  quantities.select { |q| q.unit == 'm' }

  # Nice
  case quantity
  when Quantity::Unit('m')
  when Quantity::Unit('s')
  ...

  quantities.grep(Quantity::Unit('m'))
  ```

## Conversions

### To other types

* Consider providing `#to_<type>` to convert value object to other types
* `#to_<type>` protocol should be used only when format or precision of value is changed, but not when context is lost
  ```ruby
  # Good
  BigDecimal('100').to_i # => it is the same number, just loses precision
  # Bad
  Quantity.new(10, 'm').to_i # => context is lost, Quantity#amount is much better convention

  # Acceptable
  Dates::Period.to_activercord # => may have sense in some context
  # Questionable
  Dates::Period.to_regexp # => probably, just #regexp would be better
  ```

### To Ruby's core types

* Never provide "implicit conversion" methods (`#to_str`, `#to_ary`, `#to_hash`, `#to_int`) unless you really know what you do (= type is really kind of string/array/hash/integer); they'll convert values violently and unexpectedly;
* Never provide `to_a` either (unless it is kind of collection), as it will unexpectedly deconstruct the value on `Array(value)` call
  * This means that if the type is descendant of `Struct`, you **should explicitly** `undef :to_a`
  * Even for objects "somewhat resembling collection", it is better to provide one or more `#each_<something>` methods, returning `Enumerator`
* Always try to provide `#to_h`, it is really good for serialization:
  * `#to_h` should probably return hash with symbolic keys, containing exactly all the structural elements of value object and nothing more;
  * If value object's constructor uses keyword arguments, `ValueType.new(**value.to_h) == value` should be always true
* Always provide `#to_s`, as Ruby's default `#to_s` will expose object_id and look really unhelpful on string interpolations
  * for value objects that represent typed values (time, geometry, quantities) consider providing as "human-readable" `#to_s` as possible, without any quoting and type names;
  * for value objects that represent complicated domain structures, consider making `#to_s` just an alias to `#inspect` (see "`#inspect` and `#pp`" section above)
  ```ruby
  # Good
  puts Quantity.new(10 'm') # "10 m"
  # Also good
  puts StoreId.fetch('xyz') # => "#<StoreId xyz>"
  # Questionable
  puts StoreId.fetch('xyz') # => "xyz" -- Loses too much of domain context
  # if you needed this to interpolate sql, probably #to_sql method would be better
  ```
  * If there are a lot of way to represent value as a string, consider providing `#format(lot: of, **options)` or `strf<typename>`

### From other types

* Consider providing `Type.from_<othertype>()` methods for as much of basic Ruby types, and domain types, as possible;
* As with `to_<othertype>`, the `from_` naming convention can ONLY be used if format or precision of data is changed, but not when context is lost or attached:
```ruby
# Good
Quantity.from_a([10, 'm']) # => #<Quantity 10 m>
# Bad
Quantity.from_f(10, unit: 'm') # It is constructor (maybe specialized one), not "converter from Float"!
```
* Most of the time, `Type.from_othertype(value.to_othertype) == value` should be `true`;
* Sometimes, it is useful to provide two methods for conversion: one raising on incorrect input, and other just returning `nil`:
```ruby
Quantity.from_a([10, 'm']) # => #<Quantity 10 m>
Quantity.from_a([10]) # => ArgumentError: expected 2-element array
Quantity.try_from_a([10]) # => nil
```
* If the domain data can have very variable string representation, consider providing two ways to parse:
  * `Typename.parse(string)` that accepts any input, tries to guess how to parse it, and returns `nil` if it absolutely can not;
  * Set of methods, or set of options, or pattern DSL allowing user to specify how data should be parsed:
  ```ruby
  # set of methods:
  Quantity.amount_unit('10m') # => #<Quantity 10 m>
  Quantity.unit_amount('$10') # => #<Quantity 10 $>
  # set of options
  Quantity.from_s('$&nbsp;10', order: :unit_amount, separator: '&nbsp;')
  # pattern DSL
  Quantity.strpquantity('%amount (%unit)', '20 (m)')
  ```
  Note: `strp<typename>` is probably not the best convention, but it is like Ruby's `Date.strptime`

## Behavior in hashes

* If it is _a slightest possibility_ the value type could be used as a key in hashes, implement `#hash`, returning unique number for each unique combination of structural elements. The easiest implementation is probably
  ```ruby
  def hash
    [each, of, structural, elements].map(&:hash).hash
  end
  ```
* In this case `#eql?` method also **should** be implemented, as Hash uses it to decide on key's equality. Typically, it can be just an alias to `#==`, but if `#==` is forgiving, `#eql?` should be strict.
  ```ruby
  # Imagine Paragraph class, which is just a wrapper around String, but with some fancy interface
  # It can have...
  def ==(other)
    @string == other.to_s
  end

  # In this case...
  h = {'test' => 1, Paragraph.new('test') => 2}
  # ...may lead to only ONE key being stored
  ```
  Probable approach to reimplement stricter `#eql?` is
  ```ruby
  def eql?(other)
    hash == other.hash
  end
  ```

## Behavior in ranges

For most of its functionality, Ruby's `Range` currently relies on value providing `#succ` (next value in ordered values space). Unfortunately, this includes case equality `===` too. Therefore, two opposite rules:

* Consider providing `#succ` method if value space is small and has unambiguous granularity, to allow code like this:
  ```ruby
  case DayOfWeek.current
  when DayOfWeek('Mon')..DayOfWeek('Thu')
  ```
* Consider consciously NOT providing `#succ` to explicitly disallow code like this:
  ```ruby
  # Idiomatic, yet slow: calculates thousands of IPs inside range
  case ip
  when IP("172.16.10.1")..IP("172.16.11.255")
  ...

  # Can't be used in `case`, yet fast:
  if (IP("172.16.10.1")..IP("172.16.11.255")).cover?(ip) ...

  # Another case
  #
  # Ruby will try to do #succ on start value, but what it should be?
  # "Obvious" from the first sight Quantity.new(2, 'm') will leave Quantity.new(1.5, 'm') outside the comparison
  case quantity
  when Quantity.new(1, 'm')..Quantity.new(10, 'm')
  ...

  # The only solution, again:
  if (Quantity.new(1, 'm')..Quantity.new(10, 'm')).cover?(quantity)
  ```

See also corresponding [bug](https://bugs.ruby-lang.org/issues/14575) in Ruby tracker for discussion if this behavior.

## Serialization/deserialization

* Consider providing reasonable `#to_json` implementation. For lot of cases, this should be enough (if you have provided `#to_h` which is strongly advised above):
  ```ruby
  def to_json(*opts)
    to_h.to_json(*opts)
  end
  ```
* Consider your value object's YAML-friendliness
  * Default YAML implementation will dump all object's instance variables on `YAML.dump`, and just set them all to an uninitialized allocated object on `YAML.load`. You can alter this behavior by redefining methods with inventive and memoizable names `encode_with(coder)` and `init_with(coder)`
  ```yaml
  # good
  - !ruby/object:Quantity
    amount: 1
    unit: m

  # not so good
  - !ruby/object:Quantity
    amount: 1
    unit: !ruby/object:Quantity::Unit
      name: meter
      synonym: metre
      plural: metres
      short: m
      domain: distance
      base: true
      system: !ruby/object:Quantity::System
        ...
    _memoized_method_cache_: # memoist was here....
    ...
  ```

## Inheritance friendliness

For small value objects it is always a temptation to inherit from, to add several more methods, change constructor or formatting, required by current domain. Your types should be ready to be inherited, which most of the time, means not hardcoding class (by name or by value) in methods (or, sometimes, vice versa, hardcoding it, look at examples)

```ruby
class FancyQuantity < Quantity
end

# Bad
FancyQuantity.new(10, 'm').inspect # => #<Quantity 10 m>, because #inspect hardcodes "#<Quantity" part
# solution is
def inspect
  "#<#{self.class} .... >"
end

# Probably bad
FancyQuantity.new(10, 'm') == Quantity.new(10, 'm') # => false, because #== has self.class == other.class

# solution?
def ==(other)
  # Bad: only values of exactly same type are compatible
  self.class == other.class && ...
  # Bad: Quantity#==(FancyQuantity) would work, but not vice versa
  other.kind_of?(self.class) && ...

  # Good: just hardcode the base
  other.is_a?(Quantity) && ...
  # ...or, sometimes, duck type
  other.respond_to?(:amount) && other.respond_to?(:unit) && ...
```