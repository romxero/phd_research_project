-- =============================================================================
-- PhD Research Project — PostgreSQL schema
-- r/Natalism corpus + computational pipeline + reflexive thematic analysis + RAG
--
-- Layers:
--   1. Raw Reddit ingest (posts, comments)
--   2. Analysis runs and document units (retrieval/RAG index grain)
--   3. Computational outputs (topics, sentiment, engagement strata, embeddings)
--   4. Thematic analysis (Braun & Clarke phases, codes, themes, extracts)
--   5. RAG (retrieve → rerank → grounded generation)
--   6. Triangulation (convergence / divergence across methods)
--
-- Optional: pgvector for in-database similarity search
--   CREATE EXTENSION IF NOT EXISTS vector;
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Raw Reddit ingest
-- ---------------------------------------------------------------------------

CREATE TABLE reddit_posts (
    name text PRIMARY KEY,              -- e.g. t3_1462qz
    id text NOT NULL UNIQUE,            -- e.g. 1462qz

    subreddit text NOT NULL,
    subreddit_id text,
    author text,
    author_fullname text,

    title text NOT NULL,
    selftext text,
    selftext_html text,
    url text,
    permalink text,
    domain text,

    created_utc bigint NOT NULL,
    retrieved_on bigint,
    retrieved_utc bigint,

    score integer,
    ups integer,
    downs integer,
    upvote_ratio numeric,
    num_comments integer,

    is_self boolean,
    over_18 boolean,
    spoiler boolean,
    stickied boolean,
    locked boolean,
    archived boolean,
    distinguished text,
    edited jsonb,

    media jsonb,
    media_embed jsonb,
    secure_media jsonb,
    secure_media_embed jsonb,
    all_awardings jsonb,
    mod_reports jsonb,
    user_reports jsonb,

    raw jsonb NOT NULL,

    CONSTRAINT reddit_posts_name_matches_id
        CHECK (name = 't3_' || id)
);

CREATE TABLE reddit_comments (
    name text PRIMARY KEY,              -- e.g. t1_c7a6yvf
    id text NOT NULL UNIQUE,            -- e.g. c7a6yvf

    link_id text NOT NULL REFERENCES reddit_posts(name),

    parent_id text NOT NULL,
    parent_comment_name text
        REFERENCES reddit_comments(name),

    subreddit text NOT NULL,
    subreddit_id text,
    author text,
    author_fullname text,

    body text,
    body_html text,
    permalink text,

    created_utc bigint NOT NULL,
    retrieved_on bigint,
    retrieved_utc bigint,

    score integer,
    ups integer,
    downs integer,
    controversiality integer,

    is_submitter boolean,
    stickied boolean,
    locked boolean,
    archived boolean,
    collapsed boolean,
    score_hidden boolean,
    distinguished text,
    edited jsonb,

    all_awardings jsonb,
    gildings jsonb,
    mod_reports jsonb,
    user_reports jsonb,
    report_reasons jsonb,

    raw jsonb NOT NULL,

    CONSTRAINT reddit_comments_name_matches_id
        CHECK (name = 't1_' || id),

    CONSTRAINT reddit_comments_parent_comment_consistency
        CHECK (
            (parent_id LIKE 't1_%' AND parent_comment_name = parent_id)
            OR
            (parent_id LIKE 't3_%' AND parent_comment_name IS NULL)
        )
);

CREATE INDEX reddit_comments_link_id_idx
    ON reddit_comments(link_id);

CREATE INDEX reddit_comments_parent_id_idx
    ON reddit_comments(parent_id);

CREATE INDEX reddit_comments_parent_comment_name_idx
    ON reddit_comments(parent_comment_name);

CREATE INDEX reddit_posts_subreddit_created_idx
    ON reddit_posts(subreddit, created_utc);

CREATE INDEX reddit_comments_subreddit_created_idx
    ON reddit_comments(subreddit, created_utc);

