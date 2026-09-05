-- =============================================================================
-- RAD-MTA / r/Natalism — SurrealDB schema
-- Source files:
--   data/r_natalism_posts.jsonl      (~8,343 rows; ~38–105 keys over 2012–2026)
--   data/r_natalism_comments.jsonl   (~299k rows; ~22–69 keys over 2012–2026)
--
-- Pin a SurrealDB 2.x/3.x server and run this file against an empty NS/DB
-- before any ingest. This file is the contract, not a drop-in of JSONL.
--
-- Schema policy:
--   post, comment, in_thread, replies_to → SCHEMALESS
--     Archive keys drift. Extra JSONL fields are allowed. DEFINE FIELD still
--     type-checks the analytic core.
--   document → SCHEMAFULL
--     RAG/affect contract is ours; unknown keys should not appear here.
--
-- Record IDs: post:⟨t3_14622a⟩, comment:⟨t1_c7a6yvf⟩.
--
-- Layers:
--   1. Frozen ingest (post, comment) + graph edges (in_thread, replies_to)
--   2. Analytic document grain (document) for embeddings, topic, affect metadata
--
-- Fallback: same field contract as main_database.sql (PostgreSQL).
-- =============================================================================

DEFINE NAMESPACE IF NOT EXISTS radmta;
DEFINE DATABASE IF NOT EXISTS natalism;
USE NS radmta DB natalism;

-- ---------------------------------------------------------------------------
-- 1. Frozen Reddit ingest
-- ---------------------------------------------------------------------------

DEFINE TABLE IF NOT EXISTS post SCHEMALESS
    COMMENT "Submission from r_natalism_posts.jsonl; SCHEMALESS because archive keys drift; PK = Reddit fullname (t3_*)";

DEFINE FIELD IF NOT EXISTS name ON post TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Reddit fullname, e.g. t3_14622a";
DEFINE FIELD IF NOT EXISTS reddit_id ON post TYPE string
    COMMENT "Short id without prefix, e.g. 14622a. JSONL field `id` maps here — never CONTENT a top-level `id`.";
DEFINE FIELD IF NOT EXISTS subreddit ON post TYPE string DEFAULT 'Natalism';
DEFINE FIELD IF NOT EXISTS subreddit_id ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author_fullname ON post TYPE option<string>;

DEFINE FIELD IF NOT EXISTS title ON post TYPE string;
DEFINE FIELD IF NOT EXISTS selftext ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS url ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS permalink ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS domain ON post TYPE option<string>;

DEFINE FIELD IF NOT EXISTS created_utc ON post TYPE int
    COMMENT "Unix seconds as archived (int in JSONL)";
-- COMPUTED: derived on read from the stored unix field. Do not write this.
-- VALUE + $created_utc is wrong: $created_utc is a query parameter, not the field.
DEFINE FIELD IF NOT EXISTS created_at ON post
    COMPUTED time::from_unix(created_utc)
    COMMENT "Derived from created_utc";
DEFINE FIELD IF NOT EXISTS retrieved_on ON post TYPE option<int>;

DEFINE FIELD IF NOT EXISTS score ON post TYPE option<int>;
DEFINE FIELD IF NOT EXISTS ups ON post TYPE option<int>;
DEFINE FIELD IF NOT EXISTS downs ON post TYPE option<int>;
DEFINE FIELD IF NOT EXISTS upvote_ratio ON post TYPE option<float>
    COMMENT "JSONL mixes int (early) and float (later); coerce to float in the client before insert";
DEFINE FIELD IF NOT EXISTS num_comments ON post TYPE option<int>;

DEFINE FIELD IF NOT EXISTS is_self ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS over_18 ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS spoiler ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS stickied ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS locked ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS archived ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS distinguished ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS removed_by_category ON post TYPE option<string>;

-- Reddit sends false or a unix timestamp. Do not use FLEXIBLE here: that
-- clause is only valid after TYPE, and only when the type contains object.
DEFINE FIELD IF NOT EXISTS edited ON post TYPE bool | int;

DEFINE FIELD IF NOT EXISTS analysis_text ON post
    COMPUTED string::trim(title + ' ' + (selftext OR ''))
    COMMENT "title + selftext; used for embedding/classification, not stuffed with metadata";

