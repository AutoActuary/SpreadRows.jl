"
Function to make testing between macros easier
"
striplines(ex) = MacroTools.postwalk(x -> x isa LineNumberNode ? nothing : x, ex)

"
Test if an expression contains the specific variable
"
has_var(ex, s::Symbol) = begin
    did_find = [false]
    MacroTools.postwalk(ex) do x
        if x == s
            did_find[1] = true
        end
        x
    end
    return did_find[1]
end

"
Get all the variable names from an expression, excluding macro names and function names
"
function get_vars(ex)
    varnames = Array{Symbol,1}()

    # behaviour for each type
    recurse(ex) = nothing
    recurse(ex::Symbol) = push!(varnames, ex)
    recurse(ex::Expr) = begin
        i₁ = ex.head ∈ [:call, :macocall] ? 2 : 1
        for i in i₁:length(ex.args)
            recurse(ex.args[i])
        end
    end

    # Apply and return
    recurse(ex)
    return varnames
end

"
Replace a variable (excluding macro names and function names) within an expression with anything
"
function replace_var(ex, var::Symbol, value)
    begin
        ex′ = Expr(:block, deepcopy(ex))

        # behaviour for each type
        recurse(ex) = nothing
        recurse(ex::Expr) = begin
            i₁ = ex.head ∈ [:call, :macocall] ? 2 : 1
            for i in i₁:length(ex.args)
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
end

"
Find references involving `x` in an equation. Note: nested referencing is currently not supported.
"
function get_indexing(ex, x::Symbol)::Vector{Pair{Symbol,Any}}
    references = Vector()

    recurse(ex) = nothing
    function recurse(ex::Expr)
        begin
            if ex.head == :ref && length(ex.args) == 2 && ex.args[1] isa Symbol
                (ex₁, ex₂) = ex.args

                if has_var(ex₂, x)
                    push!(references, ex₁ => ex₂)
                end
            end
            for i in ex.args
                recurse(i)
            end
        end
    end

    recurse(ex)
    return references
end

"
Test if expression contains an linear combination of `x`.
    if linear w.r.t. `x`: true
    if not explicitely linear w.r.t. `x`: false
    if `x` not in expression or cannot heuristically evaluate: nothing
"
function expr_is_linear(ex, x::Symbol)

    # Can we skip the investigation?
    vars = get_vars(ex)
    if !(x in vars)
        return nothing
    elseif [i for i in vars if i == x] != [x] # two or more x's
        return false
    end

    # behaviour for each type
    recurse(ex, linear_parents) = nothing
    recurse(ex::Symbol, linear_parents) = ex == x ? linear_parents : nothing
    function recurse(ex::Expr, linear_parents)
        # Test if only + - and multiplication by a constant in t
        if ex.head == :call && (ex.args[1] == :+ || ex.args[1] == :- || ex.args[1] == :*) # division? No, because Int -> Float
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

"
Collect all variables in an expression that isn't indexed by `x`
"
function get_nonindexed_vars(ex, x::Symbol)
    vars = Set()
    ex′ = Expr(:begin, ex)

    # behaviour for each type
    recurse(ex::Expr) = begin
        i₁ = ex.head ∈ [:call, :macocall] ? 2 : 1
        for i in i₁:length(ex.args)
            if i == i₁ && ex.head == :ref
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

"
Convert a formula dictionary into a directed graph describing the flow
of all the variables.
"
formulas_to_digraph(formulas::OrderedDict{Symbol,SpreadFormula})::DiGraph{Symbol} = begin
    # Convert the dictionary into a sequence
    symbol_links = Dict(key => Vector{Symbol}() for key in keys(formulas))
    for (varⱼ, spreadformula) in formulas
        ex = spreadformula.expr
        for varᵢ in get_vars(ex)
            haskey(formulas, varᵢ) && push!(symbol_links[varᵢ], varⱼ)
        end
    end
    SpreadRows.DiGraph(symbol_links)
end

