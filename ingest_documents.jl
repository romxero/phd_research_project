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


# SurrealDB schema for the namespace
## raw"..." keeps SurrealQL $value from being interpolated by Julia (i.e. $value 
## could be instruct julia to inject a value in this variable, but surrealdb also uses this syntax for using variables in its operations).
const NAMESPACE_SCHEMA = raw"""
DEFINE NAMESPACE IF NOT EXISTS radmta;
USE NS radmta;
DEFINE DATABASE IF NOT EXISTS natalism;
USE NS radmta DB natalism;
"""

# SurrealDB schema for the posts table
const TABLE_POSTS_SCHEMA = raw"""
USE NS radmta DB natalism;
DEFINE TABLE OVERWRITE posts SCHEMAFULL
    COMMENT "Study fields for one submission. Record id is the t3_ fullname.";

DEFINE FIELD OVERWRITE name ON posts TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Reddit fullname, e.g. t3_14622a";
-- string::slice(s, start) reads through the end. A third argument is an end index.
DEFINE FIELD OVERWRITE reddit_id ON posts TYPE string
    VALUE $value OR string::slice(name, 3)
    ASSERT $value = string::slice(name, 3)
    COMMENT "Short id. Derived from name.";
DEFINE FIELD OVERWRITE title ON posts TYPE string
    VALUE $value OR '';
DEFINE FIELD OVERWRITE selftext ON posts TYPE option<string>;
DEFINE FIELD OVERWRITE domain ON posts TYPE option<string>;
DEFINE FIELD OVERWRITE url ON posts TYPE option<string>;
DEFINE FIELD OVERWRITE created_utc ON posts TYPE int
    VALUE <int>$value
    COMMENT "Unix seconds";
DEFINE FIELD OVERWRITE created ON posts TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END
    COMMENT "Unix seconds from the archive created field.";
DEFINE FIELD OVERWRITE created_at ON posts
    COMMENT "Unix seconds computed to datetime.";
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD OVERWRITE score ON posts TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;
DEFINE FIELD OVERWRITE upvote_ratio ON posts TYPE option<float>
    VALUE IF $value IS NONE THEN NONE ELSE <float>$value END
    COMMENT "Archive mixes int and float. Coerced on write.";
DEFINE FIELD OVERWRITE num_comments ON posts TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;
DEFINE FIELD OVERWRITE ups ON posts TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;
DEFINE FIELD OVERWRITE downs ON posts TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;
DEFINE FIELD OVERWRITE selftext_cleaned ON posts TYPE option<string>
    COMMENT "Preprocessed selftext. Written by the ingest script.";
DEFINE FIELD OVERWRITE analysis_text ON posts TYPE option<string>
    COMMENT "Preprocessed title + selftext. Written by the ingest script.";

DEFINE INDEX OVERWRITE uniq_posts_name ON posts FIELDS name UNIQUE;
DEFINE INDEX OVERWRITE uniq_posts_reddit_id ON posts FIELDS reddit_id UNIQUE;
DEFINE INDEX OVERWRITE idx_posts_created ON posts FIELDS created_utc;
DEFINE INDEX OVERWRITE idx_posts_score ON posts FIELDS score;
DEFINE INDEX OVERWRITE idx_posts_upvote_ratio ON posts FIELDS upvote_ratio;
DEFINE INDEX OVERWRITE idx_posts_num_comments ON posts FIELDS num_comments;
"""