-- Nested dump of the original JSONL object (including its `id` key). Safe
-- because it is nested. A top-level JSONL `id` is not safe.
DEFINE FIELD IF NOT EXISTS raw ON post TYPE object FLEXIBLE
    COMMENT "Full JSONL object for fields that appear/disappear across archive years";

DEFINE INDEX IF NOT EXISTS uniq_post_name ON post FIELDS name UNIQUE;
DEFINE INDEX IF NOT EXISTS uniq_post_reddit_id ON post FIELDS reddit_id UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_post_created ON post FIELDS created_utc;
DEFINE INDEX IF NOT EXISTS idx_post_score ON post FIELDS score;
DEFINE INDEX IF NOT EXISTS idx_post_author ON post FIELDS author;
DEFINE INDEX IF NOT EXISTS idx_post_domain ON post FIELDS domain;


DEFINE TABLE IF NOT EXISTS comment SCHEMALESS
    COMMENT "Comment from r_natalism_comments.jsonl; SCHEMALESS because archive keys drift; PK = Reddit fullname (t1_*)";

DEFINE FIELD IF NOT EXISTS name ON comment TYPE string
    ASSERT $value.starts_with('t1_');
DEFINE FIELD IF NOT EXISTS reddit_id ON comment TYPE string
    COMMENT "Short id without prefix, e.g. c7a6yvf";

DEFINE FIELD IF NOT EXISTS link_id ON comment TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Parent submission fullname";
DEFINE FIELD IF NOT EXISTS parent_id ON comment TYPE string
    COMMENT "t3_* = top-level on post; t1_* = reply to comment";

-- Record links are IDs, not foreign keys. Comments on deleted/missing
-- submissions are stored; RELATE is optional and must not use ENFORCED.
DEFINE FIELD IF NOT EXISTS post ON comment TYPE option<record<post>>
    COMMENT "Record link derived from link_id; may dangle if the submission is not in the posts file";
DEFINE FIELD IF NOT EXISTS parent ON comment TYPE option<record<post> | record<comment>>
    COMMENT "Record link derived from parent_id";

DEFINE FIELD IF NOT EXISTS subreddit ON comment TYPE string DEFAULT 'Natalism';
DEFINE FIELD IF NOT EXISTS subreddit_id ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author_fullname ON comment TYPE option<string>;

DEFINE FIELD IF NOT EXISTS body ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS permalink ON comment TYPE option<string>;

DEFINE FIELD IF NOT EXISTS created_utc ON comment TYPE int;
DEFINE FIELD IF NOT EXISTS created_at ON comment
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD IF NOT EXISTS retrieved_on ON comment TYPE option<int>;

DEFINE FIELD IF NOT EXISTS score ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS ups ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS downs ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS controversiality ON comment TYPE option<int>;

DEFINE FIELD IF NOT EXISTS is_submitter ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS stickied ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS locked ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS archived ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS collapsed ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS score_hidden ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS distinguished ON comment TYPE option<string>;

DEFINE FIELD IF NOT EXISTS edited ON comment TYPE bool | int;

DEFINE FIELD IF NOT EXISTS analysis_text ON comment
    COMPUTED body
    COMMENT "Comment body for embedding/classification";

DEFINE FIELD IF NOT EXISTS raw ON comment TYPE object FLEXIBLE;

DEFINE INDEX IF NOT EXISTS uniq_comment_name ON comment FIELDS name UNIQUE;
DEFINE INDEX IF NOT EXISTS uniq_comment_reddit_id ON comment FIELDS reddit_id UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_comment_link ON comment FIELDS link_id;
DEFINE INDEX IF NOT EXISTS idx_comment_parent ON comment FIELDS parent_id;
DEFINE INDEX IF NOT EXISTS idx_comment_post ON comment FIELDS post;
DEFINE INDEX IF NOT EXISTS idx_comment_created ON comment FIELDS created_utc;
DEFINE INDEX IF NOT EXISTS idx_comment_score ON comment FIELDS score;
DEFINE INDEX IF NOT EXISTS idx_comment_author ON comment FIELDS author;

-- Graph: comment belongs to a submission; reply chain (post or comment).
-- Do not add ENFORCED: comments exist for submissions missing from posts.jsonl.
DEFINE TABLE IF NOT EXISTS in_thread TYPE RELATION IN comment OUT post
    COMMENT "comment → submission; default SCHEMALESS";
DEFINE TABLE IF NOT EXISTS replies_to TYPE RELATION IN comment OUT post|comment
    COMMENT "comment → parent post or parent comment; default SCHEMALESS";

