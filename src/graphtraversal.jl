struct DiNode{T}
    in::Set{T}
    out::Set{T}
	
    DiNode{T}() where T = new{T}(Set{T}(), Set{T}())
end


trim_sequence(graph::Dict{T,DiNode{T}}) where T = trim_sequence!(deepcopy(graph))

trim_sequence!(graph::Dict{T,DiNode{T}}) where T = begin 

	headseq = Vector{T}()
	tailseq = Vector{T}()
	queue = Vector{T}() # Ordered set is better
	strongclusters = Dict{T, Set{T}}()


	# viable? then add to queue
	lazyaddtoqueue!(id) = if length(graph[id].in)*length(graph[id].out) == 0
		push!(queue, id)
	end

	# !!! only valid if there are no branches or roots left
	findcycleintrimmedgraph() = begin
		id, node = first(graph)
		
		seqset = Set{T}()
		seq = Vector{T}() # use like ordered set

		idᵢ = id
		while !(idᵢ ∈ seqset)
			push!(seqset, idᵢ)
			push!(seq, idᵢ)
			idᵢ = first(graph[idᵢ].out)
		end

		# Only keep the cyclic part
		for (i, idⱼ) ∈ enumerate(seq)
			if idⱼ == idᵢ
				return seq[i:end]
			end
		end
		
		raise(ErrorException(
				"Could not find cycle in graph $(graph) starting from $(id)"))
		return seq
	end

	# for a group of ids merge together into single node
	mergeids!(ids)  = begin
		idₙ = ids[1] # reuse the first ID
		nodeₙ = DiNode{T}()

		for idᵢ ∈ ids
			nodeᵢ = graph[idᵢ]

			for idⱼ ∈ nodeᵢ.out
				if idⱼ != idₙ
					push!(nodeₙ.out, idⱼ)
					pop!(graph[idⱼ].in, idᵢ) 
					push!(graph[idⱼ].in, idₙ)
				end
			end

			for idⱼ ∈ nodeᵢ.in
				if idⱼ != idₙ
					push!(nodeₙ.in, idⱼ)
					pop!(graph[idⱼ].out, idᵢ) 
					push!(graph[idⱼ].out, idₙ)
				end
			end

			# remove idᵢ from collective histroy
			pop!(graph, idᵢ)
			if idᵢ ∈ nodeₙ.out pop!(nodeₙ.out, idᵢ) end
			if idᵢ ∈ nodeₙ.in pop!(nodeₙ.in, idᵢ) end
		end

		graph[idₙ] = nodeₙ
		strongclusters[idₙ] = Set{T}(ids) ∪ get(strongclusters, idₙ, [])

		# merge cluster with other strong clusters
		for idₘ ∈ setdiff!(ids ∩ keys(strongclusters), [idₙ])
			push!(strongclusters[idₙ], pop!(strongclusters, idₘ))
		end

		return idₙ
	end

	for (id, node) ∈ graph
		lazyaddtoqueue!(id)
	end

	while(length(graph) != 0)

		if length(queue) == 0
			# find a cycle and merge it
			seq = findcycleintrimmedgraph()
			idₙ = mergeids!(seq)
			lazyaddtoqueue!(idₙ)

		else
			idᵢ=pop!(queue)
			(nodeᵢ = get(graph, idᵢ, nothing)) === nothing && continue

			# trim either a root or a branch
			if length(nodeᵢ.in) == 0
				push!(headseq, idᵢ)
				for idⱼ ∈ nodeᵢ.out
					pop!(graph[idⱼ].in, idᵢ)
					lazyaddtoqueue!(idⱼ)
				end

			elseif length(nodeᵢ.out) == 0
				insert!(tailseq, 1, idᵢ)
				for idⱼ ∈ nodeᵢ.in
					pop!(graph[idⱼ].out, idᵢ)
					lazyaddtoqueue!(idⱼ)
				end
			end

			pop!(graph, idᵢ)

		end
	end

	sequence = Vector{Union{T, Vector{T}}}()
	for i ∈ Iterators.flatten((headseq, tailseq))
		if haskey(strongclusters, i)
			push!(sequence, collect(strongclusters[i]))
		else
			push!(sequence, i)
		end		
	end

	return sequence
end



#=
# Example of finding a sequence over a graph
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

	graph = Dict{Tₑ,DiNode{Tₑ}}()
	for (i,j) ∈ edges
		if ! haskey(graph, i)  graph[i] = DiNode{Tₑ}() end
		if ! haskey(graph, j)  graph[j] = DiNode{Tₑ}() end

		push!(graph[i].out, j)
		push!(graph[j].in, i)

	end

	graph

end

println(trim_sequence(graph))
=#