"
Calculate the possible calculation sequence of a graph
"
function generate_calculation_sequence(graph::DiGraph; preferred_sequence=nothing)
    sequence = SpreadRows.traversalsequence(graph)
    if preferred_sequence !== nothing
        sequence_bias = OrderedDict(var => i for (i, var) in enumerate(preferred_sequence))
        sequence = [sort(clus; by=x -> (sequence_bias[x])) for clus in sequence]
    end

    return sequence
end

function expr_to_formulas(expr, x::Symbol; line::Union{Nothing,LineNumberNode}=nothing)

    # Convert to convenient form
    if !(expr isa Expr) || (expr.head != :(block))
        expr = Expr(:block, expr)
    end

    # Collect all definitions into dict (e.g. Dict(:A=>:(B+C), :B=>:(C+D))
    formulas = OrderedDict{Symbol,SpreadFormula}()
    lastline = line
    for e in expr.args
        if e isa LineNumberNode || e === nothing
            lastline = e
            continue
        end

        if !(expr isa Expr) || (e.head != :(=))
            throw(
                ErrorException(
                    "Only assignment expressions are valid, like `A = 5` and `A[$x] = 5`, got: $(e)",
                ),
            )
        end

        var, bcast = if e.args[1] isa Symbol
            e.args[1], false
        elseif e.args[1].head == :ref &&
            e.args[1].args[1] isa Symbol &&
            e.args[1].args[2:end] == [x]
            e.args[1].args[1], true
        else
            throw(
                ErrorException(
                    "Only assignment expressions are valid, like `A = 5` and `A[$x] = 5`, got: $(e)",
                ),
            )
        end

        if haskey(formulas, var)
            throw(ErrorException("Formula definition for $(var) may only occur once."))
        end

        formulas[var] = SpreadFormula(e.args[2], bcast, lastline)
        lastline = line
    end

    return formulas
end

"
Last item in an OrderedDict
"
function last_item(d::OrderedDict)
    for (i, item) in enumerate(d)
        i == length(d) && return item
    end
end

"
Subsample an OrderedDict
"
function subsample(d::OrderedDict, keys)
    return OrderedDict(i => d[i] for i in keys)
end

"
This will transform `varname` into a scrabled new symgenx type version. 
Same input will have same output.
"
function symgenx_reproduce(varname)
    samplespace = [i for i in "₀₁₂₃₄₅₆₇₈₉ₐₑᵢⱼₒᵣₓₔ"]
    samples = [samplespace[(i % length(samplespace)) + 1] for i in sha1(varname)[1:6]]
    return Symbol(string("ₓ", samples[1]..., varname, samples[2:6]...))
end

"
Convenience method for generating same unique reproducable symbol.
"
reproducable_init_symbol(var) = symgenx_reproduce(string(var) * "_init")
reproducable_map_symbol(var) = symgenx_reproduce(string(var) * "_map")

function boundrycheck_transformer(vars)
    return x -> begin
        if x isa Expr && x.head == :ref && x.args[1] ∈ vars
            var = x.args[1]
            if length(x.args) != 2
                throw(error("`$x` should only be one-dimensional indexing"))
            end

            @gensymx i
            ival = SpreadRows.replace_var(
                SpreadRows.replace_var(x.args[2], :begin, Expr(:call, firstindex, var)),
                :end,
                Expr(:call, lastindex, var),
            )
            err = "Referenced `$x` before initialized."

            #=
            :($i = $ival;
            try
                $var[$i]
            catch e
                if e isa UndefRefError
                    throw($calculation_sequence_error($err))
                end
                rethrow()
            end)
            =#
            Expr(
                :block,
                Expr(:(=), i, ival),
                Expr(
                    :try,
                    Expr(:block, Expr(:ref, var, i)),
                    :e,
                    Expr(
                        :block,
                        Expr(
                            :if,
                            Expr(:call, :isa, :e, :UndefRefError),
                            Expr(
                                :block,
                                Expr(
                                    :call,
                                    :throw,
                                    Expr(:call, calculation_sequence_error, err),
                                ),
                            ),
                        ),
                        Expr(:call, :rethrow),
                    ),
                ),
            )
        else
            x
        end
    end
end