-- ---------------------------------------------------------------------------
-- 2. Analytic document grain (RAG / RAD-MTA)
--    One record per post or comment. Affect is metadata, never stuffed into
--    embedding or analysis_text.
-- ---------------------------------------------------------------------------

DEFINE TABLE IF NOT EXISTS document SCHEMAFULL
    COMMENT "Analytic unit; SCHEMAFULL on purpose — RAG/affect contract; id mirrors source fullname";

DEFINE FIELD IF NOT EXISTS unit_type ON document TYPE string
    ASSERT $value IN ['post', 'comment'];
DEFINE FIELD IF NOT EXISTS source ON document TYPE record<post> | record<comment>;
DEFINE FIELD IF NOT EXISTS reddit_name ON document TYPE string
    COMMENT "t3_* or t1_*";
DEFINE FIELD IF NOT EXISTS thread_id ON document TYPE option<string>
    COMMENT "Always the submission fullname (t3_*)";
DEFINE FIELD IF NOT EXISTS post ON document TYPE option<record<post>>;

DEFINE FIELD IF NOT EXISTS text ON document TYPE string
    COMMENT "Canonical analysis text: post title+selftext or comment body";
DEFINE FIELD IF NOT EXISTS created_utc ON document TYPE int;
DEFINE FIELD IF NOT EXISTS created_at ON document
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD IF NOT EXISTS score ON document TYPE option<int>;
DEFINE FIELD IF NOT EXISTS upvote_ratio ON document TYPE option<float>;
DEFINE FIELD IF NOT EXISTS num_comments ON document TYPE option<int>;
DEFINE FIELD IF NOT EXISTS engagement_bin ON document TYPE option<string>;
DEFINE FIELD IF NOT EXISTS year ON document TYPE option<int>;

DEFINE FIELD IF NOT EXISTS topic_id ON document TYPE option<int>;

DEFINE FIELD IF NOT EXISTS embedding ON document TYPE option<array<float>>
    COMMENT "gte-modernbert-base, 768-d; do not concatenate affect into this vector";

-- FLEXIBLE must come immediately after TYPE. Nested .label fields are defined
-- so SCHEMAFULL indexes on those paths are valid.
DEFINE FIELD IF NOT EXISTS sentiment ON document TYPE option<object> FLEXIBLE
    COMMENT "{ label, scores, confidence, model, labeled_at }";
DEFINE FIELD IF NOT EXISTS sentiment.label ON document TYPE option<string>
    ASSERT $value = NONE OR $value IN ['negative', 'neutral', 'positive'];
DEFINE FIELD IF NOT EXISTS emotions ON document TYPE option<object> FLEXIBLE
    COMMENT "{ label, scores, confidence, model, labeled_at }";
DEFINE FIELD IF NOT EXISTS emotions.label ON document TYPE option<string>
    ASSERT $value = NONE OR $value IN ['joy', 'sadness', 'anger', 'fear', 'love', 'neutral', 'surprise'];

DEFINE INDEX IF NOT EXISTS uniq_document_name ON document FIELDS reddit_name UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_document_unit ON document FIELDS unit_type;
DEFINE INDEX IF NOT EXISTS idx_document_thread ON document FIELDS thread_id;
DEFINE INDEX IF NOT EXISTS idx_document_topic ON document FIELDS topic_id;
DEFINE INDEX IF NOT EXISTS idx_document_engagement ON document FIELDS engagement_bin;
DEFINE INDEX IF NOT EXISTS idx_document_year ON document FIELDS year;
DEFINE INDEX IF NOT EXISTS idx_document_score ON document FIELDS score;
DEFINE INDEX IF NOT EXISTS idx_sentiment_label ON document FIELDS sentiment.label;
DEFINE INDEX IF NOT EXISTS idx_emotions_label ON document FIELDS emotions.label;
-- Build this AFTER embeddings are written, not before. HNSW is in-RAM; ~307k
-- × 768-d F32 plus graph overhead is a few GB. If the 5–10k subset test is
-- fine but full-corpus RAM is not, switch this index to DISKANN or fall back
-- to PostgreSQL.
DEFINE INDEX IF NOT EXISTS idx_embedding ON document FIELDS embedding HNSW DIMENSION 768 DIST COSINE TYPE F32;