# SurrealDB schema for the comments table
const TABLE_COMMENTS_SCHEMA = raw"""
USE NS radmta DB natalism;
DEFINE TABLE OVERWRITE comments SCHEMAFULL
    COMMENT "Study fields for one comment. Record id is the t1_ fullname.";

DEFINE FIELD OVERWRITE name ON comments TYPE string
    ASSERT $value.starts_with('t1_')
    COMMENT "Reddit fullname, e.g. t1_c7a6yvf";
DEFINE FIELD OVERWRITE reddit_id ON comments TYPE string
    VALUE $value OR string::slice(name, 3)
    ASSERT $value = string::slice(name, 3)
    COMMENT "Short id. Derived from name.";
DEFINE FIELD OVERWRITE link_id ON comments TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Submission fullname this comment belongs to";
DEFINE FIELD OVERWRITE parent_id ON comments TYPE string
    ASSERT $value.starts_with('t1_') OR $value.starts_with('t3_')
    COMMENT "t3_* = reply to the submission; t1_* = reply to a comment";
DEFINE FIELD OVERWRITE post ON comments TYPE option<record<posts>>
    VALUE $value OR type::record("posts", link_id)
    COMMENT "posts:⟨link_id⟩. May dangle if that submission was not copied.";
DEFINE FIELD OVERWRITE parent ON comments
    COMPUTED IF parent_id.starts_with('t1_') THEN
        type::record("comments", parent_id)
    ELSE IF parent_id.starts_with('t3_') THEN
        type::record("posts", parent_id)
    ELSE
        NONE
    END
    COMMENT "comments:⟨t1_…⟩ or posts:⟨t3_…⟩. Derived from parent_id. Do not write it.";
DEFINE FIELD OVERWRITE body ON comments TYPE option<string>;
DEFINE FIELD OVERWRITE created_utc ON comments TYPE int
    VALUE <int>$value
    COMMENT "Unix seconds";
DEFINE FIELD OVERWRITE created ON comments TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END
    COMMENT "Unix seconds from the archive created field.";
DEFINE FIELD OVERWRITE created_at ON comments
    COMMENT "Unix seconds computed to datetime.";
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD OVERWRITE score ON comments TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;
DEFINE FIELD OVERWRITE analysis_text ON comments TYPE option<string>
    COMMENT "Preprocessed comment body. Written by the ingest script.";

DEFINE INDEX OVERWRITE uniq_comments_name ON comments FIELDS name UNIQUE;
DEFINE INDEX OVERWRITE uniq_comments_reddit_id ON comments FIELDS reddit_id UNIQUE;
DEFINE INDEX OVERWRITE idx_comments_link ON comments FIELDS link_id;
DEFINE INDEX OVERWRITE idx_comments_parent ON comments FIELDS parent_id;
DEFINE INDEX OVERWRITE idx_comments_post ON comments FIELDS post;
DEFINE INDEX OVERWRITE idx_comments_created ON comments FIELDS created_utc;
DEFINE INDEX OVERWRITE idx_comments_score ON comments FIELDS score;
"""






# A helper function to check for errors in the surrealdb query results and return them as an array of strings
function surreal_statement_errors(result)
    errors = String[]
    result isa AbstractVector || return errors
    for (i, statement) in enumerate(result)
        statement isa AbstractDict || continue
        status = get(statement, "status", get(statement, :status, nothing))
        status == "ERR" || continue
        detail = get(statement, "result", get(statement, :result, statement))
        push!(errors, "statement $i: $detail")
    end
    return errors
end


# A function to apply the radmta schema to the surrealdb database, this creates the namespaces, databases, and tables. 
function apply_radmta_schema()
    db = SurrealdbWS.Surreal("ws://$(SURREALDB_HOST):$(SURREALDB_PORT)/rpc") # connect to the surrealdb database
    SurrealdbWS.connect(db) # connect to the database
    try
        SurrealdbWS.signin(db, user=SURREALDB_USER, pass=SURREALDB_PASS)
        
        # iterate through the schemas and apply them to the database, eache schema constant is a large raw string of SurrealSQL statements
        for sql in (NAMESPACE_SCHEMA, TABLE_POSTS_SCHEMA, TABLE_COMMENTS_SCHEMA)
            # apply the schema to the database
            result = SurrealdbWS.query(db, sql=sql)
            errors = surreal_statement_errors(result) # check for errors in the schema
            if !isempty(errors)
                error("SurrealDB rejected schema:\n" * join(errors, "\n")) # if there are errors, throw an error
            end
            SurrealdbWS.use(db, namespace=SURREALDB_NAMESPACE, database=SURREALDB_DATABASE) # switch to the database and namespace
        end
        info = SurrealdbWS.query(db, sql="INFO FOR DB;") # get the info for the database
        return info # return the info for the database as a dictionary
    finally
        SurrealdbWS.close(db) # close the database connection
    end
