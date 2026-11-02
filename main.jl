#!/usr/bin/env julia

# Making sure the packages are instantiated within the current directory
using Pkg
Pkg.activate(@__DIR__) # Activates the directory where the script lives
Pkg.instantiate()      # Installs any missing dependencies

# precompile everything for good speed on the explicit platform
precompile

# dependencies
using HTTP
using JSON3
using PromptingTools
using PromptingTools: SystemMessage, UserMessage, OllamaManagedSchema, render, aigenerate
using RAGTools
using RAGTools: AbstractChunkIndex, AbstractSimilarityFinder, CandidateChunks
using SurrealdbWS
using HorseML
import RAGTools: find_closest, HasEmbeddings, chunkdata, chunks, sources, indexid


# SurrealDB port

## Eventually place this in from macro expansion
const SURREALDB_PORT = 65005
const _TEST_SURREALDB_PORT = 65002
# default surrealdb host
const DEFAULT_SURREALDB_HOST = "localhost"
# test surrealdb host
const _TEST_SURREALDB_HOST = "localhost"

# Surreal Connection
surreal_db_client = Surreal("ws://$(DEFAULT_SURREALDB_HOST):$(SURREALDB_PORT)/rpc")



function radmta_surrealdb_connect_and_return_db(_SURREALDB_HOST::String, _SURREALDB_PORT::Int, _SURREALDB_USER::String, _SURREALDB_PASS::String, _SURREALDB_NAMESPACE::String, _SURREALDB_DATABASE::String)


    _internalDB = SurrealdbWS.Surreal("ws://$(_SURREALDB_HOST):$(_SURREALDB_PORT)/rpc")
    
    # connect to the surrealdb database
    SurrealdbWS.connect(_internalDB)

    # authenticate with the surrealdb database
    SurrealdbWS.signin(_internalDB, user=_SURREALDB_USER, pass=_SURREALDB_PASS)

    # use the namespace and database
    SurrealdbWS.use(_internalDB, namespace=_SURREALDB_NAMESPACE, database=_SURREALDB_DATABASE)

    # return the database connection
    return _internalDB

end







# maybe don't do a try and catch statement here.
function radmta_surrealdb_disconnect(_internalDB::Surreal)
    _returnCode = 0
    try
        # Try to close the database connection
        SurrealdbWS.close(_internalDB)
    catch e
        # An error occurred while closing the database connection
        _returnCode = 1
        println("An error occurred while closing the database connection: ", e)
    finally
        # Always runs, whether an error happened or not
        println("Database connection closed successfully.")
    end

    return _returnCode
end



# this function queries the surrealdb database and returns the result
function radmta_surrealdb_query(_internalDB::Surreal, _query::String)
    _result = SurrealdbWS.query(_internalDB, sql=_query)
    return _result
end


# this function returns the authors of the posts
function radmta_surrealdb_get_authors(_internalDB::Surreal, _table::String)
    _result = radmta_surrealdb_query(_internalDB, sql="select id,author from $(_table) limit 10")
    return _result
end




function radmta_surrealdb_get_keys(_internalDB::Surreal, _table::String)
    _result = radmta_surrealdb_query(_internalDB, sql="RETURN object::keys((SELECT * FROM $(_table))[0])")
    return _result
end

# main portion of the program


# note that these are all test cases at the moment.
function main()
    _internalDB = radmta_surrealdb_connect_and_return_db(DEFAULT_SURREALDB_HOST, SURREALDB_PORT, "root", "root", "test_namespace", "test_database")
    _result = radmta_surrealdb_get_authors(_internalDB, "posts")
    println(_result)
    radmta_surrealdb_disconnect(_internalDB)
end

main()


### Below might be junk 

#strip_thinking(content::AbstractString) = strip(replace(content, THINKING_TAG_PATTERN => ""))


#const OLLAMA_URL = "http://localhost:11434/api/generate"
#const OLLAMA_MODEL = "gemma4:12b-mlx"
#const OLLAMA_MODEL = "lfm2.5:latest"
#const THINKING_TAG_PATTERN = r"<(?:think|redacted_thinking)>[\s\S]*?</think>"



#greet() = print("Hello World!")

#const SENTIMENT_PROMPT = [
#    SystemMessage("""
#        You are an expert, objective data annotation assistant. Your task is to perform one-shot sentiment analysis. Analyze the provided customer text and classify its overall sentiment into exactly one of three categories: Positive, Negative, or Neutral. Respond ONLY with the category name. Do not include any introductory words, explanations, or punctuation.
#        Do not include any other text or formatting in your response. No thinking output. Just the category name.
#        Example:
#        Text: "The battery life is terrible, but the camera is great."
#        Sentiment: Neutral
#        """),
#    UserMessage("""Text: {{text}}
#        Sentiment:""")
#]

#function ollama_prompt(text::String)
#    rendered = render(OllamaManagedSchema(), SENTIMENT_PROMPT; text)
#    response = HTTP.post(
#        OLLAMA_URL,
#        body = JSON3.write(Dict(
#            "model" => OLLAMA_MODEL,
#            "system" => rendered.system,
#            "prompt" => rendered.prompt,
#            "think" => false,
#            "options" => Dict("temperature" => 0.0),
#        )),
#    )
#    parsed = JSON3.read(String(response.body))
#    return strip_thinking(get(parsed, :response, ""))
#end

#function ollama_sentiment(text::String)
#    msg = aigenerate(
#        OllamaManagedSchema(),
#        SENTIMENT_PROMPT;
#        text,
#        model = OLLAMA_MODEL,
#        api_kwargs = (think = false, options = Dict("temperature" => 0.0)),
#    )
#    return strip_thinking(msg.content)
#end


