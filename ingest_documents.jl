#!/usr/bin/env julia

# Making sure the packages are instantiated within the current directory
using Pkg
Pkg.activate(@__DIR__) # Activates the directory where the script lives
Pkg.instantiate()      # Installs any missing dependencies

# precompile everything for good speed on the explicit platform
precompile

# dependencies
using HTTP # http library for making requests to the web
# SurrealdbWS keeps one HTTP.jl connection per pool slot until the process exits.
# On one Julia thread the default cap is 16. Schema (1) plus the two document
# pools (8 + 8) passes that, and the next connect sits there until the 10s timeout.
HTTP.set_default_connection_limit!(256)
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


# SurrealDB schema for the namespace
## raw"..." keeps SurrealQL $value from being interpolated by Julia (i.e. $value 
## could be instruct julia to inject a value in this variable, but surrealdb also uses this syntax for using variables in its operations).
const NAMESPACE_SCHEMA = raw"""
DEFINE NAMESPACE IF NOT EXISTS radmta;
USE NS radmta;
DEFINE DATABASE IF NOT EXISTS natalism;
USE NS radmta DB natalism;
"""


const DOCUMENTS_TABLE_SCHEMA = raw"""

DEFINE NAMESPACE IF NOT EXISTS radmta;
DEFINE DATABASE IF NOT EXISTS natalism;
USE NS radmta DB natalism;

DEFINE TABLE OVERWRITE documents SCHEMAFULL
    COMMENT "One post or one comment. Record id is the t3_ or t1_ fullname.";

DEFINE FIELD OVERWRITE kind ON documents TYPE string
    ASSERT $value IN ['post', 'comment']
    COMMENT "post = submission. comment = reply.";

DEFINE FIELD OVERWRITE name ON documents TYPE string
    ASSERT ($value.starts_with('t3_') AND kind = 'post')
        OR ($value.starts_with('t1_') AND kind = 'comment')
    COMMENT "Reddit fullname, e.g. t3_14622a or t1_c7a6yvf.";

-- string::slice(name, 3) reads from index 3 through the end. Both prefixes are 3 characters.
DEFINE FIELD OVERWRITE reddit_id ON documents TYPE string
    VALUE $value OR string::slice(name, 3)
    ASSERT $value = string::slice(name, 3)
    COMMENT "Short id. Derived from name.";

-- ---------------------------------------------------------------------------
-- Comment linkage. Empty on a post.
-- ---------------------------------------------------------------------------

DEFINE FIELD OVERWRITE link_id ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN NONE ELSE $value END
    ASSERT IF kind = 'comment' THEN
        $value IS NOT NONE AND $value.starts_with('t3_')
    ELSE
        $value IS NONE
    END
    COMMENT "Submission fullname this comment belongs to.";

DEFINE FIELD OVERWRITE parent_id ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN NONE ELSE $value END
    ASSERT IF kind = 'comment' THEN
        $value IS NOT NONE AND ($value.starts_with('t1_') OR $value.starts_with('t3_'))
    ELSE
        $value IS NONE
    END
    COMMENT "t3_* = reply to the submission; t1_* = reply to a comment.";

DEFINE FIELD OVERWRITE thread ON documents TYPE record<documents>
    VALUE IF kind = 'post' THEN
        type::record("documents", name)
    ELSE
        type::record("documents", link_id)
    END
    COMMENT "The submission row. A post points at itself. A comment points at documents:⟨link_id⟩. Derived. Do not write it. May dangle if that submission was not copied.";

DEFINE FIELD OVERWRITE parent ON documents TYPE option<record<documents>>
    VALUE IF kind = 'comment' AND parent_id IS NOT NONE THEN
        type::record("documents", parent_id)
    ELSE
        NONE
    END
    COMMENT "documents:⟨parent_id⟩. Derived from parent_id. Do not write it. May dangle.";

-- ---------------------------------------------------------------------------
-- Text. Post-only and comment-only fields are cleared for the other kind.
-- ---------------------------------------------------------------------------

DEFINE FIELD OVERWRITE title ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN $value OR '' ELSE NONE END
    COMMENT "Submission title. Empty string when the archive omits it.";

DEFINE FIELD OVERWRITE selftext ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN $value ELSE NONE END;

DEFINE FIELD OVERWRITE selftext_cleaned ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN $value ELSE NONE END
    COMMENT "Preprocessed selftext. Written by the ingest script.";

DEFINE FIELD OVERWRITE body ON documents TYPE option<string>
    VALUE IF kind = 'comment' THEN $value ELSE NONE END;

DEFINE FIELD OVERWRITE domain ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN $value ELSE NONE END;

DEFINE FIELD OVERWRITE url ON documents TYPE option<string>
    VALUE IF kind = 'post' THEN $value ELSE NONE END;

DEFINE FIELD OVERWRITE analysis_text ON documents TYPE option<string>
    COMMENT "Encoder input. Post: title + selftext. Comment: body. Written by the ingest script.";

DEFINE FIELD OVERWRITE permalink ON documents TYPE option<string>
    COMMENT "Archive permalink. Private identifier for checking a quotation. Not an analytic variable.";

DEFINE FIELD OVERWRITE stickied ON documents TYPE option<bool>
    VALUE IF kind = 'comment' OR $value IS NONE THEN NONE ELSE <bool>$value END
    COMMENT "Posts only. Moderator pin. Not part of the score rank. A comment's stickied flag is dropped.";

-- Archive `edited` is false, or a Unix timestamp once the text changes. Pass that raw value here.
DEFINE FIELD OVERWRITE edited_utc ON documents TYPE option<int>
    VALUE IF $value IS NONE OR $value IS false OR $value IS true THEN
        NONE
    ELSE
        <int>$value
    END
    COMMENT "Unix seconds the text was edited. false and true become NONE, because neither carries a timestamp. The score may belong to an earlier wording.";

-- ---------------------------------------------------------------------------
-- Time and score. Shared. upvote_ratio and num_comments are post-only.
-- ---------------------------------------------------------------------------

DEFINE FIELD OVERWRITE created_utc ON documents TYPE int
    VALUE <int>$value
    COMMENT "Unix seconds.";

DEFINE FIELD OVERWRITE created ON documents TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END
    COMMENT "Unix seconds from the archive created field. Absent on early rows.";

DEFINE FIELD OVERWRITE created_datetime ON documents TYPE option<datetime>
    VALUE IF $value IS NONE THEN NONE ELSE <datetime>$value END;

DEFINE FIELD OVERWRITE created_utc_datetime ON documents TYPE option<datetime>
    VALUE IF $value IS NONE THEN NONE ELSE <datetime>$value END;

DEFINE FIELD OVERWRITE created_at ON documents
    COMPUTED time::from_unix(created_utc);

DEFINE FIELD OVERWRITE score ON documents TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END
    COMMENT "Post scores floor at 0 in the archive. Comment scores can be negative.";

DEFINE FIELD OVERWRITE ups ON documents TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;

DEFINE FIELD OVERWRITE downs ON documents TYPE option<int>
    VALUE IF $value IS NONE THEN NONE ELSE <int>$value END;

DEFINE FIELD OVERWRITE upvote_ratio ON documents TYPE option<float>
    VALUE IF kind = 'comment' OR $value IS NONE THEN NONE ELSE <float>$value END
    COMMENT "Posts only. Archive mixes int and float. Coerced on write. A comment's copy of this key is dropped.";

DEFINE FIELD OVERWRITE num_comments ON documents TYPE option<int>
    VALUE IF kind = 'comment' OR $value IS NONE THEN NONE ELSE <int>$value END
    COMMENT "Posts only. On a modern comment this key repeats the parent count and is dropped.";

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

DEFINE INDEX OVERWRITE uniq_documents_name ON documents FIELDS name UNIQUE;
DEFINE INDEX OVERWRITE uniq_documents_reddit_id ON documents FIELDS reddit_id UNIQUE;
DEFINE INDEX OVERWRITE idx_documents_kind ON documents FIELDS kind;
DEFINE INDEX OVERWRITE idx_documents_thread ON documents FIELDS thread;
DEFINE INDEX OVERWRITE idx_documents_parent ON documents FIELDS parent;
DEFINE INDEX OVERWRITE idx_documents_link ON documents FIELDS link_id;
DEFINE INDEX OVERWRITE idx_documents_parent_id ON documents FIELDS parent_id;
DEFINE INDEX OVERWRITE idx_documents_created ON documents FIELDS created_utc;
DEFINE INDEX OVERWRITE idx_documents_kind_created ON documents FIELDS kind, created_utc;
DEFINE INDEX OVERWRITE idx_documents_score ON documents FIELDS score;
DEFINE INDEX OVERWRITE idx_documents_upvote_ratio ON documents FIELDS upvote_ratio;
DEFINE INDEX OVERWRITE idx_documents_num_comments ON documents FIELDS num_comments;
DEFINE INDEX OVERWRITE idx_documents_stickied ON documents FIELDS stickied;

""" 


