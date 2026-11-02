    -- =============================================================================
-- RAD-MTA / r/Natalism — SurrealDB schema
-- 
-- Pin a SurrealDB 2.x/3.x server and run this file against an empty NS/DB
-- before any ingest. This file is the contract, not a drop-in of JSONL.
--
-- Schema policy:
--   post, comment, in_thread, replies_to → SCHEMALESS
--     Archive keys drift. Extra JSONL fields are allowed. DEFINE FIELD still
--     type-checks the analytic core.
--   document, thread, thread_member → SCHEMAFULL
--     RAG/affect contract is ours; unknown keys should not appear here.
--
-- Record IDs: post:⟨t3_14622a⟩, comment:⟨t1_c7a6yvf⟩, thread:⟨t3_14622a⟩.
--
-- Layers:
--   1. Frozen ingest (post, comment) + graph edges (in_thread, replies_to)
--   2. Analytic document grain (document) for embeddings, topic, affect metadata
--   3. Thread reading order (thread, thread_member). Texts stay on document.
--   4. Theme construction (code, coded, theme, built_from, reviewed_against, memo).
--      The qualitative unit is the thread. topic_id is not a theme.
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
    COMMENT "Posts from an Arctic Shift dump of the selected subreddit; SCHEMALESS because archive keys drift; PK = Reddit fullname (t3_*)";

-- Core identifiers
DEFINE FIELD IF NOT EXISTS name ON post TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Reddit fullname, e.g. t3_14622a";
DEFINE FIELD IF NOT EXISTS reddit_id ON post TYPE string
    COMMENT "Short id without prefix, e.g. 14622a. JSONL field `id` maps here — never CONTENT a top-level `id`.";
DEFINE FIELD IF NOT EXISTS subreddit ON post TYPE string DEFAULT 'Natalism';
DEFINE FIELD IF NOT EXISTS subreddit_id ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author_fullname ON post TYPE option<string>;

-- Content
DEFINE FIELD IF NOT EXISTS title ON post TYPE string;
DEFINE FIELD IF NOT EXISTS selftext ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS url ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS permalink ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS domain ON post TYPE option<string>;

-- Timestamps
DEFINE FIELD IF NOT EXISTS created_utc ON post TYPE int
    COMMENT "Unix seconds as archived (int in JSONL)";
-- COMPUTED: derived on read from the stored unix field. Do not write this.
-- VALUE + $created_utc is wrong: $created_utc is a query parameter, not the field.
DEFINE FIELD IF NOT EXISTS created_at ON post
    COMPUTED time::from_unix(created_utc)
    COMMENT "Derived from created_utc";
DEFINE FIELD IF NOT EXISTS retrieved_on ON post TYPE option<int>;

-- Engagement
DEFINE FIELD IF NOT EXISTS score ON post TYPE option<int>;
DEFINE FIELD IF NOT EXISTS ups ON post TYPE option<int>;
DEFINE FIELD IF NOT EXISTS downs ON post TYPE option<int>;
DEFINE FIELD IF NOT EXISTS upvote_ratio ON post TYPE option<float>
    COMMENT "JSONL mixes int (early) and float (later); coerce to float in the client before insert";
DEFINE FIELD IF NOT EXISTS num_comments ON post TYPE option<int>;

-- Flags
DEFINE FIELD IF NOT EXISTS is_self ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS over_18 ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS spoiler ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS stickied ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS locked ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS archived ON post TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS distinguished ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS removed_by_category ON post TYPE option<string>;

-- Reddit sends false or a unix int. In r_natalism_posts the field is always
-- present: bool, or int on the edited rows. FLEXIBLE is only valid after TYPE
-- when the type contains object.
DEFINE FIELD IF NOT EXISTS edited ON post TYPE bool | int;

-- Flair is usually JSON null. crosspost_parent exists only on crossposts.
-- num_crossposts is missing on older rows.
DEFINE FIELD IF NOT EXISTS link_flair_text ON post TYPE option<string>;
DEFINE FIELD IF NOT EXISTS crosspost_parent ON post TYPE option<string>
    ASSERT $value = NONE OR $value.starts_with('t3_')
    COMMENT "Fullname of the parent post when this submission is a crosspost";