-- ---------------------------------------------------------------------------
-- 2. Analysis runs and document units
-- ---------------------------------------------------------------------------

-- One row per end-to-end pipeline execution (Julia topic pass, embedding pass, etc.).
CREATE TABLE analysis_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_label text NOT NULL UNIQUE,
    description text,

    encoder_model text NOT NULL DEFAULT 'ModernBERT',
    decoder_model text DEFAULT 'Gemma 4',
    pipeline_language text NOT NULL DEFAULT 'Julia',

    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    status text NOT NULL DEFAULT 'running'
        CHECK (status IN ('running', 'completed', 'failed', 'archived')),

    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    notes text
);

-- Unified analytic / retrieval grain. Every RAG hit and TA extract points here.
CREATE TABLE document_units (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    unit_kind text NOT NULL
        CHECK (unit_kind IN ('post', 'comment', 'thread_segment')),

    reddit_post_name text REFERENCES reddit_posts(name),
    reddit_comment_name text REFERENCES reddit_comments(name),
    thread_link_id text NOT NULL REFERENCES reddit_posts(name),

    chunk_index integer,
    char_start integer,
    char_end integer,

    canonical_text text NOT NULL,
    token_count integer,

    created_utc bigint NOT NULL,
    score integer,

    source_permalink text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT document_units_source_consistency
        CHECK (
            (unit_kind = 'post' AND reddit_post_name IS NOT NULL AND reddit_comment_name IS NULL)
            OR
            (unit_kind = 'comment' AND reddit_comment_name IS NOT NULL)
            OR
            (unit_kind = 'thread_segment'
                AND thread_link_id IS NOT NULL
                AND char_start IS NOT NULL
                AND char_end IS NOT NULL)
        ),

    CONSTRAINT document_units_chunk_bounds
        CHECK (
            chunk_index IS NULL
            OR (char_start IS NOT NULL AND char_end IS NOT NULL AND char_end > char_start)
        )
);

CREATE UNIQUE INDEX document_units_post_unique_idx
    ON document_units(analysis_run_id, reddit_post_name)
    WHERE unit_kind = 'post';

CREATE UNIQUE INDEX document_units_comment_unique_idx
    ON document_units(analysis_run_id, reddit_comment_name)
    WHERE unit_kind = 'comment';

CREATE UNIQUE INDEX document_units_thread_chunk_unique_idx
    ON document_units(analysis_run_id, thread_link_id, chunk_index)
    WHERE unit_kind = 'thread_segment';

CREATE INDEX document_units_run_thread_idx
    ON document_units(analysis_run_id, thread_link_id);

CREATE INDEX document_units_run_created_idx
    ON document_units(analysis_run_id, created_utc);

CREATE INDEX document_units_run_score_idx
    ON document_units(analysis_run_id, score);

-- ---------------------------------------------------------------------------
-- 3. Computational outputs (encoder / Julia pipeline)
-- ---------------------------------------------------------------------------

CREATE TABLE topic_model_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL UNIQUE REFERENCES analysis_runs(id) ON DELETE CASCADE,

    algorithm text NOT NULL DEFAULT 'custom_julia_embedding_cluster',
    embedding_model text NOT NULL DEFAULT 'ModernBERT',
    reduction_method text DEFAULT 'UMAP',
    clustering_method text DEFAULT 'HDBSCAN',

    num_topics integer,
    hyperparameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    completed_at timestamptz
);

CREATE TABLE topic_clusters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_model_run_id uuid NOT NULL REFERENCES topic_model_runs(id) ON DELETE CASCADE,

    cluster_label integer NOT NULL,
    cluster_slug text,
    top_terms text[] NOT NULL DEFAULT '{}',
    representative_unit_id uuid REFERENCES document_units(id),

    document_count integer NOT NULL DEFAULT 0,
    summary_text text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    UNIQUE (topic_model_run_id, cluster_label)
);

