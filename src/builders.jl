struct RowSheetParseError <: Exception
    var::String
end


@testset "@rowsheet" begin
    T = collect(1:100)

    @rowsheet t ∈ T A[t] = t 
    @test A == collect(1:100)
    
    @rowsheet x ∈ T[end:-1:1] B[x] = x
    @test B == collect(100:-1:1)

    @rowsheet t ∈ T begin D[t] = t + T[t] end
    @test D == collect(1:100)*2

    @test (@rowsheet t ∈ T begin
                a = 999
                C[t] = ( t==1  ? 51 : C[t-1]+1 )
           end) == collect(51:50+100)

    q = 10
    @rowsheet t ∈ T D[t] = B[t] + 7 + q
    @test D == @.(B + 7 + q)

    @rowsheet t ∈ T begin sum_assured_t0 = 
        10000
    end
    @test sum_assured_t0 == 10000

    @rowsheet t ∈ T  H[t] = t==1 ? 1 : A[t-1] + B[t]
    @test H == [t==1 ? 1 : A[t-1] + B[t] for t ∈ T]

    @test_throws CalculationSequenceError @rowsheet t ∈ 1:10 a[t] = a[t]

    @rowsheet t ∈ 1:600  begin
        age_t0 = 30
        duration_t0 = 6
        premium_t0 = 100
        sum_assured_t0 = 10000
        age[t] = floor(Int, age_t0 + t/12)
        duration[t] = duration_t0 + t
        qx[t] = age[t] / 1000
        lapse_rate_m[t] = 1 / qx[t] / 1000
        no_pols_som[t] = if t==1 1 else no_pols_eom[t-1] end
        no_deaths[t] = no_pols_som[t]*qx[t]/12*(1-0.5*lapse_rate_m[t])
        no_surrenders[t] = no_pols_som[t]*lapse_rate_m[t]*(1-0.5*qx[t])
        no_pols_eom[t] = if t==1 1 else no_pols_eom[t-1] end - no_deaths[t] - no_surrenders[t]
        premium_income[t] = premium_t0*no_pols_eom[t]/12
        claims_outgo[t] = sum_assured_t0*no_deaths[t]
        profit[t] = premium_income[t]-claims_outgo[t]
        yield_curve = 0.1
        profit_discounted[t]  = profit[t]*(1+yield_curve)^(-t)
        liability[t] = -profit_discounted[t] + if t<600 liability[t+1] else 0 end
    end
end


@testset "cluster_topology" begin
    formulas = OrderedDict(
        :A => :((t == 1 ? 1 : A[t - 1]- C[t]) - D[t]),
        :B => :(t == 1 ? 1 : A[t - 1]),
        :C => :(((B[t] * E[t]) / 12) * (1 - 0.5*F[t])),
        :D => :(B[t] * F[t] * (1 - 0.5*E))
      )
      @test cluster_topology(formulas, :t) == (-1, [:B, :C, :D, :A])

      formulas = OrderedDict(
        :A => :((t == 1 ? 1 : A[t - 1]- C[t]) - D),
        :B => :(t == 1 ? 1 : A[t - 1]),
        :C => :(((B[t] * E[t]) / 12) * (1 - 0.5*F[t])),
        :D => :(B[t] * F[t] * (1 - 0.5*E))
      )
      @test_throws CalculationSequenceError cluster_topology(formulas, :t)
end


"
For a given cluster of formulae, derive the order in which these formulae
should be computed within `for x ∈ T` and return this order along with
how t is referenced: [-1, 0, +1, nothing]
"
function cluster_topology(formulas::OrderedDict, x::Symbol)
    refs_dict = Dict{Symbol, Any}()
    Δ_dict = Dict{Symbol, Any}()
    all_Δ = Set()

    # Get all the t references and convert them to offsets Δ
    for (key, value) ∈ formulas
        for var ∈ get_nonindexed_vars(value, x) 
            if haskey(formulas, var)
                throw(CalculationSequenceError("Cannot reference full vector while it is part of a cycle: $var"))
            end
        end

        refs = (Set(var=>ex for (var, ex) ∈ get_indexing(value, x) if haskey(formulas, var)))

        Δ = Set(var=>   if expr_is_linear(expr, x) == true
                            eval(replace_var(expr, x, 0))
                        else
                            0 # TODO: more inspection needed
                        end for (var, expr) ∈ refs)

        refs_dict[key] = refs
        Δ_dict[key] = Δ
        all_Δ = all_Δ ∪ [δ for (_, δ) ∈ Δ]
    end

    # Continue only if all the references are either backwards or forwards looking and not mixed
    rtype = all(all_Δ .<= 0) ? -1 : all(all_Δ .>= 0) ? +1 : nothing
    if rtype === nothing
        return rtype, keys(formulas)
    end

    edges = Vector{Tuple{Symbol, Symbol}}()
    for (key, Δ) in Δ_dict 
        for (var, δ) ∈ Δ 
            if δ==0 
                push!(edges, (var, key))
            end
        end 
    end

    # Get sequence... flatten... append lost keys
    sequence = traversalsequence!(DiGraph(edges))
    sequence = [var for cluster in sequence for var in cluster]
    sequence = [sequence; setdiff!(OrderedSet(keys(formulas)), sequence)...]

    return rtype, sequence
end


@testset "transform_expr_rowsheet" begin
    transform_expr_rowsheet(:(t ∈ T), quote
        A[t] = (t == 1 ? 1 : A[t - 1]- C[t]) - D[t]
        B[t] = t == 1 ? 1 : A[t - 1]
        C[t] = ((B[t] * E[t]) / 12) * (1 - 0.5*F[t])
        D[t] = B[t] * F[t] * (1 - 0.5*E)
        Z = 1
    end);
