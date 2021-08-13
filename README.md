# SpreadRows.jl

A package that allows for spreadsheet-like syntax for row-dependent calculations:

```julia
@spread i ∈ I = 1:N begin
  a[i] = b[i] + c[i] + d
  b = [x for x in I]
  c[i] = b[i]^2
  d = 9
end
```

What the `@spread` macro in the above example does is:
  - From `i ∈ I = 1:N` defines a _spread_ variable `i` and defines the domain over which to _spread_ as `I = 1:N`
  - Detects which formulas should be _spreaded_ over `I` (in this case `a[i]=...` and `c[i]=...`)
  - Detects which formulas should be taken as it is (in this case `b=...` and `d=9`)
  - Reorder the formulas to allow for a caculation sequence that will first calculate a formula's dependencies

The `@spread` macro can take two or one expression blocks, the first can be used for establishing the iteration definition (like `i ∈ I = 1:N`), the main block can be used to define the formulae of the model. Depending on how the `@spread` macro is used, the model can either export a function, evaluated the sequence in place:
```
         ┌── `Symbol` Referring to a range-like iterator, e.g.: `I`
         │
         ├── `Expr` To create a range-like iterator. This can be attached to a name,
         │   like `I=1:100` or be kept anonymous, like `1:100`
         │
         ├── `Expr` using `∈` to attach an inner-loop `Symbol` to the above two, 
         │    cases, like `i ∈ I` or `i ∈ I = 1:100`
         │   
@spread [1] [2]
             │   
             ├── `Expr` a block of spreadsheet like formulae to describes a model.
             │   This model will be created and executed within the current scope.
             │   For example, given the desired formulae:
             │     x[i] = i
             │     y[i] = x[i]^2
             │   If we run `@spread 1:10=>i begin x[i] = i; y[i] = x[i]^2 end`, the
             │   surrounding scope will gain the following two variables
             │     x = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
             │     y = [1, 4, 9, 16, 25, 36, 49, 64, 81, 100]
             │
             └── `Expr` a function-like expression to define a function that can 
                 evaluate its body and return a NamedTuple with formulae result.
                 Placeholder `_` is optional and can be used as a positional or 
                 keyword argument to allow iterators alternative to [1] to be 
                 passed to the function.
                 Placeholder `__` is optional and can be passed as a keyword 
                 argument to allow overwriting variables within the function body.
                 For example:
                   @spread i∈1:100 f(a, b, _; __) = begin
                       x[i] = i + a
                       y[i] = x[i] + b
                   end
                 Calling `f` like `f(1, 2, 1:10)` returns a `NamedTuple{(:x, :y)}`,
                 with parameters
                   x = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
                   y = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

@spread [1]
         │   
         └── `Expr` a function-like expression in the same fashion as [2] in the
             case of `@spread [1] [2]`, but where the placeholder `_` is replaced
             by an `Expr` with `∈`. This requires the iterator definition to be
             explicitely stated as a function argument.
             For example:
               @spread f(a, b, i∈1:100) = begin
                   x[i] = i + a
                   y[i] = x[i] + b
               end
```

TODO:
 - Move some of the generic AutoryBroadcastMacros functionaility over here
 - Write a manifesto for why a package like this is useful.
 - Explain how complex interactions between formulas work