CREATE TABLE document_topic_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_cluster_id uuid NOT NULL REFERENCES topic_clusters(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    probability numeric,
    is_primary boolean NOT NULL DEFAULT true,

    UNIQUE (topic_cluster_id, document_unit_id)
);

CREATE INDEX document_topic_assignments_unit_idx
    ON document_topic_assignments(document_unit_id);

CREATE TABLE sentiment_scores (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    model_name text NOT NULL DEFAULT 'ModernBERT',
    label text NOT NULL
        CHECK (label IN ('positive', 'negative', 'neutral', 'mixed', 'unknown')),
    confidence numeric,

    probabilities jsonb,
    scored_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (analysis_run_id, document_unit_id, model_name)
);

CREATE INDEX sentiment_scores_run_label_idx
    ON sentiment_scores(analysis_run_id, label);

-- Engagement bins for selective-exposure comparisons (e.g. top/bottom decile).
CREATE TABLE engagement_strata (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    stratum_scheme text NOT NULL,       -- e.g. 'score_decile_by_year'
    stratum_label text NOT NULL,        -- e.g. 'top_decile', 'bottom_decile'
    stratum_rank integer,
    window_start_utc bigint,
    window_end_utc bigint,

    UNIQUE (analysis_run_id, document_unit_id, stratum_scheme)
);

CREATE INDEX engagement_strata_run_label_idx
    ON engagement_strata(analysis_run_id, stratum_label);

-- Embedding store metadata. Store vectors in pgvector, object storage, or an external index.
CREATE TABLE embedding_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    model_name text NOT NULL DEFAULT 'ModernBERT',
    model_version text,
    dimensions integer NOT NULL,

    storage_backend text NOT NULL DEFAULT 'external'
        CHECK (storage_backend IN ('pgvector', 'external', 'file')),
    storage_uri text,
    -- Uncomment when pgvector is enabled:
    -- embedding vector(768),

    indexed_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (analysis_run_id, document_unit_id, model_name)
);

CREATE INDEX embedding_records_run_model_idx
    ON embedding_records(analysis_run_id, model_name);

-- ---------------------------------------------------------------------------
-- 4. Reflexive thematic analysis (Braun & Clarke phases)
-- ---------------------------------------------------------------------------

-- Phases: 1 familiarize, 2 code, 3 initial_themes, 4 review, 5 define, 6 writeup
CREATE TABLE ta_phases (
    code text PRIMARY KEY,
    phase_number integer NOT NULL UNIQUE,
    name text NOT NULL,
    description text
);

INSERT INTO ta_phases (code, phase_number, name, description) VALUES
    ('familiarize', 1, 'Familiarization',
        'Repeated reading, immersion, initial analytic notes'),
    ('code', 2, 'Coding',
        'Provisional codes, systematic annotation, collation'),
    ('initial_themes', 3, 'Initial themes',
        'Candidate themes, thematic collation, viability review'),
    ('review', 4, 'Theme review',
        'Theme-data fit, counter-evidence, split/combine/discard'),
    ('define', 5, 'Define and name',
        'Definitions, scope, informative names, theme stories'),
    ('writeup', 6, 'Write-up',
        'Analytic narrative, evidence extracts, synthesis')
ON CONFLICT (code) DO NOTHING;

-- Tracks recursion: which phase a unit/theme returned to and why.
CREATE TABLE ta_workflow_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    from_phase text NOT NULL REFERENCES ta_phases(code),
    to_phase text NOT NULL REFERENCES ta_phases(code),

    trigger_reason text NOT NULL,
    related_entity_type text
        CHECK (related_entity_type IN ('document_unit', 'code', 'candidate_theme', 'theme_definition', 'rag_query')),
    related_entity_id uuid,

    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ta_memos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    phase_code text NOT NULL REFERENCES ta_phases(code),
    memo_kind text NOT NULL DEFAULT 'analytic'
        CHECK (memo_kind IN ('analytic', 'reflexivity', 'positionality', 'method')),

    title text,
    body text NOT NULL,

    document_unit_id uuid REFERENCES document_units(id),
    topic_cluster_id uuid REFERENCES topic_clusters(id),

    author text NOT NULL DEFAULT 'researcher',
    model_assist text,                  -- e.g. 'Gemma 4' when draft-assisted
    rag_session_id uuid,                -- FK added after rag_generation_sessions

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ta_memos_run_phase_idx
    ON ta_memos(analysis_run_id, phase_code);

