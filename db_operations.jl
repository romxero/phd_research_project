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
