-- Verlium schema for Oracle AI Database 26ai (Autonomous or Free).
-- Statements are separated by a line containing only "/".
-- migrate.py ignores "already exists" errors, so this file is re-runnable.
-- Every synced table carries: id (client-generated UUID), updated_at, change_seq, deleted.

CREATE SEQUENCE vl_change_seq START WITH 1 INCREMENT BY 1 NOCACHE ORDER
/

CREATE TABLE notebooks (
  id           VARCHAR2(36) PRIMARY KEY,
  title        VARCHAR2(500) DEFAULT 'Untitled notebook' NOT NULL,
  emoji        VARCHAR2(16),
  summary      CLOB,
  chat_config  JSON,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE TABLE sources (
  id           VARCHAR2(36) PRIMARY KEY,
  notebook_id  VARCHAR2(36) NOT NULL REFERENCES notebooks(id),
  kind         VARCHAR2(20) NOT NULL,          -- pdf | text | markdown | url | youtube | paste | audio | image
  title        VARCHAR2(1000),
  url          VARCHAR2(4000),
  blob_key     VARCHAR2(200),
  mime         VARCHAR2(200),
  size_bytes   NUMBER,
  sha256       VARCHAR2(64),
  status       VARCHAR2(20) DEFAULT 'queued' NOT NULL,  -- queued | processing | ready | error
  error        VARCHAR2(4000),
  content      CLOB,                            -- extracted plain text
  summary      CLOB,                            -- source guide
  key_topics   JSON,
  selected     NUMBER(1) DEFAULT 1 NOT NULL,
  embed_model  VARCHAR2(300),
  char_count   NUMBER,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE INDEX sources_nb_idx ON sources(notebook_id)
/

CREATE TABLE chunks (
  id           VARCHAR2(36) PRIMARY KEY,
  source_id    VARCHAR2(36) NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  notebook_id  VARCHAR2(36) NOT NULL,
  seq          NUMBER NOT NULL,
  text         CLOB NOT NULL,
  char_start   NUMBER NOT NULL,
  char_end     NUMBER NOT NULL,
  page         NUMBER,
  embed_model  VARCHAR2(300),
  embedding    VECTOR(*, FLOAT32)
)
/

CREATE INDEX chunks_src_idx ON chunks(source_id, seq)
/

CREATE INDEX chunks_nb_idx ON chunks(notebook_id)
/

CREATE INDEX chunks_text_idx ON chunks(text) INDEXTYPE IS CTXSYS.CONTEXT PARAMETERS ('SYNC (ON COMMIT)')
/

CREATE TABLE notes (
  id           VARCHAR2(36) PRIMARY KEY,
  notebook_id  VARCHAR2(36) NOT NULL REFERENCES notebooks(id),
  kind         VARCHAR2(30) DEFAULT 'note' NOT NULL,   -- note | saved_response | report | ...
  title        VARCHAR2(1000),
  content      CLOB,
  citations    JSON,
  version      NUMBER DEFAULT 1 NOT NULL,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE INDEX notes_nb_idx ON notes(notebook_id)
/

CREATE TABLE chat_messages (
  id           VARCHAR2(36) PRIMARY KEY,
  notebook_id  VARCHAR2(36) NOT NULL REFERENCES notebooks(id),
  role         VARCHAR2(20) NOT NULL,          -- user | assistant
  content      CLOB,
  citations    JSON,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE INDEX chat_nb_idx ON chat_messages(notebook_id, created_at)
/

CREATE TABLE providers (
  id           VARCHAR2(36) PRIMARY KEY,
  name         VARCHAR2(200) NOT NULL,
  base_url     VARCHAR2(1000) NOT NULL,
  adapter      VARCHAR2(40) DEFAULT 'openai' NOT NULL,
  api_key_enc  VARCHAR2(4000),
  headers      JSON,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE TABLE model_roles (
  role         VARCHAR2(30) PRIMARY KEY,       -- chat | vision | embeddings | tts | stt | image | video | realtime | rerank
  provider_id  VARCHAR2(36) REFERENCES providers(id),
  model_id     VARCHAR2(300),
  params       JSON,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER
)
/

CREATE TABLE jobs (
  id           VARCHAR2(36) PRIMARY KEY,
  kind         VARCHAR2(40) NOT NULL,          -- ingest | studio_* ...
  notebook_id  VARCHAR2(36),
  ref_id       VARCHAR2(36),
  status       VARCHAR2(20) DEFAULT 'queued' NOT NULL,  -- queued | running | done | error
  progress     NUMBER DEFAULT 0,
  attempts     NUMBER DEFAULT 0 NOT NULL,
  error        VARCHAR2(4000),
  payload      JSON,
  result       JSON,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
)
/

CREATE INDEX jobs_status_idx ON jobs(status, created_at)
/

CREATE OR REPLACE TRIGGER notebooks_seq BEFORE INSERT OR UPDATE ON notebooks FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER sources_seq BEFORE INSERT OR UPDATE ON sources FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER notes_seq BEFORE INSERT OR UPDATE ON notes FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER chat_seq BEFORE INSERT OR UPDATE ON chat_messages FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER providers_seq BEFORE INSERT OR UPDATE ON providers FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER model_roles_seq BEFORE INSERT OR UPDATE ON model_roles FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER jobs_upd BEFORE UPDATE ON jobs FOR EACH ROW
BEGIN :NEW.updated_at := SYSTIMESTAMP; END;
/

-- ---- v2: chat threads, thinking, memory, studio --------------------------------

CREATE TABLE chat_threads (
  id           VARCHAR2(36) PRIMARY KEY,
  notebook_id  VARCHAR2(36) NOT NULL REFERENCES notebooks(id),
  title        VARCHAR2(500) DEFAULT 'New chat' NOT NULL,
  summary      CLOB,                            -- recap used to personalise the next chat
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE INDEX threads_nb_idx ON chat_threads(notebook_id, updated_at)
/

ALTER TABLE chat_messages ADD (thread_id VARCHAR2(36), thinking CLOB, steps JSON)
/

CREATE INDEX chat_thread_idx ON chat_messages(thread_id, created_at)
/

CREATE TABLE memories (
  id           VARCHAR2(36) PRIMARY KEY,
  content      VARCHAR2(1000) NOT NULL,         -- one fact about the user's goals/preferences
  source_thread_id VARCHAR2(36),
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE TABLE app_settings (
  key          VARCHAR2(100) PRIMARY KEY,
  value        JSON,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER
)
/

CREATE TABLE studio_outputs (
  id           VARCHAR2(36) PRIMARY KEY,
  notebook_id  VARCHAR2(36) NOT NULL REFERENCES notebooks(id),
  type         VARCHAR2(30) NOT NULL,           -- audio | report | flashcards | quiz | mindmap | table | slides | video | infographic
  title        VARCHAR2(1000),
  status       VARCHAR2(20) DEFAULT 'queued' NOT NULL,  -- queued | running | ready | error
  progress     NUMBER DEFAULT 0,
  error        VARCHAR2(4000),
  prompt       CLOB,                            -- the user's focus prompt
  options      JSON,                            -- format, length, difficulty, ...
  source_ids   JSON,
  content      JSON,                            -- structured result (markdown, cards, questions, tree, table, transcript)
  blob_key     VARCHAR2(200),                   -- media file (mp3/mp4/png)
  mime         VARCHAR2(100),
  duration_s   NUMBER,
  unread       NUMBER(1) DEFAULT 1 NOT NULL,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  change_seq   NUMBER,
  deleted      NUMBER(1) DEFAULT 0 NOT NULL
)
/

CREATE INDEX studio_nb_idx ON studio_outputs(notebook_id, created_at)
/

CREATE OR REPLACE TRIGGER threads_seq BEFORE INSERT OR UPDATE ON chat_threads FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER memories_seq BEFORE INSERT OR UPDATE ON memories FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER app_settings_seq BEFORE INSERT OR UPDATE ON app_settings FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

CREATE OR REPLACE TRIGGER studio_seq BEFORE INSERT OR UPDATE ON studio_outputs FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/

-- ---- v3: chat attachments (images / video) ---------------------------------------------------
CREATE TABLE chat_attachments (
  id           VARCHAR2(36) PRIMARY KEY,
  notebook_id  VARCHAR2(36) NOT NULL REFERENCES notebooks(id),
  kind         VARCHAR2(10) NOT NULL,          -- image | video
  mime         VARCHAR2(100) NOT NULL,
  name         VARCHAR2(500),
  size_bytes   NUMBER,
  blob_key     VARCHAR2(80) NOT NULL,          -- original file
  model_key    VARCHAR2(80),                   -- downscaled JPEG sent to models (images)
  thumb_key    VARCHAR2(80),                   -- preview (image thumbnail / video poster)
  width        NUMBER,
  height       NUMBER,
  duration_s   NUMBER,
  description  CLOB,                           -- vision-model description, cached for follow-ups
  deleted      NUMBER(1) DEFAULT 0 NOT NULL,
  change_seq   NUMBER,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
)
/

ALTER TABLE chat_messages ADD (attachments JSON)
/

CREATE OR REPLACE TRIGGER attachments_seq BEFORE INSERT OR UPDATE ON chat_attachments FOR EACH ROW
BEGIN :NEW.change_seq := vl_change_seq.NEXTVAL; :NEW.updated_at := SYSTIMESTAMP; END;
/
