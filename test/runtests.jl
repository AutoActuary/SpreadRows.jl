using RowSheets
using Test

@testset "graphtraversal.jl" begin
    edges = [(:x1, :x2),
             (:x1, :x1),
             (:x2, :x3),
             (:x3, :x4),
             (:x4, :x5),
             (:x5, :x6),
             (:x5, :x8),
             (:x8, :x3),
             (:x8, :x9),
             (:x6, :x7)]

    graph₁ = RowSheets.DiGraph(edges)

    # (i → j) and (j → k)
    for (j, node) ∈ graph₁.nodedict
        for i ∈ node.in
            @test (i,j) ∈ edges
        end
        for k ∈ node.out
            @test (j,k) ∈ edges
        end
    end

    deps = Dict(:x1 => [:x1, :x2, ],
                :x2 => [:x3],
                :x3 => [:x4],
                :x4 => [:x5],
                :x5 => [:x6, :x8],
                :x6 => [:x7],
                :x8 => [:x3, :x9]
                )
    graph₂ = RowSheets.DiGraph(deps)

    # Test if both approaches for building a graph are the same
    @test all(keys(graph₁.nodedict) .== keys(graph₂.nodedict))
    @test all([graph₁.nodedict[k].out == graph₂.nodedict[k].out for k ∈ keys(graph₁.nodedict)])
    @test all([graph₁.nodedict[k].in == graph₂.nodedict[k].in for k ∈ keys(graph₁.nodedict)])

    @test RowSheets.traversalsequence(graph₁) == [[:x1], [:x2], [:x5, :x3, :x8, :x4], [:x9], [:x6], [:x7]]
end;
