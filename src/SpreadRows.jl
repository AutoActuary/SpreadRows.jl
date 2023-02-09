module SpreadRows
export @spread

using ReTest
using DataStructures: OrderedDict, OrderedSet
using GenSymx
using SHA: sha1
using ExprTools: ExprTools
using MacroTools: MacroTools
using DocStringExtensions


include("graphtraversal.jl")
include("structs.jl")
include("formulautils.jl")
include("formulaclusters.jl")
include("macros.jl")
end
