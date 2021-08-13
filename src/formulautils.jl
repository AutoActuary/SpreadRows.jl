"
Function to make testing between macros easier
"
striplines(ex) = begin
    ex′ = Expr(:block, deepcopy(ex))

    # Define the mutation
    recurse(ex) = begin
        if ex isa Expr
            for i ∈ 1:length(ex.args)
                if ex.args[i] isa LineNumberNode
                    ex.args[i] = nothing
                else 
                    recurse(ex.args[i])
    
                end 
            end 
        end 
    end

    recurse(ex′)

    ex = ex′.args[1]
    return ex

end

@testset "has_var" begin
    @test has_var(:(a + b + c + foo(a + b + c + foo(d))), :d)
    @test !has_var(:(a + b + c + foo(a + b + c + foo(d))), :q)
end

"
Test if an expression contains the specefic variable
"
has_var(ex::Expr, s::Symbol) = any(has_var.(ex.args, s))
has_var(ex::Symbol, s::Symbol) = ex == s
has_var(ex, s::Symbol) = false


@testset "get_vars" begin
    @test get_vars(:(a = foo(b + c + bar(d) + e[f]))) == [:a, :b, :c, :d, :e, :f]
end

"
Get all the variable names from an expression, excluding macro names and function names
"
get_vars(ex) = begin
    varnames = Array{Symbol, 1}()

    # behaviour for each type
    recurse(ex) = nothing
    recurse(ex::Symbol) = push!(varnames, ex)
    recurse(ex::Expr) = begin
        i₁ = ex.head ∈ [:call, :macocall] ? 2 : 1 
        for i ∈ i₁:length(ex.args)
            recurse(ex.args[i])
        end
    end 

    # Apply and return
    recurse(ex) 
    return varnames
end


"
Replace a variable within an expression with anything
"
replace_var(ex, var::Symbol, value) = begin
    ex′ = Expr(:block, deepcopy(ex))

    # behaviour for each type
    recurse(ex) = nothing
    recurse(ex::Expr) = begin
        i₁ = ex.head ∈ [:call, :macocall] ? 2 : 1 
        for i ∈ i₁:length(ex.args)
            if ex.args[i] == var
                ex.args[i] = value
            else
                recurse(ex.args[i])
            end
        end
    end 

    # Apply and return
    recurse(ex′)
    ex = ex′.args[1]
    return ex
end


@testset "get_indexing" begin
    @test( 
        get_indexing(:(a[5] + a[8] + b[t+40]), :t) == 
        [:b => :(t + 40)]
    )
    @test(
        get_indexing(:(a[5] + a[8] + b[t+40] + b[t-30] + c[t]), :t) == 
        [:b => :(t + 40), :b => :(t - 30), :c => :t]
    )
end
"
Find references involving `x` in an equation. Note: nested referencing is currently not supported.
"
get_indexing(ex, x::Symbol)::Vector{Pair{Symbol, Any}} = begin
    references = Vector()

    recurse(ex) = nothing
    recurse(ex::Expr) = begin
        if ex.head == :ref && length(ex.args) == 2 && ex.args[1] isa Symbol
            (ex₁, ex₂) = ex.args 

            if has_var(ex₂, x)
                push!(references, ex₁=>ex₂)
            end
        end
        for i in ex.args
            recurse(i)
        end
    end

    recurse(ex)
    return references
end


@testset "expr_is_linear" begin
    @test expr_is_linear(:(t*t), :t) == false
    @test expr_is_linear(:(t^2), :t) == false
    @test expr_is_linear(:((5+67)*foo(t)), :t) == false
    @test expr_is_linear(:(t == 0 ? 1 : 2), :t) == false
    
    @test expr_is_linear(:(t+1+2/3*5), :t)
    @test expr_is_linear(:(t*2+1+2/3*5), :t)
    @test expr_is_linear(:((5+67)*t), :t)

    @test expr_is_linear(:(1+(a+t)), :t) == true
    @test expr_is_linear(:(1+(a+2t)), :t) == true
    @test expr_is_linear(:(1+(a+(t*t))), :t) == false    
    @test expr_is_linear(:(1+(a+(q*q))), :t) === nothing # no t
    @test expr_is_linear(:(1+(a+(t)+t-t+5)), :t) == false
end

"
Test if expression contains an linear combination of `x`.
    if linear w.r.t. `x`: true
    if non-linear w.r.g. `x`: false
    if heuristic cannot evaluate: nothing
"
expr_is_linear(ex, x::Symbol) = begin

    # Can we skip the investigation?
    vars = get_vars(ex)
    if !(x in vars)
        return nothing
    elseif [i for i in vars if i == x] != [x]
        return false
    end

    # behaviour for each type
    recurse(args...) = nothing
    recurse(ex::Symbol, linear_parents) = ex == x ? linear_parents : nothing 
    recurse(ex::Expr, linear_parents) = begin
        # Test if only + - and multiplication by a constant in t
        if ex.head == :call && (ex.args[1] == :+ || ex.args[1] == :- || ex.args[1] == :*)
            calls = [recurse(i, linear_parents) for i in ex.args]

            if false in calls 
                false
            elseif true in calls
                true
            else
                nothing
            end
        else
            calls = [recurse(i, false) for i in ex.args]
            if false in calls
                false
            else 
                nothing
            end
        end
    end
    

    # call the recursion
    return recurse(ex, true)
end


@testset "get_nonindexed_vars" begin
    @test get_nonindexed_vars(:(a+b[t]), :t) == Set([:a])
    @test get_nonindexed_vars(:a, :t) == Set([:a])
    @test get_nonindexed_vars(:(a+b[t]+c+t), :t) == Set([:a,:c])
