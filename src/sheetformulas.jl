#=
mutable struct SheetFormulas
    loopdef::Pair{Symbol, Any}
    formulas::OrderedDict{Symbol, FormulaPoint}
    graph::DiGraph{Symbol}
    ordered_clusters::Vector{Vector{Symbol}}
    __source__::Union{LineNumberNode, Nothing}
end



SheetFormulas(exprloop::Expr,
              exprbody::Expr;
              source::Union{LineNumberNode, Nothing}=nothing) = begin

    (x, X) = if (exprloop.head == :call && 
                length(exprloop.args) == 3 && 
                exprloop.args[1] ∈ (:in, :∈) && 
                exprloop.args[2] isa Symbol)
        (exprloop.args[2], exprloop.args[3])
    else 
        throw(RowSheetParseError("Expected loop definition like `t ∈ T`, got `$exprloop`"))
    end

end

=#