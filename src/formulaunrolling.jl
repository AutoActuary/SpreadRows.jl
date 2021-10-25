@inline function _setindex_and_widen_and_initialize!(
    vec::Nothing,
    index,
    element, 
    initial_size
)
    vec = Vector{typeof(element)}(undef, initial_size)
    vec[index] = element
    return vec
end


@inline function _setindex_and_widen_and_initialize!(
    vec::AbstractArray{T},
    index,
    element, 
    initial_size=nothing
) where T
    
    if element isa T || typeof(element) === T
        vec[index] = element::T
        return vec
        
    else
        new = Base.setindex_widen_up_to(vec, element, index)
        return new
    end
end

boundsvar(var) = symgenx_reproduce(string(var) * "_map")

boundrycheck_transformer(vars) = begin	
	x -> begin
		if x isa Expr && x.head == :ref && x.args[1] ∈ vars
			var = x.args[1]
			if length(x.args) != 2
				throw(error("`$x` should only be one-dimensional indexing"))
			end
			
			@gensymx i
			ival = SpreadRows.replace_var(
				SpreadRows.replace_var(
					x.args[2],
					:begin,
					:(firstindex($var))
				),
				:end,
				:(lastindex($var))
			)
			err = "Referenced `$x` before initialized."

			Expr(:block, 
				Expr(:(=), i, ival),
				Expr(:(||), Expr(:ref, boundsvar(var), i),
							Expr(:call,
								 :throw,
								 :($calculation_sequence_error($err)))),
				Expr(:ref, var, i)
			)
		else
			x
		end
	end
end

formula_unrolling_expr(formulas::OrderedDict{Symbol, SpreadFormula}, x::Symbol, X::Symbol; with_inits=false) = begin

        # Broadcast via long way around
        rtype, seq = formula_cluster_topology(OrderedDict(i=>j.expr for (i,j) ∈ formulas), x)
        doreverse = rtype>0
        
        definitions = Expr(:block)
        for var ∈ seq
            push!(definitions.args,
                  initwrap(
                      var,
                      Expr(:block,
                          formulas[var].line,
                            :($(var) = Vector(undef, length($X))))))

             push!(definitions.args,
                   :($(boundsvar(var)) = BitVector(false for _ ∈ 1:length($X))))

        end

        loopover =  if doreverse :(reverse($X)) else X end
        
        f_bounds = boundrycheck_transformer(seq)
        assignments = Expr(:block)
        for var ∈ seq
            push!(assignments.args, formulas[var].line)
            push!(assignments.args, :($(var)[$x] = $(MacroTools.postwalk(f_bounds, formulas[var].expr))))
            push!(assignments.args, :($(boundsvar(var))[$x] = true))
        end
        
        @gensymx e
        ret = (quote
            $definitions
            for $x in $loopover
                $assignments
            end
            nothing
        end)
end