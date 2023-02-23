@testitem "has_var" begin
    @test SpreadRows.has_var(:(a + b + c + foo(a + b + c + foo(d))), :d)
    @test !SpreadRows.has_var(:(a + b + c + foo(a + b + c + foo(d))), :q)
end

@testitem "expr_to_formulas" begin
    dict = SpreadRows.expr_to_formulas(
        quote
            a = 1
            b[t] = cat
            d = hello
        end,
        :t,
    )

    @test [keys(dict)...] == [:a, :b, :d]

    @test [x.line isa LineNumberNode for (_, x) in dict] == [true, true, true]

    @test [SpreadRows.SpreadFormula(x.expr, x.broadcast, nothing) for (_, x) in dict] == [
        SpreadRows.SpreadFormula(:(1), false, nothing)
        SpreadRows.SpreadFormula(:(cat), true, nothing)
        SpreadRows.SpreadFormula(:(hello), false, nothing)
    ]
end

@testitem "formulas_to_digraph" begin
    dict = SpreadRows.expr_to_formulas(
        quote
            A[t] = (t == 1 ? 1 : A[t - 1] - C[t]) - D[t]
            B[t] = t == 1 ? 1 : A[t - 1]
            C[t] = ((B[t] * E[t]) / 12) * (1 - 0.5 * F[t])
            D[t] = B[t] * F[t] * (1 - 0.5 * E)
            Z = 1
        end,
        :t,
    )

    graph = SpreadRows.formulas_to_digraph(dict)

    # Test forwards and backwards
    edges₁ = Set()
    edges₂ = Set()
    for (var, links) in graph.nodedict
        for varᵢ in links.in
            push!(edges₁, varᵢ => var)
        end
        for varₒ in links.out
            push!(edges₂, var => varₒ)
        end
    end

    @test edges₁ == Set([:A => :A, :C => :A, :D => :A, :A => :B, :B => :C, :B => :D])
    @test edges₂ == edges₁
end

@testitem "get_nonindexed_vars" begin
    @test SpreadRows.get_nonindexed_vars(:(a + b[t]), :t) == Set([:a])
    @test SpreadRows.get_nonindexed_vars(:a, :t) == Set([:a])
    @test SpreadRows.get_nonindexed_vars(:(a + b[t] + c + t), :t) == Set([:a, :c])
    @test SpreadRows.get_nonindexed_vars(:(a[t + 1] + b[t] + c + t), :t) == Set([:c])
    @test SpreadRows.get_nonindexed_vars(:(a[foo(2^t) + 1] + b[t] + c + t), :t) == Set([:c])
end

@testitem "expr_is_linear" begin
    @test SpreadRows.expr_is_linear(:(t * t), :t) == false
    @test SpreadRows.expr_is_linear(:(t^2), :t) == false
    @test SpreadRows.expr_is_linear(:((5 + 67) * foo(t)), :t) == false
    @test SpreadRows.expr_is_linear(:(t == 0 ? 1 : 2), :t) == false

    @test SpreadRows.expr_is_linear(:(t + 1 + 2 / 3 * 5), :t)
    @test SpreadRows.expr_is_linear(:(t * 2 + 1 + 2 / 3 * 5), :t)
    @test SpreadRows.expr_is_linear(:((5 + 67) * t), :t)

    @test SpreadRows.expr_is_linear(:(1 + (a + t)), :t) == true
    @test SpreadRows.expr_is_linear(:(1 + (a + 2t)), :t) == true
    @test SpreadRows.expr_is_linear(:(1 + (a + (t * t))), :t) == false
    @test SpreadRows.expr_is_linear(:(1 + (a + (q * q))), :t) === nothing # no t
    @test SpreadRows.expr_is_linear(:(1 + (a + (t) + t - t + 5)), :t) == false
end

@testitem "get_indexing" begin
    @test(SpreadRows.get_indexing(:(a[5] + a[8] + b[t + 40]), :t) == [:b => :(t + 40)])
    @test(
        SpreadRows.get_indexing(:(a[5] + a[8] + b[t + 40] + b[t - 30] + c[t]), :t) ==
            [:b => :(t + 40), :b => :(t - 30), :c => :t]
    )
end

@testitem "get_vars" begin
    @test SpreadRows.get_vars(:(a = foo(b + c + bar(d) + e[f]))) == [:a, :b, :c, :d, :e, :f]
end