function put_some!(d, k, v)
    v === nothing || (d[k] = v)
    return d
end


function sql_fallback_eligible(e)::Bool
    # create() runs inside @spawn, so this is usually a TaskFailedException
    # whose text still contains the server message.
    msg = sprint(showerror, e)
    occursin("Couldn't coerce value for field", msg) || return false
    occursin("Expected", msg) && occursin("string", msg) || return false
    return true
end


# JSON-RPC create, and query variables, both parse some colon-shaped strings
# as record ids before SCHEMAFULL runs (surrealdb#7685). A quoted literal in
# the SQL text stays a string, so the fallback must not bind the row as $data.
function surrealql_literal(v)::String
    v isa Bool && return v ? "true" : "false"
    v isa Integer && return string(v)
    v isa AbstractFloat && return string(v)
    v isa AbstractString && return surrealql_string(v)
    error("cannot inline $(typeof(v)) into SurrealQL")
end


function surrealql_string(s::AbstractString)::String
    io = IOBuffer()
    print(io, '\'')
    for c in s
        if c == '\\' || c == '\''
            print(io, '\\', c)
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif c == '\b'
            print(io, "\\b")
        elseif c == '\f'
            print(io, "\\f")
        elseif isascii(c) && iscntrl(c)
            print(io, "\\u", string(UInt16(c), base=16, pad=4))
        else
            print(io, c)
        end
    end
    print(io, '\'')
    return String(take!(io))
