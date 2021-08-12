@testset "@sheet" begin
    T = collect(1:100)

    @sheet_ t ∈ T A[t] = t 
    @test A == collect(1:100)
    
    @sheet_ x ∈ T[end:-1:1] B[x] = x
    @test B == collect(100:-1:1)

    @sheet_ t ∈ T begin D[t] = t + T[t] end
    @test D == collect(1:100)*2

    @test (@sheet_ t ∈ T begin
                a = 999
                C[t] = ( t==1  ? 51 : C[t-1]+1 )
           end) == collect(51:50+100)

    q = 10
    @sheet_ t ∈ T D[t] = B[t] + 7 + q
    @test D == @.(B + 7 + q)

    @sheet_ t ∈ T begin sum_assured_t0 = 
        10000
    end
    @test sum_assured_t0 == 10000

    @sheet_ t ∈ T  H[t] = t==1 ? 1 : A[t-1] + B[t]
    @test H == [t==1 ? 1 : A[t-1] + B[t] for t ∈ T]

    @test_throws CalculationSequenceError @sheet_ t ∈ 1:10 a[t] = a[t]

    @sheet_ t ∈ 1:600  begin
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

sheet_expr(sheetconfig::SheetConfig; with_inits=false) = begin
    x = sheetconfig.loopdef[1]
    X′ = gensymx("X")

    expr = quote end
    push!(expr.args, sheetconfig.source)
    push!(expr.args, :($X′ = $(sheetconfig.loopdef[2])))

    if with_inits
        for var ∈ keys(sheetconfig.formulas)
            push!(expr.args, :($(initsym(var)) = $var === nothing))
        end
    end

    for cluster ∈ sheetconfig.ordered_clusters
        push!(
            expr.args,
            formula_cluster_to_expr(
                subsample(sheetconfig.formulas, cluster), x, X′; with_inits))
    end

    (lastvar, lastformula) = last(sheetconfig.formulas)
    push!(expr.args, lastformula.line)
    push!(expr.args, lastvar)

    return expr
end

macro sheet(exprloop::Expr, exprbody)
    sheetconfig = SheetConfig(exprloop, exprbody; source=__source__)
    esc(sheet_expr(sheetconfig))
end


@testset "@sheetfn" begin
    f = @sheet_ (i ∈ loop)->begin
        a[i] = i^2
    end
    f(1:100)

    f = @sheetfn (a, b, i ∈ loop)->begin
        c[i] = 5^i + b
    end
    f(1, 2, 1:10)

    @sheetfn test₁(a, b; i∈loop=1:10) = begin
        c[i] = 5^i + b
    end
    test₁(1, 2; loop=1:10)
end

sheetfn_expr(funcsplit::Dict, sheetconfig::SheetConfig) = begin
    funcsplit′ = deepcopy(funcsplit)
     expr = sheet_expr(sheetconfig)
    
     push!(expr.args, 
           Expr(:tuple, 
                [Expr(:(=), var, var) for var in keys(sheetconfig.formulas)]...))

    funcsplit′[:body] = expr

    return ExprTools.combinedef(funcsplit′)
end

macro sheetfn(exprbody::Expr)
    funcsplit = ExprTools.splitdef(exprbody)
    exprloop = extract_loopdef_and_adjust_args_and_kwargs!(funcsplit)
    sheetconfig = SheetConfig(exprloop, funcsplit[:body]; source=__source__)

    return esc(sheetfn_expr(funcsplit, sheetconfig))
end


@testset "@sheetfnkw" begin

    @sheet_ test₂(a, b, x∈X; __) = begin
         c[x] = 20
    end
    @test test₂(1, 2, 1:100; c=10).c == 10

    @sheet_ test₃(;t∈T = 1:600, __) = begin
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
        liability[t] = -profit_discounted[t] + if t<length(T) liability[t+1] else 0 end
    end

    @test test₃().age_t0 == 30
    [test₃(;T=(1:600), premium_t0=10+x/10).liability[30] for x ∈ 50:10:500]

end

sheetfnkw_expr(funcsplit::Dict, sheetconfig::SheetConfig) = begin
    funcsplit′ = deepcopy(funcsplit)
    args = [MacroTools.splitarg(i)[1] for i in [funcsplit′[:args]; funcsplit′[:kwargs]]]

    for arg in args
        if haskey(sheetconfig.formulas, arg)
            throw(ErrorException("Keyword `$arg` both defined in function body and in function header."))
        end
    end

    for arg ∈ keys(sheetconfig.formulas)
        push!(funcsplit′[:kwargs], Expr(:kw, arg, nothing))
    end

    expr = sheet_expr(sheetconfig; with_inits=true)

    push!(expr.args, 
    Expr(:tuple, 
         [Expr(:(=), var, var) for var in keys(sheetconfig.formulas)]...))

    funcsplit′[:body] = expr
    return esc(ExprTools.combinedef(funcsplit′))
end

macro sheet_(expr::Expr)
    sheetconfig_to_expr(SheetConfig(nothing, expr; source=__source__))
end

macro sheet_(expriter::Expr, exprbody::Expr)
    sheetconfig_to_expr(SheetConfig(nothing, expriter, exprbody; source=__source__))
end

sheetconfig_to_expr(sheetconfig::SheetConfig) = begin
    
    # Iterator Symbols
    x = sheetconfig.iterator.inner
    X = sheetconfig.iterator.outer
    if X === nothing 
        X = gensymx(x) 
    end
    itr = sheetconfig.iterator.iterator

    # Don't mutate function definition
    funcdef = deepcopy(sheetconfig.funcdef)
    # if you want to pass keyword arguments to overwrite variable in the body
    
    with_inits = false
    if funcdef !== nothing 
        for (i, kwarg) ∈ enumerate(get(funcdef, :kwargs, []))
            if kwarg == :__
                with_inits = true
                deleteat!(funcdef[:kwargs], i)
                break
            end
        end
    end

    with_argiter = false
    if funcdef !== nothing
        for arg_kwarg ∈ (get(funcdef, :args, []),
                         get(funcdef, :kwargs, [])) # Will this allow mutation?
            for (i, arg) ∈ enumerate(arg_kwarg)
                if arg == :_
                    with_argiter = true
                    arg_kwarg[i] = itr === nothing ? X : Expr(:kw, X, itr)
                end
            end
        end
    end

    expr = quote end
    push!(expr.args, sheetconfig.source)
    if !with_argiter
        push!(expr.args, :($X = $(itr)))
    end

    if with_inits
        # Inject keyword arguments to the function header
        if !haskey(funcdef, :kwargs)
            funcdef[:kwargs] = []
        end
        for arg ∈ keys(sheetconfig.formulas)
            push!(funcdef[:kwargs], Expr(:kw, arg, nothing))
        end

        # Inject/wrap formula definitions in a `if x === nothing x[i] = ... end`
        # to allow keyword arguments to overwrite their definitions
        for var ∈ keys(sheetconfig.formulas)
            push!(expr.args, :($(initsym(var)) = $var === nothing))
        end
    end

    # Populate all the formula code
    for cluster ∈ sheetconfig.ordered_clusters
        push!(
            expr.args,
            formula_cluster_to_expr(
                subsample(sheetconfig.formulas, cluster), x, X; with_inits))
    end

    (lastvar, _) = last(sheetconfig.formulas)
    push!(expr.args, lastvar)

    if funcdef !== nothing
        push!(expr.args, 
            Expr(:tuple, [Expr(:(=), var, var) for var in keys(sheetconfig.formulas)]...))

        funcdef[:body] = expr
        return esc(ExprTools.combinedef(funcdef))
    else
        return esc(expr)
    end
end