@testitem "formula_cluster_topology" begin
    include("helpers.jl")

    formulas = OrderedDict(
        :A => :((t == 1 ? 1 : A[t - 1] - C[t]) - D[t]),
        :B => :(t == 1 ? 1 : A[t - 1]),
        :C => :(((B[t] * E[t]) / 12) * (1 - 0.5 * F[t])),
        :D => :(B[t] * F[t] * (1 - 0.5 * E)),
    )
    @test SpreadRows.formula_cluster_topology(formulas, :t) == (-1, [:B, :C, :D, :A])

    formulas = OrderedDict(
        :A => :((t == 1 ? 1 : A[t - 1] - C[t]) - D),
        :B => :(t == 1 ? 1 : A[t - 1]),
        :C => :(((B[t] * E[t]) / 12) * (1 - 0.5 * F[t])),
        :D => :(B[t] * F[t] * (1 - 0.5 * E)),
    )
    @test_throws SpreadRows.CalculationSequenceError SpreadRows.formula_cluster_topology(
        formulas, :t
    )

    @test_throws SpreadRows.CalculationSequenceError @spread i ∈ 1:10 begin
        a[i] = b[i]
        b[i] = a[i]
    end
end

@testitem "formula_cluster_to_expr" begin
    dict = SpreadRows.expr_to_formulas(
        quote
            A[t] = (t == 1 ? 1 : A[t - 1] - C[t]) - D[t]
            B[t] = t == 1 ? 1 : A[t - 1]
            C[t] = (B[t] / 12) * (1 - 0.5 * B[t])
            D[t] = B[t] * 0.5
        end,
        :t,
    )

    @test collect(keys(dict)) == [:A, :B, :C, :D]
    @test eval(
        Expr(:block, :(T = 1:10), SpreadRows.formula_cluster_to_expr(dict, :t, :T), :B)
    ) isa Vector
end

@testitem "SpreadConfig" begin
    @test SpreadRows.SpreadConfig(:(x ∈ X = 1:10), :(
        begin
            p[x] = 5
        end
    )) !== nothing
    @test SpreadRows.SpreadConfig(:(x ∈ X = 1:10), :(function (_) end)) !== nothing
    @test SpreadRows.SpreadConfig(:(function (x in X=1:10,) end)) !== nothing
end

@testitem "@spread" begin
    T = collect(1:100)

    @spread t ∈ T A[t] = t
    @test A == collect(1:100)

    @spread x ∈ T[end:-1:1] B[x] = x
    @test B == collect(100:-1:1)

    @spread t ∈ T begin
        D[t] = t + T[t]
    end
    @test D == collect(1:100) * 2

    @test (@spread t ∈ T begin
        a = 999
        C[t] = (t == 1 ? 51 : C[t - 1] + 1)
    end) == collect(51:(50 + 100))

    q = 10
    @spread t ∈ T D[t] = B[t] + 7 + q
    @test D == @.(B + 7 + q)

    @spread t ∈ T begin
        sum_assured_t0 = 10000
    end
    @test sum_assured_t0 == 10000

    @spread t ∈ T H[t] = t == 1 ? 1 : A[t - 1] + B[t]
    @test H == [t == 1 ? 1 : A[t - 1] + B[t] for t in T]

    @test_throws SpreadRows.CalculationSequenceError @spread t ∈ 1:10 a[t] = a[t]

    @spread t ∈ T = 1:600 begin
        age_t0 = 30
        duration_t0 = 6
        premium_t0 = 100
        sum_assured_t0 = 10000
        age[t] = floor(Int, age_t0 + t / 12)
        duration[t] = duration_t0 + t
        qx[t] = age[t] / 1000
        lapse_rate_m[t] = 1 / qx[t] / 1000
        no_pols_som[t] = if t == 1
            1
        else
            no_pols_eom[t - 1]
        end
        no_deaths[t] = no_pols_som[t] * qx[t] / 12 * (1 - 0.5 * lapse_rate_m[t])
        no_surrenders[t] = no_pols_som[t] * lapse_rate_m[t] * (1 - 0.5 * qx[t])
        no_pols_eom[t] = if t == 1
            1
        else
            no_pols_eom[t - 1]
        end - no_deaths[t] - no_surrenders[t]
        premium_income[t] = premium_t0 * no_pols_eom[t] / 12
        claims_outgo[t] = sum_assured_t0 * no_deaths[t]
        profit[t] = premium_income[t] - claims_outgo[t]
        yield_curve = 0.1
        profit_discounted[t] = profit[t] * (1 + yield_curve)^(-t)
        liability[t] = -profit_discounted[t] + if t < length(T)
            liability[t + 1]
        else
            0
        end
    end

    f = @spread (i ∈ loop) -> begin
        a[i] = i^2
    end
    f(1:100)

    f = @spread (a, b, i ∈ loop) -> begin
        c[i] = 5^i + b
    end
    f(1, 2, 1:10)

    @spread test₁(a, b; i ∈ loop=1:10) = begin
        c[i] = 5^i + b
    end
    test₁(1, 2; loop=1:10)

    @spread test₂(a, b, x ∈ X; __) = begin
        c[x] = 20
    end
    @test test₂(1, 2, 1:100; c=10).c == 10

    @spread function test₃(; t ∈ T=1:600, __)
        age_t0 = 30
        duration_t0 = 6
        premium_t0 = 100
        sum_assured_t0 = 10000
        age[t] = floor(Int, age_t0 + t / 12)
        duration[t] = duration_t0 + t
        qx[t] = age[t] / 1000
        lapse_rate_m[t] = 1 / qx[t] / 1000
        no_pols_som[t] = if t == 1
            1
        else
            no_pols_eom[t - 1]
        end
        no_deaths[t] = no_pols_som[t] * qx[t] / 12 * (1 - 0.5 * lapse_rate_m[t])
        no_surrenders[t] = no_pols_som[t] * lapse_rate_m[t] * (1 - 0.5 * qx[t])
        no_pols_eom[t] = if t == 1
            1
        else
            no_pols_eom[t - 1]
        end - no_deaths[t] - no_surrenders[t]
        premium_income[t] = premium_t0 * no_pols_eom[t] / 12
        claims_outgo[t] = sum_assured_t0 * no_deaths[t]
        profit[t] = premium_income[t] - claims_outgo[t]
        yield_curve = 0.1
        profit_discounted[t] = profit[t] * (1 + yield_curve)^(-t)
        #! format: off
        liability[t] = -profit_discounted[t] + if t < length(T)
            liability[t + 1]
        else
            0
        end
        #! format: on
    end

    @test test₃().age_t0 == 30