end


# A helper function to get a value from a JSON row using a Symbol or String key
function json_get(row, key)
    if haskey(row, Symbol(key))
        return row[Symbol(key)]
    elseif haskey(row, key)  # string key
        return row[key]
    else
        return nothing
    end
end

# A helper function to convert unix seconds to a datetime
function unix_seconds_to_datetime(utc)
    utc === nothing && return nothing
    utc isa Integer && return unix2datetime(utc)
    utc isa AbstractFloat && return unix2datetime(round(Int, utc))
    utc isa AbstractString && return unix2datetime(parse(Int, utc))
    error("expected unix seconds as number or numeric string, got $(typeof(utc))")
end


# A helper function to preprocess text for the radmta project
function radmta_preprocess_text(_text::String)
        
    fused_url_pattern = r"\bhttps?www[a-zA-Z0-9]+"s
    # Strip HTML tags and collapse whitespace. Leave letters, digits, and punctuation.
    ## Make a copy of the string so we don't modify the original.
    _internalText = StringDocument(_text)

    # Apply cleaning and normalization steps
    prepare!(_internalText, strip_html_tags | strip_whitespace)

    post_text = replace(_internalText.text, fused_url_pattern => "")
    
    return String(strip(post_text))

end


# A helper function to read a jsonl file and return an array of dicts
function read_jsonl_and_return_array_of_dicts(file_path::String)
    # create an empty array to store the jsonl data
    _jsonl_data = []

    # open the file and read the data line by line
    open(file_path, "r") do io
        for line in eachline(io)
            # if the line is not empty, read the data into the array
            _intermediate_line = strip(line)
            isempty(_intermediate_line) && continue
            push!(_jsonl_data, JSON.parse(_intermediate_line)) # push the data into the array
        end
    end
    return _jsonl_data # return the array of dicts
end



function insert_radmta_posts_data(posts_data)

    # connect to the surrealdb database
    _db = SurrealdbWS.Surreal("ws://$(SURREALDB_HOST):$(SURREALDB_PORT)/rpc")
    SurrealdbWS.connect(_db) # connect to the database
    
    try
        # sign in to the database
        SurrealdbWS.signin(_db, user=SURREALDB_USER, pass=SURREALDB_PASS)
        # switch to the database and namespace
        SurrealdbWS.use(_db, namespace=SURREALDB_NAMESPACE, database=SURREALDB_DATABASE)
        # iterate through the posts data and insert the data into the database
        
        for post in posts_data
            # a temporary dictionary buffer, then use this for inserting the data into the database. 
            _insert_data = Dict{String, Any}(
                "name" => json_get(post, "name"),
                "title" => json_get(post, "title"),
                "selftext" => json_get(post, "selftext"),
                "domain" => json_get(post, "domain"),
                "created_utc" => json_get(post, "created_utc"), # unix time in utc
                "created" => json_get(post, "created"), # unix time in local time
                "score" => json_get(post, "score"),
                "upvote_ratio" => json_get(post, "upvote_ratio"),
                "num_comments" => json_get(post, "num_comments"),
                "ups" => json_get(post, "ups"),
                "downs" => json_get(post, "downs"),
                "url" => json_get(post, "url"),
                "selftext_cleaned" => radmta_preprocess_text(String(strip(json_get(post, "selftext")))),
                "analysis_text" => radmta_preprocess_text(String(strip(json_get(post, "title") * " " * json_get(post, "selftext")))),
            )

            if _insert_data["name"] !== nothing

                SurrealdbWS.create(_db, thing="posts:$(_insert_data["name"])", data=_insert_data)
            else
                continue
            end


        end

    finally
        # close the database connection
        SurrealdbWS.close(_db)
    end
end