end


function surrealql_content(data::AbstractDict)::String
    parts = String[]
    for (k, v) in data
        key = String(k)
        occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", key) || error("refusing to inline field $key")
        push!(parts, key * ": " * surrealql_literal(v))
    end
    return "{" * join(parts, ", ") * "}"
end


function document_create_sql(name_s::AbstractString, data::AbstractDict)::String
    return "CREATE type::record('documents', " * surrealql_string(name_s) * ") CONTENT " * surrealql_content(data) * ";"
end


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
        #for sql in (NAMESPACE_SCHEMA, TABLE_POSTS_SCHEMA, TABLE_COMMENTS_SCHEMA)
        for sql in (NAMESPACE_SCHEMA, DOCUMENTS_TABLE_SCHEMA)
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
function radmta_preprocess_text(_text::String)::String
        
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
function read_jsonl_and_return_array_of_dicts(file_path::String)::Array
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
                #"created" => json_get(post, "created"), # unix time in local time
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

                # drop keys that would become JSON null
                for k in collect(keys(_insert_data))
                    _insert_data[k] === nothing && delete!(_insert_data, k)
                end
                # create the record in the database
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
                #"created" => json_get(comment, "created"), # unix time in local time
                "score" => json_get(comment, "score"),
                "analysis_text" => radmta_preprocess_text(String(strip(json_get(comment, "body")))),
            )

            if _insert_data["name"] !== nothing
                # drop keys that would become JSON null
                for k in collect(keys(_insert_data))
                    _insert_data[k] === nothing && delete!(_insert_data, k)
                end

                # create the record in the database
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

function archive_edited_to_utc(edited)
    edited === nothing && return nothing
    edited === false && return nothing
    edited === true && return nothing   # rare; same as “no timestamp”
    return edited                       # expect Integer
end
# One function handles both. The fullname prefix sets `kind`, and the record id is `documents:` plus that fullname. `edited` is passed through as `edited_utc`.

