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

rowsheet_expr(sheetformulas::SheetFormulas; with_inits=false) = begin
    x = sheetformulas.loopdef[1]
    X′ = gensymx("X")

    expr = quote end
    push!(expr.args, sheetformulas.__source__)
    push!(expr.args, :($X′ = $(sheetformulas.loopdef[2])))

    if with_inits
        for var ∈ keys(sheetformulas.formulas)
            push!(expr.args, :($(initsym(var)) = $var === nothing))
        end
    end

    for cluster ∈ sheetformulas.ordered_clusters
        push!(
            expr.args,
            formula_cluster_to_expr(
                subsample(sheetformulas.formulas, cluster), x, X′; with_inits))
    end

    (lastvar, lastformula) = last(sheetformulas.formulas)
    push!(expr.args, lastformula.line)
    push!(expr.args, lastvar)

    return expr
end

macro rowsheet(exprloop::Expr, exprbody)
    sheetformulas = SheetFormulas(exprloop, exprbody; source=__source__)
    esc(rowsheet_expr(sheetformulas))
end


@testset "@rowsheetfn" begin
    f = @rowsheetfn hello(i ∈ loop)->begin
        a[i] = i^2
    end
    f(1:100)

    f = @rowsheetfn (a, b, i ∈ loop)->begin
        c[i] = 5^i + b
    end
    f(1, 2, 1:10)

    @rowsheetfn test₁(a, b; i∈loop=1:10)->begin
        c[i] = 5^i + b
    end
    test₁(1, 2; loop=1:10)
end

rowsheetfn_expr(funcsplit::Dict, sheetformulas::SheetFormulas) = begin
    funcsplit′ = deepcopy(funcsplit)
     expr = rowsheet_expr(sheetformulas)
    
     push!(expr.args, 
           Expr(:tuple, 
                [Expr(:(=), var, var) for var in keys(sheetformulas.formulas)]...))

    funcsplit′[:body] = expr

    return combinedef(funcsplit′)
end

macro rowsheetfn(exprbody::Expr)
    funcsplit = splitdef(exprbody)
    exprloop = extract_loopdef_and_adjust_args_and_kwargs!(funcsplit)
    sheetformulas = SheetFormulas(exprloop, funcsplit[:body]; source=__source__)

    return esc(rowsheetfn_expr(funcsplit, sheetformulas))
end


@testset "@rowsheetfnkw" begin

    @rowsheetfnkw test₂(a, b, x∈X)->begin
         c[x] = 20
    end

    test₂(1, 2, 1:100; c=10)

    @rowsheetfnkw test₃(;t∈T = 1:600)->begin
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
    [test₃(;T=(1:600),
            premium_t0=10+x/10).liability[30] for x ∈ 50:10:500]

end

rowsheetfnkw_expr(funcsplit::Dict, sheetformulas::SheetFormulas) = begin
    funcsplit′ = deepcopy(funcsplit)
    args = [splitarg(i)[1] for i in [funcsplit′[:args]; funcsplit′[:kwargs]]]

    for arg in args
        if haskey(sheetformulas.formulas, arg)
            throw(ErrorException("Keyword `$arg` both defined in function body and in function header."))
        end
    end

    for arg ∈ keys(sheetformulas.formulas)
        push!(funcsplit′[:kwargs], Expr(:kw, arg, nothing))
    end

    expr = rowsheet_expr(sheetformulas; with_inits=true)

    push!(expr.args, 
    Expr(:tuple, 
         [Expr(:(=), var, var) for var in keys(sheetformulas.formulas)]...))

    funcsplit′[:body] = expr
    return esc(combinedef(funcsplit′))
end

macro rowsheetfnkw(exprbody::Expr)
    funcsplit = splitdef(exprbody)
    exprloop = extract_loopdef_and_adjust_args_and_kwargs!(funcsplit)
    sheetformulas = SheetFormulas(exprloop, funcsplit[:body]; source=__source__)
    rowsheetfnkw_expr(funcsplit, sheetformulas)
end
