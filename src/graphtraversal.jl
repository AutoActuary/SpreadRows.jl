struct DiNode{T}
    in::Set{T}
    out::Set{T}
	
    DiNode{T}() where T = new{T}(Set{T}(), Set{T}())
end


struct DiGraph{T}
	nodedict::Dict{T,DiNode{T}}
	DiGraph{T}() where T = new{T}(Dict{T,DiNode{T}}())
end


traversalsequence(graph::DiGraph{T}) where T = traversalsequence!(deepcopy(graph))

traversalsequence!(graph::DiGraph{T})  where T = begin 

	headseq = Vector{T}()
	tailseq = Vector{T}()
	queue = Vector{T}() # Ordered set is better
	strongclusters = Dict{T, Set{T}}()


	# viable? then add to queue
	lazyaddtoqueue!(id) = if length(graph.nodedict[id].in)*length(graph.nodedict[id].out) == 0
		push!(queue, id)
	end

	# !!! only valid if there are no branches or roots left
	findcycleintrimmedgraph() = begin
		id, node = first(graph.nodedict)
		
		seqset = Set{T}()
		seq = Vector{T}() # use like ordered set

		idᵢ = id
		while !(idᵢ ∈ seqset)
			push!(seqset, idᵢ)
			push!(seq, idᵢ)
			idᵢ = first(graph.nodedict[idᵢ].out)
		end

		# Only keep the cyclic part
		for (i, idⱼ) ∈ enumerate(seq)
			if idⱼ == idᵢ
				return seq[i:end]
			end
		end
		
		raise(ErrorException(
				"Could not find cycle in graph.nodedict $(graph.nodedict) starting from $(id)"))
		return seq
	end

	# for a group of ids merge together into single node
	mergeids!(ids)  = begin
		idₙ = ids[1] # reuse the first ID
		nodeₙ = DiNode{T}()

		for idᵢ ∈ ids
			nodeᵢ = graph.nodedict[idᵢ]

			for idⱼ ∈ nodeᵢ.out
				if idⱼ != idₙ
					push!(nodeₙ.out, idⱼ)
					pop!(graph.nodedict[idⱼ].in, idᵢ) 
					push!(graph.nodedict[idⱼ].in, idₙ)
				end
			end

			for idⱼ ∈ nodeᵢ.in
				if idⱼ != idₙ
					push!(nodeₙ.in, idⱼ)
					pop!(graph.nodedict[idⱼ].out, idᵢ) 
					push!(graph.nodedict[idⱼ].out, idₙ)
				end
			end

			# remove idᵢ from collective histroy
			pop!(graph.nodedict, idᵢ)
			if idᵢ ∈ nodeₙ.out pop!(nodeₙ.out, idᵢ) end
			if idᵢ ∈ nodeₙ.in pop!(nodeₙ.in, idᵢ) end
		end

		graph.nodedict[idₙ] = nodeₙ
		strongclusters[idₙ] = Set{T}(ids) ∪ get(strongclusters, idₙ, [])

		# merge cluster with other strong clusters
		for idₘ ∈ setdiff!(ids ∩ keys(strongclusters), [idₙ])
			push!(strongclusters[idₙ], pop!(strongclusters, idₘ))
		end

		return idₙ
	end

	for (id, node) ∈ graph.nodedict
		lazyaddtoqueue!(id)
	end

	while(length(graph.nodedict) != 0)

		if length(queue) == 0
			# find a cycle and merge it
			seq = findcycleintrimmedgraph()
			idₙ = mergeids!(seq)
			lazyaddtoqueue!(idₙ)

		else
			idᵢ=pop!(queue)
			(nodeᵢ = get(graph.nodedict, idᵢ, nothing)) === nothing && continue

			# trim either a root or a branch
			if length(nodeᵢ.in) == 0
				push!(headseq, idᵢ)
				for idⱼ ∈ nodeᵢ.out
					pop!(graph.nodedict[idⱼ].in, idᵢ)
					lazyaddtoqueue!(idⱼ)
				end

			elseif length(nodeᵢ.out) == 0
				insert!(tailseq, 1, idᵢ)
				for idⱼ ∈ nodeᵢ.in
					pop!(graph.nodedict[idⱼ].out, idᵢ)
					lazyaddtoqueue!(idⱼ)
				end
			end

			pop!(graph.nodedict, idᵢ)

		end
	end

	sequence = Vector{Union{T, Vector{T}}}()
	for i ∈ Iterators.flatten((headseq, tailseq))
		if haskey(strongclusters, i)
			push!(sequence, collect(strongclusters[i]))
		else
			push!(sequence, [i])
		end		
	end

	return sequence
end


DiGraph(edges::Vector{<:Union{Vector{T}, Tuple{T, T}}}) where T= begin
	graph = DiGraph{T}()
	for (i,j) ∈ edges
		if ! haskey(graph.nodedict, i)  graph.nodedict[i] = DiNode{T}() end
		if ! haskey(graph.nodedict, j)  graph.nodedict[j] = DiNode{T}() end

		push!(graph.nodedict[i].out, j)
		push!(graph.nodedict[j].in, i)

	end

	graph
end


DiGraph(mapping::Dict{T,<:Union{Vector{T},Set{T}}}) where T  = begin
	graph = DiGraph{T}()

	for (i, outs) ∈ mapping
		for j ∈ outs
			if ! haskey(graph.nodedict, i)  graph.nodedict[i] = DiNode{T}() end
			if ! haskey(graph.nodedict, j)  graph.nodedict[j] = DiNode{T}() end

			push!(graph.nodedict[i].out, j)
			push!(graph.nodedict[j].in, i)
		end
	end

	graph
end

#=
# Example of finding a sequence over a graph.nodedict
begin
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
		(:x6, :x7)]
	
	Tₑ = Union{[Union{typeof.(e)...} for e in edges]...}

	graph.nodedict = Dict{Tₑ,DiNode{Tₑ}}()
	for (i,j) ∈ edges
		if ! haskey(graph.nodedict, i)  graph.nodedict[i] = DiNode{Tₑ}() end
		if ! haskey(graph.nodedict, j)  graph.nodedict[j] = DiNode{Tₑ}() end

		push!(graph.nodedict[i].out, j)
		push!(graph.nodedict[j].in, i)

	end

	graph.nodedict

end

println(traversalsequence!(graph.nodedict))
=#

