#!/usr/bin/env julia

# Making sure the packages are instantiated within the current directory
using Pkg
Pkg.activate(@__DIR__) # Activates the directory where the script lives
Pkg.instantiate()      # Installs any missing dependencies

# precompile everything for good speed on the explicit platform
precompile

# dependencies
using HTTP # http library for making requests to the web
using JSON3 # json3 library for parsing json data. Deprecated but has quite a few dependencies in our package stack.
using JSON # json library for parsing json data. More modern and has less dependencies in our package stack.
using SurrealdbWS # surrealdbws library for interacting with the surrealdb database
using TextAnalysis # text analysis library for text analysis tasks
using Dates # dates library for working with dates and times
using Distributed # distributed library for distributed computing/multiprocessing

# packages for topic modeling
using Base64
using Clustering
using Distances
using LinearAlgebra
using Printf
using Random
using Statistics
import HDBSCAN
import UMAP 

# the main constants to use for the operations of this script to the SurrealDB database.

# SurrealDB configuration constants
const SURREALDB_HOST = "localhost"
const SURREALDB_PORT = 65002
const SURREALDB_USER = "root"
const SURREALDB_PASS = "root"
const SURREALDB_NAMESPACE = "radmta"
const SURREALDB_DATABASE = "natalism"
# SurrealDB connection pool size and timeout constants
const SURREALDB_CONNECTION_POOL_SIZE = 8
# SurrealDB connection timeout constants
const SURREALDB_CONNECTION_TIMEOUT = 30


# tei configuration constants
const TEI_HOST = "localhost"
const TEI_PORT = 65003
const TEI_USER = "root"
const TEI_PASS = "root"


const MAX_TOKENS = 8192
const BODY = 8190  # 8192 minus [CLS] + [SEP]


const EMBEDDING_MODEL = "Alibaba-NLP/gte-modernbert-base"
const RERANKING_MODEL = "Alibaba-NLP/gte-reranker-modernbert-base"


function get_embedding(text::String)::Array{Float32, 1}
HTTP.get("http://$(TEI_HOST):$(TEI_PORT)/embedding", headers=["Authorization" => "Bearer $(TEI_PASS)"], body=text)

end 



###############################################################################################
#################### PROTOTYPE: within-thread topics, then a hierarchy ########################
###############################################################################################
#
# A thread is one document. HDBSCAN topics inside it are provisional codes.
# Each topic is the unit-length centroid of its comment embeddings. Cosine
# distance between those centroids, then average-linkage clustering, proposes
# parent codes that recur across threads. The tree is a draft for the codebook.
# It is not the corpus topic layer, and it does not run from main().
#
#   sample_threads()              posts with at least 40 comments
#   run_thread_topic_prototype()  clean, embed, cluster each thread, build the tree

const TEI_EMBED_URL = "http://$(TEI_HOST):$(TEI_PORT)/embed"
const TEI_EMBED_BATCH = 32
const THREAD_TOPIC_MIN_COMMENTS = 40

const _ACCENT = Dict{Char,Char}(
    'á'=>'a','é'=>'e','í'=>'i','ó'=>'o','ú'=>'u','ü'=>'u','ñ'=>'n',
    'à'=>'a','è'=>'e','ì'=>'i','ò'=>'o','ù'=>'u','â'=>'a','ê'=>'e','î'=>'i','ô'=>'o','û'=>'u')

const _TOPIC_STOP = Set(split("""a about above after again against all am an and any are as at be because been before
being below between both but by can could did do does doing down during each few for from further had has have
having he her here hers herself him himself his how i if in into is it its itself just let me more most my myself
no nor not now of off on once only or other our ours ourselves out over own same she should so some such than
that the their theirs them themselves then there these they this those through to too under until up very was we
were what when where which while who whom why will with would you your yours yourself yourselves also get got
like just really im dont doesnt didnt thats isnt its youre theyre ive id one would think people even make know
don't it's i'm that's can't didn't don't really lot much way
el la los las de del al un una unos unas que en por para con sin sobre entre desde hasta hacia durante contra
pero porque como cuando donde quien este esta estos estas eso muy mas menos tambien hay ser estar
reddit comment comments post posts subreddit upvote downvote op edit edited https http www com org said lol lmao imo tbh btw deleted removed"""))

"""Run one SurrealQL statement over HTTP. Returns the decoded JSON result list."""



function surreal_sql(q::String)
    hdrs = [
        "Accept" => "application/json",
        "surreal-ns" => SURREALDB_NAMESPACE,
        "surreal-db" => SURREALDB_DATABASE,
        "Authorization" => "Basic " * base64encode("$(SURREALDB_USER):$(SURREALDB_PASS)"),
    ]
    r = HTTP.post("http://$(SURREALDB_HOST):$(SURREALDB_PORT)/sql", hdrs, q)
    body = JSON3.read(String(r.body))
    body[1].status == "OK" || error("SurrealQL failed: ", body[1])
    return body[1].result
end

