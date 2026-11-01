\restrict dbmate

-- Dumped from database version 16.13 (Homebrew)
-- Dumped by pg_dump version 16.13 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: snippets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.snippets (
    id text NOT NULL,
    user_id text NOT NULL,
    title text NOT NULL,
    tags text DEFAULT ''::text NOT NULL,
    markup text DEFAULT 'markdown'::text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    zku_id text NOT NULL,
    CONSTRAINT snippets_markup_check CHECK ((markup = ANY (ARRAY['markdown'::text, 'scripta'::text, 'plaintext'::text])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id text NOT NULL,
    email text NOT NULL,
    pw_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    username text NOT NULL
);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: snippets snippets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snippets
    ADD CONSTRAINT snippets_pkey PRIMARY KEY (id);


--
-- Name: snippets snippets_zku_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snippets
    ADD CONSTRAINT snippets_zku_id_key UNIQUE (zku_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: snippets_user_updated_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX snippets_user_updated_idx ON public.snippets USING btree (user_id, updated_at DESC);


--
-- Name: snippets snippets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snippets
    ADD CONSTRAINT snippets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('001'),
    ('002'),
    ('003');
