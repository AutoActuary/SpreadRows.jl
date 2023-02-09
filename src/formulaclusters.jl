calculationsequenceerrormessage = join(
    strip.(
        split(
            """
            Note that @spread cannot always ensure the formula ordering at compile time.
            For example @spread has to guess when 
            (1.) mixing forwards `+1` and backwards `-1` references
                (like `A[i+1] + A[i-1]`),
            (2.) using runtime variables in references (like `c` in `A[i+c]`),
            (3.) nonlinear indexing (like `A[i^2-3i]`),
            (4.) absolute indexing (like `A[34]` without any `i`).
            """,
            "\n",
        )
    ),
    " ",
)

struct CalculationSequenceError <: Exception
    var::String
end
CalculationSequenceError() = begin
    CalculationSequenceError(calculationsequenceerrormessage)
end
function calculation_sequence_error(additional_error)
    return CalculationSequenceError("$additional_error $calculationsequenceerrormessage")
end

"
For a given cluster of formulae, derive the order in which these formulae
should be computed within `for i ∈ I` and return this order along with
how `i` is referenced: 
    backwards: -1
    no-offset: 0
    forwards: +1
    unknown: nothing
"
function formula_cluster_topology(formulas::OrderedDict, x::Symbol)
    refs_dict = Dict{Symbol,Any}()
    Δ_dict = Dict{Symbol,Any}()
    all_Δ = Set()

    # Get all the t references and convert them to offsets Δ
    for (key, value) in formulas
        for var in get_nonindexed_vars(value, x)
            if haskey(formulas, var)
                throw(
                    CalculationSequenceError(
                        "Cannot reference full vector while it is part of a cycle: expected `$(var)[$x] = ...`, got `$var = ...`",
                    ),
                )
            end
        end

        refs = (Set(
            var => ex for (var, ex) in get_indexing(value, x) if haskey(formulas, var)
        ))

        Δ = Set(var => if expr_is_linear(expr, x) == true
            eval(replace_var(expr, x, 0))
        else
            0 # TODO: more inspection needed
        end for (var, expr) in refs)

        refs_dict[key] = refs
        Δ_dict[key] = Δ
        all_Δ = all_Δ ∪ [δ for (_, δ) in Δ]
    end

    # Continue only if all the references are either backwards or forwards looking and not mixed
    rtype = if all(all_Δ .<= 0)
        -1
    elseif all(all_Δ .>= 0)
        +1
    else
        nothing
    end
    if rtype === nothing
        return rtype, keys(formulas)
    end

    edges = Vector{Tuple{Symbol,Symbol}}()
    for (key, Δ) in Δ_dict
        for (var, δ) in Δ
            if δ == 0
                push!(edges, (var, key))
            end
        end
    end

    # Get sequence... flatten... append lost keys
    sequence = traversalsequence!(DiGraph(edges))
    sequence = [var for cluster in sequence for var in cluster]

    # Put the leftovers kinda in the same order than found
    not_represented = setdiff!(OrderedSet(keys(formulas)), sequence)
    pre = Vector{Symbol}()
    post = Vector{Symbol}()
    if !isempty(not_represented)
        weights = Dict(var => i for (i, var) in enumerate(keys(formulas)))
        weights_seq = [weights[i] for i in sequence]
        for var in not_represented
            if sum((-0.5 .+ (weights[var] .> weights_seq))) < 0
                push!(pre, var)
            else
                push!(post, var)
            end
        end
    end

    sequence = [pre; sequence; post]
    return rtype, sequence
end


"
Transform a cluster of formulae/equations that is possibly cyclic `:(B = t==1 ? 1 : A[t-1]; A = B[t])`
into a coherent forloop `:(for t ∈ T A[t] = B[t]; B[t] = t==1 ? 1 : A[t-1] end)`.

This can be used in each traversal step when traversing the full formuale dependency graph.
"
function formula_cluster_to_expr(
    formulas::OrderedDict{Symbol,SpreadFormula}, x::Symbol, X::Symbol; with_inits=false
)
    initwrap(var, expr) = begin
        if with_inits
            Expr(:if, reproducable_init_symbol(var), expr)
        else
            expr
        end
    end

    # Single definition might have some good shortcuts
    ret = if length(formulas) == 1
        (var, spreadformula) = first(formulas)
        e = spreadformula.expr

        # No broadcast, normal equality
        if !spreadformula.broadcast
            initwrap(var, Expr(:block, spreadformula.line, Expr(:(=), var, e)))

            # Broadcast via list comprehension
        elseif !has_var(e, var)
            initwrap(
                var,
                Expr(
                    :block,
                    spreadformula.line,
                    Expr(
                        :(=),
                        var,
                        Expr(:comprehension, Expr(:generator, e, Expr(:(=), x, X))),
                    ),
                ),
            )
        end
    end

    if ret === nothing
        for (var, spreadformula) in formulas
            if !spreadformula.broadcast
                throw(
                    CalculationSequenceError(
                        "Cannot define full vector while it is part of a cycle: expected `$(var)[$x] = ...`, got `$var = ...`",
                    ),
                )
            end
        end

        # Broadcast via long way around
        rtype, seq = formula_cluster_topology(
            OrderedDict(i => j.expr for (i, j) in formulas), x
        )

        definitions = Expr(:block)
        for var in seq
            push!(
                definitions.args,
                initwrap(
                    var,
                    Expr(:block, formulas[var].line, :($(var) = Vector(undef, length($X)))),
                ),
            )
        end

        loopover = rtype > 0 ? :(reverse($X)) : X

        f_bounds = boundrycheck_transformer(seq)
        assignments = Expr(:block)
        for var in seq
            push!(assignments.args, formulas[var].line)
            push!(
                assignments.args,
                :($(var)[$x] = $(MacroTools.postwalk(f_bounds, formulas[var].expr))),
            )
        end

        @gensymx e
        ret = (
            quote
                $definitions
                for $x in $loopover
                    $assignments
                end
                nothing
            end
        )
    end

    return ret
end
