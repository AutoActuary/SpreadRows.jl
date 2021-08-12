import ExprTools
using DocStringExtensions

@testset "SheetConfig" begin
    @test SheetConfig(nothing, :(x ∈ X = 1:10), :(begin p[x] = 5 end)) !== nothing
    @test SheetConfig(nothing, :(x ∈ X = 1:10), :(function(_) end)) !== nothing
    @test SheetConfig(nothing, :(function(x in X=1:10,)end)) !== nothing
end


struct SheetIteratorError <: Exception
    var::String
end

"""
This is a parsing of our custom syntax for defining iteration sequence for @sheet.
The iteration sequence is defines as e.g. `i ∈ I = 1:10`.

$(FIELDS)
"""
struct SheetIterator
    "The inner loop variable Symbol, e.g. `i` as in `i ∈ I = 1:10`"
    inner

    "The outer variable Symbol, e.g. `I` as in `i ∈ I = 1:10`"
    outer

    "The iterator attached to `outer`, e.g. `1:10` as in `i ∈ I = 1:10`"
    iterator
end


"""
Parse an expression as a SheetIterator object used by the @sheet macro.
"""
SheetIterator(expr::Expr, as_function_argument::Bool) = begin
    # A. When used as a function argument (as_function_argument=true) we have two options:
    #   1. x ∈ X            - without a default iterator value
    #   2. x ∈ X = 1:100    - with a default iterator value

    # B. When used as outside a function argument (as_function_argument=false), we have two options
    #   1. x ∈ 1:100        - without a default outer Symbol
    #   2. x ∈ X = 1:100    - with a default outer Symbol
    
    # split `x ∈ X` into `x` and `X`
    get_in_lhs_rhs(e::Expr) = begin
        if e.head == :call && length(e.args) == 3 
            in_, lhs, rhs = e.args
            if in_ ∈ (:(in), :(∈))
                return lhs, rhs
            end
        end
    end
    get_in_lhs_rhs(e) = nothing

    # split `x ∈ X = 1:100` into `x ∈ X` and `1:100`
    get_eq_lhs_rhs(e::Expr) = begin
        if e.head ∈ (:(=), :(kw)) # difference for arg an kwarg
            return e.args[1], e.args[2]
        end
    end
    get_eq_lhs_rhs(e) = nothing

    # A.1. split `x ∈ X = 1:100` into `x`, `X`, and `1:100`
    # A.2. split `x ∈ X` into `x`, `X`, and `nothing`
    e = expr
    arg1, arg2, arg3 = nothing, nothing, nothing

    eq_split = get_eq_lhs_rhs(e)
    if eq_split !== nothing
        arg3 = eq_split[2]
        e = eq_split[1]
    end

    in_split = get_in_lhs_rhs(e)
    if in_split !== nothing
        arg1, arg2 = in_split
    else
        throw(SheetIteratorError("Not a parsable SheetIterator object, expected something like `x ∈ X = 1:10`, got:`$(expr)`"))
    end

    # A1, A2, B1
    if as_function_argument || arg3 !== nothing
        return SheetIterator(arg1, arg2, arg3)
    else
        # B2
        return SheetIterator(arg1, arg3, arg2)
    end
end
SheetIterator(expr, ::Bool) = begin
    throw(SheetIteratorError("Not a parsable SheetIterator object, expected something like `x ∈ X = 1:10`, got: `$(expr)`"))
end


struct SheetFormula
    expr
    broadcast::Bool
    line::Union{LineNumberNode, Nothing}
end


mutable struct SheetConfig
    iterator::Union{SheetIterator, Nothing}
    funcdef::Union{Dict, Nothing}
    loopdef::Pair{Symbol, Any}
    formulas::OrderedDict{Symbol, SheetFormula}
    graph::DiGraph{Symbol}
    ordered_clusters::Vector{Vector{Symbol}}
    source::Union{LineNumberNode, Nothing}
end


# Sheet config
SheetConfig(__protect__::Nothing, exprbody; source=nothing) = begin
    SheetConfig(__protect__, nothing, exprbody; source=nothing)