-- semantic = explicit content; latent = underpinning assumptions / patterns
CREATE TABLE ta_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    code_label text NOT NULL,
    code_kind text NOT NULL DEFAULT 'semantic'
        CHECK (code_kind IN ('semantic', 'latent', 'deductive', 'inductive')),
    description text,

    status text NOT NULL DEFAULT 'provisional'
        CHECK (status IN ('provisional', 'active', 'merged', 'retired')),
    version integer NOT NULL DEFAULT 1,
    supersedes_code_id uuid REFERENCES ta_codes(id),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (analysis_run_id, code_label, version)
);

CREATE TABLE ta_code_applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code_id uuid NOT NULL REFERENCES ta_codes(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    phase_code text NOT NULL REFERENCES ta_phases(code),
    applied_by text NOT NULL DEFAULT 'researcher'
        CHECK (applied_by IN ('researcher', 'model_suggested', 'rag_assisted')),

    confidence numeric,
    reviewer_status text NOT NULL DEFAULT 'pending'
        CHECK (reviewer_status IN ('pending', 'accepted', 'rejected', 'revised')),

    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE (code_id, document_unit_id, phase_code)
);

CREATE INDEX ta_code_applications_unit_idx
    ON ta_code_applications(document_unit_id);

-- Data extracts: short vivid segments kept as evidence alongside codes/themes.
CREATE TABLE ta_data_extracts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    extract_text text NOT NULL,
    char_start integer,
    char_end integer,

    extract_role text NOT NULL DEFAULT 'illustrative'
        CHECK (extract_role IN (
            'illustrative', 'representative', 'deviant',
            'counter_evidence', 'boundary', 'writeup_quote'
        )),

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ta_code_extract_links (
    code_id uuid NOT NULL REFERENCES ta_codes(id) ON DELETE CASCADE,
    extract_id uuid NOT NULL REFERENCES ta_data_extracts(id) ON DELETE CASCADE,
    PRIMARY KEY (code_id, extract_id)
);

CREATE TABLE ta_candidate_themes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    working_name text NOT NULL,
    organizing_concept text,
    viability_status text NOT NULL DEFAULT 'candidate'
        CHECK (viability_status IN ('candidate', 'viable', 'thin', 'split', 'merged', 'discarded')),

    phase_code text NOT NULL DEFAULT 'initial_themes' REFERENCES ta_phases(code),
    narrative_draft text,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ta_theme_code_links (
    candidate_theme_id uuid NOT NULL REFERENCES ta_candidate_themes(id) ON DELETE CASCADE,
    code_id uuid NOT NULL REFERENCES ta_codes(id) ON DELETE CASCADE,
    PRIMARY KEY (candidate_theme_id, code_id)
);

CREATE TABLE ta_theme_extract_links (
    candidate_theme_id uuid NOT NULL REFERENCES ta_candidate_themes(id) ON DELETE CASCADE,
    extract_id uuid NOT NULL REFERENCES ta_data_extracts(id) ON DELETE CASCADE,
    centrality_score numeric,
    PRIMARY KEY (candidate_theme_id, extract_id)
);