end

function transform_expr_rowsheet(exprloop::Expr, exprbody; line::Union{LineNumberNode, Nothing}=nothing)

    (x, X) = if (exprloop.head == :call && 
                 length(exprloop.args) == 3 && 
                 exprloop.args[1] ∈ (:in, :∈) && 
                 exprloop.args[2] isa Symbol)
        (exprloop.args[2], exprloop.args[3])
    else 
        throw(RowSheetParseError("Expected loop definition like `t ∈ T`, got `$exprloop`"))
    end
    X′ = gensymx("X")
    X′expr = :($(X′) = collect($X))

    formulas = expr_to_formulas(exprbody, x; line)
    ret = transform_expr_all(formulas, x, X′)

    # Make sure X′ features
    insert!(ret.args, 1, X′expr)
    insert!(ret.args, 1, line)

    # return last variable instance
    (lastvar, _) = last(formulas)
    push!(ret.args, lastvar)

    return ret
end



@testset "transform_expr_all" begin
    dict = expr_to_formulas(quote
        A[t] = (t == 1 ? 1 : A[t - 1]- C[t]) - D[t]
        B[t] = t == 1 ? 1 : A[t - 1]
        C[t] = ((B[t] * E[t]) / 12) * (1 - 0.5*F[t])
        D[t] = B[t] * F[t] * (1 - 0.5*E)
        Z = 1
    end, :t)

    transform_expr_all(dict, :t, (1:100)); 
end

"
Transform all formulae/equations in a given variable library `:(B = t==1 ? 1 : A[t-1]; A = B[t]; C=A+100)`
into a coherent forloop `:(for t ∈ T A[t] = B[t]; B[t] = t==1 ? 1 : A[t-1] end; @.(C = A+100))`.

This will traverse the full graph dependencies
"
function transform_expr_all(formulas::OrderedDict{Symbol, FormulaPoint}, x::Symbol, X)
    # Convert the dictionary into a sequence
    symbol_links = Dict(key => Vector{Symbol}() for key ∈ keys(formulas))
    for (varⱼ, formulapoint) ∈ formulas
        ex = formulapoint.expr
        for varᵢ ∈ get_vars(ex)
            haskey(formulas, varᵢ) && push!(symbol_links[varᵢ], varⱼ)
        end
    end
    sequence = RowSheets.traversalsequence!(RowSheets.DiGraph(symbol_links))
    sequence_bias = OrderedDict(key=>i for (i,key) ∈ enumerate(keys(formulas)))

    # Keep order in cluster same as input order (to allow user intervension)
    expr′_list = []
    for cluster ∈ sequence
        formulas′ = OrderedDict(i=>formulas[i] for i ∈ sort(cluster, by=x->(sequence_bias[x])))
        push!(expr′_list, transform_expr_cluster(formulas′, x, X))
    end

    return Expr(:block, expr′_list...)
end



@testset "transform_expr_cluster" begin
    dict = expr_to_formulas(quote
        A[t] = (t == 1 ? 1 : A[t - 1]- C[t]) - D[t]
        B[t] = t == 1 ? 1 : A[t - 1]
        C[t] = ((B[t] * E[t]) / 12) * (1 - 0.5*F[t])
        D[t] = B[t] * F[t] * (1 - 0.5*E)
    end, :t)

    transform_expr_cluster(dict, :t, (1:100));
    
end

"
Transform a cluster of formulae/equations that is possibly cyclic `:(B = t==1 ? 1 : A[t-1]; A = B[t])`
into a coherent forloop `:(for t ∈ T A[t] = B[t]; B[t] = t==1 ? 1 : A[t-1] end)`.

This can be used in each traversal step when traversing the full formuale dependency graph.
"
function transform_expr_cluster(formulas::OrderedDict{Symbol, FormulaPoint}, x::Symbol, X)
    
    # Single definition might have some good shortcuts
    ret = if length(formulas) == 1
        (var, formulapoint) = first(formulas)
        e = formulapoint.expr

        # No broadcast, normal equality
        if !formulapoint.broadcast
            Expr(:block, formulapoint.line, Expr(:(=), var, e))

        # Broadcast via list comprehension
        elseif !has_var(e, var)
            Expr(:block, formulapoint.line, Expr(:(=), var, Expr(:comprehension, Expr(:generator, e, Expr(:(=), x, X)))))
        end
    end

    if ret === nothing
        for (var, formulapoint) ∈ formulas
            if !formulapoint.broadcast
                throw(CalculationSequenceError("Cannot define full vector while it is part of a cycle: expected `$(var)[$x] = ...`, got `$var = ...`"))
            end
        end

        # Broadcast via long way around
        rtype, seq = cluster_topology(OrderedDict(i=>j.expr for (i,j) ∈ formulas), x)
        
        definitions = Expr(:block)
        for var ∈ seq
            push!(definitions.args, formulas[var].line)
            push!(definitions.args, :($(var) = Vector(undef, length($X))))
        end

        loopover =  rtype > 0 ? :(reverse($X)) : X
        
        assignments = Expr(:block)
        for var ∈ seq
            push!(assignments.args, formulas[var].line)
            push!(assignments.args, :($(var)[$x] = $(formulas[var].expr)))
        end
        
        @gensymx e
        ret = (quote
            $definitions
            try
                for t in $loopover
                    $assignments
                end
            catch $e
                $e isa UndefRefError && throw($CalculationSequenceError())
                rethrow($e)
            end
            nothing
        end)
    end
    
    return ret
end 


macro rowsheet(exprloop::Expr, exprbody)
    esc(transform_expr_rowsheet(exprloop, exprbody; line=__source__))
end