end
SheetConfig(__protect__::Nothing, expriter, exprbody; source=nothing) = begin

    # Get the function header definition
    funcdef = try
        ExprTools.splitdef(exprbody)
    catch e 
        e isa ArgumentError ?  nothing : rethrow(e)
    end

    # Get the function body out of the function struct (and rename symbols back)
    if funcdef !== nothing
        exprbody = funcdef[:body]
        funcdef[:body] = nothing
    end

    
    # Find iterator expression (e.g. `x ∈ X = 1:10`) in either `expriter` or function header
    iterator = nothing
    if expriter !== nothing  
        iterator = SheetIterator(expriter, false)
    else
        if funcdef === nothing
            ErrorException("Iteration definition (e.g. `x ∈ X = 1:10`) must either be the first argument, "*
                           "or be withing a function definition (e.g. foo(a,b,x∈X=1:10;c=9) = ...)")
        else
            for key ∈ (:args, :kwargs)
                for (i, arg) ∈ enumerate(get(funcdef, key, []))
                    try
                        iterator = SheetIterator(arg, true)
                        funcdef[key] = Vector{Any}(funcdef[key])
                        funcdef[key][i] = :(_)
                        break
                    catch e
                        e isa SheetIteratorError || rethrow(e)
                    end
                end
            end
        end
    end

    if iterator === nothing
        candidates = []
        if expriter !== nothing
            push!(candidates, expriter)
        end
        if funcdef !== nothing 
            append!(candidates, get(funcdef, :args, []))
            append!(candidates, get(funcdef, :kwargs, []))
        end
        throw(ErrorException("Iteration definition (e.g. `x ∈ X = 1:10`) must either be the first argument to the @sheets macro, "*
                             "or be withing a function definition (e.g. `foo(a, b, x ∈ X=1:10) = ...`). Got candidates: $candidates"))
    end


    # Assert that we have valid iterator definition
    if funcdef !== nothing
        @assert(
            iterator.inner isa Symbol && iterator.outer isa Symbol,
            "Expected inner iterator symbol (e.g. `x ∈ X ...`) to be of type Symbol (e.g. `x` and `X`), got: `$(iterator.inner)` and `$(iterator.outer)`"
        )
    else
        @assert(
            iterator.inner isa Symbol,
            "Expected inner iterator symbol (e.g. `x ∈ ...`) to be of type Symbol (e.g. `x`), got: `$(iterator.inner)`"
        )
    end

    # Transform body into fomulas list
    formulas = expr_to_formulas(exprbody, iterator.inner; line=source)

    # Assert no duplicate variable definitions

    if funcdef !== nothing
        for i in [get(funcdef, :args, []); get(funcdef, :kwargs, [])]
            arg = MacroTools.splitarg(i)[1]
            if haskey(formulas, arg)
                throw(ErrorException("Variable `$arg` defined both as a function argument and as a formula"))
            end
        end
    end

    # Generate the graph and cluster order
    graph = formulas_to_digraph(formulas)
    ordered_clusters = generate_calculation_sequence(graph; preferred_sequence=keys(formulas))

    SheetConfig(iterator, funcdef, :qqq=>:qqq, formulas, graph, ordered_clusters, source)
end


SheetConfig(exprloop::Expr,
            exprbody::Expr;
            source::Union{LineNumberNode, Nothing}=nothing) = begin

    loopdef = expr_to_loop_definition(exprloop)
    x, _ = loopdef
    formulas = expr_to_formulas(exprbody, x; line=source)
    graph = formulas_to_digraph(formulas)
    ordered_clusters = generate_calculation_sequence(graph; preferred_sequence=keys(formulas))

    SheetConfig(nothing, nothing, loopdef, formulas, graph, ordered_clusters, source)
end


struct CalculationSequenceError <: Exception
    var::String
end
CalculationSequenceError() = begin
    errmessage = join(split(
        """
        The `@T` macro was unable to order the given formula(s) in a way that 
        resulted in a correct calculation flow using the current heuristics. 
        Note that `@T` cannot yet take indexing into account with (a) a mix 
        of forwards `A[t+1]` and backwards `A[t-1]` referencing, (b) with 
        runtime variables like the `c` in `A[c+t]`, (c) with nonlinear t 
        indexing like `A[t^2-3t]`, and (d) with non-t indexing like A[34].
        """, "\n"
    ))

    CalculationSequenceError(errmessage)
end