"""Embed a batch of texts. TEI expects POST /embed and returns one vector per input."""
function tei_embed_batch(texts::Vector{String})::Vector{Vector{Float32}}
    body = JSON3.write(Dict("inputs" => texts, "normalize" => true, "truncate" => true))
    r = HTTP.post(TEI_EMBED_URL, ["Content-Type" => "application/json"], body)
    return JSON3.read(String(r.body), Vector{Vector{Float32}})
end

"""Embed every text, in batches of TEI_EMBED_BATCH. Rows of the result line up with texts."""
function tei_embed_all(texts::Vector{String})::Matrix{Float32}
    n = length(texts)
    E = zeros(Float32, n, 768)
    for s in 1:TEI_EMBED_BATCH:n
        idx = s:min(s + TEI_EMBED_BATCH - 1, n)
        vecs = tei_embed_batch(texts[idx])
        for (k, i) in enumerate(idx)
            E[i, :] = vecs[k]
        end
    end
    return E
end

_fold_accents(s) = String([get(_ACCENT, c, c) for c in s])

"""Drop quoted lines, URLs, and user or subreddit mentions. Lowercased."""
function clean_comment(s::AbstractString)::String
    kept = String[]
    for l in split(s, '\n')
        t = strip(l)
        (isempty(t) || startswith(t, ">")) && continue
        push!(kept, t)
    end
    t = _fold_accents(lowercase(join(kept, " ")))
    t = replace(t, r"\[([^\]]*)\]\([^)]*\)" => s"\1")
    t = replace(t, r"https?://\S+" => " ")
    t = replace(t, r"www\.\S+" => " ")
    t = replace(t, r"(?:^|\s)/?[ur]/[a-z0-9_-]+" => " ")
    t = replace(t, r"\\?\[\d+\\?\]" => " ")
    t = replace(t, "**" => " ")
    return strip(replace(t, r"\s+" => " "))
end

_topic_tokens(s) = [w for w in split(s, r"[^a-z']+") if length(w) >= 3 && w ∉ _TOPIC_STOP]

"""c-TF-IDF terms for each cluster label. Label -1 is the unassigned set and is skipped."""
function thread_topic_terms(texts::Vector{String}, lab::Vector{Int}; top::Int = 6)
    classes = sort(setdiff(unique(lab), [-1]))
    isempty(classes) && return Dict{Int,Vector{String}}()
    tf = Dict(c => Dict{String,Int}() for c in classes)
    total = Dict{String,Int}()
    ctok = Dict(c => 0 for c in classes)
    for i in eachindex(lab)
        lab[i] == -1 && continue
        for w in _topic_tokens(texts[i])
            tf[lab[i]][w] = get(tf[lab[i]], w, 0) + 1
            total[w] = get(total, w, 0) + 1
            ctok[lab[i]] += 1
        end
    end
    A = mean(values(ctok))
    out = Dict{Int,Vector{String}}()
    for c in classes
        scored = [(w, f * log(1 + A / total[w])) for (w, f) in tf[c]]
        sort!(scored, by = x -> -x[2])
        out[c] = [w for (w, _) in scored[1:min(top, length(scored))]]
    end
    return out
end

"""Sample submission ids. num_comments is the archive count, not the usable-comment count."""
function sample_threads(n::Int = 36; min_comments::Int = THREAD_TOPIC_MIN_COMMENTS)
    surreal_sql("""
        SELECT name, title, num_comments FROM documents
        WHERE kind = 'post' AND num_comments >= $(min_comments)
        ORDER BY rand() LIMIT $(n);
    """)
end

"""Comments in one thread with analysis_text longer than 40 characters, after cleaning."""
function fetch_thread_comments(thread_name::AbstractString)::Vector{String}
    rows = surreal_sql("""
        SELECT analysis_text FROM documents
        WHERE thread = type::record("documents", "$(thread_name)")
          AND analysis_text != NONE
          AND string::len(analysis_text) > 40;
    """)
    cleaned = clean_comment.(String.(getproperty.(rows, :analysis_text)))
    return filter(c -> length(c) >= 20, cleaned)
end

"""
HDBSCAN on one thread's embeddings (n × 768). min_cluster_size is min(25, n/10), at least 5.
Returns integer labels. -1 is unassigned. Threads shorter than 15 comments are all unassigned.
"""
function cluster_thread(X::AbstractMatrix{<:Real}; seed::Int = 1)::Vector{Int}
    n = size(X, 1)
    n < 15 && return fill(-1, n)
    mcs = clamp(round(Int, n / 10), 5, 25)
    nn = min(15, n - 2)
    nd = n >= 40 ? 5 : 2
    Random.seed!(seed)
    pts = [Vector{Float64}(X[i, :]) for i in 1:n]
    res = UMAP.fit(pts, nd; n_neighbors = nn, metric = CosineDist(), min_dist = 0.001)
    emb = res.embedding
    U = size(emb, 2) == n ? permutedims(emb) : emb
    model = HDBSCAN.Hdbscan(mcs, mcs; metric = "euclidean")
    HDBSCAN.fit!(model, U)
    return Int.(vec(HDBSCAN.labels(model)))
end

