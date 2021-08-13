# SpreadRows.jl

Coming soon...

I want to make a Julia package that is a bit more generic than AutoryBroadcastMacros, and then rather let this be a dependency for the specific behaviour in AutoryBroadcastMacros. I specifically want something like this:

```julia
@spread i ∈ 1:N begin
  a[i] = b[i] + c[i] + d
  b = [x for x in 1:N]
  c[i] = b[i]^2
  d = 9
end
```

What the above code does is it automatically define two vectors `a` and `c` that can be indexed with the spread indexer `i`. Because `a` and `c` are defined as `a[1]` and `c[i]`, we see them as row-spreaded over `i`. On the other hand `b` and `d` are plainly defined like `b = ...` and are not seen as spreaded and will be evaluated as `b = [x for x in 1:N]` and `d=9`.


TODO: the following section is added first as documentation, then as implementation, so currently this is out of sync with the test of the package


The spread macro can take two expression blocks, the first for establishing what to be used as the rows indexes, and another to be used as the formulae of the model. The spread macro will then transform this into a spreadsheet like evaluation.
```
         ┌── `Symbol` Referring to a range-like iterator, e.g.: `T`
         │
         ├── `Expr` To create a range-like iterator. This can be attached to a name,
         │   like `T=1:100` or be kept anonymous, like `1:100`
         │
         ├── `Expr` using `∈` to attach an inner-loop `Symbol` to the above two, 
         │    cases, like `t ∈ T` or `t ∈ T = 1:100`
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
                   @spread t∈1:100 f(a, b, _; __) = begin
                       x[i] = i + a
                       y[i] = x[i] + b
                   end
                   f(1, 2, 1:10)

                 Will return a `NamedTuple{(:x, :y)}` instance where
                   x = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
                   y = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

@spread [1]
         │   
         └── `Expr` a function-like expression in the same fashion as [2] in the
             case of `@spread [1] [2]`, but where the placeholder `_` is replaced
             by an `Expr` with `∈`. This requires the iterator definition to be
             explicitely stated as a function argument.
             For example:
               @spread f(a, b, t∈1:100) = begin
                   x[i] = i + a
                   y[i] = x[i] + b
               end
```

TODO:
 - Move some of the generic AutoryBroadcastMacros functionaility over here
 - Write a manifesto for why a package like this is useful.
 - Explain how complex interactions between formulas work