-- Phase 4: theme-data fit and counter-evidence review.
CREATE TABLE ta_theme_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_theme_id uuid NOT NULL REFERENCES ta_candidate_themes(id) ON DELETE CASCADE,

    review_kind text NOT NULL
        CHECK (review_kind IN ('fit_check', 'counter_evidence', 'split', 'merge', 'discard', 'narrative_test')),
    outcome text NOT NULL
        CHECK (outcome IN ('hold', 'revise', 'split', 'merge', 'discard')),

    supporting_extract_count integer DEFAULT 0,
    dissonant_extract_count integer DEFAULT 0,
    review_notes text,

    rag_query_id uuid,                  -- FK added below after rag_queries
    reviewed_at timestamptz NOT NULL DEFAULT now()
);

-- Phase 5: refined definitions and informative names.
CREATE TABLE ta_theme_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_theme_id uuid NOT NULL UNIQUE REFERENCES ta_candidate_themes(id) ON DELETE CASCADE,

    final_name text NOT NULL,
    definition text NOT NULL,
    scope_includes text,
    scope_excludes text,
    theme_story text,

    version integer NOT NULL DEFAULT 1,
    finalized_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Phase 6: write-up sections tied to themes and pinned extracts.
CREATE TABLE ta_analytic_sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,
    candidate_theme_id uuid REFERENCES ta_candidate_themes(id),

    section_title text NOT NULL,
    draft_text text,
    phase_code text NOT NULL DEFAULT 'writeup' REFERENCES ta_phases(code),

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ta_section_extract_links (
    section_id uuid NOT NULL REFERENCES ta_analytic_sections(id) ON DELETE CASCADE,
    extract_id uuid NOT NULL REFERENCES ta_data_extracts(id) ON DELETE CASCADE,
    citation_order integer,
    PRIMARY KEY (section_id, extract_id)
);

-- ---------------------------------------------------------------------------
-- 5. RAG: retrieve → rerank → grounded generation
-- ---------------------------------------------------------------------------

-- Reusable query templates keyed to TA phase and selective-exposure contrasts.
CREATE TABLE rag_query_profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_key text NOT NULL UNIQUE,
    phase_code text NOT NULL REFERENCES ta_phases(code),

    description text NOT NULL,
    contrast_mode text NOT NULL DEFAULT 'none'
        CHECK (contrast_mode IN (
            'none',
            'high_vs_low_engagement',
            'same_topic_diff_engagement',
            'counter_evidence',
            'cross_time',
            'semantic_vs_latent'
        )),

    retrieval_k integer NOT NULL DEFAULT 40,
    rerank_n integer NOT NULL DEFAULT 8,

    filter_topic_cluster_id uuid REFERENCES topic_clusters(id),
    filter_sentiment_label text
        CHECK (filter_sentiment_label IS NULL OR filter_sentiment_label IN (
            'positive', 'negative', 'neutral', 'mixed', 'unknown'
        )),
    filter_engagement_stratum text,
    filter_time_start_utc bigint,
    filter_time_end_utc bigint,

    prompt_template text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

INSERT INTO rag_query_profiles (profile_key, phase_code, description, contrast_mode, retrieval_k, rerank_n) VALUES
    ('familiarize_cross_corpus', 'familiarize',
        'Surface similar discourse across threads for immersion', 'cross_time', 50, 10),
    ('code_collation', 'code',
        'Retrieve similar units and existing code applications for consistency', 'none', 40, 8),
    ('code_contrast_engagement', 'code',
        'Contrast high- and low-engagement units within the same topic', 'same_topic_diff_engagement', 40, 8),
    ('theme_collation', 'initial_themes',
        'Collate extracts across member codes for a candidate theme', 'none', 60, 12),
    ('theme_counter_evidence', 'review',
        'Retrieve dissonant or low-engagement evidence to stress-test a theme', 'counter_evidence', 40, 8),
    ('theme_boundary_cases', 'define',
        'Retrieve borderline units between related themes', 'none', 30, 6),
    ('writeup_evidence', 'writeup',
        'Rerank extracts for vividness and fit to analytic prose', 'none', 30, 5)
ON CONFLICT (profile_key) DO NOTHING;

