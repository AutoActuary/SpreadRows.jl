using DataStructures: OrderedDict, OrderedSet
using GenSymx
using SHA: sha1
using ExprTools: ExprTools
using MacroTools: MacroTools, postwalk
using SpreadRows

function strexpr(expr)
    return string(postwalk(x -> x isa LineNumberNode ? nothing : x, expr))
end

function templn(args...; mode="w")
    tmpoutput = joinpath(tempdir(), "spreadrows-testitem-debug.txt")
    open(tmpoutput, mode) do fout
        println(fout, args...)
    end
end