function insert_radmta_documents_data(records::Array)::Nothing

    # connect to the surrealdb database
    _db = SurrealdbWS.Surreal("ws://$(SURREALDB_HOST):$(SURREALDB_PORT)/rpc", npool=8)
    SurrealdbWS.connect(_db) # connect to the database

    try
        # sign in to the database
        SurrealdbWS.signin(_db, user=SURREALDB_USER, pass=SURREALDB_PASS)
        # switch to the database and namespace
        SurrealdbWS.use(_db, namespace=SURREALDB_NAMESPACE, database=SURREALDB_DATABASE)

        for record in records
            name = json_get(record, "name")
            if name === nothing
                continue
            end

            name_s = String(name)
            if startswith(name_s, "t3_")
                kind = "post"
            elseif startswith(name_s, "t1_")
                kind = "comment"
            else
                continue
            end

            # shared study fields. reddit_id, thread, and parent are filled by the schema.
            _insert_data = Dict{String, Any}(
                "kind" => kind,
                "name" => name_s,
                "created_utc" => json_get(record, "created_utc"), # unix time in utc
                "created" => json_get(record, "created"),
                "score" => json_get(record, "score"),
                "ups" => json_get(record, "ups"),
                "downs" => json_get(record, "downs"),
                "permalink" => json_get(record, "permalink"),
                "edited_utc" => archive_edited_to_utc(json_get(record, "edited")),
            )

            if kind == "post"
                title = json_get(record, "title")
                selftext = json_get(record, "selftext")
                title_s = title === nothing ? "" : String(strip(title))
                selftext_s = selftext === nothing ? "" : String(strip(selftext))

                _insert_data["title"] = title
                _insert_data["selftext"] = selftext
                _insert_data["domain"] = json_get(record, "domain")
                _insert_data["url"] = json_get(record, "url")
                _insert_data["upvote_ratio"] = json_get(record, "upvote_ratio")
                _insert_data["num_comments"] = json_get(record, "num_comments")
                _insert_data["stickied"] = json_get(record, "stickied")
                _insert_data["selftext_cleaned"] = radmta_preprocess_text(String(selftext_s))
                _insert_data["analysis_text"] = radmta_preprocess_text(String(strip(title_s * " " * selftext_s)))
            else
                body = json_get(record, "body")
                body_s = body === nothing ? "" : String(strip(body))

                _insert_data["link_id"] = json_get(record, "link_id")
                _insert_data["parent_id"] = json_get(record, "parent_id")
                _insert_data["body"] = body
                _insert_data["analysis_text"] = radmta_preprocess_text(String(body_s))
            end

            # drop keys that would become JSON null
            for k in collect(keys(_insert_data))
                _insert_data[k] === nothing && delete!(_insert_data, k)
            end
            try
                # create the record in the database
                SurrealdbWS.create(_db, thing="documents:$name_s", data=_insert_data)
            catch e
                if sql_fallback_eligible(e)
                    println("RPC create coerced a string for documents:$name_s; retrying as a SurrealQL query")
                    result = SurrealdbWS.query(_db, sql=document_create_sql(name_s, _insert_data))
                    errors = surreal_statement_errors(result)
                    isempty(errors) || error("SQL fallback failed for documents:$name_s:\n" * join(errors, "\n"))
                else
                    rethrow(e)
                end
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
#
#    # Assemble file path for the comments jsonl archive
    comments_jsonl_file = joinpath(homedir(), "Downloads", "r_natalism_comments-11-01-26.jsonl")
#    
#    # read the posts data from the jsonl file
    posts_jsonl_data = read_jsonl_and_return_array_of_dicts(posts_jsonl_file)
#
#    # read the comments data from the jsonl file
    comments_jsonl_data = read_jsonl_and_return_array_of_dicts(comments_jsonl_file)
#
#    # insert the posts data into the database
    insert_radmta_documents_data(posts_jsonl_data)
#
#    # insert the comments data into the database
    insert_radmta_documents_data(comments_jsonl_data)
#
#
#    # free up memory for processing by the garbage collector. 
    posts_jsonl_data = nothing   # or let main end
    comments_jsonl_data = nothing   # or let main end
    GC.gc()

    # Create the threads tables 

    # end of the main function here. 
end


# Run the main function
main()

# End of the script