DEFINE FIELD IF NOT EXISTS num_crossposts ON post TYPE option<int>;

-- Computed text and the original object
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
DEFINE INDEX IF NOT EXISTS idx_post_crosspost ON post FIELDS crosspost_parent;


DEFINE TABLE IF NOT EXISTS comment SCHEMALESS
    COMMENT "Reddit comments (t1_*); SCHEMALESS because archive keys drift; PK = Reddit fullname";

-- Do not DEFINE FIELD id. JSONL `id` is the short id; SurrealDB reserves `id`
-- for the record key. Map JSONL `id` → reddit_id. Record keys stay fullnames:
-- comment:⟨t1_c7a6yvf⟩, and links point at post:⟨t3_…⟩ / comment:⟨t1_…⟩.
-- string::slice(link_id, 3) would build post:⟨1xksj4v⟩, which is a different record.

DEFINE FIELD IF NOT EXISTS name ON comment TYPE string
    ASSERT $value.starts_with('t1_')
    COMMENT "Reddit fullname, e.g. t1_c7a6yvf";
-- string::slice(string, from, length). Prefix `t1_` is 3 chars.
-- `name` sorts before `reddit_id`, so this VALUE is safe before SurrealDB 3.3.
DEFINE FIELD IF NOT EXISTS reddit_id ON comment TYPE string
    VALUE $value OR string::slice(name, 3, string::len(name) - 3)
    ASSERT $value = string::slice(name, 3, string::len(name) - 3)
    COMMENT "Short id without prefix, e.g. c7a6yvf. JSONL field `id` maps here.";

DEFINE FIELD IF NOT EXISTS link_id ON comment TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Parent submission fullname, e.g. t3_14622a";
DEFINE FIELD IF NOT EXISTS parent_id ON comment TYPE string
    ASSERT $value.starts_with('t1_') OR $value.starts_with('t3_')
    COMMENT "t3_* = top-level on the submission; t1_* = reply to a comment";

-- Record links are IDs, not foreign keys. Comments on deleted or missing
-- submissions are stored; RELATE is optional and must not use ENFORCED.
-- `link_id` sorts before `post`, so this VALUE is safe before SurrealDB 3.3.
-- `parent` is COMPUTED because that name sorts before `parent_id`; a VALUE
-- clause would store NONE on servers that still evaluate fields alphabetically.
DEFINE FIELD IF NOT EXISTS post ON comment TYPE option<record<post>>
    VALUE $value OR type::thing("post", link_id)
    COMMENT "post:⟨link_id⟩. May dangle when the submission is not in the posts file. Do not slice off t3_.";
DEFINE FIELD IF NOT EXISTS parent ON comment
    COMPUTED IF parent_id.starts_with('t1_') THEN
        type::thing("comment", parent_id)
    ELSE IF parent_id.starts_with('t3_') THEN
        type::thing("post", parent_id)
    ELSE
        NONE
    END
    COMMENT "comment:⟨t1_…⟩ or post:⟨t3_…⟩ from parent_id. Derived on read. Do not write it.";

DEFINE FIELD IF NOT EXISTS author ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author_fullname ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author_is_blocked ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS author_premium ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS is_submitter ON comment TYPE option<bool>;

-- Sparse copies of the parent submission. About 48k of 485k comments carry
-- them. Canonical submission fields stay on post.
DEFINE FIELD IF NOT EXISTS link_author ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS link_title ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS link_url ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS link_permalink ON comment TYPE option<string>;

DEFINE FIELD IF NOT EXISTS body ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS permalink ON comment TYPE option<string>;
-- Present on 14,309 / 485,169 rows, range 0–29. 0 is a top-level comment.
-- thread_member.depth counts the post as 0, so these two numbers differ by one.
DEFINE FIELD IF NOT EXISTS depth ON comment TYPE option<int>
    COMMENT "Sparse Reddit listing depth. Not thread_member.depth.";

