-- =============================================================================
-- RAD-MTA / r/Natalism — posts and comments
--
-- Record ids: posts:⟨t3_14622a⟩, comments:⟨t1_c7a6yvf⟩.
-- The JSONL files on disk are the archive. surreal-sync loads them into
-- src_posts and src_comments (the filename is the table name). Copy the
-- study fields, check the counts, then REMOVE TABLE src_posts, src_comments.
--
-- Derived, do not write: reddit_id, created_at, analysis_text, comments.parent.
-- comments.post is filled from link_id.
-- =============================================================================

DEFINE NAMESPACE IF NOT EXISTS radmta;
DEFINE DATABASE IF NOT EXISTS natalism;
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
DEFINE FIELD OVERWRITE created_utc ON posts TYPE int
    COMMENT "Unix seconds";
DEFINE FIELD OVERWRITE created_at ON posts
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD OVERWRITE score ON posts TYPE option<int>;
DEFINE FIELD OVERWRITE upvote_ratio ON posts TYPE option<float>
    VALUE IF $value IS NONE THEN NONE ELSE <float>$value END
    COMMENT "Archive mixes int and float. Coerced on write.";
DEFINE FIELD OVERWRITE num_comments ON posts TYPE option<int>;
DEFINE FIELD OVERWRITE analysis_text ON posts
    COMPUTED string::trim(title + ' ' + (selftext OR ''))
    COMMENT "title + selftext. Embed this. Do not write it.";

DEFINE INDEX OVERWRITE uniq_posts_name ON posts FIELDS name UNIQUE;
DEFINE INDEX OVERWRITE uniq_posts_reddit_id ON posts FIELDS reddit_id UNIQUE;
DEFINE INDEX OVERWRITE idx_posts_created ON posts FIELDS created_utc;
DEFINE INDEX OVERWRITE idx_posts_score ON posts FIELDS score;
DEFINE INDEX OVERWRITE idx_posts_upvote_ratio ON posts FIELDS upvote_ratio;
DEFINE INDEX OVERWRITE idx_posts_num_comments ON posts FIELDS num_comments;


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
DEFINE FIELD OVERWRITE created_utc ON comments TYPE int;
DEFINE FIELD OVERWRITE created_at ON comments
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD OVERWRITE score ON comments TYPE option<int>;
DEFINE FIELD OVERWRITE analysis_text ON comments
    COMPUTED body
    COMMENT "Comment body. Embed this. Do not write it.";

DEFINE INDEX OVERWRITE uniq_comments_name ON comments FIELDS name UNIQUE;
DEFINE INDEX OVERWRITE uniq_comments_reddit_id ON comments FIELDS reddit_id UNIQUE;
DEFINE INDEX OVERWRITE idx_comments_link ON comments FIELDS link_id;
DEFINE INDEX OVERWRITE idx_comments_parent ON comments FIELDS parent_id;
DEFINE INDEX OVERWRITE idx_comments_post ON comments FIELDS post;
DEFINE INDEX OVERWRITE idx_comments_created ON comments FIELDS created_utc;
DEFINE INDEX OVERWRITE idx_comments_score ON comments FIELDS score;

-- Copy after surreal-sync. Then drop the staging tables.
--
-- INSERT INTO posts (
--     SELECT
--         type::record("posts", name) AS id,
--         name,
--         title,
--         selftext,
--         created_utc,
--         score,
--         upvote_ratio,
--         num_comments
--     FROM src_posts
-- );
--
-- INSERT INTO comments (
--     SELECT
--         type::record("comments", name) AS id,
--         name,
--         link_id,
--         parent_id,
--         body,
--         created_utc,
--         score
--     FROM src_comments
-- );
--
-- REMOVE TABLE src_posts;
-- REMOVE TABLE src_comments;