end

"
Collect all variables in an expression that isn't indexed by `x`
"
get_nonindexed_vars(ex, x::Symbol) = begin
    vars = Set()
    ex′ = Expr(:begin, ex)

    # behaviour for each type
    recurse(ex::Expr) = begin
        i₁ = ex.head ∈ [:call, :macocall] ? 2 : 1 
        for i ∈ i₁:length(ex.args)
            if i==i₁ && ex.head == :ref 
                # nothing
            elseif ex.args[i] isa Symbol && ex.args[i] != x
                push!(vars, ex.args[i])
            elseif ex.args[i] isa Expr
                recurse(ex.args[i])
            end
        end
    end 

    recurse(ex′)
    return vars
end


@testset "formulas_to_digraph" begin
    dict = expr_to_formulas(quote
        A[t] = (t == 1 ? 1 : A[t - 1]- C[t]) - D[t]
        B[t] = t == 1 ? 1 : A[t - 1]
        C[t] = ((B[t] * E[t]) / 12) * (1 - 0.5*F[t])
        D[t] = B[t] * F[t] * (1 - 0.5*E)
        Z = 1
    end, :t)

    graph = formulas_to_digraph(dict)

    # Test forwards and backwards
    edges₁ = Set()
    edges₂ = Set()
    for (var, links) ∈ graph.nodedict
        for varᵢₙ ∈ links.in 
            push!(edges₁, varᵢₙ => var)
        end
        for varₒ ∈ links.out 
            push!(edges₂, var => varₒ)
        end
    end

    @test edges₁ == Set([:A=>:A, :C=>:A, :D=>:A, :A=>:B, :B=>:C, :B=>:D])
    @test edges₂ == edges₁ 
end

"
Convert a formula dictionary into a directed graph describing the flow
of all the variables.
"
formulas_to_digraph(formulas::OrderedDict{Symbol, SheetFormula})::DiGraph{Symbol} = begin
    # Convert the dictionary into a sequence
    symbol_links = Dict(key => Vector{Symbol}() for key ∈ keys(formulas))
    for (varⱼ, sheetformula) ∈ formulas
        ex = sheetformula.expr
        for varᵢ ∈ get_vars(ex)
            haskey(formulas, varᵢ) && push!(symbol_links[varᵢ], varⱼ)
        end
    end
    RowSheets.DiGraph(symbol_links)
end


"
Calculate the possible calculation sequence of a graph
"
generate_calculation_sequence(graph::DiGraph; preferred_sequence=nothing) = begin
    sequence = RowSheets.traversalsequence(graph)
    if preferred_sequence !== nothing
        sequence_bias = OrderedDict(var=>i for (i,var) ∈ enumerate(preferred_sequence))
        sequence = [sort(clus, by=x->(sequence_bias[x])) for clus in sequence]
    end

    return sequence
end


@testset "expr_to_formulas" begin
    dict = expr_to_formulas(
        quote
            a = 1
            b[t] = cat
            d = hello 
        end, :t) 

    @test [keys(dict)...] == [:a, :b, :d]

    @test [x.line isa LineNumberNode  for (_, x) ∈ dict] == [true, true, true]
    
    @test [SheetFormula(x.expr, x.broadcast, nothing) for (_, x) ∈ dict] == [
        SheetFormula(:(1), false, nothing)
        SheetFormula(:(cat), true, nothing)
        SheetFormula(:(hello), false, nothing)
        ]
end

expr_to_formulas(expr, x::Symbol; line::Union{Nothing, LineNumberNode}=nothing) = begin
    # Convert to convenient form
    if !(expr isa Expr) || (expr.head != :(block))
        expr = Expr(:block, expr)
    end

    # Collect all definitions into dict (e.g. Dict(:A=>:(B+C), :B=>:(C+D))
    formulas = OrderedDict{Symbol, SheetFormula}()
    lastline = line
    for e ∈ expr.args
        if e isa LineNumberNode || e === nothing
            lastline = e
            continue
        end

        if !(expr isa Expr) || (e.head != :(=))
            throw(ErrorException("Only assignment expressions are valid, like `A = 5` and `A[$x] = 5`, got: $(e)"))
        end

        var, bcast =  if e.args[1] isa Symbol
            e.args[1], false
        elseif e.args[1].head == :ref && e.args[1].args[1] isa Symbol && e.args[1].args[2:end] == [x]
            e.args[1].args[1], true
        else
            throw(ErrorException("Only assignment expressions are valid, like `A = 5` and `A[$x] = 5`, got: $(e)"))
        end

        if haskey(formulas, var)
            throw(ErrorException("Formula definition for $(var) may only occur once."))
        end

        formulas[var] = SheetFormula(e.args[2], bcast, lastline)
        lastline = line
    end

    return formulas
end


"
Last item in an OrderedDict
"
last(d::OrderedDict) = begin
    for (i, item) ∈ enumerate(d)
        i == length(d) && return item
    end
end

"
Subsample an OrderedDict
"
subsample(d::OrderedDict, keys) = begin
    OrderedDict(i=>d[i] for i ∈ keys)
end


"
This will transform `varname` into a scrabled new symgenx version.
Same input will have same output.
"
symgenx_reproduce(varname) = begin
    str = [i for i ∈ "₀₁₂₃₄₅₆₇₈₉ₐₑₒₓₔ"]
    choice = [str[(i%length(str))+1] for i ∈ sha1(varname)[1:8]]
    return Symbol(join(choice[1:3]) * string(varname) * join(choice[4:end]))
end


"
Convenience method for generating same unique reproducable symbol.
"
reproducable_init_symbol(var) = begin
    symgenx_reproduce(string(var) * "_init")
end
