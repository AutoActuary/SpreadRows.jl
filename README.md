# RowSheets.jl

Coming soon...

I want to make a Julia package that is a bit more generic than AutoryBroadcastMacros, and then rather let this be a dependency for the specific behaviour in AutoryBroadcastMacros. I specifically want something like this:

```
@sheet i in 1:N begin
  a[i] = b[i] + c[i] + d
  b = [x for x in 1:N]
  c[i] = b[i]^2
  d = 9
end
```

What the above code does is it automatically define two vectors `a` and `c` that can be indexed with the sheet indexer `i`. Because `a` and `c` are defined as `a[1]` and `c[i]`, we see them as row-spreaded over `i`. On the other hand `b` and `d` are plainly defined like `b = ...` and are not seen as spreaded and will be evaluated as `b = [x for x in 1:N]` and `d=9`.

TODO:
 - Move some of the generic AutoryBroadcastMacros functionaility over here
 - Write a manifesto for why a package like this is useful.
 - Explain how complex interactions between formulas work