-- One executed retrieval request (seed unit, ad hoc filters, or profile).
CREATE TABLE rag_queries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    profile_id uuid REFERENCES rag_query_profiles(id),
    phase_code text NOT NULL REFERENCES ta_phases(code),

    query_text text,
    seed_document_unit_id uuid REFERENCES document_units(id),

    filter_topic_cluster_id uuid REFERENCES topic_clusters(id),
    filter_sentiment_label text,
    filter_engagement_stratum text,
    filter_time_start_utc bigint,
    filter_time_end_utc bigint,

    retrieval_k integer NOT NULL DEFAULT 40,
    rerank_n integer,

    encoder_model text NOT NULL DEFAULT 'ModernBERT',
    status text NOT NULL DEFAULT 'completed'
        CHECK (status IN ('pending', 'completed', 'failed')),

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX rag_queries_run_phase_idx
    ON rag_queries(analysis_run_id, phase_code);

-- Bi-encoder / dense retrieval candidates.
CREATE TABLE rag_retrieval_hits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rag_query_id uuid NOT NULL REFERENCES rag_queries(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    retrieval_rank integer NOT NULL,
    retrieval_score numeric NOT NULL,

    topic_cluster_id uuid REFERENCES topic_clusters(id),
    sentiment_label text,
    engagement_stratum text,

    UNIQUE (rag_query_id, document_unit_id)
);

CREATE INDEX rag_retrieval_hits_query_rank_idx
    ON rag_retrieval_hits(rag_query_id, retrieval_rank);

-- Cross-encoder reranking over retrieval candidates.
CREATE TABLE rag_rerank_hits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rag_query_id uuid NOT NULL REFERENCES rag_queries(id) ON DELETE CASCADE,
    retrieval_hit_id uuid NOT NULL UNIQUE REFERENCES rag_retrieval_hits(id) ON DELETE CASCADE,
    document_unit_id uuid NOT NULL REFERENCES document_units(id) ON DELETE CASCADE,

    rerank_rank integer NOT NULL,
    rerank_score numeric NOT NULL,
    reranker_model text NOT NULL DEFAULT 'ModernBERT',

    selected_for_reading boolean NOT NULL DEFAULT false,
    selected_for_writeup boolean NOT NULL DEFAULT false
);

CREATE INDEX rag_rerank_hits_query_rank_idx
    ON rag_rerank_hits(rag_query_id, rerank_rank);

-- Gemma 4 (or other decoder) sessions grounded in reranked context.
CREATE TABLE rag_generation_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rag_query_id uuid NOT NULL REFERENCES rag_queries(id) ON DELETE CASCADE,

    decoder_model text NOT NULL DEFAULT 'Gemma 4',
    generation_kind text NOT NULL
        CHECK (generation_kind IN (
            'memo', 'code_suggestion', 'theme_narrative',
            'irony_flag', 'definition_draft', 'section_draft', 'other'
        )),

    system_prompt text,
    user_prompt text NOT NULL,
    grounded_context jsonb NOT NULL DEFAULT '[]'::jsonb,
    model_output text,

    human_accepted boolean,
    human_edited_output text,

    created_at timestamptz NOT NULL DEFAULT now()
);

-- Back-reference memos and theme reviews to RAG sessions.
ALTER TABLE ta_memos
    ADD CONSTRAINT ta_memos_rag_session_fk
    FOREIGN KEY (rag_session_id) REFERENCES rag_generation_sessions(id);

ALTER TABLE ta_theme_reviews
    ADD CONSTRAINT ta_theme_reviews_rag_query_fk
    FOREIGN KEY (rag_query_id) REFERENCES rag_queries(id);

-- ---------------------------------------------------------------------------
-- 6. Triangulation across computational and qualitative evidence
-- ---------------------------------------------------------------------------

