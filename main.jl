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
using TextSearch
using TextAnalysis

import RAGTools: find_closest, HasEmbeddings, chunkdata, chunks, sources, indexid



const _test_post_text = """
>... This (Sterility) is not something that can be grasped as a plain matter of Causality (as modern science naturally enough has tried to grasp it); it is to be understood as an essentially metaphysical turn towards death. The last man of the world-city no longer wants to live - he may cling to life as an individual, but as a type, as an aggregate, no, for it is a characteristic of this collective existence that it eliminates the terror of death. That which strikes the true peasant with a deep and inexplicable fear, the notion that the family and the name may be extinguished, has now lost its meaning. The continuance of the blood-relation in the visible world is no longer a duty of the blood, and the destiny of being the last of the line is no longer felt as a doom. Children do not happen, not because children have become impossible, but principally because intelligence at the peak of intensity can no longer find any reason for their existence.

>Intelligence and sterility are allied in old families, old peoples, and old Cultures... When the ordinary thought of a highly cultivated people begins to regard \"having children\" as a question of pro's and con's, the great turning-point has come... 

>When reasons have to be put forward at all in a question of life, life itself has become questionable.  At that point begins prudent limitation of the number of births. In the Classical world the practice was deplored by Polybius as the ruin of Greece, and yet even at his date it had long been established in the great cities; in subsequent Roman times it became appallingly general. At first explained by the economic misery of the times, very soon it ceased to explain itself at all. And at that point, too, in Buddhist India as in Babylon, in Rome as in our own cities, a man's choice of the woman who is to be, not mother of his children as amongst peasants and primitives, but his own \"companion for life,\" becomes a problem of mentalities. The 'Ibsen marriage' appears, the\" higher spiritual affinity\" in which both parties are \"free\" - free, that is, as intelligences, free from the plantlike urge of the blood to continue itself, and it becomes possible for a Shaw to say \"that unless woman repudiates her womanliness, her duty to her husband, to her children, to society, to the law, and to everyone but herself, she cannot emancipate herself.\"

>The primary woman, the peasant woman, is mother. The whole vocation towards which she has yearned from childhood is included in that one word. But now emerges the Ibsen woman, the comrade, the heroine of a whole megalopolitan literature from Northern drama to Parisian novel. Instead of children, she has soul-conflicts; marriage is a craft-art for the achievement of \"mutual understanding.\" It is all the same whether the case against children is the American lady's who would not miss a season for anything, or the Parisienne's who fears that her lover would leave her, or an Ibsen heroine's who \"belongs to herself\" - they all belong to themselves and they are all unfruitful. The same fact, in conjunction with the same arguments, is to be found in the Alexandrian, in the Roman, and, as a matter of course, in every other civilized society...

>At this level all Civilizations enter upon a stage, which lasts for centuries, of appalling depopulation. The whole pyramid of cultural man vanishes. It crumbles from the summit, first the world-cities, then the provincial forms, and finally the land itself, whose best blood has incontinently poured into the towns, merely to bolster them up awhile. At the last, only the primitive blood remains, alive, but robbed of its strongest and most promising elements.",
"""

# Most of these are values for testing that will eventually be replaced when further refined.
## Eventually place this in from macro expansion
const SURREALDB_PORT = 65002
const _TEST_SURREALDB_PORT = 65002
# default surrealdb host
const DEFAULT_SURREALDB_HOST = "localhost"
# test surrealdb host
const _TEST_SURREALDB_HOST = "localhost"
const _DATABASE_NAME = "test_database"
const _NAMESPACE_NAME = "test_namespace"
const _USER_NAME = "root"
const _PASSWORD = "root"


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
function radmta_surrealdb_query(_internalDB::Surreal; _query::String)
    _result = SurrealdbWS.query(_internalDB, sql=_query)
    return _result
end


# this function returns the authors of the posts
function radmta_surrealdb_get_authors(_internalDB::Surreal, _table::String)
    _result = radmta_surrealdb_query(_internalDB, _query="select id,author from $(_table) limit 10")
    return _result
end




function radmta_surrealdb_get_keys(_internalDB::Surreal, _table::String)
    _result = radmta_surrealdb_query(_internalDB, _query="RETURN object::keys((SELECT * FROM $(_table))[0])")
    return _result
end





function radmta_preprocess_text(_text::String)
        
    # this will preprocess the text for processing by a transformer model. It will strip html tags, whitespace, and non-letters.
    ## Make a copy of the string so we don't modify the original.
    _internalText = StringDocument(_text)

    # Apply cleaning and normalization steps
    prepare!(_internalText, strip_html_tags | strip_whitespace | strip_non_letters)


    return _internalText.text
end



function radmta_launch_services()

    # launch the services
    # - sentiment analysis
    # - topic analysis
    # - emotion analysis
    # - embedding model
    # - decoder model
    # - reranker model
    # - deduplicator model
    # - writer model
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