function insert_radmta_comments_data(comments_data)

    # connect to the surrealdb database
    _db = SurrealdbWS.Surreal("ws://$(SURREALDB_HOST):$(SURREALDB_PORT)/rpc")
    SurrealdbWS.connect(_db) # connect to the database
    
    try
        # sign in to the database
        SurrealdbWS.signin(_db, user=SURREALDB_USER, pass=SURREALDB_PASS)
        # switch to the database and namespace
        SurrealdbWS.use(_db, namespace=SURREALDB_NAMESPACE, database=SURREALDB_DATABASE)
        # iterate through the comments data and insert the data into the database
        
        for comment in comments_data
            # a temporary dictionary buffer, then use this for inserting the data into the database. 
            _insert_data = Dict{String, Any}(
                "name" => json_get(comment, "name"),
                "link_id" => json_get(comment, "link_id"),
                "parent_id" => json_get(comment, "parent_id"),
                "body" => json_get(comment, "body"),
                "created_utc" => json_get(comment, "created_utc"), # unix time in utc
                "created" => json_get(comment, "created"), # unix time in local time
                "score" => json_get(comment, "score"),
                "analysis_text" => radmta_preprocess_text(String(strip(something(json_get(comment, "body"), "")))),
            )

            if _insert_data["name"] !== nothing

                SurrealdbWS.create(_db, thing="comments:$(_insert_data["name"])", data=_insert_data)
            else
                continue
            end


        end

    finally
        # close the database connection
        SurrealdbWS.close(_db)
    end
end

###############################################################################################
###################################### MAIN ###################################################
###############################################################################################

function main()

    # Create the radmta: namespace, database, and tables from the initial schema. 
    apply_radmta_schema()

    # Assemble file path fo the posts jsonl archive
    posts_jsonl_file = joinpath(homedir(), "Downloads", "r_natalism_posts-11-01-26.jsonl")

    # Assemble file path for the comments jsonl archive
    comments_jsonl_file = joinpath(homedir(), "Downloads", "r_natalism_comments-11-01-26.jsonl")
    
    # read the posts data from the jsonl file
    posts_jsonl_data = read_jsonl_and_return_array_of_dicts(posts_jsonl_file)

    # read the comments data from the jsonl file
    comments_jsonl_data = read_jsonl_and_return_array_of_dicts(comments_jsonl_file)

    # insert the posts data into the database
    insert_radmta_posts_data(posts_jsonl_data)

    # insert the comments data into the database
    insert_radmta_comments_data(comments_jsonl_data)


    # free up memory for processing by the garbage collector. 
    posts_jsonl_data = nothing   # or let main end
    comments_jsonl_data = nothing   # or let main end
    GC.gc()

    # end of the main function here. 
end


# Run the main function
main()




## comments: name as the record id, link_id, parent_id, body, created_utc, score
# Iterate through the comments data and create a dictionary for each comment
#for comment in comments_jsonl_data
#    created = json_get(comment, "created")
#    created_utc = json_get(comment, "created_utc")
#    data = Dict{String, Any}(
#        "name" => json_get(comment, "name"),
#        "link_id" => json_get(comment, "link_id"),
#        "parent_id" => json_get(comment, "parent_id"),
#        "body" => json_get(comment, "body"),
#        "created_utc" => created_utc,
#        "created" => created,
#        "score" => json_get(comment, "score"),
#        "analysis_text" => radmta_preprocess_text(String(strip(something(json_get(comment, "body"), "")))),
#    )
#    println(data)
#end


# comments


#const FIELDS_FOR_POSTS = Dict{String, Any}(
#    "name" => "null",
#    "title" => "null",
#    "selftext" => "null",
#    "domain" => "null",
#    "created_utc" => "null",
#    "created" => "null",
#    "score" => "null",
#    "upvote_ratio" => "null",
#    "num_comments" => "null",
#    "ups" => "null",
#    "downs" => "null",
#    "url" => "null",
#    "selftext_cleaned" => "null",
#    "analysis_text" => "null"
#)
#
#const FIELDS_FOR_COMMENTS = [
#    "name",
#    "link_id",
#    "parent_id",
#    "body",
#    "created_utc",
#    "created",
#    "score",
#    "analysis_text"
#]