DEFINE FIELD IF NOT EXISTS subreddit ON comment TYPE string DEFAULT 'Natalism';
DEFINE FIELD IF NOT EXISTS subreddit_id ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS subreddit_type ON comment TYPE option<string>;

DEFINE FIELD IF NOT EXISTS created_utc ON comment TYPE int;
DEFINE FIELD IF NOT EXISTS created_at ON comment
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD IF NOT EXISTS retrieved_on ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS edited ON comment TYPE bool | int
    COMMENT "false, or the unix second of the edit. Same shape as post.edited.";

DEFINE FIELD IF NOT EXISTS score ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS ups ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS downs ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS controversiality ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS score_hidden ON comment TYPE option<bool>;

DEFINE FIELD IF NOT EXISTS collapsed ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS collapsed_reason ON comment TYPE option<string>;
-- Live Reddit sends a bool. This archive has only NONE (478,358 null, 6,811 absent).
DEFINE FIELD IF NOT EXISTS collapsed_because_crowd_control ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS unrepliable_reason ON comment TYPE option<string>;

DEFINE FIELD IF NOT EXISTS stickied ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS locked ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS archived ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS distinguished ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS no_follow ON comment TYPE option<bool>;
DEFINE FIELD IF NOT EXISTS send_replies ON comment TYPE option<bool>;

DEFINE FIELD IF NOT EXISTS gilded ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS total_awards_received ON comment TYPE option<int>;
DEFINE FIELD IF NOT EXISTS associated_award ON comment TYPE option<object> FLEXIBLE
    COMMENT "Award object when present. NONE throughout the current comments file.";

DEFINE FIELD IF NOT EXISTS analysis_text ON comment
    COMPUTED body
    COMMENT "Comment body for embedding and classification";

DEFINE FIELD IF NOT EXISTS raw ON comment TYPE object FLEXIBLE
    COMMENT "Full JSONL object. Nested raw.id is fine; a top-level id is not.";

-- No subreddit index: every comment in the archive is r/Natalism.
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
-- 3. Thread reading order
--    One thread per submission. thread_member is the ordered link to each
--    document (the post at ordinal 0, then comments). Built once at ingest
--    so retrieve-thread does not rewalk replies_to. Do not store concatenated
--    thread text here. Skip threads whose submission is missing from post.
-- ---------------------------------------------------------------------------

DEFINE TABLE IF NOT EXISTS thread SCHEMAFULL
    COMMENT "One r/Natalism submission as a processing unit; id mirrors the t3_* fullname";

DEFINE FIELD IF NOT EXISTS post ON thread TYPE record<post>;
DEFINE FIELD IF NOT EXISTS reddit_name ON thread TYPE string
    ASSERT $value.starts_with('t3_')
    COMMENT "Submission fullname, e.g. t3_14622a. Record id is thread:⟨t3_14622a⟩.";
DEFINE FIELD IF NOT EXISTS created_utc ON thread TYPE int;
DEFINE FIELD IF NOT EXISTS created_at ON thread
    COMPUTED time::from_unix(created_utc);
DEFINE FIELD IF NOT EXISTS comment_count ON thread TYPE int
    COMMENT "Comments linked through thread_member, not Reddit's num_comments";

DEFINE INDEX IF NOT EXISTS uniq_thread_name ON thread FIELDS reddit_name UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_thread_created ON thread FIELDS created_utc;
DEFINE INDEX IF NOT EXISTS idx_thread_post ON thread FIELDS post;

-- Reading order from assemble_thread: depth-first, siblings oldest-first.
-- depth 0 is the post document. depth 1 is a reply to the post.
DEFINE TABLE IF NOT EXISTS thread_member SCHEMAFULL TYPE RELATION IN thread OUT document
    COMMENT "thread → document in reading order";

DEFINE FIELD IF NOT EXISTS ordinal ON thread_member TYPE int
    COMMENT "0 is the post; comments follow. Unique within a thread.";
DEFINE FIELD IF NOT EXISTS depth ON thread_member TYPE int
    COMMENT "0 = post, 1 = reply to the post, then +1 per replies_to hop";

