module SpreadRows
    export @spread

    using ReTest
    using DataStructures: OrderedDict, OrderedSet
    using GenSymx
    using SHA: sha1
    import ExprTools
    import MacroTools

    include("formulaunrolling.jl")
    include("graphtraversal.jl")
    include("structs.jl")
    include("formulautils.jl")
    include("formulaclusters.jl")
    include("macros.jl")
end
