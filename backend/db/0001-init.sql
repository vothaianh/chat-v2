-- Enables the uuid extension (spec requirement: postgres with uuid extension).
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- TypeORM manages entity schema (synchronize=true in dev). These tables are
-- provided as the canonical schema for reference / production migrations.
-- uuid_generate_v4() is available for manual use.

CREATE TABLE IF NOT EXISTS "user" (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username        VARCHAR(64)  NOT NULL UNIQUE,
  full_name       VARCHAR(128) NOT NULL,
  email           VARCHAR(255) NOT NULL UNIQUE,
  password_hash   VARCHAR(255) NOT NULL,
  avatar_url      VARCHAR(255),
  last_seen_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS device_token (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  token        VARCHAR(512) NOT NULL,
  platform     VARCHAR(16),                      -- ios | android | web
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

CREATE TABLE IF NOT EXISTS conversation (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type         VARCHAR(16) NOT NULL,             -- private | group
  title        VARCHAR(128),
  avatar_url   VARCHAR(255),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS conversation_member (
  conversation_id UUID NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  role            VARCHAR(16) NOT NULL DEFAULT 'member', -- owner | admin | member
  last_read_at    TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_member_user ON conversation_member(user_id);