DEFINE INDEX IF NOT EXISTS uniq_thread_member_ordinal ON thread_member FIELDS in, ordinal UNIQUE;
DEFINE INDEX IF NOT EXISTS uniq_thread_member_document ON thread_member FIELDS in, out UNIQUE;

-- ---------------------------------------------------------------------------
-- 4. Theme construction (codebook thematic analysis)
--    Applied to the stratified sample, not to the archive.
--    A topic cluster stays on document.topic_id. It is not written here.
--    The decoder may propose a code. It does not name a theme.
--    Quotes are copied from document.text and checked against that text.
-- ---------------------------------------------------------------------------

DEFINE TABLE IF NOT EXISTS code SCHEMAFULL
    COMMENT "One codebook entry. Inductive. Stabilized before it is applied to the rest of the sample.";

DEFINE FIELD IF NOT EXISTS label ON code TYPE string;
DEFINE FIELD IF NOT EXISTS definition ON code TYPE option<string>
    COMMENT "Required before status becomes active";
DEFINE FIELD IF NOT EXISTS status ON code TYPE string
    ASSERT $value IN ['provisional', 'active', 'merged', 'retired'];
DEFINE FIELD IF NOT EXISTS proposed_by ON code TYPE string
    ASSERT $value IN ['researcher', 'decoder']
    COMMENT "decoder is a suggestion. It stays provisional until decision is accepted";
DEFINE FIELD IF NOT EXISTS decision ON code TYPE string
    ASSERT $value IN ['pending', 'accepted', 'rejected'];
DEFINE FIELD IF NOT EXISTS supersedes ON code TYPE option<record<code>>
    COMMENT "Set on the surviving code when another code is merged or retired into it";

DEFINE INDEX IF NOT EXISTS uniq_code_label ON code FIELDS label UNIQUE;

-- One code applied to one thread. The thread is the unit.
-- document is the post or comment the quote was taken from.
DEFINE TABLE IF NOT EXISTS coded SCHEMAFULL TYPE RELATION IN code OUT thread
    COMMENT "code → thread in the qualitative sample";

DEFINE FIELD IF NOT EXISTS document ON coded TYPE option<record<document>>
    COMMENT "Source of the quote. Must be a member of the OUT thread";
DEFINE FIELD IF NOT EXISTS extract ON coded TYPE option<string>
    COMMENT "Quote copied from document.text. Not a paraphrase";
DEFINE FIELD IF NOT EXISTS applied_by ON coded TYPE string
    ASSERT $value IN ['researcher', 'decoder'];
DEFINE FIELD IF NOT EXISTS decision ON coded TYPE string
    ASSERT $value IN ['pending', 'accepted', 'rejected'];

DEFINE INDEX IF NOT EXISTS uniq_coded_span ON coded FIELDS in, out, document UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_coded_thread ON coded FIELDS out;
DEFINE INDEX IF NOT EXISTS idx_coded_decision ON coded FIELDS decision;

DEFINE TABLE IF NOT EXISTS theme SCHEMAFULL
    COMMENT "A patterned reading under construction. Named by the researcher, in language members use";

DEFINE FIELD IF NOT EXISTS working_name ON theme TYPE string;
DEFINE FIELD IF NOT EXISTS status ON theme TYPE string
    ASSERT $value IN ['candidate', 'thin', 'reviewed', 'named', 'split', 'merged', 'discarded']
    COMMENT "thin means retrieve more threads before the theme is settled. named requires final_name";
DEFINE FIELD IF NOT EXISTS definition ON theme TYPE option<string>;
DEFINE FIELD IF NOT EXISTS final_name ON theme TYPE option<string>
    COMMENT "Members' language. Not a topic label and not a decoder title";
DEFINE FIELD IF NOT EXISTS scope_includes ON theme TYPE option<string>;
DEFINE FIELD IF NOT EXISTS scope_excludes ON theme TYPE option<string>;
DEFINE FIELD IF NOT EXISTS supersedes ON theme TYPE option<record<theme>>;

DEFINE INDEX IF NOT EXISTS idx_theme_status ON theme FIELDS status;

