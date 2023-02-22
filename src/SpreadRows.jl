module SpreadRows
export @spread

using DataStructures: OrderedDict, OrderedSet, SortedSet, DefaultDict
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
