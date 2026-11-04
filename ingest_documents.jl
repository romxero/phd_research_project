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
using SurrealdbWS
using TextAnalysis
using Dates


# Study fields written on copy. reddit_id, created_at, analysis_text, and
# comments.parent are filled by the schema. comments.post is filled from link_id.
const EXAMPLE_POST = Dict{String,Any}(
    "name" => "t3_14622a",
    "title" => "Wikipedia on Natalism",
    "selftext" => "Whoops, this is the post body.",
    "created_utc" => 1354485197,
    "score" => 0,
    "upvote_ratio" => 1.0,
    "num_comments" => 1,
)

const EXAMPLE_COMMENT = Dict{String,Any}(
    "name" => "t1_c7a76o4",
    "body" => "Whoops...",
    "link_id" => "t3_14622a",
    "parent_id" => "t3_14622a",
    "created_utc" => 1354487261,
    "score" => 1,
)

# JSON3 rows use Symbol keys (:created_utc). String keys in get() miss and hit the default.
json_get(row, key) = get(row, Symbol(key), get(row, key, nothing))

function unix_seconds_to_datetime(utc)
    utc === nothing && return nothing
    utc isa Integer && return unix2datetime(utc)
    utc isa AbstractFloat && return unix2datetime(round(Int, utc))
    utc isa AbstractString && return unix2datetime(parse(Int, utc))
    error("expected unix seconds as number or numeric string, got $(typeof(utc))")
end


#JSON3.Object{Base.CodeUnits{UInt8, String}, Vector{UInt64}} with 41 entries:
#  :archived               => true
#  :author                 => "[deleted]"
#  :author_flair_css_class => nothing
#  :author_flair_text      => nothing
#  :created                => 1403471016
#  :created_utc            => 1403467416
#  :distinguished          => nothing
#  :domain                 => "people.com"
#  :downs                  => 0
#  :edited                 => false
#  :from                   => nothing
#  :from_id                => nothing
#  :from_kind              => nothing
#  :gilded                 => 0
#  :hide_score             => false
#  :id                     => "28tcy0"
#  :is_self                => false
#  :link_flair_css_class   => nothing
#  :link_flair_text        => nothing
#  :media                  => nothing
#  :media_embed            => {}
#  :name                   => "t3_28tcy0"
#  :num_comments           => 8
#  :over_18                => false
#  :permalink              => "/r/Natalism/comments/28tcy0/how_others_view_natalism/"
#  :quarantine             => false
#  :retrieved_on           => 1441300462
#  :saved                  => false
#  :score                  => 2
#  :secure_media           => nothing
#  :secure_media_embed     => {}
#  :selftext               => ""
#  :spoiler                => false
#  :stickied               => false
#  :subreddit              => "Natalism"
#  :subreddit_id           => "t5_2vp2p"
#  :thumbnail              => "http://b.thumbs.redditmedia.com/uovk_WpiUuBbqPHs.jpg"
#  :title                  => "How others view Natalism"
#  :ups                    => 2
#  :url                    => "http://www.people.com/article/jill-duggar-married-derick-dillard-19-kids-and-counting"
#  :upvote_ratio           => 1


# posts
## posts: name as the record id, title, selftext, created_utc, score, upvote_ratio, num_comments

posts_jsonl_file = joinpath(homedir(), "Downloads", "r_natalism_posts-11-01-26.jsonl")
posts_jsonl_data = []
open(posts_jsonl_file, "r") do io
    for line in eachline(io)
        if !isempty(strip(line))
            push!(posts_jsonl_data, JSON3.read(line))
        end
    end
end

for post in posts_jsonl_data
    created = json_get(post, "created")
    created_utc = json_get(post, "created_utc")
    data = Dict{String, Any}(
        "name" => json_get(post, "name"),
        "title" => json_get(post, "title"),
        "selftext" => json_get(post, "selftext"),
        "domain" => json_get(post, "domain"),
        "created_utc" => created_utc,
        "created" => created,
        "created_datetime" => unix_seconds_to_datetime(created),
        "created_utc_datetime" => unix_seconds_to_datetime(created_utc),
        "score" => json_get(post, "score"),
        "upvote_ratio" => json_get(post, "upvote_ratio"),
        "num_comments" => json_get(post, "num_comments"),
        "ups" => json_get(post, "ups"),
        "downs" => json_get(post, "downs"),
        "url" => json_get(post, "url"),
    )
    println(data)
end


# comments
## comments: name as the record id, link_id, parent_id, body, created_utc, score

comments_jsonl_file = joinpath(homedir(), "Downloads", "r_natalism_comments-11-01-26.jsonl")
comments_jsonl_data = []
open(comments_jsonl_file, "r") do io
    for line in eachline(io)
        if !isempty(strip(line))
            push!(comments_jsonl_data, JSON3.read(line))
        end
    end
end



# Comment Keys
#[:_meta, :all_awardings, :approved_at_utc, :approved_by, :archived, :associated_award, :author, :author_flair_background_color, :author_flair_css_class, :author_flair_richtext, :author_flair_template_id, :author_flair_text, :author_flair_text_color, :author_flair_type, :author_fullname, :author_is_blocked, :author_patreon_flair, :author_premium, :awarders, :banned_at_utc, :banned_by, :body, :can_gild, :can_mod_post, :collapsed, :collapsed_because_crowd_control, :collapsed_reason, :collapsed_reason_code, :comment_type, :controversiality, :created, :created_utc, :distinguished, :downs, :edited, :gilded, :gildings, :id, :is_submitter, :likes, :link_id, :locked, :mod_note, :mod_reason_by, :mod_reason_title, :mod_reports, :name, :no_follow, :num_reports, :parent_id, :permalink, :removal_reason, :replies, :report_reasons, :retrieved_on, :saved, :score, :score_hidden, :send_replies, :stickied, :subreddit, :subreddit_id, :subreddit_name_prefixed, :subreddit_type, :top_awarded_type, :total_awards_received, :treatment_tags, :unrepliable_reason, :ups, :user_reports]

for comment in comments_jsonl_data
    created = json_get(comment, "created")
    created_utc = json_get(comment, "created_utc")
    data = Dict{String, Any}(
        "name" => json_get(comment, "name"),
        "link_id" => json_get(comment, "link_id"),
        "parent_id" => json_get(comment, "parent_id"),
        "body" => json_get(comment, "body"),
        "created_utc" => created_utc,
        "created" => created,
        "created_datetime" => unix_seconds_to_datetime(created),
        "created_utc_datetime" => unix_seconds_to_datetime(created_utc),
        "score" => json_get(comment, "score"),
    )
    # println(data)
end


