#!/usr/bin/env julia

# This script will purge the entire database of the radmta namespace and natalism database.
# 
#
#
#

#


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


# SurrealDB configuration constants
const SURREALDB_HOST = "localhost"
const SURREALDB_PORT = 65002
const SURREALDB_USER = "root"
const SURREALDB_PASS = "root"
const SURREALDB_NAMESPACE = "radmta"
const SURREALDB_DATABASE = "natalism"

function main()

    # connect to the surrealdb database
    _db = SurrealdbWS.Surreal("ws://$(SURREALDB_HOST):$(SURREALDB_PORT)/rpc")
    SurrealdbWS.connect(_db) # connect to the database
    SurrealdbWS.signin(_db, user="root", pass="root") # sign in to the database
    SurrealdbWS.use(_db, namespace="radmta", database="natalism") # use the database and namespace
    SurrealdbWS.query(_db, sql="USE NS radmta; REMOVE DATABASE natalism;") # remove the database
    SurrealdbWS.close(_db)

end

# run the main function 
main()