-- The theme is built from codebook entries, then tested against whole threads.
DEFINE TABLE IF NOT EXISTS built_from SCHEMAFULL TYPE RELATION IN theme OUT code
    COMMENT "theme → code. A theme is a pattern across codes, not a cluster id";

DEFINE INDEX IF NOT EXISTS uniq_built_from ON built_from FIELDS in, out UNIQUE;

DEFINE TABLE IF NOT EXISTS reviewed_against SCHEMAFULL TYPE RELATION IN theme OUT thread
    COMMENT "theme → thread used as support, counter-evidence, boundary, or dissonance";

DEFINE FIELD IF NOT EXISTS role ON reviewed_against TYPE string
    ASSERT $value IN ['support', 'counter_evidence', 'boundary', 'dissonant']
    COMMENT "A theme is not named until a counter_evidence thread has been reviewed";

DEFINE INDEX IF NOT EXISTS uniq_reviewed_against ON reviewed_against FIELDS in, out, role UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_reviewed_role ON reviewed_against FIELDS role;

DEFINE TABLE IF NOT EXISTS memo SCHEMAFULL
    COMMENT "Interpretive journal kept beside coding and theme construction";

DEFINE FIELD IF NOT EXISTS phase ON memo TYPE string
    ASSERT $value IN ['familiarize', 'code', 'candidate_themes', 'review', 'name'];
DEFINE FIELD IF NOT EXISTS kind ON memo TYPE string
    ASSERT $value IN ['analytic', 'reflexivity', 'positionality', 'method'];
DEFINE FIELD IF NOT EXISTS body ON memo TYPE string;
DEFINE FIELD IF NOT EXISTS author ON memo TYPE string
    ASSERT $value IN ['researcher', 'decoder'];
DEFINE FIELD IF NOT EXISTS thread ON memo TYPE option<record<thread>>;
DEFINE FIELD IF NOT EXISTS code ON memo TYPE option<record<code>>;
DEFINE FIELD IF NOT EXISTS theme ON memo TYPE option<record<theme>>;

DEFINE INDEX IF NOT EXISTS idx_memo_phase ON memo FIELDS phase;
DEFINE INDEX IF NOT EXISTS idx_memo_theme ON memo FIELDS theme;

-- ---------------------------------------------------------------------------
-- 5. Ingest rules (Julia / HTTP POST /sql)
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
--   5. Do not write created_at, analysis_text, or comment.parent; they are COMPUTED
--   6. comment.post may be omitted. It is stored as post:⟨link_id⟩, the t3_ fullname.
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
--   author: "SammyD1st",
--   body: "Whoops...",
--   created_utc: 1354487261,
--   score: 1,
--   controversiality: 0,
--   raw: { ... }
-- };
-- parent is COMPUTED: parent_id t3_14622a → post:⟨t3_14622a⟩.
-- A nested reply with parent_id t1_nnouben → comment:⟨t1_nnouben⟩.
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
-- Thread record and reading-order edges. Include the post document at
-- ordinal 0, depth 0. Comment order matches assemble_thread.
-- CREATE thread:⟨t3_14622a⟩ CONTENT {
--   post: post:⟨t3_14622a⟩,
--   reddit_name: "t3_14622a",
--   created_utc: 1354485197,
--   comment_count: 1
-- };
-- RELATE thread:⟨t3_14622a⟩->thread_member->document:⟨t3_14622a⟩
--   CONTENT { ordinal: 0, depth: 0 };
-- RELATE thread:⟨t3_14622a⟩->thread_member->document:⟨t1_c7a76o4⟩
--   CONTENT { ordinal: 1, depth: 1 };
--
-- One query for sentiment, topics, embeddings, or the decoder:
-- SELECT ordinal, depth, out.unit_type, out.text, out.sentiment, out.topic_id
-- FROM thread_member
-- WHERE in = thread:⟨t3_14622a⟩
-- ORDER BY ordinal;
--
-- Reply-chain walk (parent link, not reading order):
-- SELECT *, ->in_thread->post AS submission,
--           ->replies_to AS parent
-- FROM comment:⟨t1_nnp1rjo⟩;