"""Unit-length mean of the row vectors in idx."""
function _centroid(X::AbstractMatrix{<:Real}, idx::AbstractVector{Int})
    μ = vec(mean(X[idx, :]; dims = 1))
    μ ./= max(norm(μ), 1e-9)
    return μ
end

"""
Cosine distance between topic centroids, then average-linkage clustering.
topics is a vector of named tuples with fields thread and centroid.
Returns the Clustering.Hclust and the K × K distance matrix.
"""
function topic_centroid_tree(topics)
    C = vcat([permutedims(tp.centroid) for tp in topics]...)
    D = max.(0.0, 1 .- C * C')
    D[diagind(D)] .= 0.0
    return hclust(D; linkage = :average), D
end

"""Groups produced by cutting the tree at height h. Each group lists its member indices."""
function cut_topic_tree(topics, hc, h::Real)
    labs = cutree(hc; h = h)
    rows = NamedTuple[]
    for c in sort(unique(labs))
        idx = findall(==(c), labs)
        threads = unique([topics[i].thread for i in idx])
        push!(rows, (label = c, idx = idx, n_threads = length(threads), n_topics = length(idx)))
    end
    return rows
end

"""
Run the prototype. Pass thread_names to reuse a sample; otherwise sample n_threads posts.
Prints the within-thread topics and the cross-thread groups at the median merge height.
Returns (threads, topics, tree, distances, groups).
"""
function run_thread_topic_prototype(; n_threads::Int = 36,
                                     min_comments::Int = THREAD_TOPIC_MIN_COMMENTS,
                                     thread_names::Union{Nothing,AbstractVector{<:AbstractString}} = nothing)
    picked = thread_names === nothing ? sample_threads(n_threads; min_comments = min_comments) : nothing
    names = thread_names === nothing ? String.(getproperty.(picked, :name)) : collect(String, thread_names)
    println("threads: ", length(names))

    threads = NamedTuple[]
    for name in names
        texts = fetch_thread_comments(name)
        push!(threads, (name = name, texts = texts))
        println("  ", name, "  usable=", length(texts))
    end

    all_texts = String[]
    spans = Tuple{Int,Int}[]
    for t in threads
        a = length(all_texts) + 1
        append!(all_texts, t.texts)
        push!(spans, (a, length(all_texts)))
    end
    println("embedding ", length(all_texts), " comments")
    E = tei_embed_all(all_texts)

    topics = NamedTuple[]
    for (ti, t) in enumerate(threads)
        a, b = spans[ti]
        n = b - a + 1
        n < 15 && continue
        X = E[a:b, :]
        lab = cluster_thread(X; seed = sum(Int.(codeunits(t.name))))
        terms = thread_topic_terms(t.texts, lab)
        println("\n", t.name, "  n=", n, "  topics=", length(setdiff(unique(lab), [-1])),
                "  unassigned=", count(==(-1), lab))
        for c in sort(setdiff(unique(lab), [-1]); by = c -> -count(==(c), lab))
            idx = findall(==(c), lab)
            μ = _centroid(X, idx)
            d = [1 - dot(view(X, i, :), μ) for i in idx]
            example = first(t.texts[idx[argmin(d)]], 140)
            line = join(get(terms, c, String[]), ", ")
            println(@sprintf("    %4d  %s", length(idx), line))
            push!(topics, (thread = t.name, cluster = c, size = length(idx),
                           centroid = μ, terms = get(terms, c, String[]), example = example))
        end
    end
    println("\nwithin-thread topics: ", length(topics),
            " across ", length(unique([tp.thread for tp in topics])), " threads")
    isempty(topics) && return (threads = threads, topics = topics, tree = nothing,
                               distances = nothing, groups = nothing)

    hc, D = topic_centroid_tree(topics)
    hq = quantile(hc.heights, [0.25, 0.5, 0.75])
    h = hq[2]
    groups = cut_topic_tree(topics, hc, h)
    println("cut height ", round(h, digits = 3), " (median merge)")
    for g in sort(filter(g -> g.n_threads >= 2, groups); by = g -> (-g.n_threads, -g.n_topics))
        wc = Dict{String,Int}()
        for i in g.idx, w in topics[i].terms
            wc[w] = get(wc, w, 0) + 1
        end
        top = sort(collect(wc); by = x -> (-x[2], x[1]))
        tw = join([w for (w, _) in top[1:min(8, length(top))]], ", ")
        println(@sprintf("  %d threads, %d topics:  %s", g.n_threads, g.n_topics, tw))
    end
    return (threads = threads, topics = topics, tree = hc, distances = D, groups = groups)
end


###############################################################################################
###################################### MAIN ###################################################
###############################################################################################


function main()::Nothing
    # create a connection pool to the surrealdb database
    db = SurrealdbWS.Surreal("ws://$(SURREALDB_HOST):$(SURREALDB_PORT)/rpc", npool=SURREALDB_CONNECTION_POOL_SIZE)
    SurrealdbWS.connect(db, timeout=SURREALDB_CONNECTION_TIMEOUT) # connect to the database
    return nothing
end




main()