CREATE TABLE triangulation_observations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id) ON DELETE CASCADE,

    claim_summary text NOT NULL,
    evidence_kind text NOT NULL
        CHECK (evidence_kind IN (
            'topic_cluster', 'sentiment', 'engagement',
            'qual_theme', 'rag_retrieval', 'mixed'
        )),

    topic_cluster_id uuid REFERENCES topic_clusters(id),
    candidate_theme_id uuid REFERENCES ta_candidate_themes(id),
    document_unit_id uuid REFERENCES document_units(id),

    convergence_status text NOT NULL
        CHECK (convergence_status IN ('converges', 'diverges', 'qualifies', 'unresolved')),

    computational_summary text,
    qualitative_summary text,
    notes text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX triangulation_observations_run_status_idx
    ON triangulation_observations(analysis_run_id, convergence_status);

-- ---------------------------------------------------------------------------
-- 7. Views for RAG-facing metadata filters
-- ---------------------------------------------------------------------------

CREATE VIEW v_document_unit_analysis AS
SELECT
    du.id AS document_unit_id,
    du.analysis_run_id,
    du.unit_kind,
    du.thread_link_id,
    du.canonical_text,
    du.created_utc,
    du.score,
    tc.id AS topic_cluster_id,
    tc.cluster_label,
    tc.cluster_slug,
    dta.probability AS topic_probability,
    ss.label AS sentiment_label,
    ss.confidence AS sentiment_confidence,
    es.stratum_label AS engagement_stratum,
    es.stratum_scheme AS engagement_scheme
FROM document_units du
LEFT JOIN document_topic_assignments dta
    ON dta.document_unit_id = du.id AND dta.is_primary = true
LEFT JOIN topic_clusters tc
    ON tc.id = dta.topic_cluster_id
LEFT JOIN sentiment_scores ss
    ON ss.document_unit_id = du.id AND ss.analysis_run_id = du.analysis_run_id
LEFT JOIN engagement_strata es
    ON es.document_unit_id = du.id AND es.analysis_run_id = du.analysis_run_id;

COMMENT ON VIEW v_document_unit_analysis IS
    'Primary RAG filter surface: topic, sentiment, engagement, and text metadata per document unit.';

CREATE VIEW v_rag_grounded_extracts AS
SELECT
    rq.id AS rag_query_id,
    rq.phase_code,
    rq.analysis_run_id,
    rr.rerank_rank,
    rr.rerank_score,
    rr.selected_for_reading,
    rr.selected_for_writeup,
    du.id AS document_unit_id,
    du.canonical_text,
    du.score,
    du.created_utc,
    v.topic_cluster_id,
    v.sentiment_label,
    v.engagement_stratum
FROM rag_queries rq
JOIN rag_rerank_hits rr ON rr.rag_query_id = rq.id
JOIN document_units du ON du.id = rr.document_unit_id
LEFT JOIN v_document_unit_analysis v
    ON v.document_unit_id = du.id AND v.analysis_run_id = rq.analysis_run_id
ORDER BY rq.id, rr.rerank_rank;

COMMENT ON VIEW v_rag_grounded_extracts IS
    'Reranked extracts ready for close reading, TA collation, or Gemma 4 grounding.';

CREATE VIEW v_ta_theme_collations AS
SELECT
    ct.id AS candidate_theme_id,
    ct.analysis_run_id,
    ct.working_name,
    ct.organizing_concept,
    ct.viability_status,
    c.id AS code_id,
    c.code_label,
    c.code_kind,
    e.id AS extract_id,
    e.extract_text,
    e.extract_role,
    tel.centrality_score
FROM ta_candidate_themes ct
LEFT JOIN ta_theme_code_links tcl ON tcl.candidate_theme_id = ct.id
LEFT JOIN ta_codes c ON c.id = tcl.code_id
LEFT JOIN ta_theme_extract_links tel ON tel.candidate_theme_id = ct.id
LEFT JOIN ta_data_extracts e ON e.id = tel.extract_id;

COMMENT ON VIEW v_ta_theme_collations IS
    'Candidate themes with member codes and collated extracts for phase 3–5 review.';