-- ---------------------------------------------------------------------------
-- 3. Ingest rules (Julia / HTTP POST /sql)
-- ---------------------------------------------------------------------------
--
-- NEVER: CREATE post CONTENT $jsonl_row
--   JSONL has a field named `id`. SurrealDB uses `id` as the record id.
--   That write either fails or silently replaces the record key.
--
-- ALWAYS:
--   1. Map JSONL `id` → reddit_id
--   2. Use JSONL `name` as the record key (t3_ / t1_)
--   3. Coerce upvote_ratio to float
--   4. Put the original object under `raw` (nested `raw.id` is fine)
--   5. Do not write created_at or analysis_text; they are COMPUTED
--
-- CREATE post:⟨t3_14622a⟩ CONTENT {
--   name: "t3_14622a",
--   reddit_id: "14622a",
--   subreddit: "Natalism",
--   subreddit_id: "t5_2vp2p",
--   author: "SammyD1st",
--   title: "Wikipedia on Natalism",
--   selftext: "...",
--   url: "...",
--   permalink: "/r/Natalism/comments/14622a/wikipedia_on_natalism/",
--   domain: "self.Natalism",
--   created_utc: 1354485197,
--   retrieved_on: 1413325789,
--   score: 0,
--   ups: 0,
--   downs: 0,
--   upvote_ratio: 1.0,
--   num_comments: 1,
--   is_self: true,
--   over_18: false,
--   spoiler: false,
--   stickied: false,
--   edited: false,
--   raw: { ... entire JSONL object, including its `id` key ... }
-- };
--
-- CREATE comment:⟨t1_c7a76o4⟩ CONTENT {
--   name: "t1_c7a76o4",
--   reddit_id: "c7a76o4",
--   link_id: "t3_14622a",
--   parent_id: "t3_14622a",
--   post: post:⟨t3_14622a⟩,
--   parent: post:⟨t3_14622a⟩,
--   author: "SammyD1st",
--   body: "Whoops...",
--   created_utc: 1354487261,
--   score: 1,
--   controversiality: 0,
--   raw: { ... }
-- };
--
-- RELATE only when the OUT record exists. Skip or defer edges whose
-- submission is missing from posts.jsonl. Do not DEFINE these tables ENFORCED.
-- RELATE comment:⟨t1_c7a76o4⟩->in_thread->post:⟨t3_14622a⟩;
-- RELATE comment:⟨t1_c7a76o4⟩->replies_to->post:⟨t3_14622a⟩;
-- -- nested reply:
-- RELATE comment:⟨t1_nnp1rjo⟩->replies_to->comment:⟨t1_nnouben⟩;
--
-- CREATE document:⟨t3_14622a⟩ CONTENT {
--   unit_type: "post",
--   source: post:⟨t3_14622a⟩,
--   reddit_name: "t3_14622a",
--   thread_id: "t3_14622a",
--   post: post:⟨t3_14622a⟩,
--   text: "Wikipedia on Natalism ...",
--   created_utc: 1354485197,
--   score: 0,
--   upvote_ratio: 1.0,
--   num_comments: 1
-- };
--
-- UPDATE document:⟨t3_14622a⟩ MERGE {
--   sentiment: {
--     label: "neutral",
--     scores: { negative: 0.1, neutral: 0.8, positive: 0.1 },
--     confidence: 0.8,
--     model: "EbukaGaus/EbukaMBert",
--     labeled_at: time::now()
--   },
--   emotions: {
--     label: "neutral",
--     scores: { joy: 0.0, sadness: 0.0, anger: 0.0, fear: 0.0, love: 0.0, neutral: 1.0, surprise: 0.0 },
--     confidence: 0.9,
--     model: "cirimus/modernbert-base-emotions",
--     labeled_at: time::now()
--   }
-- };
--
-- Filtered KNN: put attribute filters BEFORE the KNN operator. SurrealDB
-- issue #7314: if embedding <|K,EF|> comes first and the other predicates
-- are indexed, the planner can return 0 rows.
-- SELECT id, text, sentiment, emotions, score,
--        vector::distance::knn() AS distance
-- FROM document
-- WHERE sentiment.label = $sent
--   AND engagement_bin = $bin
--   AND embedding <|50, 40|> $query_vec
-- ORDER BY distance;
--
-- Thread walk:
-- SELECT *, ->in_thread->post AS submission,
--           ->replies_to AS parent
-- FROM comment:⟨t1_nnp1rjo⟩;