end

@testitem "dont add nothing linenumbers" begin
    include("helpers.jl")

    @spread f₂(t ∈ T;) = begin
        a[t] = b[t]
        b[t] = if t == 1
            1
        else
            a[t - 1]
        end
    end

    @test f₂(1:10).a == f₂(1:10).b

    expr = :(f₂(t ∈ T;) = begin
        a[t] = b[t]
        b[t] = if t == 1
            1
        else
            a[t - 1]
        end
    end)

    expr = postwalk(x -> x isa LineNumberNode ? nothing : x, expr)

    expr = SpreadRows.spreadconfig_to_expr(SpreadRows.SpreadConfig(expr))

end

@testitem "graphtraversal" begin
    edges = [
        (:x1, :x2),
        (:x1, :x1),
        (:x2, :x3),
        (:x3, :x4),
        (:x4, :x5),
        (:x5, :x6),
        (:x5, :x8),
        (:x8, :x3),
        (:x8, :x9),
        (:x6, :x7),
    ]

    graph₁ = SpreadRows.DiGraph(edges)

    # (i → j) and (j → k)
    for (j, node) in graph₁.nodedict
        for i in node.in
            @test (i, j) ∈ edges
        end
        for k in node.out
            @test (j, k) ∈ edges
        end
    end

    deps = Dict(
        :x1 => [:x1, :x2],
        :x2 => [:x3],
        :x3 => [:x4],
        :x4 => [:x5],
        :x5 => [:x6, :x8],
        :x6 => [:x7],
        :x8 => [:x3, :x9],
    )
    graph₂ = SpreadRows.DiGraph(deps)

    # Test if both approaches for building a graph are the same
    @test all(keys(graph₁.nodedict) .== keys(graph₂.nodedict))
    @test all([
        graph₁.nodedict[k].out == graph₂.nodedict[k].out for k in keys(graph₁.nodedict)
    ])
    @test all([
        graph₁.nodedict[k].in == graph₂.nodedict[k].in for k in keys(graph₁.nodedict)
    ])

    @test SpreadRows.traversalsequence(graph₁) ==
        [[:x1], [:x2], [:x3, :x4, :x5, :x8], [:x6], [:x7], [:x9]]

    deps = Dict{Symbol,Vector{Symbol}}(
        :x1 => [:x1, :x2],
        :x2 => [:x3],
        :x3 => [:x4],
        :x4 => [:x5],
        :x5 => [:x6, :x8],
        :x6 => [:x7],
        :x8 => [:x3, :x9],
        :x10 => [],
    )
    graph₃ = SpreadRows.DiGraph(deps)
    @test SpreadRows.traversalsequence(graph₃) ==
        [[:x10], [:x1], [:x2], [:x3, :x4, :x5, :x8], [:x6], [:x7], [:x9]]
end
