--
-- PostgreSQL database dump
--

-- Dumped from database version 16.3
-- Dumped by pg_dump version 16.3

-- Started on 2024-12-19 23:50:24

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

--
-- TOC entry 234 (class 1255 OID 64507)
-- Name: trigger_update_submission_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_update_submission_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Call the procedure to update submission status
    CALL updateSubmissionStatus(NEW.submission_id);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trigger_update_submission_status() OWNER TO postgres;

--
-- TOC entry 235 (class 1255 OID 64508)
-- Name: update_evaluation_score(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_evaluation_score() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_correct_points NUMERIC;
BEGIN
	SELECT SUM(tc.test_point * l.rate) INTO total_correct_points
	FROM SubmissionLine sl
	JOIN test_case tc ON sl.test_id = tc.test_id
	JOIN submission s ON sl.submission_id = s.submission_id
	JOIN question q ON s.question_id = q.question_id
	JOIN level l ON q.level_id = l.level_id
	WHERE sl.submission_id = NEW.submission_id
	AND sl.is_accepted = TRUE;


    IF total_correct_points IS NULL THEN
        total_correct_points := 0;
    END IF;

    -- Update the evaluation_point in the Submission table
    UPDATE Submission
    SET evaluation_point = total_correct_points
    WHERE submission_id = NEW.submission_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_evaluation_score() OWNER TO postgres;

--
-- TOC entry 236 (class 1255 OID 64509)
-- Name: update_participant_points(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_participant_points() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update the participants table for the affected student and contest
    UPDATE participants
    SET point = (
        SELECT SUM(max_points) FROM (
            SELECT MAX(evaluation_point) AS max_points
            FROM submission
            WHERE student_id = NEW.student_id
              AND contest_id = NEW.contest_id
            GROUP BY question_id
        ) AS subquery
    )
    WHERE student_id = NEW.student_id
      AND contest_id = NEW.contest_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_participant_points() OWNER TO postgres;

--
-- TOC entry 237 (class 1255 OID 64721)
-- Name: update_participant_question_points(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_participant_question_points() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update the point in participant_question table
    UPDATE participant_question
    SET point = GREATEST(
        point,
        (SELECT MAX(evaluation_point)
         FROM submission
         WHERE student_id = NEW.student_id
           AND contest_id = NEW.contest_id
           AND question_id = NEW.question_id)
    )
    WHERE student_id = NEW.student_id
      AND contest_id = NEW.contest_id
      AND question_id = NEW.question_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_participant_question_points() OWNER TO postgres;

--
-- TOC entry 250 (class 1255 OID 64723)
-- Name: update_participant_question_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_participant_question_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if the record already exists in participant_question
    IF EXISTS (
        SELECT 1
        FROM participant_question
        WHERE student_id = NEW.student_id
          AND contest_id = NEW.contest_id
          AND question_id = NEW.question_id
    ) THEN
        -- Record exists, update it
        IF NEW.status = 'Accepted' THEN
            UPDATE participant_question
            SET is_accepted = TRUE
            WHERE student_id = NEW.student_id
              AND contest_id = NEW.contest_id
              AND question_id = NEW.question_id;
        END IF;
    ELSE
        -- Record does not exist, insert a new row
        INSERT INTO participant_question (student_id, contest_id, question_id, point, is_accepted)
        VALUES (
            NEW.student_id,
            NEW.contest_id,
            NEW.question_id,
            CASE WHEN NEW.status = 'Accepted' THEN TRUE ELSE FALSE END
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_participant_question_trigger() OWNER TO postgres;

--
-- TOC entry 249 (class 1255 OID 64510)
-- Name: updatesubmissionstatus(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.updatesubmissionstatus(IN a_submission_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    count_passed INT;
    total_test_cases INT;
    a_question_id INT;
BEGIN
    -- Get the question_id associated with this submission
    SELECT question_id INTO a_question_id
    FROM Submission
    WHERE submission_id = a_submission_id;

    -- Count the number of passed test cases for the given submission
    SELECT COUNT(sl.submissionline_id)
    INTO count_passed
    FROM SubmissionLine sl
    JOIN Submission s USING (submission_id)
    WHERE sl.submission_id = a_submission_id AND sl.is_accepted = TRUE;

    -- Count the total number of test cases for the given question
    SELECT COUNT(*)
    INTO total_test_cases
    FROM test_case
    WHERE question_id = a_question_id;

    -- Update the status_id based on the counts
    IF count_passed = total_test_cases THEN
        -- All test cases passed
        UPDATE Submission
        SET status = 'Accepted'
        WHERE submission_id = a_submission_id;
    ELSIF count_passed > 0 THEN
        -- Some test cases passed
        UPDATE Submission
        SET status = 'Partial'
        WHERE submission_id = a_submission_id;
    ELSE
        -- No test cases passed
        UPDATE Submission
        SET status = 'Failed'
        WHERE submission_id = a_submission_id;
    END IF;
END;
$$;


ALTER PROCEDURE public.updatesubmissionstatus(IN a_submission_id integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 215 (class 1259 OID 64511)
-- Name: contest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contest (
    contest_id integer NOT NULL,
    name character varying(50),
    prof_id integer NOT NULL,
    created_at date DEFAULT CURRENT_DATE NOT NULL
);


ALTER TABLE public.contest OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 64515)
-- Name: contest_contest_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.contest_contest_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contest_contest_id_seq OWNER TO postgres;

--
-- TOC entry 4966 (class 0 OID 0)
-- Dependencies: 216
-- Name: contest_contest_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.contest_contest_id_seq OWNED BY public.contest.contest_id;


--
-- TOC entry 217 (class 1259 OID 64516)
-- Name: level; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.level (
    level_id integer NOT NULL,
    name character varying(10) NOT NULL,
    rate numeric
);


ALTER TABLE public.level OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 64521)
-- Name: level_level_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.level_level_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.level_level_id_seq OWNER TO postgres;

--
-- TOC entry 4967 (class 0 OID 0)
-- Dependencies: 218
-- Name: level_level_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.level_level_id_seq OWNED BY public.level.level_id;


--
-- TOC entry 233 (class 1259 OID 64687)
-- Name: participant_question; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.participant_question (
    student_id integer NOT NULL,
    contest_id integer NOT NULL,
    question_id integer NOT NULL,
    point numeric DEFAULT 0 NOT NULL,
    is_accepted boolean DEFAULT false NOT NULL
);


ALTER TABLE public.participant_question OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 64522)
-- Name: participants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.participants (
    student_id integer NOT NULL,
    contest_id integer NOT NULL,
    point integer DEFAULT 0 NOT NULL,
    participant character varying(20) DEFAULT 'Waiting'::character varying NOT NULL
);


ALTER TABLE public.participants OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 64527)
-- Name: professor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.professor (
    prof_id integer NOT NULL,
    first_name character varying(10) NOT NULL,
    last_name character varying(50) NOT NULL,
    username character varying(50) NOT NULL,
    password character varying(50) NOT NULL,
    created_at date DEFAULT CURRENT_DATE NOT NULL
);


ALTER TABLE public.professor OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 64531)
-- Name: professor_prof_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.professor_prof_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.professor_prof_id_seq OWNER TO postgres;

--
-- TOC entry 4968 (class 0 OID 0)
-- Dependencies: 221
-- Name: professor_prof_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.professor_prof_id_seq OWNED BY public.professor.prof_id;


--
-- TOC entry 222 (class 1259 OID 64532)
-- Name: question; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.question (
    question_id integer NOT NULL,
    title character varying(50) NOT NULL,
    description text,
    level_id integer NOT NULL,
    prof_id integer NOT NULL
);


ALTER TABLE public.question OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 64537)
-- Name: question_contest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.question_contest (
    question_id integer NOT NULL,
    contest_id integer NOT NULL,
    created_at date DEFAULT CURRENT_DATE NOT NULL
);


ALTER TABLE public.question_contest OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 64541)
-- Name: question_question_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.question_question_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.question_question_id_seq OWNER TO postgres;

--
-- TOC entry 4969 (class 0 OID 0)
-- Dependencies: 224
-- Name: question_question_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.question_question_id_seq OWNED BY public.question.question_id;


--
-- TOC entry 225 (class 1259 OID 64542)
-- Name: student; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student (
    student_id integer NOT NULL,
    first_name character varying(10) NOT NULL,
    last_name character varying(10) NOT NULL,
    username character varying(50) NOT NULL,
    password character varying(100) NOT NULL,
    created_at date DEFAULT CURRENT_DATE NOT NULL
);


ALTER TABLE public.student OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 64546)
-- Name: student_studentid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_studentid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_studentid_seq OWNER TO postgres;

--
-- TOC entry 4970 (class 0 OID 0)
-- Dependencies: 226
-- Name: student_studentid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_studentid_seq OWNED BY public.student.student_id;


--
-- TOC entry 227 (class 1259 OID 64547)
-- Name: submission; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.submission (
    submission_id integer NOT NULL,
    student_id integer NOT NULL,
    question_id integer NOT NULL,
    contest_id integer NOT NULL,
    created_at date DEFAULT CURRENT_DATE NOT NULL,
    evaluation_point numeric DEFAULT 0 NOT NULL,
    status character varying(30)
);


ALTER TABLE public.submission OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 64554)
-- Name: submission_submission_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.submission_submission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.submission_submission_id_seq OWNER TO postgres;

--
-- TOC entry 4971 (class 0 OID 0)
-- Dependencies: 228
-- Name: submission_submission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.submission_submission_id_seq OWNED BY public.submission.submission_id;


--
-- TOC entry 229 (class 1259 OID 64555)
-- Name: submissionline; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.submissionline (
    submissionline_id integer NOT NULL,
    submission_id integer,
    test_id integer NOT NULL,
    is_accepted boolean
);


ALTER TABLE public.submissionline OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 64558)
-- Name: submissionline_submissionline_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.submissionline_submissionline_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.submissionline_submissionline_id_seq OWNER TO postgres;

--
-- TOC entry 4972 (class 0 OID 0)
-- Dependencies: 230
-- Name: submissionline_submissionline_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.submissionline_submissionline_id_seq OWNED BY public.submissionline.submissionline_id;


--
-- TOC entry 231 (class 1259 OID 64559)
-- Name: test_case; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.test_case (
    test_id integer NOT NULL,
    input text NOT NULL,
    output text NOT NULL,
    question_id integer NOT NULL,
    test_point integer DEFAULT 20 NOT NULL
);


ALTER TABLE public.test_case OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 64564)
-- Name: test_case_test_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.test_case_test_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_case_test_id_seq OWNER TO postgres;

--
-- TOC entry 4973 (class 0 OID 0)
-- Dependencies: 232
-- Name: test_case_test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.test_case_test_id_seq OWNED BY public.test_case.test_id;


--
-- TOC entry 4741 (class 2604 OID 64565)
-- Name: contest contest_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contest ALTER COLUMN contest_id SET DEFAULT nextval('public.contest_contest_id_seq'::regclass);


--
-- TOC entry 4743 (class 2604 OID 64566)
-- Name: level level_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.level ALTER COLUMN level_id SET DEFAULT nextval('public.level_level_id_seq'::regclass);


--
-- TOC entry 4746 (class 2604 OID 64567)
-- Name: professor prof_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.professor ALTER COLUMN prof_id SET DEFAULT nextval('public.professor_prof_id_seq'::regclass);


--
-- TOC entry 4748 (class 2604 OID 64568)
-- Name: question question_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question ALTER COLUMN question_id SET DEFAULT nextval('public.question_question_id_seq'::regclass);


--
-- TOC entry 4750 (class 2604 OID 64569)
-- Name: student student_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student ALTER COLUMN student_id SET DEFAULT nextval('public.student_studentid_seq'::regclass);


--
-- TOC entry 4752 (class 2604 OID 64570)
-- Name: submission submission_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submission ALTER COLUMN submission_id SET DEFAULT nextval('public.submission_submission_id_seq'::regclass);


--
-- TOC entry 4755 (class 2604 OID 64571)
-- Name: submissionline submissionline_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submissionline ALTER COLUMN submissionline_id SET DEFAULT nextval('public.submissionline_submissionline_id_seq'::regclass);


--
-- TOC entry 4756 (class 2604 OID 64572)
-- Name: test_case test_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_case ALTER COLUMN test_id SET DEFAULT nextval('public.test_case_test_id_seq'::regclass);


--
-- TOC entry 4942 (class 0 OID 64511)
-- Dependencies: 215
-- Data for Name: contest; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.contest (contest_id, name, prof_id, created_at) FROM stdin;
1	Semester 2024-1	1	2024-12-08
2	Contest round 1	3	2024-12-19
3	Contest round 2	3	2024-12-19
4	Contest round 3	2	2024-12-19
5	Contest round 4	2	2024-12-19
6	Contest round 5	3	2024-12-19
7	Contest round 6	2	2024-12-19
8	Contest round 7	1	2024-12-19
9	Contest round 8	1	2024-12-19
10	Contest round 9	2	2024-12-19
11	Contest round 10	3	2024-12-19
12	Contest round 11	3	2024-12-19
13	Contest round 12	3	2024-12-19
14	Contest round 13	2	2024-12-19
15	Contest round 14	1	2024-12-19
16	Contest round 15	2	2024-12-19
17	Contest round 16	3	2024-12-19
18	Contest round 17	2	2024-12-19
19	Contest round 18	3	2024-12-19
20	Contest round 19	1	2024-12-19
21	Contest round 20	1	2024-12-19
22	Contest round 21	1	2024-12-19
23	Contest round 22	1	2024-12-19
24	Contest round 23	3	2024-12-19
25	Contest round 24	1	2024-12-19
26	Contest round 25	2	2024-12-19
27	Contest round 26	2	2024-12-19
28	Contest round 27	1	2024-12-19
29	Contest round 28	3	2024-12-19
30	Contest round 29	3	2024-12-19
31	Contest round 30	3	2024-12-19
32	Contest round 31	3	2024-12-19
33	Contest round 32	1	2024-12-19
34	Contest round 33	3	2024-12-19
35	Contest round 34	1	2024-12-19
36	Contest round 35	1	2024-12-19
37	Contest round 36	2	2024-12-19
38	Contest round 37	3	2024-12-19
39	Contest round 38	2	2024-12-19
40	Contest round 39	2	2024-12-19
41	Contest round 40	1	2024-12-19
42	Contest round 41	3	2024-12-19
43	Contest round 42	1	2024-12-19
44	Contest round 43	3	2024-12-19
45	Contest round 44	1	2024-12-19
46	Contest round 45	1	2024-12-19
47	Contest round 46	3	2024-12-19
48	Contest round 47	1	2024-12-19
49	Contest round 48	2	2024-12-19
50	Contest round 49	3	2024-12-19
51	Contest round 50	2	2024-12-19
\.


--
-- TOC entry 4944 (class 0 OID 64516)
-- Dependencies: 217
-- Data for Name: level; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.level (level_id, name, rate) FROM stdin;
1	Easy	1
2	Medium	1.5
3	Hard	2
\.


--
-- TOC entry 4960 (class 0 OID 64687)
-- Dependencies: 233
-- Data for Name: participant_question; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.participant_question (student_id, contest_id, question_id, point, is_accepted) FROM stdin;
73	1	9	20	t
52	1	3	60	t
14	2	2	60.0	t
55	4	2	60.0	t
105	5	2	60.0	t
196	6	7	90.0	t
22	8	9	20	t
92	8	5	90.0	t
184	8	3	60	t
79	9	4	120	t
165	11	5	90.0	t
10	12	4	120	t
181	13	6	60	t
20	13	7	90.0	t
87	14	7	90.0	t
130	15	9	20	t
68	15	9	20	t
20	15	9	20	t
20	16	4	120	t
194	17	2	60.0	t
103	18	3	60	t
27	19	8	90.0	t
16	20	10	120	t
200	21	2	60.0	t
126	21	6	60	t
11	23	3	60	t
115	23	10	120	t
81	23	10	120	t
74	25	10	120	t
79	26	5	90.0	t
7	28	9	20	t
7	28	8	90.0	t
38	28	7	90.0	t
191	30	9	20	t
125	34	5	90.0	t
134	35	8	90.0	t
100	36	2	60.0	t
159	38	8	90.0	t
89	39	9	20	t
70	39	3	60	t
132	39	4	120	t
162	41	10	120	t
89	42	4	120	t
25	42	4	120	t
8	46	7	90.0	t
81	47	3	60	t
130	50	3	60	t
1	1	2	60.0	t
1	1	7	90.0	t
1	1	3	60	t
1	1	9	20	t
42	1	9	20	t
86	1	9	20	t
73	1	2	60.0	t
39	1	3	60	t
39	1	9	20	t
182	1	9	20	t
23	1	2	60.0	t
23	1	3	60	t
88	1	3	60	t
168	1	3	60	t
168	1	6	60	t
61	2	9	20	t
61	2	5	90.0	t
50	2	9	20	t
125	2	4	120	t
52	2	5	90.0	t
52	2	2	60.0	t
178	3	9	20	t
100	3	4	120	t
176	3	9	20	t
38	3	8	90.0	t
46	3	9	20	t
58	3	8	90.0	t
6	4	2	60.0	t
6	4	9	20	t
172	4	9	20	t
64	4	9	20	t
196	4	9	20	t
173	5	8	90.0	t
185	5	7	90.0	t
33	6	9	20	t
85	6	9	20	t
85	6	7	90.0	t
114	6	10	120	t
53	7	4	120	t
176	7	4	120	t
29	7	2	60.0	t
202	7	8	90.0	t
94	7	2	60.0	t
168	8	9	20	t
82	8	3	60	t
5	8	9	20	t
35	8	9	20	t
103	8	9	20	t
40	8	9	20	t
153	9	5	90.0	t
43	9	4	120	t
63	10	5	90.0	t
150	10	9	20	t
148	10	4	120	t
171	10	9	20	t
143	11	5	90.0	t
25	12	5	90.0	t
155	12	4	120	t
1	12	9	20	t
132	12	4	120	t
58	13	2	60.0	t
83	14	7	90.0	t
155	15	2	60.0	t
155	15	8	90.0	t
82	15	7	90.0	t
82	15	2	60.0	t
136	15	7	90.0	t
188	17	7	90.0	t
72	18	7	90.0	t
56	18	9	20	t
13	18	7	90.0	t
169	18	9	20	t
23	18	9	20	t
100	19	8	90.0	t
147	19	5	90.0	t
81	19	4	120	t
120	20	8	90.0	t
48	21	4	120	t
199	21	5	90.0	t
157	21	4	120	t
157	21	5	90.0	t
107	21	5	90.0	t
98	22	5	90.0	t
163	22	5	90.0	t
134	22	4	120	t
111	23	3	60	t
27	23	10	120	t
45	23	10	120	t
60	24	4	120	t
5	25	3	60	t
143	26	6	60	t
126	26	5	90.0	t
126	26	3	60	t
68	26	10	120	t
96	26	6	60	t
84	27	9	20	t
80	27	9	20	t
178	27	10	120	t
103	27	9	20	t
14	27	9	20	t
142	27	9	20	t
66	28	7	90.0	t
115	28	7	90.0	t
77	28	9	20	t
144	28	9	20	t
192	29	6	60	t
122	29	4	120	t
41	30	5	90.0	t
23	30	9	20	t
23	30	5	90.0	t
11	30	9	20	t
125	30	9	20	t
118	31	9	20	t
95	31	9	20	t
27	31	4	120	t
60	31	9	20	t
78	31	9	20	t
78	31	4	120	t
74	31	9	20	t
9	31	9	20	t
9	31	4	120	t
22	31	9	20	t
52	32	2	60.0	t
45	32	10	120	t
99	32	2	60.0	t
72	32	4	120	t
72	32	2	60.0	t
140	32	2	60.0	t
23	32	2	60.0	t
62	32	8	90.0	t
187	33	5	90.0	t
103	33	6	60	t
135	34	2	60.0	t
198	34	4	120	t
198	34	2	60.0	t
164	34	2	60.0	t
74	34	4	120	t
12	36	5	90.0	t
39	37	5	90.0	t
143	37	3	60	t
143	37	2	60.0	t
102	37	5	90.0	t
138	37	2	60.0	t
51	37	5	90.0	t
51	37	2	60.0	t
115	37	10	120	t
144	37	2	60.0	t
88	38	10	120	t
175	38	8	90.0	t
175	38	4	120	t
44	38	3	60	t
85	39	9	20	t
6	39	4	120	t
82	39	9	20	t
94	39	9	20	t
29	39	9	20	t
69	39	4	120	t
114	39	8	90.0	t
2	40	9	20	t
3	40	9	20	t
12	40	2	60.0	t
7	40	9	20	t
85	40	2	60.0	t
169	40	4	120	t
93	41	4	120	t
140	41	2	60.0	t
22	42	4	120	t
25	42	2	60.0	t
25	42	6	60	t
116	42	2	60.0	t
23	43	7	90.0	t
54	43	7	90.0	t
66	43	5	90.0	t
194	44	3	60	t
5	44	8	90.0	t
198	45	3	60	t
174	45	10	120	t
73	45	6	60	t
115	45	7	90.0	t
120	46	7	90.0	t
21	46	8	90.0	t
46	49	10	120	t
56	49	4	120	t
111	49	3	60	t
14	49	10	120	t
96	50	6	60	t
20	50	8	90.0	t
109	41	4	80	f
83	24	4	40	f
102	22	5	60.0	f
31	39	7	60.0	f
111	49	7	0	f
45	23	7	60.0	f
198	45	5	60.0	f
10	38	10	80	f
69	39	7	0	f
77	32	4	0	f
113	42	6	40	f
154	2	4	80	f
25	1	3	20	f
63	42	6	20	f
86	1	7	30.0	f
115	23	8	60.0	f
127	5	8	30.0	f
58	41	10	40	f
21	7	8	30.0	f
145	37	10	0	f
119	43	3	20	f
140	35	7	60.0	f
143	11	8	60.0	f
96	48	8	30.0	f
52	2	4	80	f
14	23	10	80	f
53	12	5	0	f
125	24	4	0	f
179	5	6	0	f
161	8	6	40	f
50	31	7	30.0	f
42	11	8	0	f
134	38	10	40	f
94	7	4	80	f
19	40	2	0	f
43	48	8	60.0	f
43	28	8	60.0	f
7	28	7	60.0	f
23	32	4	40	f
144	28	7	60.0	f
126	26	6	40	f
90	12	6	40	f
50	47	10	80	f
122	43	3	40	f
134	12	6	20	f
13	3	8	60.0	f
77	34	5	0	f
75	9	8	30.0	f
41	45	5	60.0	f
166	33	4	40	f
124	14	6	20	f
21	44	7	0	f
10	32	10	80	f
51	36	2	0	f
187	33	10	80	f
166	13	2	30.0	f
10	12	6	20	f
41	30	9	0	f
199	7	8	30.0	f
113	29	6	20	f
179	26	10	40	f
181	13	4	80	f
83	34	5	30.0	f
174	12	5	0	f
154	10	4	40	f
60	21	4	80	f
82	8	5	60.0	f
2	33	6	20	f
136	30	5	30.0	f
46	19	3	20	f
151	7	4	40	f
102	37	10	40	f
169	18	3	40	f
194	22	2	30.0	f
185	24	8	0	f
194	17	7	60.0	f
143	37	10	0	f
115	37	3	20	f
45	20	5	60.0	f
44	44	8	60.0	f
146	37	10	40	f
103	8	10	40	f
48	21	6	40	f
199	47	4	80	f
185	50	2	0	f
137	15	7	30.0	f
123	36	8	30.0	f
35	49	10	40	f
148	10	5	60.0	f
155	28	5	30.0	f
154	13	2	30.0	f
130	46	5	60.0	f
119	43	4	80	f
72	32	10	40	f
1	44	7	30.0	f
113	29	8	60.0	f
61	2	4	40	f
8	20	10	80	f
93	8	5	30.0	f
102	16	5	30.0	f
20	13	6	0	f
137	32	8	0	f
174	45	6	40	f
89	42	3	40	f
11	31	7	60.0	f
16	24	4	40	f
133	20	3	20	f
156	42	4	80	f
166	11	3	20	f
154	2	3	20	f
195	20	10	40	f
37	28	8	60.0	f
43	23	10	80	f
16	35	7	60.0	f
137	49	4	80	f
120	20	10	40	f
182	1	6	0	f
194	44	2	30.0	f
111	23	7	30.0	f
73	1	6	40	f
50	1	2	0	f
128	42	6	20	f
157	21	2	0	f
74	31	8	60.0	f
154	10	3	40	f
29	39	8	60.0	f
200	11	5	30.0	f
180	5	6	20	f
201	48	6	20	f
96	48	6	20	f
6	39	8	60.0	f
156	50	3	20	f
152	45	7	60.0	f
142	34	7	30.0	f
83	36	8	60.0	f
40	33	5	30.0	f
173	20	3	20	f
122	43	4	40	f
173	3	10	80	f
169	40	2	30.0	f
134	22	5	30.0	f
6	4	5	60.0	f
127	5	6	20	f
125	36	8	30.0	f
103	32	4	80	f
171	10	5	30.0	f
143	22	5	60.0	f
130	50	8	0	f
131	4	2	0	f
137	43	4	40	f
59	6	9	0	f
113	2	3	40	f
198	42	4	80	f
178	31	8	60.0	f
25	27	10	40	f
122	47	7	60.0	f
32	19	5	60.0	f
130	15	2	0	f
2	9	5	30.0	f
135	4	5	60.0	f
4	14	6	20	f
151	32	8	30.0	f
6	39	7	0	f
7	17	3	20	f
64	4	2	0	f
83	14	6	40	f
169	50	8	30.0	f
94	15	7	30.0	f
150	33	4	40	f
23	21	4	80	f
140	35	6	40	f
118	23	10	80	f
200	13	4	80	f
196	46	8	0	f
69	22	5	0	f
4	35	6	40	f
100	2	3	40	f
19	20	3	20	f
170	48	6	20	f
29	39	7	0	f
185	5	6	0	f
98	20	8	60.0	f
16	20	5	0	f
164	34	3	40	f
74	31	7	30.0	f
63	13	2	30.0	f
111	23	8	60.0	f
179	5	7	30.0	f
45	36	6	40	f
17	33	6	20	f
5	8	10	40	f
165	19	3	0	f
154	21	5	30.0	f
132	39	8	30.0	f
37	28	7	30.0	f
16	35	8	60.0	f
42	18	7	60.0	f
202	10	4	40	f
68	17	3	40	f
82	15	8	30.0	f
79	22	2	30.0	f
22	33	5	60.0	f
68	2	4	40	f
152	36	6	20	f
110	28	5	30.0	f
18	20	8	0	f
79	43	5	30.0	f
36	40	3	40	f
21	14	7	30.0	f
46	26	5	60.0	f
1	44	8	30.0	f
14	20	3	40	f
1	1	6	20	f
92	47	3	40	f
7	40	2	0	f
63	10	3	0	f
45	37	3	20	f
83	16	7	30.0	f
23	13	4	40	f
78	48	8	30.0	f
84	11	7	60.0	f
63	5	2	30.0	f
73	21	4	80	f
171	35	8	30.0	f
73	45	7	60.0	f
78	48	6	20	f
176	3	10	40	f
184	8	6	20	f
30	30	5	0	f
97	26	10	80	f
102	22	2	30.0	f
133	2	4	40	f
173	4	10	40	f
140	41	10	40	f
23	1	7	0	f
118	45	10	40	f
186	43	5	60.0	f
143	33	7	60.0	f
175	47	7	0	f
68	2	9	0	f
98	39	7	30.0	f
128	37	5	30.0	f
111	37	3	40	f
174	45	7	30.0	f
179	22	4	40	f
152	36	8	60.0	f
198	42	3	40	f
180	19	8	30.0	f
182	1	7	0	f
144	28	8	60.0	f
54	43	6	40	f
16	35	6	0	f
137	9	4	40	f
137	43	3	40	f
27	15	8	30.0	f
75	33	5	60.0	f
118	31	4	80	f
198	43	5	60.0	f
198	34	7	60.0	f
44	45	7	30.0	f
46	49	7	60.0	f
169	50	6	40	f
140	34	2	0	f
152	45	6	0	f
63	10	4	80	f
125	34	2	30.0	f
110	24	8	30.0	f
150	11	3	20	f
77	34	2	0	f
175	50	2	30.0	f
180	5	7	30.0	f
68	1	10	40	f
189	38	4	80	f
79	9	5	30.0	f
47	17	2	30.0	f
40	6	10	40	f
40	3	8	60.0	f
23	20	5	30.0	f
158	11	3	20	f
68	2	3	40	f
15	34	2	0	f
1	12	5	30.0	f
91	2	5	0	f
197	27	10	40	f
163	22	2	30.0	f
45	23	8	30.0	f
78	39	9	0	f
18	41	4	40	f
35	25	3	20	f
104	22	2	30.0	f
194	22	5	60.0	f
202	10	3	20	f
64	1	2	30.0	f
37	26	3	20	f
11	28	3	40	f
144	37	5	60.0	f
31	39	8	60.0	f
192	9	5	60.0	f
192	29	4	40	f
161	8	10	80	f
29	38	8	0	f
40	2	4	0	f
53	24	5	60.0	f
101	11	7	60.0	f
180	41	4	80	f
20	47	10	0	f
7	40	3	40	f
123	17	3	40	f
173	20	5	60.0	f
77	34	4	80	f
140	34	4	40	f
143	49	3	40	f
64	49	4	80	f
147	36	6	20	f
103	13	2	0	f
123	24	5	30.0	f
141	23	3	0	f
14	2	5	60.0	f
128	17	2	30.0	f
82	39	8	60.0	f
193	45	3	40	f
142	13	8	0	f
116	18	10	0	f
20	50	3	20	f
153	4	10	0	f
138	37	5	30.0	f
60	21	5	0	f
52	8	10	40	f
157	12	5	30.0	f
154	10	5	60.0	f
55	4	7	30.0	f
202	21	4	80	f
35	8	10	80	f
125	39	3	20	f
122	47	10	0	f
103	33	4	40	f
104	22	4	80	f
115	28	8	30.0	f
68	17	2	0	f
188	6	10	80	f
66	43	3	40	f
83	34	4	80	f
167	18	10	40	f
130	50	10	0	f
148	10	9	0	f
42	1	3	20	f
196	4	5	60.0	f
200	8	6	20	f
15	17	3	20	f
189	42	6	0	f
113	45	7	30.0	f
7	14	6	20	f
168	38	10	80	f
100	2	2	30.0	f
138	49	10	0	f
41	46	7	0	f
125	39	9	0	f
202	23	7	60.0	f
8	20	8	30.0	f
130	21	4	80	f
118	40	3	40	f
13	29	6	20	f
65	35	7	60.0	f
11	13	6	20	f
90	13	7	60.0	f
154	36	6	40	f
43	23	8	60.0	f
42	18	10	40	f
162	41	4	40	f
56	46	2	30.0	f
195	20	8	30.0	f
66	14	3	20	f
86	25	3	0	f
56	48	6	40	f
65	2	5	30.0	f
1	42	6	20	f
39	25	10	40	f
178	3	4	40	f
56	48	8	0	f
83	34	3	20	f
66	43	4	40	f
42	50	2	30.0	f
109	26	10	40	f
197	30	4	80	f
60	46	5	60.0	f
15	34	3	0	f
189	28	7	60.0	f
154	38	3	40	f
35	23	8	30.0	f
188	44	7	30.0	f
125	39	4	40	f
108	38	3	20	f
52	1	6	20	f
183	26	5	30.0	f
36	5	2	30.0	f
64	1	3	20	f
175	47	10	80	f
154	36	8	30.0	f
15	45	10	40	f
116	44	3	40	f
13	29	8	30.0	f
73	21	2	30.0	f
39	9	4	80	f
23	1	10	40	f
64	49	3	20	f
143	22	4	40	f
171	10	4	80	f
125	5	2	30.0	f
147	16	8	30.0	f
137	48	9	0	f
62	34	7	60.0	f
77	29	7	30.0	f
40	33	4	80	f
73	45	10	0	f
77	21	2	30.0	f
40	2	3	20	f
175	50	3	40	f
56	18	3	40	f
141	16	4	0	f
176	32	4	80	f
133	35	6	40	f
113	9	8	30.0	f
8	41	4	40	f
92	29	7	0	f
172	9	8	60.0	f
119	43	5	30.0	f
112	24	4	40	f
64	1	9	0	f
15	18	9	0	f
147	44	8	30.0	f
162	20	8	0	f
182	10	3	40	f
172	4	7	0	f
61	36	6	40	f
40	6	7	0	f
4	28	8	60.0	f
135	7	4	80	f
140	48	8	60.0	f
147	19	4	40	f
9	13	4	40	f
132	13	8	30.0	f
6	49	3	40	f
1	3	10	40	f
2	30	5	30.0	f
188	16	7	30.0	f
102	16	4	40	f
200	13	2	30.0	f
85	40	3	40	f
91	37	2	0	f
40	39	4	0	f
84	19	8	30.0	f
45	32	2	30.0	f
27	31	8	30.0	f
23	21	2	30.0	f
134	38	8	30.0	f
124	25	3	40	f
58	3	10	40	f
34	3	4	0	f
22	33	4	80	f
27	31	7	60.0	f
68	2	5	30.0	f
60	46	2	0	f
91	2	3	40	f
144	43	7	60.0	f
14	23	7	30.0	f
188	16	8	30.0	f
17	33	10	80	f
57	38	8	60.0	f
144	37	3	40	f
99	48	9	0	f
11	28	5	60.0	f
170	30	10	40	f
199	11	3	20	f
3	40	4	80	f
77	28	7	60.0	f
132	13	7	60.0	f
4	28	7	60.0	f
114	39	7	30.0	f
153	21	5	30.0	f
40	6	8	60.0	f
141	7	4	40	f
134	3	4	40	f
40	3	10	80	f
155	25	8	30.0	f
68	14	7	60.0	f
86	1	10	80	f
111	49	10	80	f
77	21	5	60.0	f
19	16	7	30.0	f
59	27	10	0	f
79	43	4	80	f
130	24	4	40	f
13	18	9	0	f
151	48	9	0	f
42	21	6	40	f
150	11	5	0	f
70	39	9	0	f
81	13	6	40	f
154	13	4	40	f
79	26	10	80	f
107	21	4	40	f
2	43	3	40	f
111	37	5	60.0	f
128	37	3	20	f
1	1	10	0	f
137	43	5	60.0	f
5	10	4	40	f
54	25	3	40	f
190	42	6	20	f
187	33	7	60.0	f
38	38	4	80	f
22	34	3	40	f
46	3	10	80	f
109	24	8	30.0	f
90	13	6	40	f
11	13	7	0	f
198	14	3	20	f
175	11	8	60.0	f
175	38	10	0	f
88	38	4	40	f
120	16	5	60.0	f
35	23	7	60.0	f
21	46	2	0	f
157	47	3	20	f
50	47	7	30.0	f
19	40	9	0	f
52	44	7	60.0	f
68	34	5	30.0	f
23	21	5	30.0	f
186	43	3	0	f
150	33	5	30.0	f
51	50	2	30.0	f
134	35	4	80	f
18	35	4	80	f
75	4	10	80	f
70	8	6	40	f
91	37	5	60.0	f
69	22	4	40	f
61	2	2	30.0	f
174	6	8	0	f
36	3	10	80	f
96	26	5	30.0	f
45	37	5	30.0	f
72	35	4	80	f
113	38	4	80	f
169	40	3	20	f
174	25	3	40	f
126	24	8	30.0	f
43	23	7	0	f
31	19	8	30.0	f
199	21	2	30.0	f
71	46	8	30.0	f
94	39	8	60.0	f
14	20	5	60.0	f
142	49	3	20	f
109	45	3	20	f
65	35	8	60.0	f
166	27	5	30.0	f
176	7	8	30.0	f
154	49	7	60.0	f
66	28	5	60.0	f
108	49	7	30.0	f
170	16	8	60.0	f
106	8	3	20	f
19	40	4	40	f
116	21	8	30.0	f
84	27	10	40	f
137	17	7	60.0	f
81	43	3	40	f
105	18	9	0	f
50	1	3	40	f
41	46	8	60.0	f
179	8	3	40	f
30	7	2	30.0	f
97	1	2	0	f
100	19	3	0	f
60	21	2	0	f
149	34	7	60.0	f
186	15	8	30.0	f
110	28	3	40	f
104	5	6	20	f
57	19	8	60.0	f
136	47	10	0	f
70	39	4	0	f
60	18	3	20	f
77	29	6	20	f
135	4	9	0	f
1	12	4	80	f
156	50	2	30.0	f
140	27	9	0	f
43	9	8	30.0	f
136	39	7	60.0	f
8	33	6	40	f
53	26	3	40	f
21	10	3	20	f
6	27	10	80	f
114	6	9	0	f
92	29	6	20	f
100	2	5	60.0	f
169	9	8	60.0	f
133	35	7	30.0	f
99	32	10	40	f
42	21	8	0	f
196	4	2	0	f
131	49	4	80	f
154	2	2	0	f
106	8	9	0	f
77	32	2	30.0	f
176	14	6	40	f
88	38	3	40	f
151	30	4	80	f
113	2	5	30.0	f
151	32	10	40	f
142	13	7	60.0	f
169	50	10	40	f
50	1	9	0	f
5	10	3	0	f
115	37	2	30.0	f
174	32	2	30.0	f
171	20	3	40	f
150	14	7	60.0	f
3	14	6	0	f
28	30	4	0	f
169	13	4	40	f
100	36	6	0	f
2	43	4	0	f
69	1	3	40	f
19	3	8	60.0	f
33	13	7	0	f
179	22	5	0	f
95	32	10	80	f
101	11	8	60.0	f
65	2	2	0	f
28	30	10	40	f
132	12	9	0	f
45	32	8	30.0	f
200	13	8	0	f
23	21	8	30.0	f
142	34	4	0	f
60	24	8	60.0	f
120	16	8	30.0	f
116	42	6	20	f
22	42	2	0	f
58	41	2	0	f
189	28	5	60.0	f
169	18	7	60.0	f
50	31	9	0	f
79	26	3	20	f
85	39	8	60.0	f
109	24	5	60.0	f
170	48	9	0	f
128	37	10	80	f
131	48	8	30.0	f
27	15	9	0	f
103	46	8	30.0	f
13	18	10	80	f
153	9	4	80	f
135	34	3	20	f
106	33	5	30.0	f
99	32	4	80	f
147	44	2	30.0	f
95	24	4	80	f
126	21	2	30.0	f
69	39	9	0	f
117	2	2	0	f
78	39	8	0	f
8	33	5	60.0	f
60	32	8	60.0	f
21	44	3	20	f
143	26	3	40	f
122	43	7	60.0	f
68	33	6	20	f
78	31	8	60.0	f
95	38	4	80	f
13	28	5	30.0	f
150	11	8	30.0	f
80	11	5	60.0	f
77	21	8	30.0	f
122	30	10	0	f
73	21	8	60.0	f
197	4	7	30.0	f
23	13	8	30.0	f
125	5	8	60.0	f
103	27	10	80	f
124	15	7	30.0	f
21	46	7	60.0	f
100	36	5	30.0	f
69	39	3	40	f
96	42	3	40	f
11	28	8	60.0	f
21	15	7	30.0	f
11	13	2	30.0	f
137	49	7	60.0	f
54	43	4	40	f
10	32	2	0	f
31	39	3	20	f
31	40	2	0	f
39	13	2	0	f
23	43	3	40	f
78	32	10	80	f
39	1	10	40	f
42	50	8	60.0	f
173	12	6	40	f
4	14	3	40	f
75	33	10	40	f
11	31	4	80	f
86	1	3	40	f
56	46	8	60.0	f
82	44	7	60.0	f
3	41	4	80	f
105	18	10	80	f
135	15	2	0	f
46	3	4	80	f
42	50	6	0	f
53	26	10	80	f
132	39	9	0	f
11	23	10	40	f
137	9	8	60.0	f
135	34	4	40	f
89	39	4	80	f
60	30	5	30.0	f
36	5	6	20	f
180	19	4	0	f
73	21	6	20	f
135	4	10	80	f
63	8	9	0	f
55	4	5	60.0	f
96	50	3	0	f
69	1	10	40	f
153	21	6	40	f
125	5	6	40	f
33	19	5	60.0	f
74	25	3	40	f
42	21	5	60.0	f
25	27	5	60.0	f
142	34	3	20	f
169	50	3	20	f
181	13	7	30.0	f
41	50	8	60.0	f
137	15	9	0	f
112	39	7	30.0	f
169	9	5	60.0	f
196	4	7	60.0	f
23	43	4	80	f
179	12	5	60.0	f
106	8	10	80	f
105	5	7	60.0	f
59	6	8	60.0	f
149	47	4	80	f
6	27	9	0	f
124	16	4	40	f
5	30	5	60.0	f
174	25	10	40	f
132	39	3	0	f
86	46	7	30.0	f
93	41	10	80	f
110	35	7	30.0	f
107	18	7	0	f
136	47	3	40	f
118	31	8	30.0	f
131	48	6	20	f
66	28	8	30.0	f
22	33	10	40	f
142	13	2	30.0	f
81	6	8	60.0	f
103	20	10	40	f
33	13	2	30.0	f
50	1	10	80	f
189	38	8	0	f
13	32	8	30.0	f
31	19	5	30.0	f
20	16	8	60.0	f
70	8	5	60.0	f
4	35	4	80	f
95	38	3	20	f
140	35	4	80	f
94	15	9	0	f
145	40	2	30.0	f
197	38	4	40	f
21	14	3	20	f
189	43	4	40	f
58	3	4	40	f
64	4	10	80	f
174	32	8	30.0	f
8	20	5	60.0	f
93	8	10	80	f
161	8	9	0	f
84	11	3	20	f
77	32	8	60.0	f
44	38	8	30.0	f
64	10	4	80	f
192	29	7	60.0	f
103	8	5	30.0	f
200	22	4	40	f
188	6	9	0	f
149	34	5	30.0	f
149	19	3	40	f
122	43	6	20	f
8	6	10	40	f
133	20	8	30.0	f
155	24	4	80	f
166	11	8	60.0	f
119	43	6	0	f
126	32	2	30.0	f
181	13	8	60.0	f
199	7	4	40	f
34	48	8	30.0	f
9	6	9	0	f
35	33	6	20	f
169	36	5	60.0	f
177	12	4	80	f
193	45	10	80	f
144	17	7	30.0	f
6	4	10	80	f
41	46	2	30.0	f
155	12	5	60.0	f
33	6	8	60.0	f
47	5	7	60.0	f
37	28	9	0	f
167	18	3	0	f
42	18	9	0	f
42	1	10	40	f
116	21	2	0	f
63	42	3	0	f
51	50	6	0	f
98	39	4	40	f
88	11	7	30.0	f
25	1	6	0	f
20	50	10	80	f
13	3	4	80	f
175	47	4	80	f
144	44	2	0	f
52	8	3	40	f
113	42	3	40	f
35	8	3	20	f
199	21	8	30.0	f
82	44	8	0	f
124	9	4	40	f
53	24	8	60.0	f
13	3	9	0	f
16	24	8	60.0	f
144	43	5	30.0	f
137	32	4	80	f
125	30	5	60.0	f
90	12	4	80	f
133	9	5	30.0	f
199	21	6	0	f
134	12	4	40	f
157	32	10	80	f
25	2	5	30.0	f
126	21	5	60.0	f
173	4	2	30.0	f
128	42	3	20	f
42	11	3	20	f
40	42	2	0	f
23	13	7	0	f
72	2	3	20	f
73	1	3	40	f
117	2	5	30.0	f
30	47	4	80	f
185	24	4	80	f
48	6	10	80	f
157	12	6	20	f
2	33	4	40	f
113	29	4	40	f
116	24	5	30.0	f
23	1	9	0	f
34	48	6	20	f
172	9	5	30.0	f
197	38	3	40	f
85	42	4	80	f
143	11	3	20	f
62	1	7	60.0	f
106	27	5	60.0	f
6	49	10	0	f
177	12	9	0	f
154	38	10	40	f
198	33	4	80	f
122	47	4	80	f
20	3	8	0	f
72	29	7	60.0	f
70	15	8	0	f
64	1	10	80	f
113	42	4	80	f
15	18	10	0	f
136	30	10	40	f
174	45	3	40	f
89	42	6	0	f
179	26	5	60.0	f
182	1	3	0	f
43	28	3	40	f
72	18	3	40	f
103	32	8	0	f
8	43	6	20	f
149	45	6	40	f
103	46	7	30.0	f
180	41	10	40	f
62	6	10	80	f
150	33	7	60.0	f
5	27	10	40	f
9	31	7	60.0	f
27	23	8	30.0	f
201	48	9	0	f
200	13	7	60.0	f
22	31	8	30.0	f
63	8	5	60.0	f
198	14	6	40	f
116	35	8	0	f
130	50	2	0	f
141	7	8	30.0	f
81	47	4	40	f
8	6	7	30.0	f
63	42	2	0	f
153	4	2	30.0	f
151	48	6	40	f
186	43	6	20	f
130	24	8	0	f
43	21	6	20	f
31	19	3	20	f
18	41	10	40	f
94	39	3	20	f
102	16	7	60.0	f
40	39	7	60.0	f
68	15	7	0	f
33	24	4	80	f
2	43	6	40	f
72	40	3	40	f
4	25	8	60.0	f
83	36	2	30.0	f
94	15	2	0	f
34	3	8	60.0	f
59	47	4	0	f
161	5	8	60.0	f
13	32	10	80	f
189	38	10	40	f
111	30	4	80	f
169	13	6	20	f
103	18	7	60.0	f
14	20	10	80	f
54	43	5	0	f
96	26	10	80	f
157	21	8	60.0	f
99	48	6	20	f
45	37	10	40	f
39	1	6	20	f
198	43	6	40	f
127	12	4	80	f
75	33	6	40	f
71	44	7	30.0	f
194	44	8	0	f
56	31	7	60.0	f
98	20	5	60.0	f
9	16	4	40	f
167	6	10	80	f
100	5	7	30.0	f
42	1	7	30.0	f
137	32	2	30.0	f
12	40	4	80	f
142	34	5	0	f
72	40	9	0	f
40	33	7	30.0	f
85	42	2	30.0	f
154	13	8	30.0	f
179	12	9	0	f
5	8	3	20	f
62	10	4	40	f
180	46	2	30.0	f
101	11	3	0	f
176	3	4	80	f
71	17	2	0	f
143	49	7	30.0	f
1	16	5	30.0	f
102	47	3	40	f
141	23	7	60.0	f
40	36	2	30.0	f
192	9	8	30.0	f
14	27	10	80	f
6	49	7	30.0	f
173	4	9	0	f
53	22	2	30.0	f
198	45	7	30.0	f
3	14	3	20	f
59	47	3	20	f
69	1	6	20	f
38	28	5	60.0	f
107	21	6	40	f
45	11	8	30.0	f
134	17	2	30.0	f
48	21	2	0	f
26	28	7	30.0	f
72	40	4	40	f
81	13	4	80	f
70	39	8	30.0	f
48	29	7	60.0	f
57	38	3	40	f
179	12	4	80	f
23	43	5	60.0	f
8	46	2	30.0	f
20	13	2	0	f
128	41	2	30.0	f
174	6	9	0	f
35	25	10	80	f
132	12	5	60.0	f
95	29	7	60.0	f
110	24	5	0	f
12	40	9	0	f
18	35	6	20	f
134	35	6	40	f
13	28	3	20	f
45	36	5	30.0	f
17	33	5	30.0	f
106	23	10	80	f
189	28	9	0	f
193	43	6	40	f
42	50	10	40	f
162	29	7	30.0	f
176	14	3	20	f
60	31	8	30.0	f
9	24	8	60.0	f
102	47	4	80	f
91	37	10	0	f
150	33	10	40	f
154	21	6	20	f
163	35	8	30.0	f
144	28	5	60.0	f
140	18	7	30.0	f
193	44	7	30.0	f
74	34	2	30.0	f
135	34	5	60.0	f
171	41	4	40	f
62	10	3	20	f
93	26	3	20	f
143	26	5	60.0	f
152	36	5	60.0	f
165	11	8	30.0	f
140	34	7	30.0	f
22	33	6	20	f
97	26	3	20	f
83	22	2	30.0	f
148	17	7	60.0	f
62	34	3	20	f
125	34	7	30.0	f
95	31	4	40	f
13	28	9	0	f
35	27	10	80	f
9	22	4	80	f
127	5	2	30.0	f
109	45	6	40	f
183	49	4	80	f
22	8	3	40	f
43	21	8	60.0	f
64	1	7	30.0	f
70	31	8	30.0	f
188	44	3	40	f
33	19	4	40	f
106	8	6	20	f
173	27	10	80	f
154	38	8	0	f
50	47	3	40	f
173	3	4	40	f
117	2	9	0	f
20	3	10	40	f
202	21	8	30.0	f
22	34	7	0	f
96	42	2	30.0	f
20	6	8	30.0	f
31	40	3	40	f
26	2	9	0	f
42	45	6	20	f
177	43	7	60.0	f
143	33	5	60.0	f
177	12	5	60.0	f
103	32	10	40	f
48	21	5	60.0	f
106	27	9	0	f
159	38	4	80	f
2	43	7	60.0	f
23	22	5	30.0	f
102	37	3	40	f
175	50	8	60.0	f
7	14	3	20	f
124	9	5	30.0	f
183	26	10	40	f
33	13	4	40	f
165	11	7	0	f
93	8	6	40	f
185	5	2	30.0	f
82	39	4	80	f
193	44	8	30.0	f
27	15	2	30.0	f
109	26	5	0	f
45	36	2	30.0	f
60	31	7	60.0	f
169	13	7	30.0	f
179	26	3	20	f
114	39	9	0	f
92	8	3	0	f
20	50	6	40	f
25	1	10	40	f
68	14	3	40	f
154	49	4	80	f
61	49	3	40	f
198	43	7	60.0	f
130	21	8	60.0	f
162	20	3	20	f
39	1	7	60.0	f
42	11	5	60.0	f
157	32	8	30.0	f
178	3	8	60.0	f
66	43	6	20	f
137	49	10	40	f
3	41	2	30.0	f
10	38	3	20	f
42	1	6	20	f
18	36	8	60.0	f
134	38	3	0	f
52	32	8	30.0	f
107	23	3	20	f
45	11	7	0	f
166	13	7	30.0	f
144	43	3	40	f
124	25	8	60.0	f
64	10	5	60.0	f
41	30	10	40	f
114	39	3	40	f
145	37	3	20	f
149	34	4	80	f
199	47	10	40	f
199	11	7	60.0	f
81	23	8	30.0	f
63	5	6	20	f
150	14	3	40	f
198	45	6	40	f
63	5	8	30.0	f
156	50	10	0	f
82	39	3	40	f
5	34	7	60.0	f
29	38	3	40	f
94	26	3	0	f
137	15	2	0	f
35	8	5	30.0	f
154	13	7	60.0	f
1	44	2	0	f
48	29	6	40	f
97	1	10	40	f
43	49	4	80	f
89	41	10	40	f
33	6	10	0	f
135	4	7	0	f
23	30	4	0	f
159	38	3	40	f
52	8	5	60.0	f
181	26	6	40	f
25	4	10	40	f
69	1	7	30.0	f
182	16	5	30.0	f
50	2	2	30.0	f
1	42	4	80	f
93	33	4	40	f
83	36	5	60.0	f
11	23	7	30.0	f
202	25	10	80	f
13	29	4	40	f
166	33	10	40	f
11	13	4	80	f
125	39	8	30.0	f
52	1	9	0	f
115	28	3	20	f
53	12	6	20	f
43	46	7	30.0	f
105	18	7	30.0	f
178	27	5	30.0	f
64	19	4	40	f
103	8	3	40	f
9	13	8	30.0	f
81	8	10	40	f
50	1	7	60.0	f
161	5	7	0	f
63	13	8	0	f
135	7	8	30.0	f
37	28	5	30.0	f
153	12	6	20	f
50	35	8	60.0	f
95	32	2	30.0	f
93	10	3	40	f
53	7	2	0	f
144	43	4	40	f
110	28	7	60.0	f
40	39	8	60.0	f
84	19	4	40	f
174	32	10	40	f
133	9	4	80	f
125	30	4	80	f
175	50	6	20	f
127	26	3	20	f
112	24	8	30.0	f
155	28	8	30.0	f
180	46	5	30.0	f
44	38	10	40	f
142	49	7	60.0	f
176	32	8	30.0	f
120	20	3	0	f
109	41	10	80	f
117	2	4	0	f
173	3	9	0	f
13	25	8	30.0	f
45	20	8	30.0	f
84	11	5	60.0	f
81	19	3	0	f
126	21	4	80	f
155	12	9	0	f
178	35	6	20	f
22	31	7	30.0	f
\.


--
-- TOC entry 4946 (class 0 OID 64522)
-- Dependencies: 219
-- Data for Name: participants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.participants (student_id, contest_id, point, participant) FROM stdin;
39	1	200	Accepted
182	1	20	Accepted
69	1	130	Accepted
97	1	40	Accepted
13	3	140	Accepted
34	3	60	Accepted
58	3	170	Accepted
197	4	30	Accepted
131	4	0	Accepted
23	1	160	Accepted
50	1	180	Accepted
68	1	40	Accepted
52	1	80	Accepted
62	1	60	Accepted
127	5	80	Accepted
161	5	60	Accepted
85	6	110	Accepted
174	6	0	Accepted
29	7	60	Accepted
199	7	70	Accepted
64	1	160	Accepted
88	1	60	Accepted
168	1	120	Accepted
25	1	60	Accepted
72	2	20	Accepted
143	11	170	Accepted
150	11	50	Accepted
174	12	0	Accepted
25	12	90	Accepted
173	12	40	Accepted
200	13	170	Accepted
61	2	180	Accepted
65	2	30	Accepted
154	2	100	Accepted
91	2	40	Accepted
50	2	50	Accepted
133	2	40	Accepted
125	2	120	Accepted
21	14	50	Accepted
68	14	100	Accepted
124	14	20	Accepted
27	15	60	Accepted
130	15	20	Accepted
135	15	0	Accepted
194	17	120	Accepted
15	17	20	Accepted
100	2	130	Accepted
113	2	70	Accepted
26	2	0	Accepted
25	2	30	Accepted
52	2	230	Accepted
7	17	20	Accepted
148	17	60	Accepted
47	17	30	Accepted
13	18	170	Accepted
107	18	0	Accepted
149	19	40	Accepted
81	19	120	Accepted
14	20	180	Accepted
18	20	0	Accepted
117	2	30	Accepted
14	2	120	Accepted
40	2	20	Accepted
68	2	110	Accepted
20	3	40	Accepted
178	3	120	Accepted
98	20	120	Accepted
154	21	50	Accepted
134	22	150	Accepted
102	22	90	Accepted
27	23	150	Accepted
171	1	0	Accepted
167	1	0	Accepted
185	1	0	Accepted
1	1	250	Accepted
196	2	0	Accepted
199	2	0	Accepted
194	3	0	Accepted
96	3	0	Accepted
141	3	0	Accepted
42	1	130	Accepted
87	4	0	Accepted
9	4	0	Accepted
177	4	0	Accepted
201	4	0	Accepted
59	4	0	Accepted
154	4	0	Accepted
115	4	0	Accepted
159	5	0	Accepted
86	1	170	Accepted
119	5	0	Accepted
196	5	0	Accepted
49	5	0	Accepted
120	5	0	Accepted
12	5	0	Accepted
84	5	0	Accepted
162	6	0	Accepted
73	1	160	Accepted
151	6	0	Accepted
161	7	0	Accepted
72	7	0	Accepted
141	23	60	Accepted
136	7	0	Accepted
124	7	0	Accepted
22	7	0	Accepted
194	7	0	Accepted
81	7	0	Accepted
111	7	0	Accepted
26	7	0	Accepted
80	8	0	Accepted
112	24	70	Accepted
101	8	0	Accepted
100	3	120	Accepted
19	3	60	Accepted
98	9	0	Accepted
136	9	0	Accepted
20	9	0	Accepted
111	9	0	Accepted
83	9	0	Accepted
36	3	80	Accepted
186	9	0	Accepted
89	10	0	Accepted
54	10	0	Accepted
159	10	0	Accepted
33	10	0	Accepted
153	10	0	Accepted
32	10	0	Accepted
200	10	0	Accepted
190	10	0	Accepted
170	11	0	Accepted
176	3	140	Accepted
1	3	40	Accepted
4	11	0	Accepted
189	11	0	Accepted
181	11	0	Accepted
64	11	0	Accepted
2	11	0	Accepted
22	12	0	Accepted
173	3	120	Accepted
198	12	0	Accepted
195	12	0	Accepted
71	12	0	Accepted
191	12	0	Accepted
43	13	0	Accepted
40	3	140	Accepted
129	13	0	Accepted
134	3	40	Accepted
145	14	0	Accepted
9	14	0	Accepted
38	3	90	Accepted
44	14	0	Accepted
197	14	0	Accepted
17	14	0	Accepted
26	14	0	Accepted
177	14	0	Accepted
86	15	0	Accepted
145	15	0	Accepted
106	15	0	Accepted
62	15	0	Accepted
117	15	0	Accepted
46	3	180	Accepted
125	24	0	Accepted
181	16	0	Accepted
13	25	30	Accepted
14	16	0	Accepted
52	16	0	Accepted
48	16	0	Accepted
105	16	0	Accepted
118	16	0	Accepted
6	16	0	Accepted
66	17	0	Accepted
22	17	0	Accepted
168	17	0	Accepted
81	17	0	Accepted
6	4	220	Accepted
131	17	0	Accepted
78	18	0	Accepted
83	18	0	Accepted
173	4	70	Accepted
142	18	0	Accepted
82	19	0	Accepted
49	19	0	Accepted
127	19	0	Accepted
25	4	40	Accepted
97	19	0	Accepted
19	19	0	Accepted
2	20	0	Accepted
183	20	0	Accepted
153	4	30	Accepted
192	20	0	Accepted
118	20	0	Accepted
148	21	0	Accepted
55	4	150	Accepted
26	21	0	Accepted
75	4	80	Accepted
134	21	0	Accepted
122	22	0	Accepted
172	4	20	Accepted
137	22	0	Accepted
131	22	0	Accepted
34	22	0	Accepted
130	22	0	Accepted
22	23	0	Accepted
161	23	0	Accepted
70	23	0	Accepted
144	23	0	Accepted
135	4	140	Accepted
33	23	0	Accepted
172	23	0	Accepted
175	24	0	Accepted
64	4	100	Accepted
135	24	0	Accepted
119	25	0	Accepted
133	25	0	Accepted
176	25	0	Accepted
15	25	0	Accepted
196	4	140	Accepted
102	25	0	Accepted
132	25	0	Accepted
96	25	0	Accepted
150	26	0	Accepted
146	26	0	Accepted
36	5	50	Accepted
91	26	0	Accepted
100	5	30	Accepted
191	27	0	Accepted
1	27	0	Accepted
82	27	0	Accepted
168	27	0	Accepted
47	5	60	Accepted
119	28	0	Accepted
173	5	90	Accepted
14	28	0	Accepted
21	28	0	Accepted
61	28	0	Accepted
42	29	0	Accepted
34	29	0	Accepted
171	29	0	Accepted
126	29	0	Accepted
194	29	0	Accepted
4	29	0	Accepted
184	29	0	Accepted
125	5	130	Accepted
96	29	0	Accepted
45	29	0	Accepted
46	30	0	Accepted
105	5	120	Accepted
184	30	0	Accepted
104	30	0	Accepted
121	31	0	Accepted
48	31	0	Accepted
192	31	0	Accepted
179	5	30	Accepted
19	31	0	Accepted
15	31	0	Accepted
73	31	0	Accepted
185	5	120	Accepted
174	25	80	Accepted
5	33	0	Accepted
63	5	80	Accepted
194	33	0	Accepted
43	33	0	Accepted
27	33	0	Accepted
104	5	20	Accepted
27	34	0	Accepted
134	34	0	Accepted
132	34	0	Accepted
194	34	0	Accepted
3	34	0	Accepted
180	5	50	Accepted
87	35	0	Accepted
200	35	0	Accepted
188	6	80	Accepted
157	35	0	Accepted
148	35	0	Accepted
178	36	0	Accepted
1	36	0	Accepted
26	36	0	Accepted
142	36	0	Accepted
8	6	70	Accepted
108	37	0	Accepted
118	37	0	Accepted
105	37	0	Accepted
158	37	0	Accepted
196	6	90	Accepted
126	37	0	Accepted
89	37	0	Accepted
167	6	80	Accepted
36	38	0	Accepted
48	38	0	Accepted
81	6	60	Accepted
16	38	0	Accepted
39	38	0	Accepted
33	6	80	Accepted
87	39	0	Accepted
104	39	0	Accepted
116	39	0	Accepted
190	40	0	Accepted
202	40	0	Accepted
175	40	0	Accepted
143	40	0	Accepted
59	40	0	Accepted
83	40	0	Accepted
40	6	100	Accepted
39	25	40	Accepted
62	6	80	Accepted
36	41	0	Accepted
158	41	0	Accepted
178	41	0	Accepted
115	41	0	Accepted
195	41	0	Accepted
123	41	0	Accepted
97	41	0	Accepted
59	6	60	Accepted
3	42	0	Accepted
9	6	0	Accepted
138	42	0	Accepted
185	42	0	Accepted
133	42	0	Accepted
114	6	120	Accepted
111	43	0	Accepted
20	6	30	Accepted
101	43	0	Accepted
135	43	0	Accepted
51	43	0	Accepted
48	6	80	Accepted
97	44	0	Accepted
35	44	0	Accepted
7	44	0	Accepted
121	44	0	Accepted
14	44	0	Accepted
151	7	40	Accepted
117	44	0	Accepted
93	45	0	Accepted
13	45	0	Accepted
53	7	120	Accepted
52	45	0	Accepted
188	45	0	Accepted
157	45	0	Accepted
128	45	0	Accepted
21	7	30	Accepted
173	46	0	Accepted
201	46	0	Accepted
151	46	0	Accepted
198	46	0	Accepted
136	46	0	Accepted
108	46	0	Accepted
164	47	0	Accepted
64	47	0	Accepted
33	47	0	Accepted
135	7	110	Accepted
152	47	0	Accepted
187	47	0	Accepted
186	47	0	Accepted
5	48	0	Accepted
114	48	0	Accepted
141	7	70	Accepted
10	48	0	Accepted
115	48	0	Accepted
128	48	0	Accepted
107	48	0	Accepted
122	48	0	Accepted
176	7	150	Accepted
202	7	90	Accepted
155	49	0	Accepted
29	49	0	Accepted
135	49	0	Accepted
22	50	0	Accepted
68	50	0	Accepted
159	50	0	Accepted
62	50	0	Accepted
94	7	140	Accepted
183	50	0	Accepted
76	50	0	Accepted
78	50	0	Accepted
48	50	0	Accepted
30	7	30	Accepted
17	50	0	Accepted
106	8	120	Accepted
168	8	20	Accepted
82	8	120	Accepted
200	8	20	Accepted
22	8	60	Accepted
92	8	90	Accepted
63	8	60	Accepted
35	25	100	Accepted
97	26	100	Accepted
106	27	60	Accepted
142	27	20	Accepted
6	27	80	Accepted
184	8	80	Accepted
5	8	80	Accepted
161	8	120	Accepted
35	8	150	Accepted
103	8	130	Accepted
25	27	100	Accepted
144	28	200	Accepted
192	29	160	Accepted
122	29	120	Accepted
52	8	140	Accepted
81	8	40	Accepted
93	8	150	Accepted
70	8	100	Accepted
179	8	40	Accepted
40	8	20	Accepted
39	9	80	Accepted
125	30	160	Accepted
118	31	130	Accepted
178	31	60	Accepted
103	32	120	Accepted
176	32	110	Accepted
153	9	170	Accepted
137	9	100	Accepted
124	9	70	Accepted
2	9	30	Accepted
169	9	120	Accepted
192	9	90	Accepted
133	9	110	Accepted
113	9	30	Accepted
79	9	150	Accepted
172	9	90	Accepted
75	9	30	Accepted
43	9	150	Accepted
174	32	100	Accepted
202	10	60	Accepted
182	10	40	Accepted
63	10	170	Accepted
150	10	20	Accepted
64	10	140	Accepted
93	10	40	Accepted
148	10	180	Accepted
5	10	40	Accepted
62	10	60	Accepted
171	10	130	Accepted
154	10	140	Accepted
21	10	20	Accepted
75	33	140	Accepted
93	33	40	Accepted
80	11	60	Accepted
199	11	80	Accepted
200	11	30	Accepted
158	11	20	Accepted
45	11	30	Accepted
175	11	60	Accepted
165	11	120	Accepted
101	11	120	Accepted
88	11	30	Accepted
42	11	80	Accepted
166	11	80	Accepted
84	11	140	Accepted
10	12	140	Accepted
177	12	140	Accepted
153	12	20	Accepted
127	12	80	Accepted
155	12	180	Accepted
179	12	140	Accepted
1	12	130	Accepted
53	12	20	Accepted
132	12	180	Accepted
134	12	60	Accepted
90	12	120	Accepted
157	12	50	Accepted
181	13	230	Accepted
142	13	90	Accepted
11	13	130	Accepted
166	13	60	Accepted
81	13	120	Accepted
132	13	90	Accepted
20	13	90	Accepted
63	13	30	Accepted
169	13	90	Accepted
164	34	100	Accepted
9	13	70	Accepted
33	13	70	Accepted
58	13	60	Accepted
23	13	70	Accepted
103	13	0	Accepted
39	13	0	Accepted
90	13	100	Accepted
154	13	160	Accepted
176	14	60	Accepted
3	14	20	Accepted
66	14	20	Accepted
83	14	130	Accepted
5	34	60	Accepted
150	14	100	Accepted
7	14	40	Accepted
87	14	90	Accepted
198	14	60	Accepted
4	14	60	Accepted
70	15	0	Accepted
94	15	30	Accepted
155	15	150	Accepted
82	15	180	Accepted
186	15	30	Accepted
21	15	30	Accepted
136	15	90	Accepted
124	15	30	Accepted
137	15	30	Accepted
140	34	70	Accepted
68	15	20	Accepted
20	15	20	Accepted
20	16	180	Accepted
147	16	30	Accepted
9	16	40	Accepted
1	16	30	Accepted
188	16	60	Accepted
170	16	60	Accepted
19	16	30	Accepted
83	16	30	Accepted
182	16	30	Accepted
102	16	130	Accepted
120	16	90	Accepted
141	16	0	Accepted
124	16	40	Accepted
128	17	30	Accepted
71	17	0	Accepted
178	35	20	Accepted
123	17	40	Accepted
134	17	30	Accepted
137	17	60	Accepted
188	17	90	Accepted
68	17	40	Accepted
144	17	30	Accepted
72	18	130	Accepted
116	18	0	Accepted
56	18	60	Accepted
105	18	110	Accepted
103	18	120	Accepted
15	18	0	Accepted
140	18	30	Accepted
42	18	100	Accepted
167	18	40	Accepted
45	36	100	Accepted
169	18	120	Accepted
23	18	20	Accepted
60	18	20	Accepted
64	19	40	Accepted
165	19	0	Accepted
46	19	20	Accepted
33	19	100	Accepted
180	19	30	Accepted
84	19	70	Accepted
27	19	90	Accepted
100	19	90	Accepted
57	19	60	Accepted
32	19	60	Accepted
31	19	80	Accepted
147	19	130	Accepted
8	20	170	Accepted
120	20	130	Accepted
103	20	40	Accepted
16	20	120	Accepted
173	20	80	Accepted
23	20	30	Accepted
171	20	40	Accepted
45	20	90	Accepted
19	20	20	Accepted
133	20	50	Accepted
162	20	20	Accepted
195	20	70	Accepted
91	37	60	Accepted
200	21	60	Accepted
153	21	70	Accepted
43	21	80	Accepted
23	21	170	Accepted
48	21	220	Accepted
73	21	190	Accepted
199	21	150	Accepted
126	21	230	Accepted
146	37	40	Accepted
157	21	270	Accepted
60	21	80	Accepted
202	21	110	Accepted
130	21	140	Accepted
107	21	170	Accepted
116	21	30	Accepted
77	21	120	Accepted
42	21	100	Accepted
98	22	90	Accepted
163	22	120	Accepted
39	37	90	Accepted
104	22	110	Accepted
9	22	80	Accepted
143	22	100	Accepted
53	22	30	Accepted
179	22	40	Accepted
23	22	30	Accepted
200	22	40	Accepted
79	22	30	Accepted
194	22	90	Accepted
69	22	40	Accepted
83	22	30	Accepted
118	23	80	Accepted
107	23	20	Accepted
111	23	150	Accepted
14	23	110	Accepted
11	23	130	Accepted
106	23	80	Accepted
115	23	180	Accepted
81	23	150	Accepted
35	23	90	Accepted
43	23	140	Accepted
202	23	60	Accepted
45	23	210	Accepted
16	24	100	Accepted
33	24	80	Accepted
9	24	60	Accepted
185	24	80	Accepted
88	38	200	Accepted
110	24	30	Accepted
155	24	80	Accepted
109	24	90	Accepted
123	24	30	Accepted
53	24	120	Accepted
116	24	30	Accepted
83	24	40	Accepted
130	24	40	Accepted
126	24	30	Accepted
95	24	80	Accepted
60	24	180	Accepted
5	25	60	Accepted
74	25	160	Accepted
54	25	40	Accepted
86	25	0	Accepted
202	25	80	Accepted
168	38	80	Accepted
124	25	100	Accepted
155	25	30	Accepted
4	25	60	Accepted
53	26	120	Accepted
181	26	40	Accepted
143	26	160	Accepted
37	26	20	Accepted
183	26	70	Accepted
127	26	20	Accepted
126	26	190	Accepted
68	26	120	Accepted
96	26	170	Accepted
109	26	40	Accepted
179	26	120	Accepted
93	26	20	Accepted
46	26	60	Accepted
79	26	190	Accepted
94	26	0	Accepted
197	27	40	Accepted
140	27	0	Accepted
173	27	80	Accepted
5	27	40	Accepted
84	27	60	Accepted
80	27	20	Accepted
166	27	30	Accepted
178	27	150	Accepted
35	27	80	Accepted
103	27	100	Accepted
14	27	100	Accepted
59	27	0	Accepted
57	38	100	Accepted
7	28	170	Accepted
66	28	180	Accepted
115	28	140	Accepted
77	28	80	Accepted
4	28	120	Accepted
110	28	130	Accepted
37	28	120	Accepted
13	28	50	Accepted
38	28	150	Accepted
197	38	80	Accepted
155	28	60	Accepted
189	28	120	Accepted
11	28	160	Accepted
43	28	100	Accepted
26	28	30	Accepted
48	29	100	Accepted
72	29	60	Accepted
95	29	60	Accepted
13	29	90	Accepted
113	29	120	Accepted
92	29	20	Accepted
77	29	50	Accepted
162	29	30	Accepted
136	30	70	Accepted
197	30	80	Accepted
151	30	80	Accepted
41	30	130	Accepted
191	30	20	Accepted
5	30	60	Accepted
28	30	40	Accepted
111	30	80	Accepted
60	30	30	Accepted
122	30	0	Accepted
170	30	40	Accepted
23	30	110	Accepted
30	30	0	Accepted
11	30	20	Accepted
2	30	30	Accepted
82	39	200	Accepted
145	40	30	Accepted
50	31	30	Accepted
95	31	60	Accepted
11	31	140	Accepted
56	31	60	Accepted
70	31	30	Accepted
27	31	210	Accepted
60	31	110	Accepted
78	31	200	Accepted
74	31	110	Accepted
9	31	200	Accepted
22	31	80	Accepted
12	40	140	Accepted
8	41	40	Accepted
77	32	90	Accepted
52	32	90	Accepted
95	32	110	Accepted
45	32	180	Accepted
126	32	30	Accepted
99	32	180	Accepted
72	32	220	Accepted
78	32	80	Accepted
60	32	60	Accepted
10	32	80	Accepted
13	32	110	Accepted
151	32	70	Accepted
140	32	60	Accepted
89	41	40	Accepted
23	32	100	Accepted
157	32	110	Accepted
137	32	110	Accepted
62	32	90	Accepted
17	33	130	Accepted
150	33	170	Accepted
143	33	120	Accepted
22	33	200	Accepted
68	33	20	Accepted
3	41	110	Accepted
8	33	100	Accepted
187	33	230	Accepted
35	33	20	Accepted
40	33	140	Accepted
198	33	80	Accepted
2	33	60	Accepted
103	33	100	Accepted
106	33	30	Accepted
166	33	80	Accepted
135	34	180	Accepted
198	34	240	Accepted
125	34	150	Accepted
68	34	30	Accepted
77	34	80	Accepted
149	34	170	Accepted
74	34	150	Accepted
83	34	130	Accepted
15	34	0	Accepted
62	34	80	Accepted
22	34	40	Accepted
142	34	50	Accepted
65	35	120	Accepted
110	35	30	Accepted
116	35	0	Accepted
4	35	120	Accepted
50	35	60	Accepted
72	35	80	Accepted
133	35	70	Accepted
140	35	180	Accepted
18	35	100	Accepted
16	35	120	Accepted
134	35	210	Accepted
171	35	30	Accepted
163	35	30	Accepted
2	43	140	Accepted
169	36	60	Accepted
152	36	140	Accepted
147	36	20	Accepted
125	36	30	Accepted
12	36	90	Accepted
83	36	150	Accepted
100	36	90	Accepted
40	36	30	Accepted
51	36	0	Accepted
123	36	30	Accepted
154	36	70	Accepted
18	36	60	Accepted
61	36	40	Accepted
45	37	90	Accepted
79	43	110	Accepted
143	37	120	Accepted
145	37	20	Accepted
128	37	130	Accepted
102	37	170	Accepted
111	37	100	Accepted
138	37	90	Accepted
51	37	150	Accepted
115	37	170	Accepted
144	37	160	Accepted
82	44	60	Accepted
134	38	70	Accepted
29	38	40	Accepted
175	38	210	Accepted
95	38	100	Accepted
154	38	80	Accepted
113	38	80	Accepted
10	38	100	Accepted
189	38	120	Accepted
38	38	80	Accepted
159	38	210	Accepted
108	38	20	Accepted
44	38	130	Accepted
125	39	90	Accepted
31	39	140	Accepted
85	39	80	Accepted
40	39	120	Accepted
89	39	100	Accepted
70	39	90	Accepted
6	39	180	Accepted
136	39	60	Accepted
94	39	100	Accepted
78	39	0	Accepted
112	39	30	Accepted
29	39	80	Accepted
132	39	150	Accepted
98	39	70	Accepted
69	39	160	Accepted
114	39	160	Accepted
2	40	20	Accepted
36	40	40	Accepted
31	40	40	Accepted
3	40	100	Accepted
198	45	190	Accepted
7	40	60	Accepted
85	40	100	Accepted
72	40	80	Accepted
118	40	40	Accepted
19	40	40	Accepted
169	40	170	Accepted
93	41	200	Accepted
180	41	120	Accepted
58	41	40	Accepted
109	41	160	Accepted
171	41	40	Accepted
128	41	30	Accepted
140	41	100	Accepted
71	46	30	Accepted
162	41	160	Accepted
18	41	80	Accepted
156	42	80	Accepted
96	42	70	Accepted
128	42	40	Accepted
1	42	100	Accepted
22	42	120	Accepted
189	42	0	Accepted
113	42	160	Accepted
198	42	120	Accepted
89	42	160	Accepted
25	42	240	Accepted
63	42	20	Accepted
116	42	80	Accepted
190	42	20	Accepted
85	42	110	Accepted
40	42	0	Accepted
23	43	270	Accepted
119	43	130	Accepted
186	43	80	Accepted
198	43	160	Accepted
120	46	90	Accepted
56	46	90	Accepted
193	43	40	Accepted
54	43	170	Accepted
137	43	140	Accepted
177	43	60	Accepted
189	43	40	Accepted
81	43	40	Accepted
144	43	170	Accepted
8	43	20	Accepted
122	43	160	Accepted
66	43	190	Accepted
196	46	0	Accepted
194	44	90	Accepted
116	44	40	Accepted
147	44	60	Accepted
21	44	20	Accepted
188	44	70	Accepted
52	44	60	Accepted
5	44	90	Accepted
71	44	30	Accepted
193	44	60	Accepted
1	44	60	Accepted
144	44	0	Accepted
44	44	60	Accepted
149	45	40	Accepted
15	45	40	Accepted
175	47	160	Accepted
174	45	230	Accepted
42	45	20	Accepted
193	45	120	Accepted
113	45	30	Accepted
73	45	120	Accepted
109	45	60	Accepted
118	45	40	Accepted
115	45	90	Accepted
41	45	60	Accepted
152	45	60	Accepted
44	45	30	Accepted
8	46	120	Accepted
103	46	60	Accepted
180	46	60	Accepted
41	46	90	Accepted
60	46	60	Accepted
21	46	150	Accepted
130	46	60	Accepted
86	46	30	Accepted
43	46	30	Accepted
136	47	40	Accepted
199	47	120	Accepted
81	47	100	Accepted
50	47	150	Accepted
149	47	80	Accepted
122	47	140	Accepted
30	47	80	Accepted
102	47	120	Accepted
20	47	0	Accepted
92	47	40	Accepted
59	47	20	Accepted
157	47	20	Accepted
34	48	50	Accepted
170	48	20	Accepted
56	48	40	Accepted
140	48	60	Accepted
151	48	40	Accepted
201	48	20	Accepted
137	48	0	Accepted
43	48	60	Accepted
131	48	50	Accepted
99	48	20	Accepted
96	48	50	Accepted
78	48	50	Accepted
138	49	0	Accepted
64	49	100	Accepted
143	49	70	Accepted
43	49	80	Accepted
46	49	180	Accepted
183	49	80	Accepted
142	49	80	Accepted
61	49	40	Accepted
6	49	70	Accepted
56	49	120	Accepted
111	49	140	Accepted
14	49	120	Accepted
35	49	40	Accepted
108	49	30	Accepted
154	49	140	Accepted
137	49	180	Accepted
131	49	80	Accepted
42	50	130	Accepted
96	50	60	Accepted
156	50	50	Accepted
51	50	30	Accepted
20	50	230	Accepted
169	50	130	Accepted
175	50	150	Accepted
41	50	60	Accepted
185	50	0	Accepted
130	50	60	Accepted
\.


--
-- TOC entry 4947 (class 0 OID 64527)
-- Dependencies: 220
-- Data for Name: professor; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.professor (prof_id, first_name, last_name, username, password, created_at) FROM stdin;
1	Le	Hau	iamhauoftoday	toiyeunhieuem	2024-12-03
2	NGUYEN	MINH	NGUYENCONGMINH	123	2024-12-18
3	PHAM	HOANG	MUNWIND	abc	2024-12-18
\.


--
-- TOC entry 4949 (class 0 OID 64532)
-- Dependencies: 222
-- Data for Name: question; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.question (question_id, title, description, level_id, prof_id) FROM stdin;
2	Simmulation Priority Queue	A Database D stores elements which are positive integers. Perform a sequence of operations over D including:\\nPUSH e: add the element e to D (e is a positive integer)\\nPOP: remove the element having smallest value out of D and return this element\\nInput\\nEach line contain the information about one operation (the format is described above)\\nThe input is terminated by a line containing the character #\\nOutput\\nWrite the result of the POP operation on separate lines	2	1
3	Binary sequence generation	Given an integer n, write a program that generates all the binary sequences of length n in a lexicographic order.\\nInput\\nLine 1: contains an integer n (1 <= n <= 20)\\nOutput\\nWrite binary sequences in a lexicographic order, each sequence in a line	1	1
4	Range Minimum Query	Given a sequence of n integers a[0], a[1], ..., a[n-1], we denote rmq(i, j) as the minimum element of the subsequence a[i], a[i+1], ..., a[j]. Given m pairs (i1, j1), (i2, j2), ..., (im, jm), compute the sum Q = rmq(i1, j1) + rmq(i2, j2) + ... + rmq(im, jm).\\nInput\\nLine 1: n (1 <= n <= 10^6)\\nLine 2: a[0], a[1], ..., a[n-1] (1 <= ai <= 10^6)\\nLine 3: m (1 <= m <= 10^6)\\nNext m lines: each line contains two integers ik and jk (0 <= ik < jk < n)\\nOutput\\nWrite the value of Q	3	1
5	CHECK FOR EXISTENCE	Given a sequence of integers A1, A2, ..., An, for each integer Ai, check if there exists any Aj such that Aj = Ai with j < i.\\nInput\\nThe first line contains the number n (1 ≤ n ≤ 100,000).\\nThe second line contains n integers A1, A2, ..., An (1 ≤ Ai ≤ 1,000,000,000).\\nOutput\\nPrint n lines, where the i-th line contains 1 if there exists any Aj = Ai with j < i, otherwise print 0.\\nExample\\ninput\\n5\\n1 4 3 1 4\\noutput\\n0\\n0\\n0\\n1\\n1	2	2
6	Add two integers	Compute the sum of two integers 𝑎 a and 𝑏 b.\\nInput\\nLine 1 contains two integers 𝑎 a and 𝑏 b (0 ≤ 𝑎 , 𝑏 a,b ≤ 1 0 19 10 19 ).\\nOutput\\nWrite the sum of 𝑎 a and 𝑏 b.\\nExample\\nInput\\n3 5\\nOutput\\n8	1	2
7	Sum pair of sequence equal to a number	Given a sequence 𝑎 1 , 𝑎 2 , . . . , 𝑎 𝑛 a 1 ​ ,a 2 ​ ,...,a n ​ where all elements are distinct and a positive integer 𝑀 M. Count the number of pairs 𝑄 Q such that 1 ≤ 𝑖 < 𝑗 ≤ 𝑛 1≤i<j≤n and 𝑎 𝑖 + 𝑎 𝑗 = 𝑀 a i ​ +a j ​ =M.\\n\\nInput\\nLine 1: Contains 𝑛 n and 𝑀 M (1 ≤ 𝑛 , 𝑀 n,M ≤ 1,000,000).\\nLine 2: Contains 𝑎 1 , 𝑎 2 , . . . , 𝑎 𝑛 a 1 ​ ,a 2 ​ ,...,a n ​ .\\n\\nOutput\\nPrint the value of 𝑄 Q.\\n\\nExample\\nInput\\n5 6\\n5 2 1 4 3\\nOutput\\n2	2	3
8	Max Subsequence No 2 adjacent elements selected	Given a sequence of positive integers 𝑎 1 , 𝑎 2 , . . . , 𝑎 𝑛 a 1 ​ ,a 2 ​ ,...,a n ​ , select a subset of elements such that the sum is maximal and no two adjacent elements are selected.\\n\\nInput\\nLine 1: Contains a positive integer 𝑛 n (1 ≤ 𝑛 n ≤ 100,000).\\nLine 2: Contains 𝑎 1 , 𝑎 2 , . . . , 𝑎 𝑛 a 1 ​ ,a 2 ​ ,...,a n ​ (1 ≤ 𝑎 𝑖 a i ​ ≤ 1,000).\\n\\nOutput\\nWrite the sum of the elements in the subset found.\\n\\nExample\\nInput\\n5\\n2 5 4 6 7\\nOutput\\n13\\n\\nExplanation\\nThe subset found is: {2, 4, 7}	2	3
9	Find sum of numbers	Write a program to compute the sum of 𝑛 n integers entered from the keyboard.\\n\\nInput\\n- The first line contains 𝑛 n: the number of integers to be entered (1 ≤ 𝑛 n ≤ 10).\\n- The second line contains 𝑎 1 , 𝑎 2 , . . . , 𝑎 𝑛 a 1 ​ ,a 2 ​ ,...,a n ​ : the integers.\\n\\nOutput\\n- Print the sum of the integers.\\n\\nExample\\nInput\\n3\\n1 2 3\\nOutput\\n6	1	2
10	Gold mining	The Kingdom ALPHA has 𝑛 n warehouses of gold located on a straight line, numbered 1 , 2 , . . . , 𝑛 1,2,...,n. Warehouse 𝑖 i contains an amount of gold 𝑎 𝑖 a i ​ (a non-negative integer) and is located at coordinate 𝑖 i ( 𝑖 = 1 , . . . , 𝑛 i=1,...,n). The King of ALPHA opens a competition for hunters to find a subset of warehouses with the largest total amount of gold while satisfying the following conditions:\\n- The distance between any two selected warehouses must be greater than or equal to 𝐿 1 L 1 ​ and less than or equal to 𝐿 2 L 2 ​ .\\n\\nInput\\n- Line 1: Contains 𝑛 n, 𝐿 1 L 1 ​ , and 𝐿 2 L 2 ​ ( 1 ≤ 𝑛 ≤ 1 , 000 , 000 1≤n≤1,000,000, 1 ≤ 𝐿 1 ≤ 𝐿 2 ≤ 𝑛 1≤L 1 ​ ≤L 2 ​ ≤n).\\n- Line 2: Contains 𝑛 n integers 𝑎 1 , 𝑎 2 , . . . , 𝑎 𝑛 a 1 ​ ,a 2 ​ ,...,a n ​ .\\n\\nOutput\\n- Print a single integer denoting the total amount of gold of the selected warehouses.\\n\\nExample\\nInput\\n\\n6 2 3\\n3 5 9 6 7 4\\n\\nOutput\\n\\n19\\n	3	1
\.


--
-- TOC entry 4950 (class 0 OID 64537)
-- Dependencies: 223
-- Data for Name: question_contest; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.question_contest (question_id, contest_id, created_at) FROM stdin;
2	1	2024-12-08
3	1	2024-12-09
7	1	2024-12-19
10	1	2024-12-19
9	1	2024-12-19
6	1	2024-12-19
3	2	2024-12-19
5	2	2024-12-19
2	2	2024-12-19
9	2	2024-12-19
4	2	2024-12-19
10	3	2024-12-19
4	3	2024-12-19
9	3	2024-12-19
8	3	2024-12-19
7	4	2024-12-19
9	4	2024-12-19
10	4	2024-12-19
5	4	2024-12-19
2	4	2024-12-19
2	5	2024-12-19
8	5	2024-12-19
7	5	2024-12-19
6	5	2024-12-19
9	6	2024-12-19
8	6	2024-12-19
7	6	2024-12-19
10	6	2024-12-19
4	7	2024-12-19
2	7	2024-12-19
8	7	2024-12-19
6	8	2024-12-19
10	8	2024-12-19
3	8	2024-12-19
9	8	2024-12-19
5	8	2024-12-19
4	9	2024-12-19
8	9	2024-12-19
5	9	2024-12-19
4	10	2024-12-19
5	10	2024-12-19
9	10	2024-12-19
3	10	2024-12-19
7	11	2024-12-19
3	11	2024-12-19
8	11	2024-12-19
5	11	2024-12-19
9	12	2024-12-19
4	12	2024-12-19
5	12	2024-12-19
6	12	2024-12-19
6	13	2024-12-19
4	13	2024-12-19
7	13	2024-12-19
8	13	2024-12-19
2	13	2024-12-19
3	14	2024-12-19
6	14	2024-12-19
7	14	2024-12-19
7	15	2024-12-19
2	15	2024-12-19
8	15	2024-12-19
9	15	2024-12-19
7	16	2024-12-19
5	16	2024-12-19
8	16	2024-12-19
4	16	2024-12-19
2	17	2024-12-19
7	17	2024-12-19
3	17	2024-12-19
7	18	2024-12-19
9	18	2024-12-19
10	18	2024-12-19
3	18	2024-12-19
8	19	2024-12-19
5	19	2024-12-19
4	19	2024-12-19
3	19	2024-12-19
3	20	2024-12-19
10	20	2024-12-19
5	20	2024-12-19
8	20	2024-12-19
2	21	2024-12-19
4	21	2024-12-19
6	21	2024-12-19
5	21	2024-12-19
8	21	2024-12-19
5	22	2024-12-19
2	22	2024-12-19
4	22	2024-12-19
10	23	2024-12-19
7	23	2024-12-19
3	23	2024-12-19
8	23	2024-12-19
8	24	2024-12-19
4	24	2024-12-19
5	24	2024-12-19
3	25	2024-12-19
8	25	2024-12-19
10	25	2024-12-19
10	26	2024-12-19
5	26	2024-12-19
6	26	2024-12-19
3	26	2024-12-19
10	27	2024-12-19
9	27	2024-12-19
5	27	2024-12-19
3	28	2024-12-19
5	28	2024-12-19
7	28	2024-12-19
9	28	2024-12-19
8	28	2024-12-19
6	29	2024-12-19
4	29	2024-12-19
8	29	2024-12-19
7	29	2024-12-19
10	30	2024-12-19
9	30	2024-12-19
4	30	2024-12-19
5	30	2024-12-19
7	31	2024-12-19
9	31	2024-12-19
4	31	2024-12-19
8	31	2024-12-19
10	32	2024-12-19
2	32	2024-12-19
4	32	2024-12-19
8	32	2024-12-19
6	33	2024-12-19
7	33	2024-12-19
5	33	2024-12-19
10	33	2024-12-19
4	33	2024-12-19
5	34	2024-12-19
3	34	2024-12-19
2	34	2024-12-19
4	34	2024-12-19
7	34	2024-12-19
6	35	2024-12-19
4	35	2024-12-19
7	35	2024-12-19
8	35	2024-12-19
2	36	2024-12-19
8	36	2024-12-19
5	36	2024-12-19
6	36	2024-12-19
3	37	2024-12-19
2	37	2024-12-19
10	37	2024-12-19
5	37	2024-12-19
4	38	2024-12-19
8	38	2024-12-19
10	38	2024-12-19
3	38	2024-12-19
4	39	2024-12-19
9	39	2024-12-19
8	39	2024-12-19
3	39	2024-12-19
7	39	2024-12-19
2	40	2024-12-19
4	40	2024-12-19
9	40	2024-12-19
3	40	2024-12-19
10	41	2024-12-19
4	41	2024-12-19
2	41	2024-12-19
4	42	2024-12-19
6	42	2024-12-19
3	42	2024-12-19
2	42	2024-12-19
7	43	2024-12-19
3	43	2024-12-19
5	43	2024-12-19
4	43	2024-12-19
6	43	2024-12-19
7	44	2024-12-19
2	44	2024-12-19
3	44	2024-12-19
8	44	2024-12-19
6	45	2024-12-19
5	45	2024-12-19
3	45	2024-12-19
10	45	2024-12-19
7	45	2024-12-19
2	46	2024-12-19
5	46	2024-12-19
8	46	2024-12-19
7	46	2024-12-19
4	47	2024-12-19
10	47	2024-12-19
7	47	2024-12-19
3	47	2024-12-19
6	48	2024-12-19
8	48	2024-12-19
9	48	2024-12-19
10	49	2024-12-19
7	49	2024-12-19
3	49	2024-12-19
4	49	2024-12-19
10	50	2024-12-19
8	50	2024-12-19
3	50	2024-12-19
6	50	2024-12-19
2	50	2024-12-19
\.


--
-- TOC entry 4952 (class 0 OID 64542)
-- Dependencies: 225
-- Data for Name: student; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student (student_id, first_name, last_name, username, password, created_at) FROM stdin;
1	Nguyen	Minh	umarunn	umarunnn	2024-12-03
2	Nguyen	Minh	munwind	123456789	2024-12-07
3	rgktr	erptis	izxhrevn	xquezxkugr	2024-12-19
4	oohrh	udidgv	htjhyezk	yhpfxwgprp	2024-12-19
5	Le	Hau	hauoftoday	hauchoigai	2024-12-19
6	phqgh	umeayl	nlfdxfir	cvscxggbwk	2024-12-19
7	fnqdu	xwfnfo	zvsrtkjp	repggxrpnr	2024-12-19
8	vystm	wcysyy	cqpevike	ffmznimkka	2024-12-19
9	svwsr	enzkyc	xfxtlsgy	psfadpooef	2024-12-19
10	xzbco	ejuvpv	aboygpoe	ylfpbnpljv	2024-12-19
11	rvipy	amyehw	qnqrqpmx	ujjloovaow	2024-12-19
12	uxwhm	sncbxc	oksfzkva	txdknlyjyh	2024-12-19
13	fixjs	wnkkuf	nuxxzrzb	mnmgqooket	2024-12-19
14	lyhnk	oaugzq	rcddiute	iojwayyzpv	2024-12-19
15	scmps	ajlfvg	ubfaaovl	zylntrkdcp	2024-12-19
16	wsrte	sjwhdi	zcobzcnf	wlqijtvdwv	2024-12-19
17	xhrcb	ldvgyl	wgbusbmb	orxtlhcsmp	2024-12-19
18	xohgm	gnkeuf	dxotogbg	xpeyanfetc	2024-12-19
19	ukepz	shklju	gggekjdq	zjenpevqgx	2024-12-19
20	iepjs	rdzjaz	ujllchhb	fqmkimwzob	2024-12-19
21	iwybx	duunfs	ksrsrtek	mqdcyzjeeu	2024-12-19
22	hmsrq	coziji	pfioneed	dpszrnavym	2024-12-19
23	mtatb	dzqsoe	muvnppps	uacbazuxmh	2024-12-19
24	ecthl	egrpun	kdmbppwe	qtgjoparmo	2024-12-19
25	wzdqy	oxytjb	bhawdydc	prjbxphooh	2024-12-19
26	pkwqy	uhrqzh	nbnfuvqn	qqlrzjpxio	2024-12-19
27	gvlie	xdzuzo	srkrusvo	jbrzmwzpow	2024-12-19
28	kjile	fraamd	igpnpuuh	gxpqnjwjmw	2024-12-19
29	axxmn	snhhlq	qrzudltf	zotcjtnzxu	2024-12-19
30	glsds	mzcnoc	kvfajfrm	xothowkbjz	2024-12-19
31	wucwl	jfrimp	myhchzri	wkbarxbgfc	2024-12-19
32	bceyh	jugixw	tbvtrehb	bcpxifbxvf	2024-12-19
33	bcgkc	fqckco	tzgkubmj	rmbsztsshf	2024-12-19
34	roefw	sjrxjh	guzyupzw	weiqurpixi	2024-12-19
35	qfldu	uveoow	qcudhnef	njhaimuczf	2024-12-19
36	skuid	uburis	wtbrecuy	kabfcvkdze	2024-12-19
37	ztoid	ukuhjz	efczzzbf	kqdpqzikfo	2024-12-19
38	bucdh	thxdjg	kjelrlpa	xamceroswi	2024-12-19
39	tdptp	cclifk	eljytihr	cqaybnefxn	2024-12-19
40	xvgze	dyyhng	ycdrudmp	hmeckotrwo	2024-12-19
41	spofg	hfozqv	lqfxwwkm	fxdyygmdca	2024-12-19
42	szsgo	vsodkj	ghcwmbmx	rmhuyfyqga	2024-12-19
43	jqkck	lznayx	qkqoyzwm	yubzazcpkh	2024-12-19
44	ktkyd	zivcuy	purfmbis	gekyrgzvxd	2024-12-19
45	hpoam	vafyra	rxsvkhtq	dihersigbh	2024-12-19
46	zjzuj	xmmysp	naraewke	gjccvhhrjv	2024-12-19
47	bjtsq	djootg	pknfpfyc	gfieowqrww	2024-12-19
48	wpzsq	metoge	pspxnvji	upalyynmkm	2024-12-19
49	nuvkl	hsecdw	racgfmzk	gipdfodkjm	2024-12-19
50	jqwiq	puoqhi	mvfvuzwy	vijgfullkj	2024-12-19
51	duhsj	afbtlk	mfqrmyjf	jnhhssqcty	2024-12-19
52	dteam	dcjbpr	htnegyiw	xgcjwlgrsm	2024-12-19
53	eaear	wtvjsj	baoiojlw	hypnvruiho	2024-12-19
54	swkif	ygtydh	acwyhsge	wzmtgonzlt	2024-12-19
55	jhgau	hnihre	qgjfwkjs	mtpjhaefqz	2024-12-19
56	aauld	rchjcc	dyrfvvri	vuyeegfivd	2024-12-19
57	rcygu	rqdred	akubnfgu	proqylobcw	2024-12-19
58	qxkzm	ausjgm	hcmhgdnm	phnqkamhur	2024-12-19
59	ktrff	aclvgr	zkkldacl	lteojomonx	2024-12-19
60	rqyjz	ginrnn	zwacxxae	drwudxzrfu	2024-12-19
61	sewjt	boxvyn	fhkstcen	aumnddxfdm	2024-12-19
62	vzcau	tdcckx	aaydzsxt	tobbgqngvv	2024-12-19
63	pjgoj	oglmkx	gbfcpypc	kqchbddzwr	2024-12-19
64	xbzmq	rlxvob	twhxginf	gfrcclmznm	2024-12-19
65	jugww	bsqfci	hubsjoll	msqsghmcph	2024-12-19
66	elsot	flbgsf	npcuzsru	pchynvzhcp	2024-12-19
67	qugri	wniqxd	fjpwpxfb	lkpnpeelfj	2024-12-19
68	mtkuq	pzomwn	lmbupmkt	lptndmpdsy	2024-12-19
69	dsgvf	penemw	borifsuq	hceskmkhss	2024-12-19
70	mvnon	wafxwh	gbibabvq	opqfoviuss	2024-12-19
71	qfqwe	htxdzu	jtlntxmr	jxxwtlggky	2024-12-19
72	tbiol	ydnilq	adojskkv	fxahhjmboc	2024-12-19
73	ljari	ntdwcl	dvdxropb	yjzwyyojuo	2024-12-19
74	thwml	vrglfz	dzdbtubx	uoffvncrsw	2024-12-19
75	saznm	oijoiv	vgobqpnc	kwvnhkebmt	2024-12-19
76	dhvyg	kjisux	hatmuudq	bhmknhfxax	2024-12-19
77	qxkjl	zzqtsj	faeedfuu	jkolxjoqkd	2024-12-19
78	vfepv	lhvhrw	tfdukxff	jpsswyxlij	2024-12-19
79	jhevr	yxozba	fpfmowgr	gonuatdqla	2024-12-19
80	hyggy	ljddjh	mltedzlo	dsrkeutgtn	2024-12-19
81	kntar	jkpxin	ovgzdthu	nwooxvjjmp	2024-12-19
82	svknh	kwjopm	mlebksuc	vzqlyqnwcm	2024-12-19
83	bvbhr	mlowpj	bwyvwtgt	oqnmicxapz	2024-12-19
84	arknn	xtuufa	rzrosdqw	smtcjghecq	2024-12-19
85	udosr	tjxyaa	ykqrxycr	xuwjxnpqjn	2024-12-19
86	bkcpd	mokalx	apemvbql	zsvxzkutap	2024-12-19
87	pwgzp	dpyzkz	cvbntcvf	xsxpjaoxtf	2024-12-19
88	hvxxy	tgokrc	xaetauqg	ndmphwzyia	2024-12-19
89	yabjr	qgeppx	yjsttyzu	vldvybsuxk	2024-12-19
90	bmfzv	rtnovi	dznpghoz	vafmsnsnqi	2024-12-19
91	vmvub	cwtfsr	qtmknepb	howejazhkw	2024-12-19
92	cmmtp	ixxxlz	qysxtwwt	aidyaxyqle	2024-12-19
93	prxib	exxyfv	sddygthc	uyyfwpjsfy	2024-12-19
94	bglgz	mbinta	ttnhodto	npyzwotkgn	2024-12-19
95	guphp	kxeato	wzabsdnv	qhkfcmofis	2024-12-19
96	frfqg	vpmvor	pjfzslzm	pjjnehrykx	2024-12-19
97	jzubu	acclfk	cyzobght	uoxrajvpre	2024-12-19
98	cwgxx	pswcgm	mvedewdm	fnqwcuqdsc	2024-12-19
99	iliqe	cihlui	lgmfcswt	wkkxlcbhqk	2024-12-19
100	vcswj	ebkrjl	pgfgratz	bsguvzifnh	2024-12-19
101	yxwjs	javwau	xpannamx	jdvzuhnacz	2024-12-19
102	yhepw	zolhus	lrkvwpnv	gzmiizwudw	2024-12-19
103	dfzlk	tbqdxg	yyiudsjv	ezkmesbjlk	2024-12-19
104	yerta	hnexhu	qmjicbmu	sqdklasolw	2024-12-19
105	jxptx	xeumzf	wyucpabq	seffunqpkf	2024-12-19
106	nnbec	bbcjpd	yjlibitl	lplxelrdke	2024-12-19
107	xdtqu	vpttey	htlqlbbb	voqozkynay	2024-12-19
108	yrbaq	myjhzx	ndsiyfse	xwbioewqvq	2024-12-19
109	rtcdl	pqmvji	fvgymkgo	tzjmnzqtmr	2024-12-19
110	pndev	nmthji	tsspaqnj	rdoyjwpyat	2024-12-19
111	mleyq	svkpam	svbmvxrl	livfedkjig	2024-12-19
112	avyxj	veqvrb	acuigaip	yhbbxipbzn	2024-12-19
113	cwhrb	lirizx	oqptqqwe	aafjeqiozp	2024-12-19
114	yfauu	qmvhxk	mnxmsyam	ptlzanotls	2024-12-19
115	lwuht	fqjrrw	bwhmqhzk	hdkcrfvbei	2024-12-19
116	yipvf	vpzhyu	jabtqwwt	bkdogkemhi	2024-12-19
117	byxrn	xsxrzl	etbqexkr	qoiernaplq	2024-12-19
118	yjpqo	ubvjse	balwnksv	loidzfpirw	2024-12-19
119	ycztw	zzvewx	otakudkp	edupkczlhw	2024-12-19
120	uskdn	evdcpl	bklpjmpf	dcyqtrcvvv	2024-12-19
121	trffv	pekkqm	cupryjau	teuvczvict	2024-12-19
122	hrxsx	clprgd	lwxfaiga	yrueicufdi	2024-12-19
123	amhtk	bxotdi	rxxgvzqm	eyrovfichq	2024-12-19
124	nivfj	zauqfd	ftgmopsr	gpugxtuhlc	2024-12-19
125	vspih	azrssf	szwxbqmu	rwmxcdbhum	2024-12-19
126	rgjqm	vnkyrt	nsjvwzxs	sqxnjomuyj	2024-12-19
127	njuwr	syxwqy	yxcszpok	lwjdrltbsc	2024-12-19
128	iedpi	wlaqig	esjsqhsj	lrglmwanrx	2024-12-19
129	rfnwa	kztgjh	xaunfqjv	xiohnjqrjs	2024-12-19
130	hymdo	vwgefh	jesvhtiz	iojljdpmox	2024-12-19
131	byuyo	pqjkzt	vjgkwxke	wpzhbjsuth	2024-12-19
132	syoef	jgwwye	ozluhmga	bbsqrhcrtx	2024-12-19
133	mjvca	xxsufa	hyyayzkh	uhjrjsvoqh	2024-12-19
134	tydwp	bszxsb	ziyrvgqm	lunwscpirz	2024-12-19
135	fcbts	eplkgw	fkhrouoy	srwmqojahy	2024-12-19
136	qmfev	sdcomr	yhgdmlxu	kwyzcprskw	2024-12-19
137	gxuls	uckbse	pjeiszsg	cezwapqrvl	2024-12-19
138	wigro	vjcdzx	xphqlsrz	ihmgzrioqr	2024-12-19
139	qetkz	fbldji	emsfzbhz	fnwywmxxgd	2024-12-19
140	pylra	xglmtb	iylbhcwh	lsyoyhgmgo	2024-12-19
141	pprza	xqmoms	yhgagiup	jqbzxthtop	2024-12-19
142	otmit	nqwtoe	tonxwzgh	utifklgklr	2024-12-19
143	nuwkm	syqcpu	ivahqatm	sckmaalkic	2024-12-19
144	snxuc	ovtykr	xawzadjx	wxqmndhldt	2024-12-19
145	txskn	xteznj	sqtfbccf	qmwhbvssii	2024-12-19
146	gvijs	uxiica	ahmkwywt	tjzppkwlbm	2024-12-19
147	jahtp	utiebp	bbmuegyr	hlthxwgjpr	2024-12-19
148	wvhsh	zyavqy	ecztozoa	bnanhrrbdd	2024-12-19
149	ndodx	euiozi	oiuozxqt	ihwauroqrd	2024-12-19
150	qwcvl	xzipod	iispqnzo	mcwvaptgrg	2024-12-19
151	dfnyy	tkwwqq	tmiuuyvg	aihfshccxh	2024-12-19
152	uuyyh	tgdglf	ciebduto	eunfhdaxph	2024-12-19
153	bsywz	tpwjng	jncpxrjv	bvccefkbem	2024-12-19
154	gsdym	zmmkwd	ehfkruqb	yvecmpesro	2024-12-19
155	mdxll	ubryye	shqlzmre	wqnkqitxgi	2024-12-19
156	igqus	kwtczn	lterxblt	zydyzvahnk	2024-12-19
157	ixjwz	ztdjpq	suowkvfc	cockvrjbfr	2024-12-19
158	jpcgd	jdrwdn	posrjgdr	qrvqtvppaz	2024-12-19
159	hltjq	vcclpe	ztsjpynz	frotqpoxmw	2024-12-19
160	hhwew	nvcbvd	kuzififr	twqqeojueq	2024-12-19
161	bnskw	zeewzk	aojursqg	sczvhhujzu	2024-12-19
162	migof	hwbkkf	luwzkctk	agxksmfauw	2024-12-19
163	insjl	sojtrx	hwmhlvby	pecjeiwwst	2024-12-19
164	neuiq	ubpgug	wgnmikdw	ickdilsnpd	2024-12-19
165	qsvmt	erdfbl	hwbafbga	rcsfijylbi	2024-12-19
166	imofg	xeirpb	tywqzapk	kcafcomvnt	2024-12-19
167	mdhzx	lefppy	ebeoeqzn	bhycwmfyaq	2024-12-19
168	qiann	yhqoui	zveavgzj	woblsgwnkv	2024-12-19
169	jlniv	qcwvzx	tcthynmu	xqkwwmtfis	2024-12-19
170	gglgc	oxpipy	tdbamryk	bokmwgsddp	2024-12-19
171	qkrzy	jchztm	iepagwhr	oqkhwudbci	2024-12-19
172	hpqwa	qzxugk	vakvlavk	swfzsdbvqi	2024-12-19
173	dhtbc	deytmp	phkuhsxo	rpufwhjrut	2024-12-19
174	ksslh	lrxlyd	xvkosagg	mpbgzvbafa	2024-12-19
175	zjohq	sswtor	ckqaxsre	hnrlyjiwtm	2024-12-19
176	hglko	zfkmmx	tyvoxhfk	xopvybjzox	2024-12-19
177	hzubd	ntoamz	ottcjtue	gmpqkcdbbg	2024-12-19
178	ckjqt	ebichz	npprqisw	bdhoyncsae	2024-12-19
179	tlgbf	viocfw	xwdrnlff	bfhvyxzukj	2024-12-19
180	wocyh	zqjzdh	tbrrrllk	tchfnctpir	2024-12-19
181	nawon	ydwwvu	abuqcimc	nlhqodemak	2024-12-19
182	munma	xiomke	ywcofqbk	dmzoizgqip	2024-12-19
183	zayix	rydwso	vhztkgzs	kwptkqcexr	2024-12-19
184	nnxsk	ywndqi	zlzklnis	samqazhlnd	2024-12-19
185	nvilt	koiafm	eicgguzx	hrdjzzheru	2024-12-19
186	swavn	vslono	asrudrnl	dkldkfztag	2024-12-19
187	ienat	jzwxcl	kkulncaq	ptoneqlnbt	2024-12-19
188	oddbm	ivazxz	mcojdhis	wkaxiagtut	2024-12-19
189	afrsv	pphura	aaixztwd	yruumqadje	2024-12-19
190	pvvcv	oidwmt	pbnmquio	piwpuwczda	2024-12-19
191	pdzgh	avviyi	rojnolso	wrmvvjiqsw	2024-12-19
192	ricmz	sxavdq	amnfhwfg	eohskkefut	2024-12-19
193	xxibh	pulnlw	xqwwzdgd	jgeqwapbhl	2024-12-19
194	pudoe	mnntpo	uahgxjhz	jbeplttria	2024-12-19
195	bwucr	jmbvbo	zvmxobat	khqsqchlht	2024-12-19
196	bofui	kwafkc	owuuntfh	pkdeyhokqu	2024-12-19
197	wqvwt	thhhug	jzmfeuin	ipbncizock	2024-12-19
198	aadal	ljreqt	khudblpr	zlsrwxoccs	2024-12-19
199	lutwq	zsqtij	vcwnpflr	lukdiaohqj	2024-12-19
200	hragl	griykl	dkdfrdrx	jstcwrsxgy	2024-12-19
201	wfnhc	bkpmes	upmtrvip	fbktbwzfah	2024-12-19
202	oevnh	xbrhhf	obgywcvh	ktdoxqteki	2024-12-19
203	wwurz	blmldl	fibdvemu	nnlxubykvv	2024-12-19
\.


--
-- TOC entry 4954 (class 0 OID 64547)
-- Dependencies: 227
-- Data for Name: submission; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.submission (submission_id, student_id, question_id, contest_id, created_at, evaluation_point, status) FROM stdin;
22	73	9	1	2024-12-19	20	Accepted
23	39	10	1	2024-12-19	40	Partial
24	39	7	1	2024-12-19	60.0	Partial
43	50	10	1	2024-12-19	80	Partial
44	50	2	1	2024-12-19	0	Failed
45	50	7	1	2024-12-19	60.0	Partial
46	50	9	1	2024-12-19	0	Failed
47	50	3	1	2024-12-19	40	Partial
48	68	10	1	2024-12-19	40	Partial
49	52	3	1	2024-12-19	60	Accepted
50	52	9	1	2024-12-19	0	Failed
69	65	5	2	2024-12-19	30.0	Partial
70	65	2	2	2024-12-19	0	Failed
71	154	2	2	2024-12-19	0	Failed
72	154	4	2	2024-12-19	80	Partial
73	154	3	2	2024-12-19	20	Partial
92	117	2	2	2024-12-19	0	Failed
93	117	9	2	2024-12-19	0	Failed
94	14	5	2	2024-12-19	60.0	Partial
95	14	2	2	2024-12-19	60.0	Accepted
96	40	4	2	2024-12-19	0	Failed
97	40	3	2	2024-12-19	20	Partial
98	68	4	2	2024-12-19	40	Partial
117	176	4	3	2024-12-19	80	Partial
118	1	10	3	2024-12-19	40	Partial
119	173	10	3	2024-12-19	80	Partial
120	173	4	3	2024-12-19	40	Partial
121	173	9	3	2024-12-19	0	Failed
122	40	10	3	2024-12-19	80	Partial
142	153	10	4	2024-12-19	0	Failed
143	55	2	4	2024-12-19	60.0	Accepted
144	55	5	4	2024-12-19	60.0	Partial
145	55	7	4	2024-12-19	30.0	Partial
166	125	6	5	2024-12-19	40	Partial
167	125	2	5	2024-12-19	30.0	Partial
168	125	8	5	2024-12-19	60.0	Partial
169	105	2	5	2024-12-19	60.0	Accepted
170	105	7	5	2024-12-19	60.0	Partial
171	179	6	5	2024-12-19	0	Failed
190	8	10	6	2024-12-19	40	Partial
191	196	7	6	2024-12-19	90.0	Accepted
192	167	10	6	2024-12-19	80	Partial
193	81	8	6	2024-12-19	60.0	Partial
214	53	2	7	2024-12-19	0	Failed
215	21	8	7	2024-12-19	30.0	Partial
216	135	4	7	2024-12-19	80	Partial
217	135	8	7	2024-12-19	30.0	Partial
218	141	4	7	2024-12-19	40	Partial
219	141	8	7	2024-12-19	30.0	Partial
238	22	9	8	2024-12-19	20	Accepted
239	92	5	8	2024-12-19	90.0	Accepted
240	92	3	8	2024-12-19	0	Failed
241	63	5	8	2024-12-19	60.0	Partial
242	63	9	8	2024-12-19	0	Failed
243	184	3	8	2024-12-19	60	Accepted
262	81	10	8	2024-12-19	40	Partial
263	93	5	8	2024-12-19	30.0	Partial
264	93	6	8	2024-12-19	40	Partial
265	93	10	8	2024-12-19	80	Partial
266	70	5	8	2024-12-19	60.0	Partial
283	133	5	9	2024-12-19	30.0	Partial
284	113	8	9	2024-12-19	30.0	Partial
285	79	4	9	2024-12-19	120	Accepted
286	79	5	9	2024-12-19	30.0	Partial
287	172	5	9	2024-12-19	30.0	Partial
305	5	4	10	2024-12-19	40	Partial
306	5	3	10	2024-12-19	0	Failed
307	62	4	10	2024-12-19	40	Partial
308	62	3	10	2024-12-19	20	Partial
309	171	5	10	2024-12-19	30.0	Partial
327	45	7	11	2024-12-19	0	Failed
328	45	8	11	2024-12-19	30.0	Partial
329	175	8	11	2024-12-19	60.0	Partial
330	165	5	11	2024-12-19	90.0	Accepted
347	10	6	12	2024-12-19	20	Partial
348	10	4	12	2024-12-19	120	Accepted
349	177	4	12	2024-12-19	80	Partial
350	177	9	12	2024-12-19	0	Failed
351	177	5	12	2024-12-19	60.0	Partial
370	90	6	12	2024-12-19	40	Partial
371	90	4	12	2024-12-19	80	Partial
372	157	6	12	2024-12-19	20	Partial
373	157	5	12	2024-12-19	30.0	Partial
374	173	6	12	2024-12-19	40	Partial
375	181	6	13	2024-12-19	60	Accepted
393	20	7	13	2024-12-19	90.0	Accepted
394	20	6	13	2024-12-19	0	Failed
395	63	2	13	2024-12-19	30.0	Partial
396	63	8	13	2024-12-19	0	Failed
397	169	7	13	2024-12-19	30.0	Partial
416	90	6	13	2024-12-19	40	Partial
417	154	8	13	2024-12-19	30.0	Partial
418	154	2	13	2024-12-19	30.0	Partial
419	154	7	13	2024-12-19	60.0	Partial
420	154	4	13	2024-12-19	40	Partial
437	87	7	14	2024-12-19	90.0	Accepted
438	198	6	14	2024-12-19	40	Partial
439	198	3	14	2024-12-19	20	Partial
440	4	6	14	2024-12-19	20	Partial
460	27	8	15	2024-12-19	30.0	Partial
461	130	9	15	2024-12-19	20	Accepted
462	130	2	15	2024-12-19	0	Failed
463	135	2	15	2024-12-19	0	Failed
464	68	9	15	2024-12-19	20	Accepted
465	68	7	15	2024-12-19	0	Failed
466	20	9	15	2024-12-19	20	Accepted
467	20	8	16	2024-12-19	60.0	Partial
468	20	4	16	2024-12-19	120	Accepted
485	128	2	17	2024-12-19	30.0	Partial
486	71	2	17	2024-12-19	0	Failed
487	194	2	17	2024-12-19	60.0	Accepted
488	194	7	17	2024-12-19	60.0	Partial
489	15	3	17	2024-12-19	20	Partial
508	103	3	18	2024-12-19	60	Accepted
509	103	7	18	2024-12-19	60.0	Partial
510	15	9	18	2024-12-19	0	Failed
511	15	10	18	2024-12-19	0	Failed
512	140	7	18	2024-12-19	30.0	Partial
513	42	7	18	2024-12-19	60.0	Partial
514	42	9	18	2024-12-19	0	Failed
533	180	4	19	2024-12-19	0	Failed
534	84	4	19	2024-12-19	40	Partial
535	84	8	19	2024-12-19	30.0	Partial
536	27	8	19	2024-12-19	90.0	Accepted
553	120	10	20	2024-12-19	40	Partial
554	120	3	20	2024-12-19	0	Failed
555	103	10	20	2024-12-19	40	Partial
556	16	10	20	2024-12-19	120	Accepted
557	16	5	20	2024-12-19	0	Failed
574	18	8	20	2024-12-19	0	Failed
575	98	8	20	2024-12-19	60.0	Partial
576	98	5	20	2024-12-19	60.0	Partial
577	200	2	21	2024-12-19	60.0	Accepted
578	153	5	21	2024-12-19	30.0	Partial
596	199	2	21	2024-12-19	30.0	Partial
597	199	6	21	2024-12-19	0	Failed
598	126	6	21	2024-12-19	60	Accepted
599	126	2	21	2024-12-19	30.0	Partial
600	126	4	21	2024-12-19	80	Partial
618	116	8	21	2024-12-19	30.0	Partial
619	116	2	21	2024-12-19	0	Failed
620	77	8	21	2024-12-19	30.0	Partial
621	77	2	21	2024-12-19	30.0	Partial
622	77	5	21	2024-12-19	60.0	Partial
640	179	4	22	2024-12-19	40	Partial
641	23	5	22	2024-12-19	30.0	Partial
642	200	4	22	2024-12-19	40	Partial
643	79	2	22	2024-12-19	30.0	Partial
644	194	2	22	2024-12-19	30.0	Partial
645	194	5	22	2024-12-19	60.0	Partial
662	11	3	23	2024-12-19	60	Accepted
663	106	10	23	2024-12-19	80	Partial
664	115	10	23	2024-12-19	120	Accepted
665	115	8	23	2024-12-19	60.0	Partial
666	81	10	23	2024-12-19	120	Accepted
683	112	8	24	2024-12-19	30.0	Partial
684	112	4	24	2024-12-19	40	Partial
685	125	4	24	2024-12-19	0	Failed
686	110	5	24	2024-12-19	0	Failed
703	74	3	25	2024-12-19	40	Partial
704	74	10	25	2024-12-19	120	Accepted
705	54	3	25	2024-12-19	40	Partial
706	86	3	25	2024-12-19	0	Failed
707	202	10	25	2024-12-19	80	Partial
724	37	3	26	2024-12-19	20	Partial
725	183	5	26	2024-12-19	30.0	Partial
726	183	10	26	2024-12-19	40	Partial
727	127	3	26	2024-12-19	20	Partial
744	79	3	26	2024-12-19	20	Partial
745	79	10	26	2024-12-19	80	Partial
746	79	5	26	2024-12-19	90.0	Accepted
747	94	3	26	2024-12-19	0	Failed
748	197	10	27	2024-12-19	40	Partial
770	25	5	27	2024-12-19	60.0	Partial
771	7	9	28	2024-12-19	20	Accepted
772	7	7	28	2024-12-19	60.0	Partial
773	7	8	28	2024-12-19	90.0	Accepted
774	66	5	28	2024-12-19	60.0	Partial
792	13	5	28	2024-12-19	30.0	Partial
793	13	9	28	2024-12-19	0	Failed
794	38	5	28	2024-12-19	60.0	Partial
795	38	7	28	2024-12-19	90.0	Accepted
796	144	8	28	2024-12-19	60.0	Partial
797	144	5	28	2024-12-19	60.0	Partial
815	13	6	29	2024-12-19	20	Partial
816	13	8	29	2024-12-19	30.0	Partial
817	13	4	29	2024-12-19	40	Partial
818	113	6	29	2024-12-19	20	Partial
836	41	10	30	2024-12-19	40	Partial
837	191	9	30	2024-12-19	20	Accepted
838	5	5	30	2024-12-19	60.0	Partial
839	28	10	30	2024-12-19	40	Partial
840	28	4	30	2024-12-19	0	Failed
861	95	4	31	2024-12-19	40	Partial
862	11	7	31	2024-12-19	60.0	Partial
863	11	4	31	2024-12-19	80	Partial
864	56	7	31	2024-12-19	60.0	Partial
865	70	8	31	2024-12-19	30.0	Partial
885	103	8	32	2024-12-19	0	Failed
886	103	4	32	2024-12-19	80	Partial
887	176	4	32	2024-12-19	80	Partial
888	176	8	32	2024-12-19	30.0	Partial
889	77	4	32	2024-12-19	0	Failed
908	10	10	32	2024-12-19	80	Partial
909	10	2	32	2024-12-19	0	Failed
910	13	10	32	2024-12-19	80	Partial
911	13	8	32	2024-12-19	30.0	Partial
912	151	10	32	2024-12-19	40	Partial
930	150	5	33	2024-12-19	30.0	Partial
931	150	4	33	2024-12-19	40	Partial
932	150	7	33	2024-12-19	60.0	Partial
933	143	7	33	2024-12-19	60.0	Partial
934	143	5	33	2024-12-19	60.0	Partial
951	40	5	33	2024-12-19	30.0	Partial
952	40	4	33	2024-12-19	80	Partial
953	198	4	33	2024-12-19	80	Partial
954	2	4	33	2024-12-19	40	Partial
972	125	5	34	2024-12-19	90.0	Accepted
973	68	5	34	2024-12-19	30.0	Partial
974	77	2	34	2024-12-19	0	Failed
975	77	4	34	2024-12-19	80	Partial
976	77	5	34	2024-12-19	0	Failed
977	149	7	34	2024-12-19	60.0	Partial
995	5	7	34	2024-12-19	60.0	Partial
996	140	4	34	2024-12-19	40	Partial
997	140	7	34	2024-12-19	30.0	Partial
998	140	2	34	2024-12-19	0	Failed
1015	16	6	35	2024-12-19	0	Failed
1016	16	8	35	2024-12-19	60.0	Partial
1017	16	7	35	2024-12-19	60.0	Partial
1018	134	6	35	2024-12-19	40	Partial
1019	134	8	35	2024-12-19	90.0	Accepted
1036	100	6	36	2024-12-19	0	Failed
1037	100	5	36	2024-12-19	30.0	Partial
1038	100	2	36	2024-12-19	60.0	Accepted
1039	40	2	36	2024-12-19	30.0	Partial
1040	51	2	36	2024-12-19	0	Failed
1041	123	8	36	2024-12-19	30.0	Partial
1059	128	5	37	2024-12-19	30.0	Partial
1060	128	10	37	2024-12-19	80	Partial
1061	128	3	37	2024-12-19	20	Partial
1062	102	3	37	2024-12-19	40	Partial
1080	168	10	38	2024-12-19	80	Partial
1081	134	10	38	2024-12-19	40	Partial
1082	134	8	38	2024-12-19	30.0	Partial
1083	134	3	38	2024-12-19	0	Failed
1084	29	3	38	2024-12-19	40	Partial
1101	159	4	38	2024-12-19	80	Partial
1102	159	3	38	2024-12-19	40	Partial
1103	159	8	38	2024-12-19	90.0	Accepted
1104	57	3	38	2024-12-19	40	Partial
1105	57	8	38	2024-12-19	60.0	Partial
1123	40	4	39	2024-12-19	0	Failed
1124	89	4	39	2024-12-19	80	Partial
1125	89	9	39	2024-12-19	20	Accepted
1126	70	8	39	2024-12-19	30.0	Partial
1127	70	3	39	2024-12-19	60	Accepted
1128	70	4	39	2024-12-19	0	Failed
1149	132	3	39	2024-12-19	0	Failed
1150	132	4	39	2024-12-19	120	Accepted
1151	98	7	39	2024-12-19	30.0	Partial
1152	98	4	39	2024-12-19	40	Partial
1153	69	7	39	2024-12-19	0	Failed
1175	85	3	40	2024-12-19	40	Partial
1176	72	4	40	2024-12-19	40	Partial
1177	72	3	40	2024-12-19	40	Partial
1178	72	9	40	2024-12-19	0	Failed
1179	118	3	40	2024-12-19	40	Partial
1180	19	4	40	2024-12-19	40	Partial
1199	89	10	41	2024-12-19	40	Partial
1200	3	2	41	2024-12-19	30.0	Partial
1201	3	4	41	2024-12-19	80	Partial
1202	162	4	41	2024-12-19	40	Partial
1203	162	10	41	2024-12-19	120	Accepted
1221	89	4	42	2024-12-19	120	Accepted
1222	89	6	42	2024-12-19	0	Failed
1223	89	3	42	2024-12-19	40	Partial
1224	25	4	42	2024-12-19	120	Accepted
1243	119	3	43	2024-12-19	20	Partial
1244	186	3	43	2024-12-19	0	Failed
1245	186	5	43	2024-12-19	60.0	Partial
1246	186	6	43	2024-12-19	20	Partial
1247	198	5	43	2024-12-19	60.0	Partial
1264	177	7	43	2024-12-19	60.0	Partial
1265	189	4	43	2024-12-19	40	Partial
1266	81	3	43	2024-12-19	40	Partial
1267	144	3	43	2024-12-19	40	Partial
1284	194	2	44	2024-12-19	30.0	Partial
1285	116	3	44	2024-12-19	40	Partial
1286	147	8	44	2024-12-19	30.0	Partial
1287	147	2	44	2024-12-19	30.0	Partial
1288	21	7	44	2024-12-19	0	Failed
1306	198	7	45	2024-12-19	30.0	Partial
1307	198	6	45	2024-12-19	40	Partial
1308	174	3	45	2024-12-19	40	Partial
1309	174	7	45	2024-12-19	30.0	Partial
1310	174	6	45	2024-12-19	40	Partial
1328	8	7	46	2024-12-19	90.0	Accepted
1329	103	8	46	2024-12-19	30.0	Partial
1330	103	7	46	2024-12-19	30.0	Partial
1349	136	3	47	2024-12-19	40	Partial
1350	136	10	47	2024-12-19	0	Failed
1351	199	10	47	2024-12-19	40	Partial
1352	199	4	47	2024-12-19	80	Partial
1353	81	3	47	2024-12-19	60	Accepted
1363	122	10	47	2024-12-19	0	Failed
1364	122	7	47	2024-12-19	60.0	Partial
1365	30	4	47	2024-12-19	80	Partial
1366	102	4	47	2024-12-19	80	Partial
1367	102	3	47	2024-12-19	40	Partial
1368	20	10	47	2024-12-19	0	Failed
1369	92	3	47	2024-12-19	40	Partial
1377	56	6	48	2024-12-19	40	Partial
1378	56	8	48	2024-12-19	0	Failed
1379	140	8	48	2024-12-19	60.0	Partial
1380	151	9	48	2024-12-19	0	Failed
1381	151	6	48	2024-12-19	40	Partial
1382	201	6	48	2024-12-19	20	Partial
1383	201	9	48	2024-12-19	0	Failed
1384	137	9	48	2024-12-19	0	Failed
1402	183	4	49	2024-12-19	80	Partial
1403	142	7	49	2024-12-19	60.0	Partial
1404	142	3	49	2024-12-19	20	Partial
1405	61	3	49	2024-12-19	40	Partial
1422	42	10	50	2024-12-19	40	Partial
1423	42	8	50	2024-12-19	60.0	Partial
1424	42	6	50	2024-12-19	0	Failed
1425	42	2	50	2024-12-19	30.0	Partial
1426	96	3	50	2024-12-19	0	Failed
1444	175	6	50	2024-12-19	20	Partial
1445	41	8	50	2024-12-19	60.0	Partial
1446	185	2	50	2024-12-19	0	Failed
1447	130	3	50	2024-12-19	60	Accepted
1448	130	10	50	2024-12-19	0	Failed
4	1	2	1	2024-12-08	30.0	Partial
3	1	2	1	2024-12-08	60.0	Accepted
5	1	6	1	2024-12-19	20	Partial
6	1	10	1	2024-12-19	0	Failed
7	1	7	1	2024-12-19	90.0	Accepted
8	1	3	1	2024-12-19	60	Accepted
9	1	9	1	2024-12-19	20	Accepted
10	42	6	1	2024-12-19	20	Partial
11	42	10	1	2024-12-19	40	Partial
12	42	3	1	2024-12-19	20	Partial
13	42	7	1	2024-12-19	30.0	Partial
14	42	9	1	2024-12-19	20	Accepted
15	86	10	1	2024-12-19	80	Partial
16	86	7	1	2024-12-19	30.0	Partial
17	86	9	1	2024-12-19	20	Accepted
18	86	3	1	2024-12-19	40	Partial
19	73	3	1	2024-12-19	40	Partial
20	73	6	1	2024-12-19	40	Partial
21	73	2	1	2024-12-19	60.0	Accepted
25	39	3	1	2024-12-19	60	Accepted
26	39	6	1	2024-12-19	20	Partial
27	39	9	1	2024-12-19	20	Accepted
28	182	6	1	2024-12-19	0	Failed
29	182	7	1	2024-12-19	0	Failed
30	182	3	1	2024-12-19	0	Failed
31	182	9	1	2024-12-19	20	Accepted
32	69	10	1	2024-12-19	40	Partial
33	69	6	1	2024-12-19	20	Partial
34	69	3	1	2024-12-19	40	Partial
35	69	7	1	2024-12-19	30.0	Partial
36	97	2	1	2024-12-19	0	Failed
37	97	10	1	2024-12-19	40	Partial
38	23	10	1	2024-12-19	40	Partial
39	23	9	1	2024-12-19	0	Failed
40	23	2	1	2024-12-19	60.0	Accepted
41	23	7	1	2024-12-19	0	Failed
42	23	3	1	2024-12-19	60	Accepted
51	52	6	1	2024-12-19	20	Partial
52	62	7	1	2024-12-19	60.0	Partial
53	64	2	1	2024-12-19	30.0	Partial
54	64	3	1	2024-12-19	20	Partial
55	64	9	1	2024-12-19	0	Failed
56	64	7	1	2024-12-19	30.0	Partial
57	64	10	1	2024-12-19	80	Partial
58	88	3	1	2024-12-19	60	Accepted
59	168	3	1	2024-12-19	60	Accepted
60	168	6	1	2024-12-19	60	Accepted
61	25	3	1	2024-12-19	20	Partial
62	25	6	1	2024-12-19	0	Failed
63	25	10	1	2024-12-19	40	Partial
64	72	3	2	2024-12-19	20	Partial
65	61	9	2	2024-12-19	20	Accepted
66	61	2	2	2024-12-19	30.0	Partial
67	61	4	2	2024-12-19	40	Partial
68	61	5	2	2024-12-19	90.0	Accepted
74	91	3	2	2024-12-19	40	Partial
75	91	5	2	2024-12-19	0	Failed
76	50	2	2	2024-12-19	30.0	Partial
77	50	9	2	2024-12-19	20	Accepted
78	133	4	2	2024-12-19	40	Partial
79	125	4	2	2024-12-19	120	Accepted
80	100	2	2	2024-12-19	30.0	Partial
81	100	3	2	2024-12-19	40	Partial
82	100	5	2	2024-12-19	60.0	Partial
83	113	3	2	2024-12-19	40	Partial
84	113	5	2	2024-12-19	30.0	Partial
85	26	9	2	2024-12-19	0	Failed
86	25	5	2	2024-12-19	30.0	Partial
87	52	4	2	2024-12-19	80	Partial
88	52	5	2	2024-12-19	90.0	Accepted
89	52	2	2	2024-12-19	60.0	Accepted
90	117	5	2	2024-12-19	30.0	Partial
91	117	4	2	2024-12-19	0	Failed
99	68	3	2	2024-12-19	40	Partial
100	68	9	2	2024-12-19	0	Failed
101	68	5	2	2024-12-19	30.0	Partial
102	20	10	3	2024-12-19	40	Partial
103	20	8	3	2024-12-19	0	Failed
104	178	9	3	2024-12-19	20	Accepted
105	178	8	3	2024-12-19	60.0	Partial
106	178	4	3	2024-12-19	40	Partial
107	13	9	3	2024-12-19	0	Failed
108	13	4	3	2024-12-19	80	Partial
109	13	8	3	2024-12-19	60.0	Partial
110	34	8	3	2024-12-19	60.0	Partial
111	34	4	3	2024-12-19	0	Failed
112	100	4	3	2024-12-19	120	Accepted
113	19	8	3	2024-12-19	60.0	Partial
114	36	10	3	2024-12-19	80	Partial
115	176	9	3	2024-12-19	20	Accepted
116	176	10	3	2024-12-19	40	Partial
123	40	8	3	2024-12-19	60.0	Partial
124	134	4	3	2024-12-19	40	Partial
125	38	8	3	2024-12-19	90.0	Accepted
126	46	4	3	2024-12-19	80	Partial
127	46	9	3	2024-12-19	20	Accepted
128	46	10	3	2024-12-19	80	Partial
129	58	8	3	2024-12-19	90.0	Accepted
130	58	10	3	2024-12-19	40	Partial
131	58	4	3	2024-12-19	40	Partial
132	197	7	4	2024-12-19	30.0	Partial
133	6	5	4	2024-12-19	60.0	Partial
134	6	10	4	2024-12-19	80	Partial
135	6	2	4	2024-12-19	60.0	Accepted
136	6	9	4	2024-12-19	20	Accepted
137	173	9	4	2024-12-19	0	Failed
138	173	10	4	2024-12-19	40	Partial
139	173	2	4	2024-12-19	30.0	Partial
140	25	10	4	2024-12-19	40	Partial
141	153	2	4	2024-12-19	30.0	Partial
146	75	10	4	2024-12-19	80	Partial
147	172	7	4	2024-12-19	0	Failed
148	172	9	4	2024-12-19	20	Accepted
149	135	5	4	2024-12-19	60.0	Partial
150	135	9	4	2024-12-19	0	Failed
151	135	7	4	2024-12-19	0	Failed
152	135	10	4	2024-12-19	80	Partial
153	64	9	4	2024-12-19	20	Accepted
154	64	10	4	2024-12-19	80	Partial
155	64	2	4	2024-12-19	0	Failed
156	131	2	4	2024-12-19	0	Failed
157	196	2	4	2024-12-19	0	Failed
158	196	7	4	2024-12-19	60.0	Partial
159	196	9	4	2024-12-19	20	Accepted
160	196	5	4	2024-12-19	60.0	Partial
161	36	2	5	2024-12-19	30.0	Partial
162	36	6	5	2024-12-19	20	Partial
163	100	7	5	2024-12-19	30.0	Partial
164	47	7	5	2024-12-19	60.0	Partial
165	173	8	5	2024-12-19	90.0	Accepted
172	179	7	5	2024-12-19	30.0	Partial
173	185	2	5	2024-12-19	30.0	Partial
174	185	6	5	2024-12-19	0	Failed
175	185	7	5	2024-12-19	90.0	Accepted
176	127	6	5	2024-12-19	20	Partial
177	127	8	5	2024-12-19	30.0	Partial
178	127	2	5	2024-12-19	30.0	Partial
179	161	8	5	2024-12-19	60.0	Partial
180	161	7	5	2024-12-19	0	Failed
181	63	6	5	2024-12-19	20	Partial
182	63	2	5	2024-12-19	30.0	Partial
183	63	8	5	2024-12-19	30.0	Partial
184	104	6	5	2024-12-19	20	Partial
185	180	6	5	2024-12-19	20	Partial
186	180	7	5	2024-12-19	30.0	Partial
187	188	9	6	2024-12-19	0	Failed
188	188	10	6	2024-12-19	80	Partial
189	8	7	6	2024-12-19	30.0	Partial
194	33	10	6	2024-12-19	0	Failed
195	33	9	6	2024-12-19	20	Accepted
196	33	8	6	2024-12-19	60.0	Partial
197	40	8	6	2024-12-19	60.0	Partial
198	40	7	6	2024-12-19	0	Failed
199	40	10	6	2024-12-19	40	Partial
200	85	9	6	2024-12-19	20	Accepted
201	85	7	6	2024-12-19	90.0	Accepted
202	174	9	6	2024-12-19	0	Failed
203	174	8	6	2024-12-19	0	Failed
204	62	10	6	2024-12-19	80	Partial
205	59	9	6	2024-12-19	0	Failed
206	59	8	6	2024-12-19	60.0	Partial
207	9	9	6	2024-12-19	0	Failed
208	114	9	6	2024-12-19	0	Failed
209	114	10	6	2024-12-19	120	Accepted
210	20	8	6	2024-12-19	30.0	Partial
211	48	10	6	2024-12-19	80	Partial
212	151	4	7	2024-12-19	40	Partial
213	53	4	7	2024-12-19	120	Accepted
220	176	8	7	2024-12-19	30.0	Partial
221	176	4	7	2024-12-19	120	Accepted
222	29	2	7	2024-12-19	60.0	Accepted
223	199	4	7	2024-12-19	40	Partial
224	199	8	7	2024-12-19	30.0	Partial
225	202	8	7	2024-12-19	90.0	Accepted
226	94	2	7	2024-12-19	60.0	Accepted
227	94	4	7	2024-12-19	80	Partial
228	30	2	7	2024-12-19	30.0	Partial
229	106	6	8	2024-12-19	20	Partial
230	106	9	8	2024-12-19	0	Failed
231	106	3	8	2024-12-19	20	Partial
232	106	10	8	2024-12-19	80	Partial
233	168	9	8	2024-12-19	20	Accepted
234	82	3	8	2024-12-19	60	Accepted
235	82	5	8	2024-12-19	60.0	Partial
236	200	6	8	2024-12-19	20	Partial
237	22	3	8	2024-12-19	40	Partial
244	184	6	8	2024-12-19	20	Partial
245	5	3	8	2024-12-19	20	Partial
246	5	9	8	2024-12-19	20	Accepted
247	5	10	8	2024-12-19	40	Partial
248	161	6	8	2024-12-19	40	Partial
249	161	10	8	2024-12-19	80	Partial
250	161	9	8	2024-12-19	0	Failed
251	35	10	8	2024-12-19	80	Partial
252	35	3	8	2024-12-19	20	Partial
253	35	5	8	2024-12-19	30.0	Partial
254	35	9	8	2024-12-19	20	Accepted
255	103	5	8	2024-12-19	30.0	Partial
256	103	10	8	2024-12-19	40	Partial
257	103	3	8	2024-12-19	40	Partial
258	103	9	8	2024-12-19	20	Accepted
259	52	10	8	2024-12-19	40	Partial
260	52	5	8	2024-12-19	60.0	Partial
261	52	3	8	2024-12-19	40	Partial
267	70	6	8	2024-12-19	40	Partial
268	179	3	8	2024-12-19	40	Partial
269	40	9	8	2024-12-19	20	Accepted
270	39	4	9	2024-12-19	80	Partial
271	153	4	9	2024-12-19	80	Partial
272	153	5	9	2024-12-19	90.0	Accepted
273	137	4	9	2024-12-19	40	Partial
274	137	8	9	2024-12-19	60.0	Partial
275	124	5	9	2024-12-19	30.0	Partial
276	124	4	9	2024-12-19	40	Partial
277	2	5	9	2024-12-19	30.0	Partial
278	169	8	9	2024-12-19	60.0	Partial
279	169	5	9	2024-12-19	60.0	Partial
280	192	5	9	2024-12-19	60.0	Partial
281	192	8	9	2024-12-19	30.0	Partial
282	133	4	9	2024-12-19	80	Partial
288	172	8	9	2024-12-19	60.0	Partial
289	75	8	9	2024-12-19	30.0	Partial
290	43	8	9	2024-12-19	30.0	Partial
291	43	4	9	2024-12-19	120	Accepted
292	202	4	10	2024-12-19	40	Partial
293	202	3	10	2024-12-19	20	Partial
294	182	3	10	2024-12-19	40	Partial
295	63	3	10	2024-12-19	0	Failed
296	63	4	10	2024-12-19	80	Partial
297	63	5	10	2024-12-19	90.0	Accepted
298	150	9	10	2024-12-19	20	Accepted
299	64	4	10	2024-12-19	80	Partial
300	64	5	10	2024-12-19	60.0	Partial
301	93	3	10	2024-12-19	40	Partial
302	148	4	10	2024-12-19	120	Accepted
303	148	5	10	2024-12-19	60.0	Partial
304	148	9	10	2024-12-19	0	Failed
310	171	9	10	2024-12-19	20	Accepted
311	171	4	10	2024-12-19	80	Partial
312	154	3	10	2024-12-19	40	Partial
313	154	4	10	2024-12-19	40	Partial
314	154	5	10	2024-12-19	60.0	Partial
315	21	3	10	2024-12-19	20	Partial
316	143	8	11	2024-12-19	60.0	Partial
317	143	5	11	2024-12-19	90.0	Accepted
318	143	3	11	2024-12-19	20	Partial
319	150	8	11	2024-12-19	30.0	Partial
320	150	3	11	2024-12-19	20	Partial
321	150	5	11	2024-12-19	0	Failed
322	80	5	11	2024-12-19	60.0	Partial
323	199	3	11	2024-12-19	20	Partial
324	199	7	11	2024-12-19	60.0	Partial
325	200	5	11	2024-12-19	30.0	Partial
326	158	3	11	2024-12-19	20	Partial
331	165	8	11	2024-12-19	30.0	Partial
332	165	7	11	2024-12-19	0	Failed
333	101	7	11	2024-12-19	60.0	Partial
334	101	3	11	2024-12-19	0	Failed
335	101	8	11	2024-12-19	60.0	Partial
336	88	7	11	2024-12-19	30.0	Partial
337	42	3	11	2024-12-19	20	Partial
338	42	5	11	2024-12-19	60.0	Partial
339	42	8	11	2024-12-19	0	Failed
340	166	3	11	2024-12-19	20	Partial
341	166	8	11	2024-12-19	60.0	Partial
342	84	5	11	2024-12-19	60.0	Partial
343	84	7	11	2024-12-19	60.0	Partial
344	84	3	11	2024-12-19	20	Partial
345	174	5	12	2024-12-19	0	Failed
346	25	5	12	2024-12-19	90.0	Accepted
352	153	6	12	2024-12-19	20	Partial
353	127	4	12	2024-12-19	80	Partial
354	155	9	12	2024-12-19	0	Failed
355	155	5	12	2024-12-19	60.0	Partial
356	155	4	12	2024-12-19	120	Accepted
357	179	5	12	2024-12-19	60.0	Partial
358	179	9	12	2024-12-19	0	Failed
359	179	4	12	2024-12-19	80	Partial
360	1	9	12	2024-12-19	20	Accepted
361	1	4	12	2024-12-19	80	Partial
362	1	5	12	2024-12-19	30.0	Partial
363	53	6	12	2024-12-19	20	Partial
364	53	5	12	2024-12-19	0	Failed
365	132	9	12	2024-12-19	0	Failed
366	132	4	12	2024-12-19	120	Accepted
367	132	5	12	2024-12-19	60.0	Partial
368	134	4	12	2024-12-19	40	Partial
369	134	6	12	2024-12-19	20	Partial
376	181	8	13	2024-12-19	60.0	Partial
377	181	7	13	2024-12-19	30.0	Partial
378	181	4	13	2024-12-19	80	Partial
379	142	8	13	2024-12-19	0	Failed
380	142	7	13	2024-12-19	60.0	Partial
381	142	2	13	2024-12-19	30.0	Partial
382	11	4	13	2024-12-19	80	Partial
383	11	7	13	2024-12-19	0	Failed
384	11	2	13	2024-12-19	30.0	Partial
385	11	6	13	2024-12-19	20	Partial
386	166	7	13	2024-12-19	30.0	Partial
387	166	2	13	2024-12-19	30.0	Partial
388	81	6	13	2024-12-19	40	Partial
389	81	4	13	2024-12-19	80	Partial
390	132	7	13	2024-12-19	60.0	Partial
391	132	8	13	2024-12-19	30.0	Partial
392	20	2	13	2024-12-19	0	Failed
398	169	6	13	2024-12-19	20	Partial
399	169	4	13	2024-12-19	40	Partial
400	200	7	13	2024-12-19	60.0	Partial
401	200	8	13	2024-12-19	0	Failed
402	200	4	13	2024-12-19	80	Partial
403	200	2	13	2024-12-19	30.0	Partial
404	9	8	13	2024-12-19	30.0	Partial
405	9	4	13	2024-12-19	40	Partial
406	33	4	13	2024-12-19	40	Partial
407	33	7	13	2024-12-19	0	Failed
408	33	2	13	2024-12-19	30.0	Partial
409	58	2	13	2024-12-19	60.0	Accepted
410	23	4	13	2024-12-19	40	Partial
411	23	7	13	2024-12-19	0	Failed
412	23	8	13	2024-12-19	30.0	Partial
413	103	2	13	2024-12-19	0	Failed
414	39	2	13	2024-12-19	0	Failed
415	90	7	13	2024-12-19	60.0	Partial
421	176	3	14	2024-12-19	20	Partial
422	176	6	14	2024-12-19	40	Partial
423	3	3	14	2024-12-19	20	Partial
424	3	6	14	2024-12-19	0	Failed
425	66	3	14	2024-12-19	20	Partial
426	83	6	14	2024-12-19	40	Partial
427	83	7	14	2024-12-19	90.0	Accepted
428	21	7	14	2024-12-19	30.0	Partial
429	21	3	14	2024-12-19	20	Partial
430	68	7	14	2024-12-19	60.0	Partial
431	68	3	14	2024-12-19	40	Partial
432	124	6	14	2024-12-19	20	Partial
433	150	7	14	2024-12-19	60.0	Partial
434	150	3	14	2024-12-19	40	Partial
435	7	6	14	2024-12-19	20	Partial
436	7	3	14	2024-12-19	20	Partial
441	4	3	14	2024-12-19	40	Partial
442	70	8	15	2024-12-19	0	Failed
443	94	9	15	2024-12-19	0	Failed
444	94	2	15	2024-12-19	0	Failed
445	94	7	15	2024-12-19	30.0	Partial
446	155	2	15	2024-12-19	60.0	Accepted
447	155	8	15	2024-12-19	90.0	Accepted
448	82	7	15	2024-12-19	90.0	Accepted
449	82	8	15	2024-12-19	30.0	Partial
450	82	2	15	2024-12-19	60.0	Accepted
451	186	8	15	2024-12-19	30.0	Partial
452	21	7	15	2024-12-19	30.0	Partial
453	136	7	15	2024-12-19	90.0	Accepted
454	124	7	15	2024-12-19	30.0	Partial
455	137	7	15	2024-12-19	30.0	Partial
456	137	9	15	2024-12-19	0	Failed
457	137	2	15	2024-12-19	0	Failed
458	27	2	15	2024-12-19	30.0	Partial
459	27	9	15	2024-12-19	0	Failed
469	147	8	16	2024-12-19	30.0	Partial
470	9	4	16	2024-12-19	40	Partial
471	1	5	16	2024-12-19	30.0	Partial
472	188	7	16	2024-12-19	30.0	Partial
473	188	8	16	2024-12-19	30.0	Partial
474	170	8	16	2024-12-19	60.0	Partial
475	19	7	16	2024-12-19	30.0	Partial
476	83	7	16	2024-12-19	30.0	Partial
477	182	5	16	2024-12-19	30.0	Partial
478	102	4	16	2024-12-19	40	Partial
479	102	5	16	2024-12-19	30.0	Partial
480	102	7	16	2024-12-19	60.0	Partial
481	120	5	16	2024-12-19	60.0	Partial
482	120	8	16	2024-12-19	30.0	Partial
483	141	4	16	2024-12-19	0	Failed
484	124	4	16	2024-12-19	40	Partial
490	7	3	17	2024-12-19	20	Partial
491	148	7	17	2024-12-19	60.0	Partial
492	47	2	17	2024-12-19	30.0	Partial
493	123	3	17	2024-12-19	40	Partial
494	134	2	17	2024-12-19	30.0	Partial
495	137	7	17	2024-12-19	60.0	Partial
496	188	7	17	2024-12-19	90.0	Accepted
497	68	2	17	2024-12-19	0	Failed
498	68	3	17	2024-12-19	40	Partial
499	144	7	17	2024-12-19	30.0	Partial
500	72	7	18	2024-12-19	90.0	Accepted
501	72	3	18	2024-12-19	40	Partial
502	116	10	18	2024-12-19	0	Failed
503	56	3	18	2024-12-19	40	Partial
504	56	9	18	2024-12-19	20	Accepted
505	105	9	18	2024-12-19	0	Failed
506	105	7	18	2024-12-19	30.0	Partial
507	105	10	18	2024-12-19	80	Partial
515	42	10	18	2024-12-19	40	Partial
516	167	3	18	2024-12-19	0	Failed
517	167	10	18	2024-12-19	40	Partial
518	13	7	18	2024-12-19	90.0	Accepted
519	13	9	18	2024-12-19	0	Failed
520	13	10	18	2024-12-19	80	Partial
521	107	7	18	2024-12-19	0	Failed
522	169	7	18	2024-12-19	60.0	Partial
523	169	3	18	2024-12-19	40	Partial
524	169	9	18	2024-12-19	20	Accepted
525	23	9	18	2024-12-19	20	Accepted
526	60	3	18	2024-12-19	20	Partial
527	64	4	19	2024-12-19	40	Partial
528	165	3	19	2024-12-19	0	Failed
529	46	3	19	2024-12-19	20	Partial
530	33	5	19	2024-12-19	60.0	Partial
531	33	4	19	2024-12-19	40	Partial
532	180	8	19	2024-12-19	30.0	Partial
537	100	8	19	2024-12-19	90.0	Accepted
538	100	3	19	2024-12-19	0	Failed
539	57	8	19	2024-12-19	60.0	Partial
540	32	5	19	2024-12-19	60.0	Partial
541	31	3	19	2024-12-19	20	Partial
542	31	5	19	2024-12-19	30.0	Partial
543	31	8	19	2024-12-19	30.0	Partial
544	147	5	19	2024-12-19	90.0	Accepted
545	147	4	19	2024-12-19	40	Partial
546	149	3	19	2024-12-19	40	Partial
547	81	3	19	2024-12-19	0	Failed
548	81	4	19	2024-12-19	120	Accepted
549	8	5	20	2024-12-19	60.0	Partial
550	8	8	20	2024-12-19	30.0	Partial
551	8	10	20	2024-12-19	80	Partial
552	120	8	20	2024-12-19	90.0	Accepted
558	173	3	20	2024-12-19	20	Partial
559	173	5	20	2024-12-19	60.0	Partial
560	23	5	20	2024-12-19	30.0	Partial
561	171	3	20	2024-12-19	40	Partial
562	45	8	20	2024-12-19	30.0	Partial
563	45	5	20	2024-12-19	60.0	Partial
564	19	3	20	2024-12-19	20	Partial
565	133	3	20	2024-12-19	20	Partial
566	133	8	20	2024-12-19	30.0	Partial
567	162	3	20	2024-12-19	20	Partial
568	162	8	20	2024-12-19	0	Failed
569	195	8	20	2024-12-19	30.0	Partial
570	195	10	20	2024-12-19	40	Partial
571	14	10	20	2024-12-19	80	Partial
572	14	5	20	2024-12-19	60.0	Partial
573	14	3	20	2024-12-19	40	Partial
579	153	6	21	2024-12-19	40	Partial
580	43	6	21	2024-12-19	20	Partial
581	43	8	21	2024-12-19	60.0	Partial
582	23	2	21	2024-12-19	30.0	Partial
583	23	4	21	2024-12-19	80	Partial
584	23	5	21	2024-12-19	30.0	Partial
585	23	8	21	2024-12-19	30.0	Partial
586	48	6	21	2024-12-19	40	Partial
587	48	5	21	2024-12-19	60.0	Partial
588	48	2	21	2024-12-19	0	Failed
589	48	4	21	2024-12-19	120	Accepted
590	73	8	21	2024-12-19	60.0	Partial
591	73	6	21	2024-12-19	20	Partial
592	73	2	21	2024-12-19	30.0	Partial
593	73	4	21	2024-12-19	80	Partial
594	199	8	21	2024-12-19	30.0	Partial
595	199	5	21	2024-12-19	90.0	Accepted
601	126	5	21	2024-12-19	60.0	Partial
602	154	6	21	2024-12-19	20	Partial
603	154	5	21	2024-12-19	30.0	Partial
604	157	2	21	2024-12-19	0	Failed
605	157	4	21	2024-12-19	120	Accepted
606	157	5	21	2024-12-19	90.0	Accepted
607	157	8	21	2024-12-19	60.0	Partial
608	60	5	21	2024-12-19	0	Failed
609	60	4	21	2024-12-19	80	Partial
610	60	2	21	2024-12-19	0	Failed
611	202	8	21	2024-12-19	30.0	Partial
612	202	4	21	2024-12-19	80	Partial
613	130	4	21	2024-12-19	80	Partial
614	130	8	21	2024-12-19	60.0	Partial
615	107	4	21	2024-12-19	40	Partial
616	107	6	21	2024-12-19	40	Partial
617	107	5	21	2024-12-19	90.0	Accepted
623	42	5	21	2024-12-19	60.0	Partial
624	42	8	21	2024-12-19	0	Failed
625	42	6	21	2024-12-19	40	Partial
626	98	5	22	2024-12-19	90.0	Accepted
627	163	2	22	2024-12-19	30.0	Partial
628	163	5	22	2024-12-19	90.0	Accepted
629	134	5	22	2024-12-19	30.0	Partial
630	134	4	22	2024-12-19	120	Accepted
631	102	5	22	2024-12-19	60.0	Partial
632	102	2	22	2024-12-19	30.0	Partial
633	104	2	22	2024-12-19	30.0	Partial
634	104	4	22	2024-12-19	80	Partial
635	9	4	22	2024-12-19	80	Partial
636	143	4	22	2024-12-19	40	Partial
637	143	5	22	2024-12-19	60.0	Partial
638	53	2	22	2024-12-19	30.0	Partial
639	179	5	22	2024-12-19	0	Failed
646	69	5	22	2024-12-19	0	Failed
647	69	4	22	2024-12-19	40	Partial
648	83	2	22	2024-12-19	30.0	Partial
649	118	10	23	2024-12-19	80	Partial
650	107	3	23	2024-12-19	20	Partial
651	111	3	23	2024-12-19	60	Accepted
652	111	7	23	2024-12-19	30.0	Partial
653	111	8	23	2024-12-19	60.0	Partial
654	14	7	23	2024-12-19	30.0	Partial
655	14	10	23	2024-12-19	80	Partial
656	27	8	23	2024-12-19	30.0	Partial
657	27	10	23	2024-12-19	120	Accepted
658	141	7	23	2024-12-19	60.0	Partial
659	141	3	23	2024-12-19	0	Failed
660	11	10	23	2024-12-19	40	Partial
661	11	7	23	2024-12-19	30.0	Partial
667	81	8	23	2024-12-19	30.0	Partial
668	35	7	23	2024-12-19	60.0	Partial
669	35	8	23	2024-12-19	30.0	Partial
670	43	8	23	2024-12-19	60.0	Partial
671	43	7	23	2024-12-19	0	Failed
672	43	10	23	2024-12-19	80	Partial
673	202	7	23	2024-12-19	60.0	Partial
674	45	8	23	2024-12-19	30.0	Partial
675	45	10	23	2024-12-19	120	Accepted
676	45	7	23	2024-12-19	60.0	Partial
677	16	8	24	2024-12-19	60.0	Partial
678	16	4	24	2024-12-19	40	Partial
679	33	4	24	2024-12-19	80	Partial
680	9	8	24	2024-12-19	60.0	Partial
681	185	8	24	2024-12-19	0	Failed
682	185	4	24	2024-12-19	80	Partial
687	110	8	24	2024-12-19	30.0	Partial
688	155	4	24	2024-12-19	80	Partial
689	109	8	24	2024-12-19	30.0	Partial
690	109	5	24	2024-12-19	60.0	Partial
691	123	5	24	2024-12-19	30.0	Partial
692	53	8	24	2024-12-19	60.0	Partial
693	53	5	24	2024-12-19	60.0	Partial
694	116	5	24	2024-12-19	30.0	Partial
695	83	4	24	2024-12-19	40	Partial
696	130	4	24	2024-12-19	40	Partial
697	130	8	24	2024-12-19	0	Failed
698	126	8	24	2024-12-19	30.0	Partial
699	95	4	24	2024-12-19	80	Partial
700	60	4	24	2024-12-19	120	Accepted
701	60	8	24	2024-12-19	60.0	Partial
702	5	3	25	2024-12-19	60	Accepted
708	13	8	25	2024-12-19	30.0	Partial
709	174	3	25	2024-12-19	40	Partial
710	174	10	25	2024-12-19	40	Partial
711	39	10	25	2024-12-19	40	Partial
712	35	3	25	2024-12-19	20	Partial
713	35	10	25	2024-12-19	80	Partial
714	124	8	25	2024-12-19	60.0	Partial
715	124	3	25	2024-12-19	40	Partial
716	155	8	25	2024-12-19	30.0	Partial
717	4	8	25	2024-12-19	60.0	Partial
718	53	10	26	2024-12-19	80	Partial
719	53	3	26	2024-12-19	40	Partial
720	181	6	26	2024-12-19	40	Partial
721	143	6	26	2024-12-19	60	Accepted
722	143	5	26	2024-12-19	60.0	Partial
723	143	3	26	2024-12-19	40	Partial
728	126	5	26	2024-12-19	90.0	Accepted
729	126	6	26	2024-12-19	40	Partial
730	126	3	26	2024-12-19	60	Accepted
731	68	10	26	2024-12-19	120	Accepted
732	96	10	26	2024-12-19	80	Partial
733	96	5	26	2024-12-19	30.0	Partial
734	96	6	26	2024-12-19	60	Accepted
735	109	10	26	2024-12-19	40	Partial
736	109	5	26	2024-12-19	0	Failed
737	97	10	26	2024-12-19	80	Partial
738	97	3	26	2024-12-19	20	Partial
739	179	10	26	2024-12-19	40	Partial
740	179	3	26	2024-12-19	20	Partial
741	179	5	26	2024-12-19	60.0	Partial
742	93	3	26	2024-12-19	20	Partial
743	46	5	26	2024-12-19	60.0	Partial
749	140	9	27	2024-12-19	0	Failed
750	173	10	27	2024-12-19	80	Partial
751	5	10	27	2024-12-19	40	Partial
752	84	10	27	2024-12-19	40	Partial
753	84	9	27	2024-12-19	20	Accepted
754	80	9	27	2024-12-19	20	Accepted
755	166	5	27	2024-12-19	30.0	Partial
756	178	10	27	2024-12-19	120	Accepted
757	178	5	27	2024-12-19	30.0	Partial
758	35	10	27	2024-12-19	80	Partial
759	103	9	27	2024-12-19	20	Accepted
760	103	10	27	2024-12-19	80	Partial
761	14	9	27	2024-12-19	20	Accepted
762	14	10	27	2024-12-19	80	Partial
763	59	10	27	2024-12-19	0	Failed
764	106	5	27	2024-12-19	60.0	Partial
765	106	9	27	2024-12-19	0	Failed
766	142	9	27	2024-12-19	20	Accepted
767	6	9	27	2024-12-19	0	Failed
768	6	10	27	2024-12-19	80	Partial
769	25	10	27	2024-12-19	40	Partial
775	66	7	28	2024-12-19	90.0	Accepted
776	66	8	28	2024-12-19	30.0	Partial
777	115	7	28	2024-12-19	90.0	Accepted
778	115	8	28	2024-12-19	30.0	Partial
779	115	3	28	2024-12-19	20	Partial
780	77	7	28	2024-12-19	60.0	Partial
781	77	9	28	2024-12-19	20	Accepted
782	4	8	28	2024-12-19	60.0	Partial
783	4	7	28	2024-12-19	60.0	Partial
784	110	7	28	2024-12-19	60.0	Partial
785	110	3	28	2024-12-19	40	Partial
786	110	5	28	2024-12-19	30.0	Partial
787	37	7	28	2024-12-19	30.0	Partial
788	37	9	28	2024-12-19	0	Failed
789	37	5	28	2024-12-19	30.0	Partial
790	37	8	28	2024-12-19	60.0	Partial
791	13	3	28	2024-12-19	20	Partial
798	144	7	28	2024-12-19	60.0	Partial
799	144	9	28	2024-12-19	20	Accepted
800	155	5	28	2024-12-19	30.0	Partial
801	155	8	28	2024-12-19	30.0	Partial
802	189	5	28	2024-12-19	60.0	Partial
803	189	7	28	2024-12-19	60.0	Partial
804	189	9	28	2024-12-19	0	Failed
805	11	8	28	2024-12-19	60.0	Partial
806	11	3	28	2024-12-19	40	Partial
807	11	5	28	2024-12-19	60.0	Partial
808	43	8	28	2024-12-19	60.0	Partial
809	43	3	28	2024-12-19	40	Partial
810	26	7	28	2024-12-19	30.0	Partial
811	48	6	29	2024-12-19	40	Partial
812	48	7	29	2024-12-19	60.0	Partial
813	72	7	29	2024-12-19	60.0	Partial
814	95	7	29	2024-12-19	60.0	Partial
819	113	4	29	2024-12-19	40	Partial
820	113	8	29	2024-12-19	60.0	Partial
821	92	6	29	2024-12-19	20	Partial
822	92	7	29	2024-12-19	0	Failed
823	192	6	29	2024-12-19	60	Accepted
824	192	7	29	2024-12-19	60.0	Partial
825	192	4	29	2024-12-19	40	Partial
826	122	4	29	2024-12-19	120	Accepted
827	77	7	29	2024-12-19	30.0	Partial
828	77	6	29	2024-12-19	20	Partial
829	162	7	29	2024-12-19	30.0	Partial
830	136	10	30	2024-12-19	40	Partial
831	136	5	30	2024-12-19	30.0	Partial
832	197	4	30	2024-12-19	80	Partial
833	151	4	30	2024-12-19	80	Partial
834	41	5	30	2024-12-19	90.0	Accepted
835	41	9	30	2024-12-19	0	Failed
841	111	4	30	2024-12-19	80	Partial
842	60	5	30	2024-12-19	30.0	Partial
843	122	10	30	2024-12-19	0	Failed
844	170	10	30	2024-12-19	40	Partial
845	23	9	30	2024-12-19	20	Accepted
846	23	5	30	2024-12-19	90.0	Accepted
847	23	4	30	2024-12-19	0	Failed
848	30	5	30	2024-12-19	0	Failed
849	11	9	30	2024-12-19	20	Accepted
850	2	5	30	2024-12-19	30.0	Partial
851	125	5	30	2024-12-19	60.0	Partial
852	125	4	30	2024-12-19	80	Partial
853	125	9	30	2024-12-19	20	Accepted
854	118	4	31	2024-12-19	80	Partial
855	118	9	31	2024-12-19	20	Accepted
856	118	8	31	2024-12-19	30.0	Partial
857	178	8	31	2024-12-19	60.0	Partial
858	50	9	31	2024-12-19	0	Failed
859	50	7	31	2024-12-19	30.0	Partial
860	95	9	31	2024-12-19	20	Accepted
866	27	7	31	2024-12-19	60.0	Partial
867	27	8	31	2024-12-19	30.0	Partial
868	27	4	31	2024-12-19	120	Accepted
869	60	7	31	2024-12-19	60.0	Partial
870	60	8	31	2024-12-19	30.0	Partial
871	60	9	31	2024-12-19	20	Accepted
872	78	9	31	2024-12-19	20	Accepted
873	78	8	31	2024-12-19	60.0	Partial
874	78	4	31	2024-12-19	120	Accepted
875	74	8	31	2024-12-19	60.0	Partial
876	74	9	31	2024-12-19	20	Accepted
877	74	7	31	2024-12-19	30.0	Partial
878	9	9	31	2024-12-19	20	Accepted
879	9	4	31	2024-12-19	120	Accepted
880	9	7	31	2024-12-19	60.0	Partial
881	22	8	31	2024-12-19	30.0	Partial
882	22	7	31	2024-12-19	30.0	Partial
883	22	9	31	2024-12-19	20	Accepted
884	103	10	32	2024-12-19	40	Partial
890	77	2	32	2024-12-19	30.0	Partial
891	77	8	32	2024-12-19	60.0	Partial
892	52	8	32	2024-12-19	30.0	Partial
893	52	2	32	2024-12-19	60.0	Accepted
894	95	2	32	2024-12-19	30.0	Partial
895	95	10	32	2024-12-19	80	Partial
896	45	8	32	2024-12-19	30.0	Partial
897	45	10	32	2024-12-19	120	Accepted
898	45	2	32	2024-12-19	30.0	Partial
899	126	2	32	2024-12-19	30.0	Partial
900	99	10	32	2024-12-19	40	Partial
901	99	4	32	2024-12-19	80	Partial
902	99	2	32	2024-12-19	60.0	Accepted
903	72	4	32	2024-12-19	120	Accepted
904	72	10	32	2024-12-19	40	Partial
905	72	2	32	2024-12-19	60.0	Accepted
906	78	10	32	2024-12-19	80	Partial
907	60	8	32	2024-12-19	60.0	Partial
913	151	8	32	2024-12-19	30.0	Partial
914	140	2	32	2024-12-19	60.0	Accepted
915	174	8	32	2024-12-19	30.0	Partial
916	174	2	32	2024-12-19	30.0	Partial
917	174	10	32	2024-12-19	40	Partial
918	23	2	32	2024-12-19	60.0	Accepted
919	23	4	32	2024-12-19	40	Partial
920	157	8	32	2024-12-19	30.0	Partial
921	157	10	32	2024-12-19	80	Partial
922	137	8	32	2024-12-19	0	Failed
923	137	4	32	2024-12-19	80	Partial
924	137	2	32	2024-12-19	30.0	Partial
925	62	8	32	2024-12-19	90.0	Accepted
926	17	6	33	2024-12-19	20	Partial
927	17	10	33	2024-12-19	80	Partial
928	17	5	33	2024-12-19	30.0	Partial
929	150	10	33	2024-12-19	40	Partial
935	22	5	33	2024-12-19	60.0	Partial
936	22	4	33	2024-12-19	80	Partial
937	22	6	33	2024-12-19	20	Partial
938	22	10	33	2024-12-19	40	Partial
939	68	6	33	2024-12-19	20	Partial
940	75	5	33	2024-12-19	60.0	Partial
941	75	10	33	2024-12-19	40	Partial
942	75	6	33	2024-12-19	40	Partial
943	93	4	33	2024-12-19	40	Partial
944	8	5	33	2024-12-19	60.0	Partial
945	8	6	33	2024-12-19	40	Partial
946	187	5	33	2024-12-19	90.0	Accepted
947	187	10	33	2024-12-19	80	Partial
948	187	7	33	2024-12-19	60.0	Partial
949	35	6	33	2024-12-19	20	Partial
950	40	7	33	2024-12-19	30.0	Partial
955	2	6	33	2024-12-19	20	Partial
956	103	4	33	2024-12-19	40	Partial
957	103	6	33	2024-12-19	60	Accepted
958	106	5	33	2024-12-19	30.0	Partial
959	166	10	33	2024-12-19	40	Partial
960	166	4	33	2024-12-19	40	Partial
961	135	5	34	2024-12-19	60.0	Partial
962	135	4	34	2024-12-19	40	Partial
963	135	2	34	2024-12-19	60.0	Accepted
964	135	3	34	2024-12-19	20	Partial
965	198	4	34	2024-12-19	120	Accepted
966	198	2	34	2024-12-19	60.0	Accepted
967	198	7	34	2024-12-19	60.0	Partial
968	164	3	34	2024-12-19	40	Partial
969	164	2	34	2024-12-19	60.0	Accepted
970	125	2	34	2024-12-19	30.0	Partial
971	125	7	34	2024-12-19	30.0	Partial
978	149	4	34	2024-12-19	80	Partial
979	149	5	34	2024-12-19	30.0	Partial
980	74	2	34	2024-12-19	30.0	Partial
981	74	4	34	2024-12-19	120	Accepted
982	83	5	34	2024-12-19	30.0	Partial
983	83	3	34	2024-12-19	20	Partial
984	83	4	34	2024-12-19	80	Partial
985	15	3	34	2024-12-19	0	Failed
986	15	2	34	2024-12-19	0	Failed
987	62	7	34	2024-12-19	60.0	Partial
988	62	3	34	2024-12-19	20	Partial
989	22	3	34	2024-12-19	40	Partial
990	22	7	34	2024-12-19	0	Failed
991	142	7	34	2024-12-19	30.0	Partial
992	142	5	34	2024-12-19	0	Failed
993	142	3	34	2024-12-19	20	Partial
994	142	4	34	2024-12-19	0	Failed
999	178	6	35	2024-12-19	20	Partial
1000	65	7	35	2024-12-19	60.0	Partial
1001	65	8	35	2024-12-19	60.0	Partial
1002	110	7	35	2024-12-19	30.0	Partial
1003	116	8	35	2024-12-19	0	Failed
1004	4	4	35	2024-12-19	80	Partial
1005	4	6	35	2024-12-19	40	Partial
1006	50	8	35	2024-12-19	60.0	Partial
1007	72	4	35	2024-12-19	80	Partial
1008	133	6	35	2024-12-19	40	Partial
1009	133	7	35	2024-12-19	30.0	Partial
1010	140	7	35	2024-12-19	60.0	Partial
1011	140	6	35	2024-12-19	40	Partial
1012	140	4	35	2024-12-19	80	Partial
1013	18	6	35	2024-12-19	20	Partial
1014	18	4	35	2024-12-19	80	Partial
1020	134	4	35	2024-12-19	80	Partial
1021	171	8	35	2024-12-19	30.0	Partial
1022	163	8	35	2024-12-19	30.0	Partial
1023	45	2	36	2024-12-19	30.0	Partial
1024	45	6	36	2024-12-19	40	Partial
1025	45	5	36	2024-12-19	30.0	Partial
1026	169	5	36	2024-12-19	60.0	Partial
1027	152	5	36	2024-12-19	60.0	Partial
1028	152	8	36	2024-12-19	60.0	Partial
1029	152	6	36	2024-12-19	20	Partial
1030	147	6	36	2024-12-19	20	Partial
1031	125	8	36	2024-12-19	30.0	Partial
1032	12	5	36	2024-12-19	90.0	Accepted
1033	83	2	36	2024-12-19	30.0	Partial
1034	83	8	36	2024-12-19	60.0	Partial
1035	83	5	36	2024-12-19	60.0	Partial
1042	154	6	36	2024-12-19	40	Partial
1043	154	8	36	2024-12-19	30.0	Partial
1044	18	8	36	2024-12-19	60.0	Partial
1045	61	6	36	2024-12-19	40	Partial
1046	45	3	37	2024-12-19	20	Partial
1047	45	5	37	2024-12-19	30.0	Partial
1048	45	10	37	2024-12-19	40	Partial
1049	91	10	37	2024-12-19	0	Failed
1050	91	5	37	2024-12-19	60.0	Partial
1051	91	2	37	2024-12-19	0	Failed
1052	146	10	37	2024-12-19	40	Partial
1053	39	5	37	2024-12-19	90.0	Accepted
1054	143	3	37	2024-12-19	60	Accepted
1055	143	10	37	2024-12-19	0	Failed
1056	143	2	37	2024-12-19	60.0	Accepted
1057	145	10	37	2024-12-19	0	Failed
1058	145	3	37	2024-12-19	20	Partial
1063	102	5	37	2024-12-19	90.0	Accepted
1064	102	10	37	2024-12-19	40	Partial
1065	111	3	37	2024-12-19	40	Partial
1066	111	5	37	2024-12-19	60.0	Partial
1067	138	2	37	2024-12-19	60.0	Accepted
1068	138	5	37	2024-12-19	30.0	Partial
1069	51	5	37	2024-12-19	90.0	Accepted
1070	51	2	37	2024-12-19	60.0	Accepted
1071	115	2	37	2024-12-19	30.0	Partial
1072	115	10	37	2024-12-19	120	Accepted
1073	115	3	37	2024-12-19	20	Partial
1074	144	5	37	2024-12-19	60.0	Partial
1075	144	3	37	2024-12-19	40	Partial
1076	144	2	37	2024-12-19	60.0	Accepted
1077	88	4	38	2024-12-19	40	Partial
1078	88	3	38	2024-12-19	40	Partial
1079	88	10	38	2024-12-19	120	Accepted
1085	29	8	38	2024-12-19	0	Failed
1086	175	8	38	2024-12-19	90.0	Accepted
1087	175	4	38	2024-12-19	120	Accepted
1088	175	10	38	2024-12-19	0	Failed
1089	95	3	38	2024-12-19	20	Partial
1090	95	4	38	2024-12-19	80	Partial
1091	154	8	38	2024-12-19	0	Failed
1092	154	10	38	2024-12-19	40	Partial
1093	154	3	38	2024-12-19	40	Partial
1094	113	4	38	2024-12-19	80	Partial
1095	10	3	38	2024-12-19	20	Partial
1096	10	10	38	2024-12-19	80	Partial
1097	189	4	38	2024-12-19	80	Partial
1098	189	8	38	2024-12-19	0	Failed
1099	189	10	38	2024-12-19	40	Partial
1100	38	4	38	2024-12-19	80	Partial
1106	197	3	38	2024-12-19	40	Partial
1107	197	4	38	2024-12-19	40	Partial
1108	108	3	38	2024-12-19	20	Partial
1109	44	3	38	2024-12-19	60	Accepted
1110	44	10	38	2024-12-19	40	Partial
1111	44	8	38	2024-12-19	30.0	Partial
1112	125	4	39	2024-12-19	40	Partial
1113	125	3	39	2024-12-19	20	Partial
1114	125	8	39	2024-12-19	30.0	Partial
1115	125	9	39	2024-12-19	0	Failed
1116	31	3	39	2024-12-19	20	Partial
1117	31	8	39	2024-12-19	60.0	Partial
1118	31	7	39	2024-12-19	60.0	Partial
1119	85	9	39	2024-12-19	20	Accepted
1120	85	8	39	2024-12-19	60.0	Partial
1121	40	8	39	2024-12-19	60.0	Partial
1122	40	7	39	2024-12-19	60.0	Partial
1129	70	9	39	2024-12-19	0	Failed
1130	6	7	39	2024-12-19	0	Failed
1131	6	8	39	2024-12-19	60.0	Partial
1132	6	4	39	2024-12-19	120	Accepted
1133	136	7	39	2024-12-19	60.0	Partial
1134	82	8	39	2024-12-19	60.0	Partial
1135	82	4	39	2024-12-19	80	Partial
1136	82	9	39	2024-12-19	20	Accepted
1137	82	3	39	2024-12-19	40	Partial
1138	94	8	39	2024-12-19	60.0	Partial
1139	94	3	39	2024-12-19	20	Partial
1140	94	9	39	2024-12-19	20	Accepted
1141	78	9	39	2024-12-19	0	Failed
1142	78	8	39	2024-12-19	0	Failed
1143	112	7	39	2024-12-19	30.0	Partial
1144	29	9	39	2024-12-19	20	Accepted
1145	29	7	39	2024-12-19	0	Failed
1146	29	8	39	2024-12-19	60.0	Partial
1147	132	9	39	2024-12-19	0	Failed
1148	132	8	39	2024-12-19	30.0	Partial
1154	69	4	39	2024-12-19	120	Accepted
1155	69	3	39	2024-12-19	40	Partial
1156	69	9	39	2024-12-19	0	Failed
1157	114	3	39	2024-12-19	40	Partial
1158	114	7	39	2024-12-19	30.0	Partial
1159	114	8	39	2024-12-19	90.0	Accepted
1160	114	9	39	2024-12-19	0	Failed
1161	2	9	40	2024-12-19	20	Accepted
1162	36	3	40	2024-12-19	40	Partial
1163	31	3	40	2024-12-19	40	Partial
1164	31	2	40	2024-12-19	0	Failed
1165	3	4	40	2024-12-19	80	Partial
1166	3	9	40	2024-12-19	20	Accepted
1167	145	2	40	2024-12-19	30.0	Partial
1168	12	9	40	2024-12-19	0	Failed
1169	12	2	40	2024-12-19	60.0	Accepted
1170	12	4	40	2024-12-19	80	Partial
1171	7	2	40	2024-12-19	0	Failed
1172	7	3	40	2024-12-19	40	Partial
1173	7	9	40	2024-12-19	20	Accepted
1174	85	2	40	2024-12-19	60.0	Accepted
1181	19	9	40	2024-12-19	0	Failed
1182	19	2	40	2024-12-19	0	Failed
1183	169	3	40	2024-12-19	20	Partial
1184	169	2	40	2024-12-19	30.0	Partial
1185	169	4	40	2024-12-19	120	Accepted
1186	93	10	41	2024-12-19	80	Partial
1187	93	4	41	2024-12-19	120	Accepted
1188	180	4	41	2024-12-19	80	Partial
1189	180	10	41	2024-12-19	40	Partial
1190	58	10	41	2024-12-19	40	Partial
1191	58	2	41	2024-12-19	0	Failed
1192	109	10	41	2024-12-19	80	Partial
1193	109	4	41	2024-12-19	80	Partial
1194	171	4	41	2024-12-19	40	Partial
1195	128	2	41	2024-12-19	30.0	Partial
1196	140	10	41	2024-12-19	40	Partial
1197	140	2	41	2024-12-19	60.0	Accepted
1198	8	4	41	2024-12-19	40	Partial
1204	18	4	41	2024-12-19	40	Partial
1205	18	10	41	2024-12-19	40	Partial
1206	156	4	42	2024-12-19	80	Partial
1207	96	3	42	2024-12-19	40	Partial
1208	96	2	42	2024-12-19	30.0	Partial
1209	128	3	42	2024-12-19	20	Partial
1210	128	6	42	2024-12-19	20	Partial
1211	1	6	42	2024-12-19	20	Partial
1212	1	4	42	2024-12-19	80	Partial
1213	22	2	42	2024-12-19	0	Failed
1214	22	4	42	2024-12-19	120	Accepted
1215	189	6	42	2024-12-19	0	Failed
1216	113	4	42	2024-12-19	80	Partial
1217	113	3	42	2024-12-19	40	Partial
1218	113	6	42	2024-12-19	40	Partial
1219	198	3	42	2024-12-19	40	Partial
1220	198	4	42	2024-12-19	80	Partial
1225	25	2	42	2024-12-19	60.0	Accepted
1226	25	6	42	2024-12-19	60	Accepted
1227	63	6	42	2024-12-19	20	Partial
1228	63	2	42	2024-12-19	0	Failed
1229	63	3	42	2024-12-19	0	Failed
1230	116	2	42	2024-12-19	60.0	Accepted
1231	116	6	42	2024-12-19	20	Partial
1232	190	6	42	2024-12-19	20	Partial
1233	85	2	42	2024-12-19	30.0	Partial
1234	85	4	42	2024-12-19	80	Partial
1235	40	2	42	2024-12-19	0	Failed
1236	23	7	43	2024-12-19	90.0	Accepted
1237	23	4	43	2024-12-19	80	Partial
1238	23	5	43	2024-12-19	60.0	Partial
1239	23	3	43	2024-12-19	40	Partial
1240	119	4	43	2024-12-19	80	Partial
1241	119	5	43	2024-12-19	30.0	Partial
1242	119	6	43	2024-12-19	0	Failed
1248	198	6	43	2024-12-19	40	Partial
1249	198	7	43	2024-12-19	60.0	Partial
1250	2	7	43	2024-12-19	60.0	Partial
1251	2	3	43	2024-12-19	40	Partial
1252	2	4	43	2024-12-19	0	Failed
1253	2	6	43	2024-12-19	40	Partial
1254	79	5	43	2024-12-19	30.0	Partial
1255	79	4	43	2024-12-19	80	Partial
1256	193	6	43	2024-12-19	40	Partial
1257	54	6	43	2024-12-19	40	Partial
1258	54	4	43	2024-12-19	40	Partial
1259	54	7	43	2024-12-19	90.0	Accepted
1260	54	5	43	2024-12-19	0	Failed
1261	137	5	43	2024-12-19	60.0	Partial
1262	137	4	43	2024-12-19	40	Partial
1263	137	3	43	2024-12-19	40	Partial
1268	144	5	43	2024-12-19	30.0	Partial
1269	144	4	43	2024-12-19	40	Partial
1270	144	7	43	2024-12-19	60.0	Partial
1271	8	6	43	2024-12-19	20	Partial
1272	122	6	43	2024-12-19	20	Partial
1273	122	7	43	2024-12-19	60.0	Partial
1274	122	4	43	2024-12-19	40	Partial
1275	122	3	43	2024-12-19	40	Partial
1276	66	4	43	2024-12-19	40	Partial
1277	66	6	43	2024-12-19	20	Partial
1278	66	5	43	2024-12-19	90.0	Accepted
1279	66	3	43	2024-12-19	40	Partial
1280	82	7	44	2024-12-19	60.0	Partial
1281	82	8	44	2024-12-19	0	Failed
1282	194	3	44	2024-12-19	60	Accepted
1283	194	8	44	2024-12-19	0	Failed
1289	21	3	44	2024-12-19	20	Partial
1290	188	3	44	2024-12-19	40	Partial
1291	188	7	44	2024-12-19	30.0	Partial
1292	52	7	44	2024-12-19	60.0	Partial
1293	5	8	44	2024-12-19	90.0	Accepted
1294	71	7	44	2024-12-19	30.0	Partial
1295	193	7	44	2024-12-19	30.0	Partial
1296	193	8	44	2024-12-19	30.0	Partial
1297	1	8	44	2024-12-19	30.0	Partial
1298	1	2	44	2024-12-19	0	Failed
1299	1	7	44	2024-12-19	30.0	Partial
1300	144	2	44	2024-12-19	0	Failed
1301	44	8	44	2024-12-19	60.0	Partial
1302	149	6	45	2024-12-19	40	Partial
1303	15	10	45	2024-12-19	40	Partial
1304	198	5	45	2024-12-19	60.0	Partial
1305	198	3	45	2024-12-19	60	Accepted
1311	174	10	45	2024-12-19	120	Accepted
1312	42	6	45	2024-12-19	20	Partial
1313	193	3	45	2024-12-19	40	Partial
1314	193	10	45	2024-12-19	80	Partial
1315	113	7	45	2024-12-19	30.0	Partial
1316	73	7	45	2024-12-19	60.0	Partial
1317	73	10	45	2024-12-19	0	Failed
1318	73	6	45	2024-12-19	60	Accepted
1319	109	3	45	2024-12-19	20	Partial
1320	109	6	45	2024-12-19	40	Partial
1321	118	10	45	2024-12-19	40	Partial
1322	115	7	45	2024-12-19	90.0	Accepted
1323	41	5	45	2024-12-19	60.0	Partial
1324	152	7	45	2024-12-19	60.0	Partial
1325	152	6	45	2024-12-19	0	Failed
1326	44	7	45	2024-12-19	30.0	Partial
1327	8	2	46	2024-12-19	30.0	Partial
1331	71	8	46	2024-12-19	30.0	Partial
1332	120	7	46	2024-12-19	90.0	Accepted
1333	56	2	46	2024-12-19	30.0	Partial
1334	56	8	46	2024-12-19	60.0	Partial
1335	196	8	46	2024-12-19	0	Failed
1336	180	2	46	2024-12-19	30.0	Partial
1337	180	5	46	2024-12-19	30.0	Partial
1338	41	7	46	2024-12-19	0	Failed
1339	41	8	46	2024-12-19	60.0	Partial
1340	41	2	46	2024-12-19	30.0	Partial
1341	60	2	46	2024-12-19	0	Failed
1342	60	5	46	2024-12-19	60.0	Partial
1343	21	2	46	2024-12-19	0	Failed
1344	21	7	46	2024-12-19	60.0	Partial
1345	21	8	46	2024-12-19	90.0	Accepted
1346	130	5	46	2024-12-19	60.0	Partial
1347	86	7	46	2024-12-19	30.0	Partial
1348	43	7	46	2024-12-19	30.0	Partial
1354	81	4	47	2024-12-19	40	Partial
1355	50	10	47	2024-12-19	80	Partial
1356	50	7	47	2024-12-19	30.0	Partial
1357	50	3	47	2024-12-19	40	Partial
1358	149	4	47	2024-12-19	80	Partial
1359	175	4	47	2024-12-19	80	Partial
1360	175	10	47	2024-12-19	80	Partial
1361	175	7	47	2024-12-19	0	Failed
1362	122	4	47	2024-12-19	80	Partial
1370	59	3	47	2024-12-19	20	Partial
1371	59	4	47	2024-12-19	0	Failed
1372	157	3	47	2024-12-19	20	Partial
1373	34	6	48	2024-12-19	20	Partial
1374	34	8	48	2024-12-19	30.0	Partial
1375	170	6	48	2024-12-19	20	Partial
1376	170	9	48	2024-12-19	0	Failed
1385	43	8	48	2024-12-19	60.0	Partial
1386	131	8	48	2024-12-19	30.0	Partial
1387	131	6	48	2024-12-19	20	Partial
1388	99	6	48	2024-12-19	20	Partial
1389	99	9	48	2024-12-19	0	Failed
1390	96	8	48	2024-12-19	30.0	Partial
1391	96	6	48	2024-12-19	20	Partial
1392	78	8	48	2024-12-19	30.0	Partial
1393	78	6	48	2024-12-19	20	Partial
1394	138	10	49	2024-12-19	0	Failed
1395	64	3	49	2024-12-19	20	Partial
1396	64	4	49	2024-12-19	80	Partial
1397	143	3	49	2024-12-19	40	Partial
1398	143	7	49	2024-12-19	30.0	Partial
1399	43	4	49	2024-12-19	80	Partial
1400	46	7	49	2024-12-19	60.0	Partial
1401	46	10	49	2024-12-19	120	Accepted
1406	6	10	49	2024-12-19	0	Failed
1407	6	7	49	2024-12-19	30.0	Partial
1408	6	3	49	2024-12-19	40	Partial
1409	56	4	49	2024-12-19	120	Accepted
1410	111	10	49	2024-12-19	80	Partial
1411	111	7	49	2024-12-19	0	Failed
1412	111	3	49	2024-12-19	60	Accepted
1413	14	10	49	2024-12-19	120	Accepted
1414	35	10	49	2024-12-19	40	Partial
1415	108	7	49	2024-12-19	30.0	Partial
1416	154	4	49	2024-12-19	80	Partial
1417	154	7	49	2024-12-19	60.0	Partial
1418	137	4	49	2024-12-19	80	Partial
1419	137	10	49	2024-12-19	40	Partial
1420	137	7	49	2024-12-19	60.0	Partial
1421	131	4	49	2024-12-19	80	Partial
1427	96	6	50	2024-12-19	60	Accepted
1428	156	2	50	2024-12-19	30.0	Partial
1429	156	3	50	2024-12-19	20	Partial
1430	156	10	50	2024-12-19	0	Failed
1431	51	2	50	2024-12-19	30.0	Partial
1432	51	6	50	2024-12-19	0	Failed
1433	20	3	50	2024-12-19	20	Partial
1434	20	10	50	2024-12-19	80	Partial
1435	20	8	50	2024-12-19	90.0	Accepted
1436	20	6	50	2024-12-19	40	Partial
1437	169	6	50	2024-12-19	40	Partial
1438	169	8	50	2024-12-19	30.0	Partial
1439	169	10	50	2024-12-19	40	Partial
1440	169	3	50	2024-12-19	20	Partial
1441	175	8	50	2024-12-19	60.0	Partial
1442	175	3	50	2024-12-19	40	Partial
1443	175	2	50	2024-12-19	30.0	Partial
1449	130	8	50	2024-12-19	0	Failed
1450	130	2	50	2024-12-19	0	Failed
\.


--
-- TOC entry 4956 (class 0 OID 64555)
-- Dependencies: 229
-- Data for Name: submissionline; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.submissionline (submissionline_id, submission_id, test_id, is_accepted) FROM stdin;
76	29	15	f
77	30	5	f
78	30	4	f
79	30	3	f
80	31	21	t
81	32	24	f
82	32	23	t
83	32	22	f
84	33	14	f
85	33	13	f
86	33	12	t
87	34	5	t
88	34	4	f
89	34	3	t
90	35	17	t
91	35	16	f
92	35	15	f
93	36	2	f
94	36	1	f
95	37	24	f
96	37	23	f
97	37	22	t
98	38	24	f
99	38	23	f
100	38	22	t
101	39	21	f
102	40	2	t
103	40	1	t
104	41	17	f
105	41	16	f
106	41	15	f
107	42	5	t
108	42	4	t
109	42	3	t
110	43	24	t
111	43	23	t
112	43	22	f
113	44	2	f
114	44	1	f
115	45	17	t
116	45	16	f
117	45	15	t
118	46	21	f
119	47	5	t
120	47	4	t
121	47	3	f
122	48	24	f
123	48	23	f
124	48	22	t
125	49	5	t
126	49	4	t
127	49	3	t
128	50	21	f
129	51	14	f
130	51	13	f
131	51	12	t
132	52	17	f
133	52	16	t
134	52	15	t
135	53	2	t
136	53	1	f
137	54	5	t
138	54	4	f
139	54	3	f
140	55	21	f
141	56	17	t
142	56	16	f
143	56	15	f
144	57	24	f
145	57	23	t
146	57	22	t
147	58	5	t
148	58	4	t
149	58	3	t
150	59	5	t
151	59	4	t
152	59	3	t
153	60	14	t
154	60	13	t
155	60	12	t
156	61	5	f
157	61	4	t
158	61	3	f
159	62	14	f
160	62	13	f
161	62	12	f
162	63	24	f
163	63	23	t
164	63	22	f
165	64	5	f
166	64	4	t
167	64	3	f
168	65	21	t
169	66	2	f
170	66	1	t
171	67	8	f
172	67	7	t
173	67	6	f
174	68	11	t
175	68	10	t
176	68	9	t
177	69	11	f
178	69	10	f
179	69	9	t
180	70	2	f
181	70	1	f
182	71	2	f
183	71	1	f
184	72	8	t
185	72	7	f
186	72	6	t
187	73	5	f
188	73	4	f
189	73	3	t
190	74	5	f
191	74	4	t
192	74	3	t
193	75	11	f
194	75	10	f
195	75	9	f
196	76	2	f
197	76	1	t
198	77	21	t
199	78	8	f
200	78	7	t
201	78	6	f
202	79	8	t
203	79	7	t
204	79	6	t
205	80	2	f
206	80	1	t
207	81	5	t
208	81	4	f
209	81	3	t
210	82	11	f
211	82	10	t
212	82	9	t
213	83	5	f
214	83	4	t
215	83	3	t
216	84	11	f
217	84	10	f
218	84	9	t
219	85	21	f
220	86	11	f
221	86	10	f
222	86	9	t
223	87	8	t
224	87	7	f
225	87	6	t
226	88	11	t
227	88	10	t
228	88	9	t
229	89	2	t
230	89	1	t
231	90	11	f
232	90	10	t
233	90	9	f
234	91	8	f
235	91	7	f
236	91	6	f
237	92	2	f
238	92	1	f
239	93	21	f
240	94	11	t
241	94	10	t
242	94	9	f
243	95	2	t
244	95	1	t
245	96	8	f
246	96	7	f
247	96	6	f
248	97	5	f
249	97	4	f
250	97	3	t
251	98	8	f
252	98	7	t
253	98	6	f
254	99	5	t
255	99	4	t
256	99	3	f
257	100	21	f
258	101	11	t
259	101	10	f
260	101	9	f
261	102	24	f
262	102	23	t
263	102	22	f
264	103	20	f
265	103	19	f
266	103	18	f
267	104	21	t
268	105	20	t
269	105	19	t
270	105	18	f
271	106	8	f
272	106	7	f
273	106	6	t
274	107	21	f
275	108	8	f
276	108	7	t
277	108	6	t
278	109	20	t
279	109	19	t
280	109	18	f
281	110	20	f
282	110	19	t
283	110	18	t
284	111	8	f
285	111	7	f
286	111	6	f
287	112	8	t
288	112	7	t
289	112	6	t
290	113	20	f
291	113	19	t
292	113	18	t
293	114	24	t
294	114	23	t
295	114	22	f
296	115	21	t
297	116	24	f
298	116	23	t
299	116	22	f
300	117	8	f
301	117	7	t
302	117	6	t
303	118	24	f
304	118	23	f
305	118	22	t
306	119	24	f
307	119	23	t
308	119	22	t
309	120	8	f
310	120	7	t
311	120	6	f
312	121	21	f
313	122	24	t
314	122	23	t
315	122	22	f
316	123	20	t
317	123	19	t
318	123	18	f
319	124	8	t
320	124	7	f
321	124	6	f
322	125	20	t
323	125	19	t
324	125	18	t
325	126	8	t
326	126	7	f
327	126	6	t
328	127	21	t
329	128	24	t
330	128	23	t
331	128	22	f
332	129	20	t
333	129	19	t
334	129	18	t
335	130	24	t
336	130	23	f
337	130	22	f
338	131	8	t
339	131	7	f
340	131	6	f
341	132	17	t
342	132	16	f
343	132	15	f
344	133	11	t
345	133	10	f
346	133	9	t
347	134	24	f
348	134	23	t
349	134	22	t
350	135	2	t
351	135	1	t
352	136	21	t
353	137	21	f
354	138	24	f
355	138	23	f
356	138	22	t
357	139	2	t
358	139	1	f
359	140	24	t
360	140	23	f
361	140	22	f
362	141	2	f
363	141	1	t
364	142	24	f
365	142	23	f
366	142	22	f
367	143	2	t
368	143	1	t
369	144	11	t
370	144	10	f
371	144	9	t
372	145	17	f
373	145	16	f
374	145	15	t
375	146	24	f
376	146	23	t
377	146	22	t
378	147	17	f
379	147	16	f
380	147	15	f
381	148	21	t
382	149	11	t
383	149	10	f
384	149	9	t
385	150	21	f
386	151	17	f
387	151	16	f
388	151	15	f
389	152	24	t
390	152	23	t
391	152	22	f
392	153	21	t
393	154	24	f
394	154	23	t
395	154	22	t
396	155	2	f
397	155	1	f
398	156	2	f
399	156	1	f
400	157	2	f
401	157	1	f
402	158	17	t
403	158	16	t
404	158	15	f
405	159	21	t
406	160	11	t
407	160	10	f
408	160	9	t
409	161	2	t
410	161	1	f
411	162	14	t
412	162	13	f
413	162	12	f
414	163	17	t
415	163	16	f
416	163	15	f
417	164	17	t
418	164	16	t
419	164	15	f
420	165	20	t
421	165	19	t
422	165	18	t
423	166	14	t
424	166	13	f
425	166	12	t
426	167	2	f
427	167	1	t
428	168	20	t
429	168	19	t
430	168	18	f
431	169	2	t
432	169	1	t
433	170	17	t
434	170	16	t
435	170	15	f
436	171	14	f
437	171	13	f
438	171	12	f
439	172	17	f
440	172	16	f
441	172	15	t
442	173	2	f
443	173	1	t
444	174	14	f
445	174	13	f
446	174	12	f
447	175	17	t
448	175	16	t
449	175	15	t
450	176	14	f
451	176	13	f
452	176	12	t
453	177	20	t
454	177	19	f
455	177	18	f
456	178	2	f
457	178	1	t
458	179	20	f
459	179	19	t
460	179	18	t
461	180	17	f
462	180	16	f
463	180	15	f
464	181	14	f
465	181	13	t
466	181	12	f
467	182	2	f
468	182	1	t
469	183	20	t
470	183	19	f
471	183	18	f
472	184	14	f
473	184	13	t
474	184	12	f
475	185	14	f
476	185	13	t
477	185	12	f
478	186	17	f
479	186	16	f
480	186	15	t
481	187	21	f
482	188	24	t
483	188	23	f
484	188	22	t
485	189	17	t
486	189	16	f
487	189	15	f
488	190	24	t
489	190	23	f
490	190	22	f
491	191	17	t
492	191	16	t
493	191	15	t
494	192	24	f
495	192	23	t
496	192	22	t
497	193	20	t
498	193	19	f
499	193	18	t
500	194	24	f
501	194	23	f
502	194	22	f
503	195	21	t
504	196	20	f
505	196	19	t
506	196	18	t
507	197	20	t
508	197	19	t
509	197	18	f
510	198	17	f
511	198	16	f
512	198	15	f
513	199	24	f
514	199	23	f
515	199	22	t
516	200	21	t
517	201	17	t
518	201	16	t
519	201	15	t
520	202	21	f
521	203	20	f
522	203	19	f
523	203	18	f
524	204	24	t
525	204	23	f
526	204	22	t
527	205	21	f
528	206	20	t
529	206	19	f
530	206	18	t
531	207	21	f
532	208	21	f
533	209	24	t
534	209	23	t
535	209	22	t
536	210	20	f
537	210	19	f
538	210	18	t
539	211	24	t
540	211	23	f
541	211	22	t
542	212	8	f
543	212	7	t
544	212	6	f
545	213	8	t
546	213	7	t
547	213	6	t
548	214	2	f
549	214	1	f
550	215	20	f
551	215	19	t
552	215	18	f
553	216	8	t
554	216	7	f
555	216	6	t
556	217	20	f
557	217	19	t
558	217	18	f
559	218	8	f
560	218	7	f
561	218	6	t
562	219	20	t
563	219	19	f
564	219	18	f
565	220	20	f
566	220	19	t
567	220	18	f
568	221	8	t
569	221	7	t
570	221	6	t
571	222	2	t
572	222	1	t
573	223	8	f
574	223	7	f
575	223	6	t
576	224	20	f
577	224	19	t
578	224	18	f
579	225	20	t
580	225	19	t
581	225	18	t
582	226	2	t
583	226	1	t
584	227	8	t
585	227	7	t
586	227	6	f
587	228	2	f
588	228	1	t
589	229	14	t
590	229	13	f
591	229	12	f
592	230	21	f
593	231	5	f
594	231	4	f
595	231	3	t
596	232	24	t
597	232	23	f
598	232	22	t
599	233	21	t
600	234	5	t
601	234	4	t
602	234	3	t
603	235	11	t
604	235	10	f
605	235	9	t
606	236	14	f
607	236	13	t
608	236	12	f
609	237	5	f
610	237	4	t
611	237	3	t
612	238	21	t
613	239	11	t
614	239	10	t
615	239	9	t
616	240	5	f
617	240	4	f
618	240	3	f
619	241	11	t
620	241	10	t
621	241	9	f
622	242	21	f
623	243	5	t
624	243	4	t
625	243	3	t
626	244	14	f
627	244	13	t
628	244	12	f
629	245	5	f
630	245	4	t
631	245	3	f
632	246	21	t
633	247	24	f
634	247	23	f
635	247	22	t
636	248	14	f
637	248	13	t
638	248	12	t
639	249	24	t
640	249	23	t
641	249	22	f
642	250	21	f
643	251	24	t
644	251	23	t
645	251	22	f
646	252	5	f
647	252	4	f
648	252	3	t
649	253	11	f
650	253	10	t
651	253	9	f
652	254	21	t
653	255	11	t
654	255	10	f
655	255	9	f
656	256	24	f
657	256	23	t
658	256	22	f
659	257	5	f
660	257	4	t
661	257	3	t
662	258	21	t
663	259	24	f
664	259	23	f
665	259	22	t
666	260	11	f
667	260	10	t
668	260	9	t
669	261	5	f
670	261	4	t
671	261	3	t
672	262	24	f
673	262	23	t
674	262	22	f
675	263	11	f
676	263	10	f
677	263	9	t
678	264	14	t
679	264	13	f
680	264	12	t
681	265	24	f
682	265	23	t
683	265	22	t
684	266	11	t
685	266	10	t
686	266	9	f
687	267	14	f
688	267	13	t
689	267	12	t
690	268	5	f
691	268	4	t
692	268	3	t
693	269	21	t
694	270	8	t
695	270	7	t
696	270	6	f
697	271	8	t
698	271	7	f
699	271	6	t
700	272	11	t
701	272	10	t
702	272	9	t
703	273	8	t
704	273	7	f
705	273	6	f
706	274	20	t
707	274	19	f
708	274	18	t
709	275	11	f
710	275	10	f
711	275	9	t
712	276	8	f
713	276	7	t
714	276	6	f
715	277	11	f
716	277	10	f
717	277	9	t
718	278	20	t
719	278	19	f
720	278	18	t
721	279	11	t
722	279	10	t
723	279	9	f
724	280	11	t
725	280	10	f
726	280	9	t
727	281	20	t
728	281	19	f
729	281	18	f
730	282	8	f
731	282	7	t
732	282	6	t
733	283	11	t
734	283	10	f
735	283	9	f
736	284	20	f
737	284	19	f
738	284	18	t
739	285	8	t
740	285	7	t
741	285	6	t
742	286	11	f
743	286	10	f
744	286	9	t
745	287	11	f
746	287	10	f
747	287	9	t
748	288	20	f
749	288	19	t
750	288	18	t
751	289	20	t
752	289	19	f
753	289	18	f
754	290	20	f
755	290	19	t
756	290	18	f
757	291	8	t
758	291	7	t
759	291	6	t
760	292	8	f
761	292	7	t
762	292	6	f
763	293	5	t
764	293	4	f
765	293	3	f
766	294	5	f
767	294	4	t
768	294	3	t
769	295	5	f
770	295	4	f
771	295	3	f
772	296	8	t
773	296	7	f
774	296	6	t
775	297	11	t
776	297	10	t
777	297	9	t
778	298	21	t
779	299	8	f
780	299	7	t
781	299	6	t
782	300	11	t
783	300	10	f
784	300	9	t
785	301	5	t
786	301	4	f
787	301	3	t
788	302	8	t
789	302	7	t
790	302	6	t
791	303	11	t
792	303	10	t
793	303	9	f
794	304	21	f
795	305	8	f
796	305	7	f
797	305	6	t
798	306	5	f
799	306	4	f
800	306	3	f
801	307	8	f
802	307	7	f
803	307	6	t
804	308	5	t
805	308	4	f
806	308	3	f
807	309	11	f
808	309	10	t
809	309	9	f
810	310	21	t
811	311	8	t
812	311	7	f
813	311	6	t
814	312	5	f
815	312	4	t
816	312	3	t
817	313	8	f
818	313	7	f
819	313	6	t
820	314	11	t
821	314	10	t
822	314	9	f
823	315	5	f
824	315	4	t
825	315	3	f
826	316	20	f
827	316	19	t
828	316	18	t
829	317	11	t
830	317	10	t
831	317	9	t
832	318	5	f
833	318	4	f
834	318	3	t
835	319	20	f
836	319	19	f
837	319	18	t
838	320	5	t
839	320	4	f
840	320	3	f
841	321	11	f
842	321	10	f
843	321	9	f
844	322	11	f
845	322	10	t
846	322	9	t
847	323	5	f
848	323	4	t
849	323	3	f
850	324	17	f
851	324	16	t
852	324	15	t
853	325	11	t
854	325	10	f
855	325	9	f
856	326	5	t
857	326	4	f
858	326	3	f
859	327	17	f
860	327	16	f
861	327	15	f
862	328	20	f
863	328	19	f
864	328	18	t
865	329	20	t
866	329	19	t
867	329	18	f
868	330	11	t
869	330	10	t
870	330	9	t
871	331	20	t
872	331	19	f
873	331	18	f
874	332	17	f
875	332	16	f
876	332	15	f
877	333	17	t
878	333	16	t
879	333	15	f
880	334	5	f
881	334	4	f
882	334	3	f
883	335	20	t
884	335	19	f
885	335	18	t
886	336	17	f
887	336	16	t
888	336	15	f
889	337	5	f
890	337	4	f
891	337	3	t
892	338	11	t
893	338	10	t
894	338	9	f
895	339	20	f
896	339	19	f
897	339	18	f
898	340	5	f
899	340	4	f
900	340	3	t
901	341	20	t
902	341	19	f
903	341	18	t
904	342	11	f
905	342	10	t
906	342	9	t
907	343	17	f
908	343	16	t
909	343	15	t
910	344	5	f
911	344	4	f
912	344	3	t
913	345	11	f
914	345	10	f
915	345	9	f
916	346	11	t
917	346	10	t
918	346	9	t
919	347	14	f
920	347	13	t
921	347	12	f
922	348	8	t
923	348	7	t
924	348	6	t
925	349	8	t
926	349	7	t
927	349	6	f
928	350	21	f
929	351	11	t
930	351	10	t
931	351	9	f
932	352	14	t
933	352	13	f
934	352	12	f
935	353	8	t
936	353	7	f
937	353	6	t
938	354	21	f
939	355	11	f
940	355	10	t
941	355	9	t
942	356	8	t
943	356	7	t
944	356	6	t
945	357	11	t
946	357	10	t
947	357	9	f
948	358	21	f
949	359	8	t
950	359	7	f
951	359	6	t
952	360	21	t
953	361	8	t
954	361	7	t
955	361	6	f
956	362	11	t
957	362	10	f
958	362	9	f
959	363	14	f
960	363	13	f
961	363	12	t
962	364	11	f
963	364	10	f
964	364	9	f
965	365	21	f
966	366	8	t
967	366	7	t
968	366	6	t
969	367	11	t
970	367	10	t
971	367	9	f
972	368	8	f
973	368	7	t
974	368	6	f
975	369	14	t
976	369	13	f
977	369	12	f
978	370	14	t
979	370	13	t
980	370	12	f
981	371	8	t
982	371	7	f
983	371	6	t
984	372	14	t
985	372	13	f
986	372	12	f
987	373	11	f
988	373	10	f
989	373	9	t
990	374	14	t
991	374	13	f
992	374	12	t
993	375	14	t
994	375	13	t
995	375	12	t
996	376	20	t
997	376	19	f
998	376	18	t
999	377	17	f
1000	377	16	t
1001	377	15	f
1002	378	8	f
1003	378	7	t
1004	378	6	t
1005	379	20	f
1006	379	19	f
1007	379	18	f
1008	380	17	t
1009	380	16	t
1010	380	15	f
1011	381	2	t
1012	381	1	f
1013	382	8	t
1014	382	7	t
1015	382	6	f
1016	383	17	f
1017	383	16	f
1018	383	15	f
1019	384	2	f
1020	384	1	t
1021	385	14	t
1022	385	13	f
1023	385	12	f
1024	386	17	f
1025	386	16	t
1026	386	15	f
1027	387	2	t
1028	387	1	f
1029	388	14	t
1030	388	13	t
1031	388	12	f
1032	389	8	t
1033	389	7	f
1034	389	6	t
1035	390	17	t
1036	390	16	f
1037	390	15	t
1038	391	20	t
1039	391	19	f
1040	391	18	f
1041	392	2	f
1042	392	1	f
1043	393	17	t
1044	393	16	t
1045	393	15	t
1046	394	14	f
1047	394	13	f
1048	394	12	f
1049	395	2	f
1050	395	1	t
1051	396	20	f
1052	396	19	f
1053	396	18	f
1054	397	17	t
1055	397	16	f
1056	397	15	f
1057	398	14	f
1058	398	13	t
1059	398	12	f
1060	399	8	f
1061	399	7	t
1062	399	6	f
1063	400	17	t
1064	400	16	f
1065	400	15	t
1066	401	20	f
1067	401	19	f
1068	401	18	f
1069	402	8	t
1070	402	7	f
1071	402	6	t
1072	403	2	t
1073	403	1	f
1074	404	20	t
1075	404	19	f
1076	404	18	f
1077	405	8	t
1078	405	7	f
1079	405	6	f
1080	406	8	f
1081	406	7	f
1082	406	6	t
1083	407	17	f
1084	407	16	f
1085	407	15	f
1086	408	2	f
1087	408	1	t
1088	409	2	t
1089	409	1	t
1090	410	8	f
1091	410	7	f
1092	410	6	t
1093	411	17	f
1094	411	16	f
1095	411	15	f
1096	412	20	f
1097	412	19	f
1098	412	18	t
1099	413	2	f
1100	413	1	f
1101	414	2	f
1102	414	1	f
1103	415	17	t
1104	415	16	t
1105	415	15	f
1106	416	14	t
1107	416	13	f
1108	416	12	t
1109	417	20	f
1110	417	19	t
1111	417	18	f
1112	418	2	t
1113	418	1	f
1114	419	17	f
1115	419	16	t
1116	419	15	t
1117	420	8	f
1118	420	7	t
1119	420	6	f
1120	421	5	f
1121	421	4	f
1122	421	3	t
1123	422	14	f
1124	422	13	t
1125	422	12	t
1126	423	5	f
1127	423	4	t
1128	423	3	f
1129	424	14	f
1130	424	13	f
1131	424	12	f
1132	425	5	f
1133	425	4	f
1134	425	3	t
1135	426	14	f
1136	426	13	t
1137	426	12	t
1138	427	17	t
1139	427	16	t
1140	427	15	t
1141	428	17	t
1142	428	16	f
1143	428	15	f
1144	429	5	f
1145	429	4	t
1146	429	3	f
1147	430	17	t
1148	430	16	f
1149	430	15	t
1150	431	5	f
1151	431	4	t
1152	431	3	t
1153	432	14	f
1154	432	13	t
1155	432	12	f
1156	433	17	t
1157	433	16	t
1158	433	15	f
1159	434	5	t
1160	434	4	f
1161	434	3	t
1162	435	14	f
1163	435	13	t
1164	435	12	f
1165	436	5	f
1166	436	4	f
1167	436	3	t
1168	437	17	t
1169	437	16	t
1170	437	15	t
1171	438	14	t
1172	438	13	f
1173	438	12	t
1174	439	5	t
1175	439	4	f
1176	439	3	f
1177	440	14	f
1178	440	13	f
1179	440	12	t
1180	441	5	t
1181	441	4	f
1182	441	3	t
1183	442	20	f
1184	442	19	f
1185	442	18	f
1186	443	21	f
1187	444	2	f
1188	444	1	f
1189	445	17	t
1190	445	16	f
1191	445	15	f
1192	446	2	t
1193	446	1	t
1194	447	20	t
1195	447	19	t
1196	447	18	t
1197	448	17	t
1198	448	16	t
1199	448	15	t
1200	449	20	t
1201	449	19	f
1202	449	18	f
1203	450	2	t
1204	450	1	t
1205	451	20	f
1206	451	19	f
1207	451	18	t
1208	452	17	f
1209	452	16	t
1210	452	15	f
1211	453	17	t
1212	453	16	t
1213	453	15	t
1214	454	17	t
1215	454	16	f
1216	454	15	f
1217	455	17	f
1218	455	16	t
1219	455	15	f
1220	456	21	f
1221	457	2	f
1222	457	1	f
1223	458	2	f
1224	458	1	t
1225	459	21	f
1226	460	20	f
1227	460	19	f
1228	460	18	t
1229	461	21	t
1230	462	2	f
1231	462	1	f
1232	463	2	f
1233	463	1	f
1234	464	21	t
1235	465	17	f
1236	465	16	f
1237	465	15	f
1238	466	21	t
1239	467	20	f
1240	467	19	t
1241	467	18	t
1242	468	8	t
1243	468	7	t
1244	468	6	t
1245	469	20	f
1246	469	19	f
1247	469	18	t
1248	470	8	f
1249	470	7	t
1250	470	6	f
1251	471	11	f
1252	471	10	t
1253	471	9	f
1254	472	17	f
1255	472	16	f
1256	472	15	t
1257	473	20	f
1258	473	19	t
1259	473	18	f
1260	474	20	t
1261	474	19	t
1262	474	18	f
1263	475	17	f
1264	475	16	f
1265	475	15	t
1266	476	17	f
1267	476	16	t
1268	476	15	f
1269	477	11	f
1270	477	10	f
1271	477	9	t
1272	478	8	f
1273	478	7	t
1274	478	6	f
1275	479	11	f
1276	479	10	f
1277	479	9	t
1278	480	17	t
1279	480	16	t
1280	480	15	f
1281	481	11	t
1282	481	10	f
1283	481	9	t
1284	482	20	f
1285	482	19	t
1286	482	18	f
1287	483	8	f
1288	483	7	f
1289	483	6	f
1290	484	8	t
1291	484	7	f
1292	484	6	f
1293	485	2	f
1294	485	1	t
1295	486	2	f
1296	486	1	f
1297	487	2	t
1298	487	1	t
1299	488	17	t
1300	488	16	f
1301	488	15	t
1302	489	5	f
1303	489	4	f
1304	489	3	t
1305	490	5	f
1306	490	4	t
1307	490	3	f
1308	491	17	t
1309	491	16	f
1310	491	15	t
1311	492	2	t
1312	492	1	f
1313	493	5	t
1314	493	4	t
1315	493	3	f
1316	494	2	t
1317	494	1	f
1318	495	17	t
1319	495	16	f
1320	495	15	t
1321	496	17	t
1322	496	16	t
1323	496	15	t
1324	497	2	f
1325	497	1	f
1326	498	5	t
1327	498	4	f
1328	498	3	t
1329	499	17	f
1330	499	16	f
1331	499	15	t
1332	500	17	t
1333	500	16	t
1334	500	15	t
1335	501	5	t
1336	501	4	t
1337	501	3	f
1338	502	24	f
1339	502	23	f
1340	502	22	f
1341	503	5	t
1342	503	4	f
1343	503	3	t
1344	504	21	t
1345	505	21	f
1346	506	17	f
1347	506	16	f
1348	506	15	t
1349	507	24	f
1350	507	23	t
1351	507	22	t
1352	508	5	t
1353	508	4	t
1354	508	3	t
1355	509	17	t
1356	509	16	t
1357	509	15	f
1358	510	21	f
1359	511	24	f
1360	511	23	f
1361	511	22	f
1362	512	17	t
1363	512	16	f
1364	512	15	f
1365	513	17	t
1366	513	16	f
1367	513	15	t
1368	514	21	f
1369	515	24	t
1370	515	23	f
1371	515	22	f
1372	516	5	f
1373	516	4	f
1374	516	3	f
1375	517	24	f
1376	517	23	t
1377	517	22	f
1378	518	17	t
1379	518	16	t
1380	518	15	t
1381	519	21	f
1382	520	24	t
1383	520	23	t
1384	520	22	f
1385	521	17	f
1386	521	16	f
1387	521	15	f
1388	522	17	t
1389	522	16	t
1390	522	15	f
1391	523	5	t
1392	523	4	f
1393	523	3	t
1394	524	21	t
1395	525	21	t
1396	526	5	t
1397	526	4	f
1398	526	3	f
1399	527	8	t
1400	527	7	f
1401	527	6	f
1402	528	5	f
1403	528	4	f
1404	528	3	f
1405	529	5	t
1406	529	4	f
1407	529	3	f
1408	530	11	t
1409	530	10	f
1410	530	9	t
1411	531	8	t
1412	531	7	f
1413	531	6	f
1414	532	20	f
1415	532	19	f
1416	532	18	t
1417	533	8	f
1418	533	7	f
1419	533	6	f
1420	534	8	f
1421	534	7	t
1422	534	6	f
1423	535	20	t
1424	535	19	f
1425	535	18	f
1426	536	20	t
1427	536	19	t
1428	536	18	t
1429	537	20	t
1430	537	19	t
1431	537	18	t
1432	538	5	f
1433	538	4	f
1434	538	3	f
1435	539	20	t
1436	539	19	t
1437	539	18	f
1438	540	11	t
1439	540	10	t
1440	540	9	f
1441	541	5	f
1442	541	4	f
1443	541	3	t
1444	542	11	t
1445	542	10	f
1446	542	9	f
1447	543	20	t
1448	543	19	f
1449	543	18	f
1450	544	11	t
1451	544	10	t
1452	544	9	t
1453	545	8	t
1454	545	7	f
1455	545	6	f
1456	546	5	t
1457	546	4	f
1458	546	3	t
1459	547	5	f
1460	547	4	f
1461	547	3	f
1462	548	8	t
1463	548	7	t
1464	548	6	t
1465	549	11	f
1466	549	10	t
1467	549	9	t
1468	550	20	f
1469	550	19	f
1470	550	18	t
1471	551	24	f
1472	551	23	t
1473	551	22	t
1474	552	20	t
1475	552	19	t
1476	552	18	t
1477	553	24	f
1478	553	23	t
1479	553	22	f
1480	554	5	f
1481	554	4	f
1482	554	3	f
1483	555	24	f
1484	555	23	t
1485	555	22	f
1486	556	24	t
1487	556	23	t
1488	556	22	t
1489	557	11	f
1490	557	10	f
1491	557	9	f
1492	558	5	f
1493	558	4	t
1494	558	3	f
1495	559	11	t
1496	559	10	t
1497	559	9	f
1498	560	11	t
1499	560	10	f
1500	560	9	f
1501	561	5	f
1502	561	4	t
1503	561	3	t
1504	562	20	t
1505	562	19	f
1506	562	18	f
1507	563	11	t
1508	563	10	t
1509	563	9	f
1510	564	5	f
1511	564	4	f
1512	564	3	t
1513	565	5	f
1514	565	4	t
1515	565	3	f
1516	566	20	f
1517	566	19	f
1518	566	18	t
1519	567	5	f
1520	567	4	t
1521	567	3	f
1522	568	20	f
1523	568	19	f
1524	568	18	f
1525	569	20	t
1526	569	19	f
1527	569	18	f
1528	570	24	t
1529	570	23	f
1530	570	22	f
1531	571	24	t
1532	571	23	f
1533	571	22	t
1534	572	11	t
1535	572	10	f
1536	572	9	t
1537	573	5	t
1538	573	4	t
1539	573	3	f
1540	574	20	f
1541	574	19	f
1542	574	18	f
1543	575	20	t
1544	575	19	f
1545	575	18	t
1546	576	11	f
1547	576	10	t
1548	576	9	t
1549	577	2	t
1550	577	1	t
1551	578	11	f
1552	578	10	f
1553	578	9	t
1554	579	14	t
1555	579	13	f
1556	579	12	t
1557	580	14	t
1558	580	13	f
1559	580	12	f
1560	581	20	t
1561	581	19	t
1562	581	18	f
1563	582	2	f
1564	582	1	t
1565	583	8	t
1566	583	7	t
1567	583	6	f
1568	584	11	f
1569	584	10	t
1570	584	9	f
1571	585	20	f
1572	585	19	f
1573	585	18	t
1574	586	14	t
1575	586	13	t
1576	586	12	f
1577	587	11	f
1578	587	10	t
1579	587	9	t
1580	588	2	f
1581	588	1	f
1582	589	8	t
1583	589	7	t
1584	589	6	t
1585	590	20	t
1586	590	19	t
1587	590	18	f
1588	591	14	f
1589	591	13	f
1590	591	12	t
1591	592	2	t
1592	592	1	f
1593	593	8	f
1594	593	7	t
1595	593	6	t
1596	594	20	f
1597	594	19	f
1598	594	18	t
1599	595	11	t
1600	595	10	t
1601	595	9	t
1602	596	2	t
1603	596	1	f
1604	597	14	f
1605	597	13	f
1606	597	12	f
1607	598	14	t
1608	598	13	t
1609	598	12	t
1610	599	2	f
1611	599	1	t
1612	600	8	t
1613	600	7	f
1614	600	6	t
1615	601	11	t
1616	601	10	t
1617	601	9	f
1618	602	14	f
1619	602	13	t
1620	602	12	f
1621	603	11	f
1622	603	10	t
1623	603	9	f
1624	604	2	f
1625	604	1	f
1626	605	8	t
1627	605	7	t
1628	605	6	t
1629	606	11	t
1630	606	10	t
1631	606	9	t
1632	607	20	f
1633	607	19	t
1634	607	18	t
1635	608	11	f
1636	608	10	f
1637	608	9	f
1638	609	8	t
1639	609	7	t
1640	609	6	f
1641	610	2	f
1642	610	1	f
1643	611	20	t
1644	611	19	f
1645	611	18	f
1646	612	8	f
1647	612	7	t
1648	612	6	t
1649	613	8	f
1650	613	7	t
1651	613	6	t
1652	614	20	t
1653	614	19	f
1654	614	18	t
1655	615	8	t
1656	615	7	f
1657	615	6	f
1658	616	14	t
1659	616	13	f
1660	616	12	t
1661	617	11	t
1662	617	10	t
1663	617	9	t
1664	618	20	f
1665	618	19	f
1666	618	18	t
1667	619	2	f
1668	619	1	f
1669	620	20	t
1670	620	19	f
1671	620	18	f
1672	621	2	t
1673	621	1	f
1674	622	11	t
1675	622	10	t
1676	622	9	f
1677	623	11	t
1678	623	10	f
1679	623	9	t
1680	624	20	f
1681	624	19	f
1682	624	18	f
1683	625	14	f
1684	625	13	t
1685	625	12	t
1686	626	11	t
1687	626	10	t
1688	626	9	t
1689	627	2	f
1690	627	1	t
1691	628	11	t
1692	628	10	t
1693	628	9	t
1694	629	11	f
1695	629	10	f
1696	629	9	t
1697	630	8	t
1698	630	7	t
1699	630	6	t
1700	631	11	f
1701	631	10	t
1702	631	9	t
1703	632	2	f
1704	632	1	t
1705	633	2	t
1706	633	1	f
1707	634	8	f
1708	634	7	t
1709	634	6	t
1710	635	8	f
1711	635	7	t
1712	635	6	t
1713	636	8	f
1714	636	7	f
1715	636	6	t
1716	637	11	f
1717	637	10	t
1718	637	9	t
1719	638	2	f
1720	638	1	t
1721	639	11	f
1722	639	10	f
1723	639	9	f
1724	640	8	f
1725	640	7	t
1726	640	6	f
1727	641	11	f
1728	641	10	t
1729	641	9	f
1730	642	8	f
1731	642	7	t
1732	642	6	f
1733	643	2	t
1734	643	1	f
1735	644	2	t
1736	644	1	f
1737	645	11	t
1738	645	10	t
1739	645	9	f
1740	646	11	f
1741	646	10	f
1742	646	9	f
1743	647	8	f
1744	647	7	t
1745	647	6	f
1746	648	2	f
1747	648	1	t
1748	649	24	t
1749	649	23	f
1750	649	22	t
1751	650	5	f
1752	650	4	f
1753	650	3	t
1754	651	5	t
1755	651	4	t
1756	651	3	t
1757	652	17	f
1758	652	16	f
1759	652	15	t
1760	653	20	t
1761	653	19	t
1762	653	18	f
1763	654	17	f
1764	654	16	t
1765	654	15	f
1766	655	24	t
1767	655	23	f
1768	655	22	t
1769	656	20	f
1770	656	19	t
1771	656	18	f
1772	657	24	t
1773	657	23	t
1774	657	22	t
1775	658	17	t
1776	658	16	f
1777	658	15	t
1778	659	5	f
1779	659	4	f
1780	659	3	f
1781	660	24	t
1782	660	23	f
1783	660	22	f
1784	661	17	t
1785	661	16	f
1786	661	15	f
1787	662	5	t
1788	662	4	t
1789	662	3	t
1790	663	24	t
1791	663	23	t
1792	663	22	f
1793	664	24	t
1794	664	23	t
1795	664	22	t
1796	665	20	t
1797	665	19	t
1798	665	18	f
1799	666	24	t
1800	666	23	t
1801	666	22	t
1802	667	20	f
1803	667	19	f
1804	667	18	t
1805	668	17	t
1806	668	16	t
1807	668	15	f
1808	669	20	t
1809	669	19	f
1810	669	18	f
1811	670	20	f
1812	670	19	t
1813	670	18	t
1814	671	17	f
1815	671	16	f
1816	671	15	f
1817	672	24	t
1818	672	23	t
1819	672	22	f
1820	673	17	t
1821	673	16	f
1822	673	15	t
1823	674	20	f
1824	674	19	f
1825	674	18	t
1826	675	24	t
1827	675	23	t
1828	675	22	t
1829	676	17	t
1830	676	16	t
1831	676	15	f
1832	677	20	t
1833	677	19	t
1834	677	18	f
1835	678	8	f
1836	678	7	t
1837	678	6	f
1838	679	8	f
1839	679	7	t
1840	679	6	t
1841	680	20	t
1842	680	19	f
1843	680	18	t
1844	681	20	f
1845	681	19	f
1846	681	18	f
1847	682	8	t
1848	682	7	f
1849	682	6	t
1850	683	20	f
1851	683	19	t
1852	683	18	f
1853	684	8	f
1854	684	7	f
1855	684	6	t
1856	685	8	f
1857	685	7	f
1858	685	6	f
1859	686	11	f
1860	686	10	f
1861	686	9	f
1862	687	20	t
1863	687	19	f
1864	687	18	f
1865	688	8	f
1866	688	7	t
1867	688	6	t
1868	689	20	f
1869	689	19	t
1870	689	18	f
1871	690	11	f
1872	690	10	t
1873	690	9	t
1874	691	11	f
1875	691	10	t
1876	691	9	f
1877	692	20	t
1878	692	19	f
1879	692	18	t
1880	693	11	f
1881	693	10	t
1882	693	9	t
1883	694	11	f
1884	694	10	f
1885	694	9	t
1886	695	8	f
1887	695	7	t
1888	695	6	f
1889	696	8	t
1890	696	7	f
1891	696	6	f
1892	697	20	f
1893	697	19	f
1894	697	18	f
1895	698	20	t
1896	698	19	f
1897	698	18	f
1898	699	8	f
1899	699	7	t
1900	699	6	t
1901	700	8	t
1902	700	7	t
1903	700	6	t
1904	701	20	f
1905	701	19	t
1906	701	18	t
1907	702	5	t
1908	702	4	t
1909	702	3	t
1910	703	5	t
1911	703	4	f
1912	703	3	t
1913	704	24	t
1914	704	23	t
1915	704	22	t
1916	705	5	f
1917	705	4	t
1918	705	3	t
1919	706	5	f
1920	706	4	f
1921	706	3	f
1922	707	24	f
1923	707	23	t
1924	707	22	t
1925	708	20	f
1926	708	19	f
1927	708	18	t
1928	709	5	f
1929	709	4	t
1930	709	3	t
1931	710	24	f
1932	710	23	t
1933	710	22	f
1934	711	24	f
1935	711	23	t
1936	711	22	f
1937	712	5	t
1938	712	4	f
1939	712	3	f
1940	713	24	f
1941	713	23	t
1942	713	22	t
1943	714	20	t
1944	714	19	f
1945	714	18	t
1946	715	5	t
1947	715	4	t
1948	715	3	f
1949	716	20	t
1950	716	19	f
1951	716	18	f
1952	717	20	t
1953	717	19	t
1954	717	18	f
1955	718	24	t
1956	718	23	f
1957	718	22	t
1958	719	5	t
1959	719	4	t
1960	719	3	f
1961	720	14	f
1962	720	13	t
1963	720	12	t
1964	721	14	t
1965	721	13	t
1966	721	12	t
1967	722	11	t
1968	722	10	f
1969	722	9	t
1970	723	5	t
1971	723	4	f
1972	723	3	t
1973	724	5	t
1974	724	4	f
1975	724	3	f
1976	725	11	f
1977	725	10	f
1978	725	9	t
1979	726	24	f
1980	726	23	f
1981	726	22	t
1982	727	5	t
1983	727	4	f
1984	727	3	f
1985	728	11	t
1986	728	10	t
1987	728	9	t
1988	729	14	f
1989	729	13	t
1990	729	12	t
1991	730	5	t
1992	730	4	t
1993	730	3	t
1994	731	24	t
1995	731	23	t
1996	731	22	t
1997	732	24	f
1998	732	23	t
1999	732	22	t
2000	733	11	f
2001	733	10	f
2002	733	9	t
2003	734	14	t
2004	734	13	t
2005	734	12	t
2006	735	24	f
2007	735	23	t
2008	735	22	f
2009	736	11	f
2010	736	10	f
2011	736	9	f
2012	737	24	t
2013	737	23	t
2014	737	22	f
2015	738	5	f
2016	738	4	f
2017	738	3	t
2018	739	24	f
2019	739	23	f
2020	739	22	t
2021	740	5	t
2022	740	4	f
2023	740	3	f
2024	741	11	t
2025	741	10	f
2026	741	9	t
2027	742	5	t
2028	742	4	f
2029	742	3	f
2030	743	11	f
2031	743	10	t
2032	743	9	t
2033	744	5	t
2034	744	4	f
2035	744	3	f
2036	745	24	t
2037	745	23	f
2038	745	22	t
2039	746	11	t
2040	746	10	t
2041	746	9	t
2042	747	5	f
2043	747	4	f
2044	747	3	f
2045	748	24	t
2046	748	23	f
2047	748	22	f
2048	749	21	f
2049	750	24	t
2050	750	23	t
2051	750	22	f
2052	751	24	t
2053	751	23	f
2054	751	22	f
2055	752	24	f
2056	752	23	t
2057	752	22	f
2058	753	21	t
2059	754	21	t
2060	755	11	f
2061	755	10	f
2062	755	9	t
2063	756	24	t
2064	756	23	t
2065	756	22	t
2066	757	11	f
2067	757	10	t
2068	757	9	f
2069	758	24	t
2070	758	23	f
2071	758	22	t
2072	759	21	t
2073	760	24	t
2074	760	23	t
2075	760	22	f
2076	761	21	t
2077	762	24	f
2078	762	23	t
2079	762	22	t
2080	763	24	f
2081	763	23	f
2082	763	22	f
2083	764	11	t
2084	764	10	t
2085	764	9	f
2086	765	21	f
2087	766	21	t
2088	767	21	f
2089	768	24	f
2090	768	23	t
2091	768	22	t
2092	769	24	t
2093	769	23	f
2094	769	22	f
2095	770	11	f
2096	770	10	t
2097	770	9	t
2098	771	21	t
2099	772	17	f
2100	772	16	t
2101	772	15	t
2102	773	20	t
2103	773	19	t
2104	773	18	t
2105	774	11	t
2106	774	10	t
2107	774	9	f
2108	775	17	t
2109	775	16	t
2110	775	15	t
2111	776	20	f
2112	776	19	f
2113	776	18	t
2114	777	17	t
2115	777	16	t
2116	777	15	t
2117	778	20	t
2118	778	19	f
2119	778	18	f
2120	779	5	f
2121	779	4	f
2122	779	3	t
2123	780	17	t
2124	780	16	f
2125	780	15	t
2126	781	21	t
2127	782	20	t
2128	782	19	f
2129	782	18	t
2130	783	17	t
2131	783	16	f
2132	783	15	t
2133	784	17	f
2134	784	16	t
2135	784	15	t
2136	785	5	f
2137	785	4	t
2138	785	3	t
2139	786	11	t
2140	786	10	f
2141	786	9	f
2142	787	17	f
2143	787	16	f
2144	787	15	t
2145	788	21	f
2146	789	11	f
2147	789	10	t
2148	789	9	f
2149	790	20	f
2150	790	19	t
2151	790	18	t
2152	791	5	f
2153	791	4	t
2154	791	3	f
2155	792	11	t
2156	792	10	f
2157	792	9	f
2158	793	21	f
2159	794	11	f
2160	794	10	t
2161	794	9	t
2162	795	17	t
2163	795	16	t
2164	795	15	t
2165	796	20	t
2166	796	19	f
2167	796	18	t
2168	797	11	t
2169	797	10	f
2170	797	9	t
2171	798	17	t
2172	798	16	t
2173	798	15	f
2174	799	21	t
2175	800	11	f
2176	800	10	t
2177	800	9	f
2178	801	20	f
2179	801	19	f
2180	801	18	t
2181	802	11	f
2182	802	10	t
2183	802	9	t
2184	803	17	f
2185	803	16	t
2186	803	15	t
2187	804	21	f
2188	805	20	t
2189	805	19	t
2190	805	18	f
2191	806	5	t
2192	806	4	t
2193	806	3	f
2194	807	11	t
2195	807	10	f
2196	807	9	t
2197	808	20	f
2198	808	19	t
2199	808	18	t
2200	809	5	t
2201	809	4	t
2202	809	3	f
2203	810	17	t
2204	810	16	f
2205	810	15	f
2206	811	14	f
2207	811	13	t
2208	811	12	t
2209	812	17	t
2210	812	16	t
2211	812	15	f
2212	813	17	t
2213	813	16	f
2214	813	15	t
2215	814	17	f
2216	814	16	t
2217	814	15	t
2218	815	14	f
2219	815	13	f
2220	815	12	t
2221	816	20	f
2222	816	19	t
2223	816	18	f
2224	817	8	f
2225	817	7	t
2226	817	6	f
2227	818	14	t
2228	818	13	f
2229	818	12	f
2230	819	8	f
2231	819	7	f
2232	819	6	t
2233	820	20	t
2234	820	19	f
2235	820	18	t
2236	821	14	f
2237	821	13	f
2238	821	12	t
2239	822	17	f
2240	822	16	f
2241	822	15	f
2242	823	14	t
2243	823	13	t
2244	823	12	t
2245	824	17	t
2246	824	16	t
2247	824	15	f
2248	825	8	t
2249	825	7	f
2250	825	6	f
2251	826	8	t
2252	826	7	t
2253	826	6	t
2254	827	17	f
2255	827	16	f
2256	827	15	t
2257	828	14	f
2258	828	13	t
2259	828	12	f
2260	829	17	t
2261	829	16	f
2262	829	15	f
2263	830	24	t
2264	830	23	f
2265	830	22	f
2266	831	11	f
2267	831	10	t
2268	831	9	f
2269	832	8	t
2270	832	7	t
2271	832	6	f
2272	833	8	t
2273	833	7	f
2274	833	6	t
2275	834	11	t
2276	834	10	t
2277	834	9	t
2278	835	21	f
2279	836	24	f
2280	836	23	t
2281	836	22	f
2282	837	21	t
2283	838	11	t
2284	838	10	t
2285	838	9	f
2286	839	24	f
2287	839	23	t
2288	839	22	f
2289	840	8	f
2290	840	7	f
2291	840	6	f
2292	841	8	t
2293	841	7	f
2294	841	6	t
2295	842	11	f
2296	842	10	t
2297	842	9	f
2298	843	24	f
2299	843	23	f
2300	843	22	f
2301	844	24	t
2302	844	23	f
2303	844	22	f
2304	845	21	t
2305	846	11	t
2306	846	10	t
2307	846	9	t
2308	847	8	f
2309	847	7	f
2310	847	6	f
2311	848	11	f
2312	848	10	f
2313	848	9	f
2314	849	21	t
2315	850	11	t
2316	850	10	f
2317	850	9	f
2318	851	11	t
2319	851	10	t
2320	851	9	f
2321	852	8	f
2322	852	7	t
2323	852	6	t
2324	853	21	t
2325	854	8	t
2326	854	7	f
2327	854	6	t
2328	855	21	t
2329	856	20	t
2330	856	19	f
2331	856	18	f
2332	857	20	t
2333	857	19	t
2334	857	18	f
2335	858	21	f
2336	859	17	f
2337	859	16	f
2338	859	15	t
2339	860	21	t
2340	861	8	f
2341	861	7	t
2342	861	6	f
2343	862	17	f
2344	862	16	t
2345	862	15	t
2346	863	8	f
2347	863	7	t
2348	863	6	t
2349	864	17	f
2350	864	16	t
2351	864	15	t
2352	865	20	t
2353	865	19	f
2354	865	18	f
2355	866	17	t
2356	866	16	f
2357	866	15	t
2358	867	20	t
2359	867	19	f
2360	867	18	f
2361	868	8	t
2362	868	7	t
2363	868	6	t
2364	869	17	t
2365	869	16	f
2366	869	15	t
2367	870	20	f
2368	870	19	t
2369	870	18	f
2370	871	21	t
2371	872	21	t
2372	873	20	t
2373	873	19	t
2374	873	18	f
2375	874	8	t
2376	874	7	t
2377	874	6	t
2378	875	20	f
2379	875	19	t
2380	875	18	t
2381	876	21	t
2382	877	17	f
2383	877	16	f
2384	877	15	t
2385	878	21	t
2386	879	8	t
2387	879	7	t
2388	879	6	t
2389	880	17	t
2390	880	16	t
2391	880	15	f
2392	881	20	t
2393	881	19	f
2394	881	18	f
2395	882	17	f
2396	882	16	t
2397	882	15	f
2398	883	21	t
2399	884	24	f
2400	884	23	f
2401	884	22	t
2402	885	20	f
2403	885	19	f
2404	885	18	f
2405	886	8	f
2406	886	7	t
2407	886	6	t
2408	887	8	f
2409	887	7	t
2410	887	6	t
2411	888	20	f
2412	888	19	t
2413	888	18	f
2414	889	8	f
2415	889	7	f
2416	889	6	f
2417	890	2	f
2418	890	1	t
2419	891	20	t
2420	891	19	t
2421	891	18	f
2422	892	20	f
2423	892	19	f
2424	892	18	t
2425	893	2	t
2426	893	1	t
2427	894	2	f
2428	894	1	t
2429	895	24	f
2430	895	23	t
2431	895	22	t
2432	896	20	f
2433	896	19	t
2434	896	18	f
2435	897	24	t
2436	897	23	t
2437	897	22	t
2438	898	2	t
2439	898	1	f
2440	899	2	t
2441	899	1	f
2442	900	24	f
2443	900	23	t
2444	900	22	f
2445	901	8	t
2446	901	7	f
2447	901	6	t
2448	902	2	t
2449	902	1	t
2450	903	8	t
2451	903	7	t
2452	903	6	t
2453	904	24	f
2454	904	23	t
2455	904	22	f
2456	905	2	t
2457	905	1	t
2458	906	24	t
2459	906	23	t
2460	906	22	f
2461	907	20	t
2462	907	19	f
2463	907	18	t
2464	908	24	t
2465	908	23	f
2466	908	22	t
2467	909	2	f
2468	909	1	f
2469	910	24	t
2470	910	23	f
2471	910	22	t
2472	911	20	f
2473	911	19	f
2474	911	18	t
2475	912	24	f
2476	912	23	t
2477	912	22	f
2478	913	20	t
2479	913	19	f
2480	913	18	f
2481	914	2	t
2482	914	1	t
2483	915	20	f
2484	915	19	t
2485	915	18	f
2486	916	2	t
2487	916	1	f
2488	917	24	f
2489	917	23	t
2490	917	22	f
2491	918	2	t
2492	918	1	t
2493	919	8	t
2494	919	7	f
2495	919	6	f
2496	920	20	f
2497	920	19	t
2498	920	18	f
2499	921	24	t
2500	921	23	t
2501	921	22	f
2502	922	20	f
2503	922	19	f
2504	922	18	f
2505	923	8	f
2506	923	7	t
2507	923	6	t
2508	924	2	f
2509	924	1	t
2510	925	20	t
2511	925	19	t
2512	925	18	t
2513	926	14	t
2514	926	13	f
2515	926	12	f
2516	927	24	f
2517	927	23	t
2518	927	22	t
2519	928	11	f
2520	928	10	f
2521	928	9	t
2522	929	24	f
2523	929	23	f
2524	929	22	t
2525	930	11	f
2526	930	10	f
2527	930	9	t
2528	931	8	f
2529	931	7	f
2530	931	6	t
2531	932	17	f
2532	932	16	t
2533	932	15	t
2534	933	17	t
2535	933	16	f
2536	933	15	t
2537	934	11	f
2538	934	10	t
2539	934	9	t
2540	935	11	f
2541	935	10	t
2542	935	9	t
2543	936	8	f
2544	936	7	t
2545	936	6	t
2546	937	14	f
2547	937	13	f
2548	937	12	t
2549	938	24	t
2550	938	23	f
2551	938	22	f
2552	939	14	f
2553	939	13	f
2554	939	12	t
2555	940	11	f
2556	940	10	t
2557	940	9	t
2558	941	24	f
2559	941	23	t
2560	941	22	f
2561	942	14	t
2562	942	13	f
2563	942	12	t
2564	943	8	f
2565	943	7	t
2566	943	6	f
2567	944	11	t
2568	944	10	f
2569	944	9	t
2570	945	14	t
2571	945	13	f
2572	945	12	t
2573	946	11	t
2574	946	10	t
2575	946	9	t
2576	947	24	f
2577	947	23	t
2578	947	22	t
2579	948	17	f
2580	948	16	t
2581	948	15	t
2582	949	14	f
2583	949	13	t
2584	949	12	f
2585	950	17	f
2586	950	16	t
2587	950	15	f
2588	951	11	f
2589	951	10	t
2590	951	9	f
2591	952	8	f
2592	952	7	t
2593	952	6	t
2594	953	8	t
2595	953	7	f
2596	953	6	t
2597	954	8	f
2598	954	7	f
2599	954	6	t
2600	955	14	f
2601	955	13	f
2602	955	12	t
2603	956	8	f
2604	956	7	t
2605	956	6	f
2606	957	14	t
2607	957	13	t
2608	957	12	t
2609	958	11	f
2610	958	10	t
2611	958	9	f
2612	959	24	t
2613	959	23	f
2614	959	22	f
2615	960	8	f
2616	960	7	t
2617	960	6	f
2618	961	11	f
2619	961	10	t
2620	961	9	t
2621	962	8	t
2622	962	7	f
2623	962	6	f
2624	963	2	t
2625	963	1	t
2626	964	5	f
2627	964	4	t
2628	964	3	f
2629	965	8	t
2630	965	7	t
2631	965	6	t
2632	966	2	t
2633	966	1	t
2634	967	17	f
2635	967	16	t
2636	967	15	t
2637	968	5	f
2638	968	4	t
2639	968	3	t
2640	969	2	t
2641	969	1	t
2642	970	2	f
2643	970	1	t
2644	971	17	t
2645	971	16	f
2646	971	15	f
2647	972	11	t
2648	972	10	t
2649	972	9	t
2650	973	11	f
2651	973	10	t
2652	973	9	f
2653	974	2	f
2654	974	1	f
2655	975	8	f
2656	975	7	t
2657	975	6	t
2658	976	11	f
2659	976	10	f
2660	976	9	f
2661	977	17	t
2662	977	16	f
2663	977	15	t
2664	978	8	f
2665	978	7	t
2666	978	6	t
2667	979	11	f
2668	979	10	f
2669	979	9	t
2670	980	2	t
2671	980	1	f
2672	981	8	t
2673	981	7	t
2674	981	6	t
2675	982	11	t
2676	982	10	f
2677	982	9	f
2678	983	5	f
2679	983	4	f
2680	983	3	t
2681	984	8	t
2682	984	7	t
2683	984	6	f
2684	985	5	f
2685	985	4	f
2686	985	3	f
2687	986	2	f
2688	986	1	f
2689	987	17	t
2690	987	16	f
2691	987	15	t
2692	988	5	f
2693	988	4	f
2694	988	3	t
2695	989	5	f
2696	989	4	t
2697	989	3	t
2698	990	17	f
2699	990	16	f
2700	990	15	f
2701	991	17	f
2702	991	16	f
2703	991	15	t
2704	992	11	f
2705	992	10	f
2706	992	9	f
2707	993	5	t
2708	993	4	f
2709	993	3	f
2710	994	8	f
2711	994	7	f
2712	994	6	f
2713	995	17	t
2714	995	16	t
2715	995	15	f
2716	996	8	f
2717	996	7	t
2718	996	6	f
2719	997	17	f
2720	997	16	t
2721	997	15	f
2722	998	2	f
2723	998	1	f
2724	999	14	t
2725	999	13	f
2726	999	12	f
2727	1000	17	f
2728	1000	16	t
2729	1000	15	t
2730	1001	20	f
2731	1001	19	t
2732	1001	18	t
2733	1002	17	f
2734	1002	16	f
2735	1002	15	t
2736	1003	20	f
2737	1003	19	f
2738	1003	18	f
2739	1004	8	t
2740	1004	7	f
2741	1004	6	t
2742	1005	14	f
2743	1005	13	t
2744	1005	12	t
2745	1006	20	t
2746	1006	19	t
2747	1006	18	f
2748	1007	8	t
2749	1007	7	f
2750	1007	6	t
2751	1008	14	f
2752	1008	13	t
2753	1008	12	t
2754	1009	17	t
2755	1009	16	f
2756	1009	15	f
2757	1010	17	f
2758	1010	16	t
2759	1010	15	t
2760	1011	14	f
2761	1011	13	t
2762	1011	12	t
2763	1012	8	t
2764	1012	7	f
2765	1012	6	t
2766	1013	14	f
2767	1013	13	t
2768	1013	12	f
2769	1014	8	t
2770	1014	7	f
2771	1014	6	t
2772	1015	14	f
2773	1015	13	f
2774	1015	12	f
2775	1016	20	t
2776	1016	19	t
2777	1016	18	f
2778	1017	17	t
2779	1017	16	t
2780	1017	15	f
2781	1018	14	f
2782	1018	13	t
2783	1018	12	t
2784	1019	20	t
2785	1019	19	t
2786	1019	18	t
2787	1020	8	f
2788	1020	7	t
2789	1020	6	t
2790	1021	20	f
2791	1021	19	f
2792	1021	18	t
2793	1022	20	f
2794	1022	19	t
2795	1022	18	f
2796	1023	2	t
2797	1023	1	f
2798	1024	14	t
2799	1024	13	f
2800	1024	12	t
2801	1025	11	t
2802	1025	10	f
2803	1025	9	f
2804	1026	11	t
2805	1026	10	t
2806	1026	9	f
2807	1027	11	t
2808	1027	10	f
2809	1027	9	t
2810	1028	20	t
2811	1028	19	t
2812	1028	18	f
2813	1029	14	t
2814	1029	13	f
2815	1029	12	f
2816	1030	14	f
2817	1030	13	t
2818	1030	12	f
2819	1031	20	f
2820	1031	19	t
2821	1031	18	f
2822	1032	11	t
2823	1032	10	t
2824	1032	9	t
2825	1033	2	t
2826	1033	1	f
2827	1034	20	t
2828	1034	19	t
2829	1034	18	f
2830	1035	11	t
2831	1035	10	t
2832	1035	9	f
2833	1036	14	f
2834	1036	13	f
2835	1036	12	f
2836	1037	11	f
2837	1037	10	t
2838	1037	9	f
2839	1038	2	t
2840	1038	1	t
2841	1039	2	f
2842	1039	1	t
2843	1040	2	f
2844	1040	1	f
2845	1041	20	f
2846	1041	19	f
2847	1041	18	t
2848	1042	14	t
2849	1042	13	t
2850	1042	12	f
2851	1043	20	f
2852	1043	19	f
2853	1043	18	t
2854	1044	20	t
2855	1044	19	f
2856	1044	18	t
2857	1045	14	t
2858	1045	13	f
2859	1045	12	t
2860	1046	5	t
2861	1046	4	f
2862	1046	3	f
2863	1047	11	f
2864	1047	10	t
2865	1047	9	f
2866	1048	24	f
2867	1048	23	t
2868	1048	22	f
2869	1049	24	f
2870	1049	23	f
2871	1049	22	f
2872	1050	11	t
2873	1050	10	f
2874	1050	9	t
2875	1051	2	f
2876	1051	1	f
2877	1052	24	f
2878	1052	23	t
2879	1052	22	f
2880	1053	11	t
2881	1053	10	t
2882	1053	9	t
2883	1054	5	t
2884	1054	4	t
2885	1054	3	t
2886	1055	24	f
2887	1055	23	f
2888	1055	22	f
2889	1056	2	t
2890	1056	1	t
2891	1057	24	f
2892	1057	23	f
2893	1057	22	f
2894	1058	5	f
2895	1058	4	t
2896	1058	3	f
2897	1059	11	t
2898	1059	10	f
2899	1059	9	f
2900	1060	24	f
2901	1060	23	t
2902	1060	22	t
2903	1061	5	f
2904	1061	4	t
2905	1061	3	f
2906	1062	5	t
2907	1062	4	f
2908	1062	3	t
2909	1063	11	t
2910	1063	10	t
2911	1063	9	t
2912	1064	24	f
2913	1064	23	f
2914	1064	22	t
2915	1065	5	t
2916	1065	4	f
2917	1065	3	t
2918	1066	11	t
2919	1066	10	t
2920	1066	9	f
2921	1067	2	t
2922	1067	1	t
2923	1068	11	f
2924	1068	10	t
2925	1068	9	f
2926	1069	11	t
2927	1069	10	t
2928	1069	9	t
2929	1070	2	t
2930	1070	1	t
2931	1071	2	t
2932	1071	1	f
2933	1072	24	t
2934	1072	23	t
2935	1072	22	t
2936	1073	5	f
2937	1073	4	f
2938	1073	3	t
2939	1074	11	t
2940	1074	10	t
2941	1074	9	f
2942	1075	5	f
2943	1075	4	t
2944	1075	3	t
2945	1076	2	t
2946	1076	1	t
2947	1077	8	f
2948	1077	7	f
2949	1077	6	t
2950	1078	5	t
2951	1078	4	t
2952	1078	3	f
2953	1079	24	t
2954	1079	23	t
2955	1079	22	t
2956	1080	24	t
2957	1080	23	t
2958	1080	22	f
2959	1081	24	f
2960	1081	23	f
2961	1081	22	t
2962	1082	20	f
2963	1082	19	f
2964	1082	18	t
2965	1083	5	f
2966	1083	4	f
2967	1083	3	f
2968	1084	5	t
2969	1084	4	t
2970	1084	3	f
2971	1085	20	f
2972	1085	19	f
2973	1085	18	f
2974	1086	20	t
2975	1086	19	t
2976	1086	18	t
2977	1087	8	t
2978	1087	7	t
2979	1087	6	t
2980	1088	24	f
2981	1088	23	f
2982	1088	22	f
2983	1089	5	t
2984	1089	4	f
2985	1089	3	f
2986	1090	8	t
2987	1090	7	f
2988	1090	6	t
2989	1091	20	f
2990	1091	19	f
2991	1091	18	f
2992	1092	24	f
2993	1092	23	f
2994	1092	22	t
2995	1093	5	f
2996	1093	4	t
2997	1093	3	t
2998	1094	8	f
2999	1094	7	t
3000	1094	6	t
3001	1095	5	t
3002	1095	4	f
3003	1095	3	f
3004	1096	24	t
3005	1096	23	t
3006	1096	22	f
3007	1097	8	t
3008	1097	7	t
3009	1097	6	f
3010	1098	20	f
3011	1098	19	f
3012	1098	18	f
3013	1099	24	f
3014	1099	23	f
3015	1099	22	t
3016	1100	8	t
3017	1100	7	t
3018	1100	6	f
3019	1101	8	t
3020	1101	7	t
3021	1101	6	f
3022	1102	5	t
3023	1102	4	f
3024	1102	3	t
3025	1103	20	t
3026	1103	19	t
3027	1103	18	t
3028	1104	5	f
3029	1104	4	t
3030	1104	3	t
3031	1105	20	f
3032	1105	19	t
3033	1105	18	t
3034	1106	5	t
3035	1106	4	f
3036	1106	3	t
3037	1107	8	f
3038	1107	7	f
3039	1107	6	t
3040	1108	5	f
3041	1108	4	f
3042	1108	3	t
3043	1109	5	t
3044	1109	4	t
3045	1109	3	t
3046	1110	24	f
3047	1110	23	f
3048	1110	22	t
3049	1111	20	f
3050	1111	19	t
3051	1111	18	f
3052	1112	8	f
3053	1112	7	t
3054	1112	6	f
3055	1113	5	t
3056	1113	4	f
3057	1113	3	f
3058	1114	20	f
3059	1114	19	f
3060	1114	18	t
3061	1115	21	f
3062	1116	5	t
3063	1116	4	f
3064	1116	3	f
3065	1117	20	f
3066	1117	19	t
3067	1117	18	t
3068	1118	17	f
3069	1118	16	t
3070	1118	15	t
3071	1119	21	t
3072	1120	20	t
3073	1120	19	t
3074	1120	18	f
3075	1121	20	t
3076	1121	19	t
3077	1121	18	f
3078	1122	17	t
3079	1122	16	f
3080	1122	15	t
3081	1123	8	f
3082	1123	7	f
3083	1123	6	f
3084	1124	8	t
3085	1124	7	f
3086	1124	6	t
3087	1125	21	t
3088	1126	20	t
3089	1126	19	f
3090	1126	18	f
3091	1127	5	t
3092	1127	4	t
3093	1127	3	t
3094	1128	8	f
3095	1128	7	f
3096	1128	6	f
3097	1129	21	f
3098	1130	17	f
3099	1130	16	f
3100	1130	15	f
3101	1131	20	t
3102	1131	19	f
3103	1131	18	t
3104	1132	8	t
3105	1132	7	t
3106	1132	6	t
3107	1133	17	f
3108	1133	16	t
3109	1133	15	t
3110	1134	20	t
3111	1134	19	t
3112	1134	18	f
3113	1135	8	f
3114	1135	7	t
3115	1135	6	t
3116	1136	21	t
3117	1137	5	t
3118	1137	4	f
3119	1137	3	t
3120	1138	20	f
3121	1138	19	t
3122	1138	18	t
3123	1139	5	f
3124	1139	4	f
3125	1139	3	t
3126	1140	21	t
3127	1141	21	f
3128	1142	20	f
3129	1142	19	f
3130	1142	18	f
3131	1143	17	f
3132	1143	16	f
3133	1143	15	t
3134	1144	21	t
3135	1145	17	f
3136	1145	16	f
3137	1145	15	f
3138	1146	20	f
3139	1146	19	t
3140	1146	18	t
3141	1147	21	f
3142	1148	20	t
3143	1148	19	f
3144	1148	18	f
3145	1149	5	f
3146	1149	4	f
3147	1149	3	f
3148	1150	8	t
3149	1150	7	t
3150	1150	6	t
3151	1151	17	f
3152	1151	16	f
3153	1151	15	t
3154	1152	8	t
3155	1152	7	f
3156	1152	6	f
3157	1153	17	f
3158	1153	16	f
3159	1153	15	f
3160	1154	8	t
3161	1154	7	t
3162	1154	6	t
3163	1155	5	t
3164	1155	4	f
3165	1155	3	t
3166	1156	21	f
3167	1157	5	t
3168	1157	4	t
3169	1157	3	f
3170	1158	17	t
3171	1158	16	f
3172	1158	15	f
3173	1159	20	t
3174	1159	19	t
3175	1159	18	t
3176	1160	21	f
3177	1161	21	t
3178	1162	5	t
3179	1162	4	t
3180	1162	3	f
3181	1163	5	t
3182	1163	4	f
3183	1163	3	t
3184	1164	2	f
3185	1164	1	f
3186	1165	8	t
3187	1165	7	t
3188	1165	6	f
3189	1166	21	t
3190	1167	2	t
3191	1167	1	f
3192	1168	21	f
3193	1169	2	t
3194	1169	1	t
3195	1170	8	t
3196	1170	7	t
3197	1170	6	f
3198	1171	2	f
3199	1171	1	f
3200	1172	5	f
3201	1172	4	t
3202	1172	3	t
3203	1173	21	t
3204	1174	2	t
3205	1174	1	t
3206	1175	5	t
3207	1175	4	t
3208	1175	3	f
3209	1176	8	f
3210	1176	7	t
3211	1176	6	f
3212	1177	5	t
3213	1177	4	t
3214	1177	3	f
3215	1178	21	f
3216	1179	5	f
3217	1179	4	t
3218	1179	3	t
3219	1180	8	f
3220	1180	7	t
3221	1180	6	f
3222	1181	21	f
3223	1182	2	f
3224	1182	1	f
3225	1183	5	f
3226	1183	4	t
3227	1183	3	f
3228	1184	2	t
3229	1184	1	f
3230	1185	8	t
3231	1185	7	t
3232	1185	6	t
3233	1186	24	t
3234	1186	23	f
3235	1186	22	t
3236	1187	8	t
3237	1187	7	t
3238	1187	6	t
3239	1188	8	f
3240	1188	7	t
3241	1188	6	t
3242	1189	24	f
3243	1189	23	f
3244	1189	22	t
3245	1190	24	f
3246	1190	23	t
3247	1190	22	f
3248	1191	2	f
3249	1191	1	f
3250	1192	24	f
3251	1192	23	t
3252	1192	22	t
3253	1193	8	f
3254	1193	7	t
3255	1193	6	t
3256	1194	8	f
3257	1194	7	f
3258	1194	6	t
3259	1195	2	t
3260	1195	1	f
3261	1196	24	f
3262	1196	23	f
3263	1196	22	t
3264	1197	2	t
3265	1197	1	t
3266	1198	8	f
3267	1198	7	f
3268	1198	6	t
3269	1199	24	f
3270	1199	23	t
3271	1199	22	f
3272	1200	2	t
3273	1200	1	f
3274	1201	8	f
3275	1201	7	t
3276	1201	6	t
3277	1202	8	f
3278	1202	7	f
3279	1202	6	t
3280	1203	24	t
3281	1203	23	t
3282	1203	22	t
3283	1204	8	f
3284	1204	7	t
3285	1204	6	f
3286	1205	24	f
3287	1205	23	f
3288	1205	22	t
3289	1206	8	t
3290	1206	7	f
3291	1206	6	t
3292	1207	5	t
3293	1207	4	t
3294	1207	3	f
3295	1208	2	f
3296	1208	1	t
3297	1209	5	f
3298	1209	4	t
3299	1209	3	f
3300	1210	14	f
3301	1210	13	f
3302	1210	12	t
3303	1211	14	f
3304	1211	13	t
3305	1211	12	f
3306	1212	8	t
3307	1212	7	f
3308	1212	6	t
3309	1213	2	f
3310	1213	1	f
3311	1214	8	t
3312	1214	7	t
3313	1214	6	t
3314	1215	14	f
3315	1215	13	f
3316	1215	12	f
3317	1216	8	f
3318	1216	7	t
3319	1216	6	t
3320	1217	5	f
3321	1217	4	t
3322	1217	3	t
3323	1218	14	f
3324	1218	13	t
3325	1218	12	t
3326	1219	5	t
3327	1219	4	f
3328	1219	3	t
3329	1220	8	t
3330	1220	7	t
3331	1220	6	f
3332	1221	8	t
3333	1221	7	t
3334	1221	6	t
3335	1222	14	f
3336	1222	13	f
3337	1222	12	f
3338	1223	5	t
3339	1223	4	t
3340	1223	3	f
3341	1224	8	t
3342	1224	7	t
3343	1224	6	t
3344	1225	2	t
3345	1225	1	t
3346	1226	14	t
3347	1226	13	t
3348	1226	12	t
3349	1227	14	t
3350	1227	13	f
3351	1227	12	f
3352	1228	2	f
3353	1228	1	f
3354	1229	5	f
3355	1229	4	f
3356	1229	3	f
3357	1230	2	t
3358	1230	1	t
3359	1231	14	f
3360	1231	13	t
3361	1231	12	f
3362	1232	14	f
3363	1232	13	t
3364	1232	12	f
3365	1233	2	f
3366	1233	1	t
3367	1234	8	f
3368	1234	7	t
3369	1234	6	t
3370	1235	2	f
3371	1235	1	f
3372	1236	17	t
8	4	2	t
7	4	1	f
9	3	2	t
10	3	1	t
13	5	14	t
14	5	13	f
15	5	12	f
16	6	24	f
17	6	23	f
18	6	22	f
19	7	17	t
20	7	16	t
21	7	15	t
22	8	5	t
23	8	4	t
24	8	3	t
25	9	21	t
26	10	14	f
27	10	13	t
28	10	12	f
29	11	24	t
30	11	23	f
31	11	22	f
32	12	5	t
33	12	4	f
34	12	3	f
35	13	17	t
36	13	16	f
37	13	15	f
38	14	21	t
39	15	24	t
40	15	23	f
41	15	22	t
42	16	17	f
43	16	16	t
44	16	15	f
45	17	21	t
46	18	5	t
47	18	4	t
48	18	3	f
49	19	5	t
50	19	4	t
51	19	3	f
52	20	14	t
53	20	13	t
54	20	12	f
55	21	2	t
56	21	1	t
57	22	21	t
58	23	24	f
59	23	23	t
60	23	22	f
61	24	17	f
62	24	16	t
63	24	15	t
64	25	5	t
65	25	4	t
66	25	3	t
67	26	14	t
68	26	13	f
69	26	12	f
70	27	21	t
71	28	14	f
72	28	13	f
73	28	12	f
74	29	17	f
75	29	16	f
3373	1236	16	t
3374	1236	15	t
3375	1237	8	t
3376	1237	7	f
3377	1237	6	t
3378	1238	11	f
3379	1238	10	t
3380	1238	9	t
3381	1239	5	t
3382	1239	4	f
3383	1239	3	t
3384	1240	8	t
3385	1240	7	f
3386	1240	6	t
3387	1241	11	t
3388	1241	10	f
3389	1241	9	f
3390	1242	14	f
3391	1242	13	f
3392	1242	12	f
3393	1243	5	t
3394	1243	4	f
3395	1243	3	f
3396	1244	5	f
3397	1244	4	f
3398	1244	3	f
3399	1245	11	t
3400	1245	10	t
3401	1245	9	f
3402	1246	14	f
3403	1246	13	f
3404	1246	12	t
3405	1247	11	t
3406	1247	10	f
3407	1247	9	t
3408	1248	14	t
3409	1248	13	f
3410	1248	12	t
3411	1249	17	t
3412	1249	16	f
3413	1249	15	t
3414	1250	17	t
3415	1250	16	t
3416	1250	15	f
3417	1251	5	t
3418	1251	4	t
3419	1251	3	f
3420	1252	8	f
3421	1252	7	f
3422	1252	6	f
3423	1253	14	t
3424	1253	13	f
3425	1253	12	t
3426	1254	11	t
3427	1254	10	f
3428	1254	9	f
3429	1255	8	t
3430	1255	7	f
3431	1255	6	t
3432	1256	14	f
3433	1256	13	t
3434	1256	12	t
3435	1257	14	t
3436	1257	13	t
3437	1257	12	f
3438	1258	8	f
3439	1258	7	f
3440	1258	6	t
3441	1259	17	t
3442	1259	16	t
3443	1259	15	t
3444	1260	11	f
3445	1260	10	f
3446	1260	9	f
3447	1261	11	t
3448	1261	10	f
3449	1261	9	t
3450	1262	8	f
3451	1262	7	t
3452	1262	6	f
3453	1263	5	f
3454	1263	4	t
3455	1263	3	t
3456	1264	17	f
3457	1264	16	t
3458	1264	15	t
3459	1265	8	f
3460	1265	7	t
3461	1265	6	f
3462	1266	5	t
3463	1266	4	f
3464	1266	3	t
3465	1267	5	f
3466	1267	4	t
3467	1267	3	t
3468	1268	11	f
3469	1268	10	f
3470	1268	9	t
3471	1269	8	f
3472	1269	7	t
3473	1269	6	f
3474	1270	17	t
3475	1270	16	t
3476	1270	15	f
3477	1271	14	f
3478	1271	13	f
3479	1271	12	t
3480	1272	14	f
3481	1272	13	f
3482	1272	12	t
3483	1273	17	f
3484	1273	16	t
3485	1273	15	t
3486	1274	8	t
3487	1274	7	f
3488	1274	6	f
3489	1275	5	t
3490	1275	4	f
3491	1275	3	t
3492	1276	8	f
3493	1276	7	f
3494	1276	6	t
3495	1277	14	t
3496	1277	13	f
3497	1277	12	f
3498	1278	11	t
3499	1278	10	t
3500	1278	9	t
3501	1279	5	f
3502	1279	4	t
3503	1279	3	t
3504	1280	17	f
3505	1280	16	t
3506	1280	15	t
3507	1281	20	f
3508	1281	19	f
3509	1281	18	f
3510	1282	5	t
3511	1282	4	t
3512	1282	3	t
3513	1283	20	f
3514	1283	19	f
3515	1283	18	f
3516	1284	2	f
3517	1284	1	t
3518	1285	5	t
3519	1285	4	t
3520	1285	3	f
3521	1286	20	f
3522	1286	19	t
3523	1286	18	f
3524	1287	2	f
3525	1287	1	t
3526	1288	17	f
3527	1288	16	f
3528	1288	15	f
3529	1289	5	f
3530	1289	4	t
3531	1289	3	f
3532	1290	5	f
3533	1290	4	t
3534	1290	3	t
3535	1291	17	f
3536	1291	16	f
3537	1291	15	t
3538	1292	17	f
3539	1292	16	t
3540	1292	15	t
3541	1293	20	t
3542	1293	19	t
3543	1293	18	t
3544	1294	17	t
3545	1294	16	f
3546	1294	15	f
3547	1295	17	f
3548	1295	16	f
3549	1295	15	t
3550	1296	20	t
3551	1296	19	f
3552	1296	18	f
3553	1297	20	t
3554	1297	19	f
3555	1297	18	f
3556	1298	2	f
3557	1298	1	f
3558	1299	17	f
3559	1299	16	f
3560	1299	15	t
3561	1300	2	f
3562	1300	1	f
3563	1301	20	t
3564	1301	19	f
3565	1301	18	t
3566	1302	14	t
3567	1302	13	t
3568	1302	12	f
3569	1303	24	t
3570	1303	23	f
3571	1303	22	f
3572	1304	11	f
3573	1304	10	t
3574	1304	9	t
3575	1305	5	t
3576	1305	4	t
3577	1305	3	t
3578	1306	17	t
3579	1306	16	f
3580	1306	15	f
3581	1307	14	f
3582	1307	13	t
3583	1307	12	t
3584	1308	5	f
3585	1308	4	t
3586	1308	3	t
3587	1309	17	t
3588	1309	16	f
3589	1309	15	f
3590	1310	14	t
3591	1310	13	t
3592	1310	12	f
3593	1311	24	t
3594	1311	23	t
3595	1311	22	t
3596	1312	14	f
3597	1312	13	f
3598	1312	12	t
3599	1313	5	t
3600	1313	4	t
3601	1313	3	f
3602	1314	24	t
3603	1314	23	t
3604	1314	22	f
3605	1315	17	t
3606	1315	16	f
3607	1315	15	f
3608	1316	17	t
3609	1316	16	f
3610	1316	15	t
3611	1317	24	f
3612	1317	23	f
3613	1317	22	f
3614	1318	14	t
3615	1318	13	t
3616	1318	12	t
3617	1319	5	f
3618	1319	4	f
3619	1319	3	t
3620	1320	14	t
3621	1320	13	t
3622	1320	12	f
3623	1321	24	t
3624	1321	23	f
3625	1321	22	f
3626	1322	17	t
3627	1322	16	t
3628	1322	15	t
3629	1323	11	t
3630	1323	10	t
3631	1323	9	f
3632	1324	17	f
3633	1324	16	t
3634	1324	15	t
3635	1325	14	f
3636	1325	13	f
3637	1325	12	f
3638	1326	17	f
3639	1326	16	t
3640	1326	15	f
3641	1327	2	t
3642	1327	1	f
3643	1328	17	t
3644	1328	16	t
3645	1328	15	t
3646	1329	20	t
3647	1329	19	f
3648	1329	18	f
3649	1330	17	f
3650	1330	16	t
3651	1330	15	f
3652	1331	20	f
3653	1331	19	f
3654	1331	18	t
3655	1332	17	t
3656	1332	16	t
3657	1332	15	t
3658	1333	2	t
3659	1333	1	f
3660	1334	20	f
3661	1334	19	t
3662	1334	18	t
3663	1335	20	f
3664	1335	19	f
3665	1335	18	f
3666	1336	2	f
3667	1336	1	t
3668	1337	11	t
3669	1337	10	f
3670	1337	9	f
3671	1338	17	f
3672	1338	16	f
3673	1338	15	f
3674	1339	20	f
3675	1339	19	t
3676	1339	18	t
3677	1340	2	f
3678	1340	1	t
3679	1341	2	f
3680	1341	1	f
3681	1342	11	f
3682	1342	10	t
3683	1342	9	t
3684	1343	2	f
3685	1343	1	f
3686	1344	17	t
3687	1344	16	t
3688	1344	15	f
3689	1345	20	t
3690	1345	19	t
3691	1345	18	t
3692	1346	11	f
3693	1346	10	t
3694	1346	9	t
3695	1347	17	f
3696	1347	16	f
3697	1347	15	t
3698	1348	17	t
3699	1348	16	f
3700	1348	15	f
3701	1349	5	t
3702	1349	4	f
3703	1349	3	t
3704	1350	24	f
3705	1350	23	f
3706	1350	22	f
3707	1351	24	f
3708	1351	23	t
3709	1351	22	f
3710	1352	8	t
3711	1352	7	f
3712	1352	6	t
3713	1353	5	t
3714	1353	4	t
3715	1353	3	t
3716	1354	8	f
3717	1354	7	t
3718	1354	6	f
3719	1355	24	f
3720	1355	23	t
3721	1355	22	t
3722	1356	17	f
3723	1356	16	t
3724	1356	15	f
3725	1357	5	t
3726	1357	4	t
3727	1357	3	f
3728	1358	8	t
3729	1358	7	t
3730	1358	6	f
3731	1359	8	t
3732	1359	7	t
3733	1359	6	f
3734	1360	24	f
3735	1360	23	t
3736	1360	22	t
3737	1361	17	f
3738	1361	16	f
3739	1361	15	f
3740	1362	8	t
3741	1362	7	f
3742	1362	6	t
3743	1363	24	f
3744	1363	23	f
3745	1363	22	f
3746	1364	17	t
3747	1364	16	f
3748	1364	15	t
3749	1365	8	t
3750	1365	7	t
3751	1365	6	f
3752	1366	8	t
3753	1366	7	t
3754	1366	6	f
3755	1367	5	f
3756	1367	4	t
3757	1367	3	t
3758	1368	24	f
3759	1368	23	f
3760	1368	22	f
3761	1369	5	t
3762	1369	4	f
3763	1369	3	t
3764	1370	5	t
3765	1370	4	f
3766	1370	3	f
3767	1371	8	f
3768	1371	7	f
3769	1371	6	f
3770	1372	5	t
3771	1372	4	f
3772	1372	3	f
3773	1373	14	f
3774	1373	13	f
3775	1373	12	t
3776	1374	20	f
3777	1374	19	t
3778	1374	18	f
3779	1375	14	f
3780	1375	13	f
3781	1375	12	t
3782	1376	21	f
3783	1377	14	t
3784	1377	13	f
3785	1377	12	t
3786	1378	20	f
3787	1378	19	f
3788	1378	18	f
3789	1379	20	t
3790	1379	19	f
3791	1379	18	t
3792	1380	21	f
3793	1381	14	t
3794	1381	13	f
3795	1381	12	t
3796	1382	14	t
3797	1382	13	f
3798	1382	12	f
3799	1383	21	f
3800	1384	21	f
3801	1385	20	t
3802	1385	19	f
3803	1385	18	t
3804	1386	20	t
3805	1386	19	f
3806	1386	18	f
3807	1387	14	f
3808	1387	13	f
3809	1387	12	t
3810	1388	14	f
3811	1388	13	t
3812	1388	12	f
3813	1389	21	f
3814	1390	20	f
3815	1390	19	f
3816	1390	18	t
3817	1391	14	f
3818	1391	13	f
3819	1391	12	t
3820	1392	20	t
3821	1392	19	f
3822	1392	18	f
3823	1393	14	f
3824	1393	13	t
3825	1393	12	f
3826	1394	24	f
3827	1394	23	f
3828	1394	22	f
3829	1395	5	t
3830	1395	4	f
3831	1395	3	f
3832	1396	8	t
3833	1396	7	f
3834	1396	6	t
3835	1397	5	t
3836	1397	4	t
3837	1397	3	f
3838	1398	17	f
3839	1398	16	f
3840	1398	15	t
3841	1399	8	f
3842	1399	7	t
3843	1399	6	t
3844	1400	17	f
3845	1400	16	t
3846	1400	15	t
3847	1401	24	t
3848	1401	23	t
3849	1401	22	t
3850	1402	8	t
3851	1402	7	f
3852	1402	6	t
3853	1403	17	f
3854	1403	16	t
3855	1403	15	t
3856	1404	5	f
3857	1404	4	t
3858	1404	3	f
3859	1405	5	f
3860	1405	4	t
3861	1405	3	t
3862	1406	24	f
3863	1406	23	f
3864	1406	22	f
3865	1407	17	t
3866	1407	16	f
3867	1407	15	f
3868	1408	5	t
3869	1408	4	f
3870	1408	3	t
3871	1409	8	t
3872	1409	7	t
3873	1409	6	t
3874	1410	24	t
3875	1410	23	t
3876	1410	22	f
3877	1411	17	f
3878	1411	16	f
3879	1411	15	f
3880	1412	5	t
3881	1412	4	t
3882	1412	3	t
3883	1413	24	t
3884	1413	23	t
3885	1413	22	t
3886	1414	24	t
3887	1414	23	f
3888	1414	22	f
3889	1415	17	f
3890	1415	16	f
3891	1415	15	t
3892	1416	8	t
3893	1416	7	f
3894	1416	6	t
3895	1417	17	t
3896	1417	16	f
3897	1417	15	t
3898	1418	8	t
3899	1418	7	f
3900	1418	6	t
3901	1419	24	f
3902	1419	23	t
3903	1419	22	f
3904	1420	17	t
3905	1420	16	t
3906	1420	15	f
3907	1421	8	f
3908	1421	7	t
3909	1421	6	t
3910	1422	24	t
3911	1422	23	f
3912	1422	22	f
3913	1423	20	t
3914	1423	19	t
3915	1423	18	f
3916	1424	14	f
3917	1424	13	f
3918	1424	12	f
3919	1425	2	t
3920	1425	1	f
3921	1426	5	f
3922	1426	4	f
3923	1426	3	f
3924	1427	14	t
3925	1427	13	t
3926	1427	12	t
3927	1428	2	t
3928	1428	1	f
3929	1429	5	t
3930	1429	4	f
3931	1429	3	f
3932	1430	24	f
3933	1430	23	f
3934	1430	22	f
3935	1431	2	f
3936	1431	1	t
3937	1432	14	f
3938	1432	13	f
3939	1432	12	f
3940	1433	5	f
3941	1433	4	f
3942	1433	3	t
3943	1434	24	t
3944	1434	23	f
3945	1434	22	t
3946	1435	20	t
3947	1435	19	t
3948	1435	18	t
3949	1436	14	t
3950	1436	13	t
3951	1436	12	f
3952	1437	14	t
3953	1437	13	f
3954	1437	12	t
3955	1438	20	f
3956	1438	19	f
3957	1438	18	t
3958	1439	24	t
3959	1439	23	f
3960	1439	22	f
3961	1440	5	t
3962	1440	4	f
3963	1440	3	f
3964	1441	20	t
3965	1441	19	f
3966	1441	18	t
3967	1442	5	t
3968	1442	4	f
3969	1442	3	t
3970	1443	2	f
3971	1443	1	t
3972	1444	14	f
3973	1444	13	t
3974	1444	12	f
3975	1445	20	t
3976	1445	19	f
3977	1445	18	t
3978	1446	2	f
3979	1446	1	f
3980	1447	5	t
3981	1447	4	t
3982	1447	3	t
3983	1448	24	f
3984	1448	23	f
3985	1448	22	f
3986	1449	20	f
3987	1449	19	f
3988	1449	18	f
3989	1450	2	f
3990	1450	1	f
\.


--
-- TOC entry 4958 (class 0 OID 64559)
-- Dependencies: 231
-- Data for Name: test_case; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.test_case (test_id, input, output, question_id, test_point) FROM stdin;
1	PUSH 163\nPUSH 161\nPUSH 187\nPUSH 148\nPUSH 145\nPUSH 7\nPUSH 119\nPUSH 66\nPUSH 157\nPUSH 31\nPUSH 68\nPUSH 178\nPUSH 157\nPUSH 168\nPUSH 22\nPUSH 176\nPUSH 187\nPUSH 34\nPUSH 33\nPUSH 147\nPUSH 109\nPUSH 79\nPUSH 122\nPUSH 47\nPUSH 131\nPUSH 27\nPUSH 175\nPUSH 188\nPUSH 169\nPUSH 173\nPUSH 105\nPUSH 110\nPUSH 23\nPUSH 175\nPUSH 73\nPUSH 102\nPUSH 173\nPUSH 43\nPUSH 73\nPUSH 97\nPUSH 114\nPUSH 134\nPUSH 84\nPUSH 192\nPUSH 119\nPUSH 26\nPUSH 64\nPUSH 112\nPUSH 79\nPUSH 142\nPUSH 18\nPOP\nPOP\nPOP\nPOP\nPUSH 22\nPUSH 131\nPOP\nPUSH 180\nPOP\nPUSH 172\nPOP\nPOP\nPUSH 20\nPUSH 81\nPUSH 127\nPUSH 83\nPUSH 18\nPOP\nPOP\nPOP\nPOP\nPOP\nPUSH 175\nPOP\nPOP\nPUSH 26\nPUSH 119\nPUSH 164\nPOP\nPUSH 61\nPUSH 176\nPUSH 166\nPUSH 105\nPUSH 58\nPOP\nPOP\nPUSH 189\nPUSH 25\nPOP\nPOP\nPOP\nPUSH 46\nPUSH 19\nPUSH 131\nPOP\nPUSH 38\nPOP\nPOP\nPUSH 1\n#\n	7\n18\n22\n23\n22\n26\n27\n31\n18\n20\n33\n34\n43\n47\n64\n26\n58\n61\n25\n66\n68\n19\n38\n46\n	2	20
2	PUSH 10\nPUSH 4\nPUSH 1 \nPUSH 8\nPUSH 7\nPOP\nPUSH 2\nPUSH 9\nPOP\nPOP\nPOP\n#\n	1\n2\n4\n7\n	2	20
3	3	000\n001\n010\n011\n100\n101\n110\n111\n	3	20
4	7	0000000\n0000001\n0000010\n0000011\n0000100\n0000101\n0000110\n0000111\n0001000\n0001001\n0001010\n0001011\n0001100\n0001101\n0001110\n0001111\n0010000\n0010001\n0010010\n0010011\n0010100\n0010101\n0010110\n0010111\n0011000\n0011001\n0011010\n0011011\n0011100\n0011101\n0011110\n0011111\n0100000\n0100001\n0100010\n0100011\n0100100\n0100101\n0100110\n0100111\n0101000\n0101001\n0101010\n0101011\n0101100\n0101101\n0101110\n0101111\n0110000\n0110001\n0110010\n0110011\n0110100\n0110101\n0110110\n0110111\n0111000\n0111001\n0111010\n0111011\n0111100\n0111101\n0111110\n0111111\n1000000\n1000001\n1000010\n1000011\n1000100\n1000101\n1000110\n1000111\n1001000\n1001001\n1001010\n1001011\n1001100\n1001101\n1001110\n1001111\n1010000\n1010001\n1010010\n1010011\n1010100\n1010101\n1010110\n1010111\n1011000\n1011001\n1011010\n1011011\n1011100\n1011101\n1011110\n1011111\n1100000\n1100001\n1100010\n1100011\n1100100\n1100101\n1100110\n1100111\n1101000\n1101001\n1101010\n1101011\n1101100\n1101101\n1101110\n1101111\n1110000\n1110001\n1110010\n1110011\n1110100\n1110101\n1110110\n1110111\n1111000\n1111001\n1111010\n1111011\n1111100\n1111101\n1111110\n1111111\n	3	20
5	5	00000\n00001\n00010\n00011\n00100\n00101\n00110\n00111\n01000\n01001\n01010\n01011\n01100\n01101\n01110\n01111\n10000\n10001\n10010\n10011\n10100\n10101\n10110\n10111\n11000\n11001\n11010\n11011\n11100\n11101\n11110\n11111\n	3	20
6	16\n2 4 6 1 6 8 7 3 3 5 8 9 1 2 6 4\n4\n1 5\n0 9\n1 15\n6 10	6	4	20
7	10\n2 3 5 1 4 7 6 19 18 17\n3\n0 5\n1 7\n2 8	3	4	20
8	7\n4 2 1 5 6 3 7\n3\n0 4\n1 7\n2 6	3	4	20
9	5\n1 4 3 1 4	0\n0\n0\n1\n1	5	20
10	10\n8 1 7 5 9 6 8 2 1 3 	0\n0\n0\n0\n0\n0\n1\n0\n1\n0\n	5	20
11	100\n48 1 57 25 69 26 88 52 91 73 65 7 45 37 11 23 99 29 34 91 34 27 73 52 5 69 35 84 44 63 61 81 29 81 73 31 11 1 7 65 68 37 41 17 49 17 99 7 77 90 96 63 21 63 79 46 29 31 22 65 41 97 86 71 13 1 85 81 38 60 60 100 6 23 49 13 81 85 1 11 91 89 85 96 1 77 81 17 53 13 55 48 85 1 10 5 85 48 71 83 \n	0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n1\n1\n0\n1\n1\n0\n1\n0\n0\n0\n0\n0\n0\n1\n1\n1\n0\n1\n1\n1\n1\n0\n1\n0\n0\n0\n1\n1\n1\n0\n0\n0\n1\n0\n1\n0\n0\n1\n1\n0\n1\n1\n0\n0\n0\n0\n1\n0\n1\n0\n0\n1\n0\n0\n1\n1\n1\n1\n1\n1\n1\n1\n0\n1\n1\n1\n1\n1\n1\n0\n1\n0\n1\n1\n1\n0\n1\n1\n1\n1\n0\n	5	20
12	10 30\n	40\n	6	20
13	1000 2000\n	3000\n	6	20
14	1 1\n	2\n	6	20
15	5 6\n5 2 1 4 3\n	2\n	7	20
16	100 120\n1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 \n	40\n	7	20
17	1000 1500\n1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299 300 301 302 303 304 305 306 307 308 309 310 311 312 313 314 315 316 317 318 319 320 321 322 323 324 325 326 327 328 329 330 331 332 333 334 335 336 337 338 339 340 341 342 343 344 345 346 347 348 349 350 351 352 353 354 355 356 357 358 359 360 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 377 378 379 380 381 382 383 384 385 386 387 388 389 390 391 392 393 394 395 396 397 398 399 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 419 420 421 422 423 424 425 426 427 428 429 430 431 432 433 434 435 436 437 438 439 440 441 442 443 444 445 446 447 448 449 450 451 452 453 454 455 456 457 458 459 460 461 462 463 464 465 466 467 468 469 470 471 472 473 474 475 476 477 478 479 480 481 482 483 484 485 486 487 488 489 490 491 492 493 494 495 496 497 498 499 500 501 502 503 504 505 506 507 508 509 510 511 512 513 514 515 516 517 518 519 520 521 522 523 524 525 526 527 528 529 530 531 532 533 534 535 536 537 538 539 540 541 542 543 544 545 546 547 548 549 550 551 552 553 554 555 556 557 558 559 560 561 562 563 564 565 566 567 568 569 570 571 572 573 574 575 576 577 578 579 580 581 582 583 584 585 586 587 588 589 590 591 592 593 594 595 596 597 598 599 600 601 602 603 604 605 606 607 608 609 610 611 612 613 614 615 616 617 618 619 620 621 622 623 624 625 626 627 628 629 630 631 632 633 634 635 636 637 638 639 640 641 642 643 644 645 646 647 648 649 650 651 652 653 654 655 656 657 658 659 660 661 662 663 664 665 666 667 668 669 670 671 672 673 674 675 676 677 678 679 680 681 682 683 684 685 686 687 688 689 690 691 692 693 694 695 696 697 698 699 700 701 702 703 704 705 706 707 708 709 710 711 712 713 714 715 716 717 718 719 720 721 722 723 724 725 726 727 728 729 730 731 732 733 734 735 736 737 738 739 740 741 742 743 744 745 746 747 748 749 750 751 752 753 754 755 756 757 758 759 760 761 762 763 764 765 766 767 768 769 770 771 772 773 774 775 776 777 778 779 780 781 782 783 784 785 786 787 788 789 790 791 792 793 794 795 796 797 798 799 800 801 802 803 804 805 806 807 808 809 810 811 812 813 814 815 816 817 818 819 820 821 822 823 824 825 826 827 828 829 830 831 832 833 834 835 836 837 838 839 840 841 842 843 844 845 846 847 848 849 850 851 852 853 854 855 856 857 858 859 860 861 862 863 864 865 866 867 868 869 870 871 872 873 874 875 876 877 878 879 880 881 882 883 884 885 886 887 888 889 890 891 892 893 894 895 896 897 898 899 900 901 902 903 904 905 906 907 908 909 910 911 912 913 914 915 916 917 918 919 920 921 922 923 924 925 926 927 928 929 930 931 932 933 934 935 936 937 938 939 940 941 942 943 944 945 946 947 948 949 950 951 952 953 954 955 956 957 958 959 960 961 962 963 964 965 966 967 968 969 970 971 972 973 974 975 976 977 978 979 980 981 982 983 984 985 986 987 988 989 990 991 992 993 994 995 996 997 998 999 1000 \n	250\n	7	20
18	5\n2 5 4 6 7\n	13\n	8	20
19	10\n7 18 17 14 1 12 22 4 5 20 \n	74\n	8	20
20	1000\n65 13 20 3 43 100 84 93 14 2 6 52 13 37 84 6 65 62 94 91 89 10 75 11 2 12 87 33 46 100 69 26 48 56 15 97 71 82 7 5 98 97 25 60 76 43 30 75 25 30 91 29 81 57 6 96 87 50 36 49 13 93 92 64 70 43 27 41 48 44 24 69 15 46 58 59 74 96 68 40 20 94 72 61 82 49 63 8 99 9 27 86 28 8 38 76 97 2 91 19 15 67 15 96 79 97 89 27 7 91 69 71 44 46 57 79 48 53 73 96 61 78 49 75 89 10 80 76 11 17 83 95 70 72 51 62 89 14 11 83 7 94 34 96 100 93 79 84 63 39 53 63 41 68 29 92 61 99 10 74 6 23 89 78 83 76 29 8 57 21 20 60 70 71 86 37 7 64 42 58 11 45 10 13 63 77 36 58 41 75 47 9 97 9 63 19 88 6 68 96 11 21 87 32 92 92 70 48 71 11 21 91 8 80 45 7 95 19 78 36 24 78 32 78 8 51 37 14 51 53 13 20 95 76 25 90 69 31 57 76 43 34 68 55 70 24 78 3 89 99 38 6 37 83 64 76 19 13 52 76 3 48 31 72 1 64 21 63 93 64 76 94 91 89 13 97 13 57 56 55 45 5 4 21 6 67 68 91 18 7 51 55 75 92 47 31 6 85 36 97 25 73 11 5 31 84 17 41 82 99 84 11 15 49 10 16 26 83 23 8 17 4 24 86 29 21 44 77 100 25 2 47 23 41 5 73 95 14 91 27 23 69 53 10 28 23 57 99 85 76 66 69 4 90 28 42 28 75 27 82 88 91 62 81 44 19 59 90 99 28 45 4 13 60 84 24 34 78 28 62 43 37 28 84 83 75 65 81 32 30 28 15 63 6 32 76 45 64 60 13 39 26 71 31 65 32 52 85 95 83 5 6 52 25 26 53 46 52 47 34 1 29 66 71 91 15 34 23 80 68 93 21 60 28 62 48 17 17 90 86 57 58 48 42 4 63 4 71 93 68 86 46 27 26 86 6 62 18 97 90 71 27 93 90 24 78 90 72 83 47 22 14 14 79 26 95 51 52 61 30 13 25 72 39 34 35 91 9 42 67 60 90 73 72 57 61 76 67 30 62 98 93 27 85 76 42 79 100 45 24 90 14 4 77 4 48 78 81 74 55 53 97 100 46 33 40 72 65 73 76 99 26 5 97 77 11 69 58 90 69 38 83 70 72 19 29 52 50 84 19 18 56 26 70 4 94 41 36 47 99 25 6 88 17 74 65 2 65 36 64 12 26 83 68 42 79 91 77 61 3 70 15 96 81 76 92 30 14 44 66 50 81 22 42 30 93 76 14 19 79 64 13 76 44 26 89 1 3 66 65 82 42 57 31 8 61 37 96 78 35 58 74 72 65 70 59 65 33 15 24 7 15 95 78 87 2 17 60 100 45 78 61 75 79 66 100 41 88 20 66 22 56 99 78 62 30 91 16 4 86 91 82 32 99 16 22 20 60 38 94 19 28 38 16 10 7 79 30 8 82 57 37 43 94 79 92 27 49 56 24 35 82 72 77 18 78 99 56 60 55 67 79 89 76 74 71 57 61 14 25 44 28 92 3 95 76 46 6 28 57 84 84 87 32 26 2 14 69 28 47 34 34 50 70 70 69 97 50 32 21 22 96 78 1 85 2 10 38 76 42 89 82 13 80 60 20 17 51 60 78 39 48 76 93 65 93 80 52 69 33 24 48 82 57 61 74 80 67 56 96 13 92 17 53 90 52 97 11 78 88 83 8 85 99 55 69 55 74 56 32 97 52 28 76 76 58 34 45 2 46 7 79 2 90 84 85 51 91 15 16 3 51 39 88 28 92 21 13 95 46 97 74 5 58 18 56 83 20 96 76 57 74 54 26 49 98 47 62 12 43 37 56 89 10 74 80 53 6 62 17 95 45 89 73 69 57 99 13 15 63 36 59 70 9 15 85 63 22 90 24 1 70 60 61 97 39 86 67 57 7 6 57 26 6 12 53 41 71 25 21 84 82 70 9 46 25 27 53 49 100 20 44 3 93 24 9 21 16 35 1 86 13 55 82 96 39 67 30 62 13 88 27 30 39 33 6 71 83 61 69 13 9 2 85 76 48 4 24 87 21 38 23 69 97 20 87 9 86 50 85 18 46 20 60 65 100 54 22 51 67 30 85 61 92 23 75 33 58 56 36 85 72 66 4 19 83 51 49 1 28 40 93 10 56 27 91 61 98 52 30 \n	30810\n	8	20
21	3\n1 2 3\n	6\n	9	20
22	6  2  3 \n3  5  9  6  7  4\n	19\n	10	20
23	1000 100 200\n18 17 1 14 16 7 6 2 14 7 5 16 16 6 7 16 4 15 10 1 15 6 17 20 9 3 9 20 6 4 7 1 6 14 4 13 18 17 15 4 12 14 14 18 13 5 8 10 13 19 1 1 14 17 18 17 4 6 10 12 17 9 1 8 9 7 1 16 12 4 14 6 7 11 2 6 11 15 9 19 8 18 1 9 5 1 9 15 12 10 3 18 5 17 3 10 2 7 19 10 2 19 20 6 2 17 6 8 3 7 6 8 13 17 10 1 20 13 7 3 17 16 15 18 15 4 2 2 18 19 2 9 3 6 12 15 18 17 20 12 9 2 8 3 2 12 1 5 18 2 3 19 15 8 19 20 7 1 5 2 5 14 18 8 17 2 2 9 11 2 18 11 1 7 18 17 6 6 13 9 9 7 9 8 13 13 17 5 12 13 16 9 15 13 20 15 10 19 6 3 1 17 20 15 18 19 16 7 8 12 11 5 7 17 6 19 12 16 19 7 11 11 4 19 8 3 7 19 19 4 1 19 4 6 5 13 5 18 7 15 13 1 10 13 13 20 9 10 4 20 5 7 1 8 3 16 8 9 16 10 4 14 6 16 19 16 1 6 14 7 14 11 13 6 2 9 15 3 2 15 13 10 13 6 8 12 8 12 2 15 5 9 13 16 10 6 8 20 8 4 5 11 5 9 4 6 15 10 12 3 10 20 7 10 5 18 1 14 12 3 15 8 16 12 13 15 4 6 9 17 11 5 14 5 1 15 9 18 10 18 2 11 20 11 17 15 5 13 15 2 13 1 7 5 13 4 18 15 8 14 10 16 20 12 1 2 17 16 13 5 18 6 7 3 12 11 1 14 7 18 12 13 10 19 14 1 2 19 2 11 6 3 13 12 2 4 13 1 5 7 13 9 19 11 12 5 11 8 5 18 1 5 18 15 15 11 3 9 13 19 10 11 11 17 17 6 10 7 11 7 10 6 3 11 18 8 13 7 12 13 6 12 18 5 2 3 17 2 4 16 2 2 10 4 2 1 13 18 2 4 19 20 10 4 7 1 6 16 18 17 15 4 7 11 7 20 16 10 3 1 15 19 19 10 13 14 19 9 2 19 17 15 5 15 12 13 3 19 19 13 6 20 20 16 2 12 19 9 8 12 1 2 1 6 14 14 9 16 3 11 16 6 12 16 9 5 1 9 17 4 6 14 18 4 12 9 13 18 18 16 17 12 20 11 6 12 11 1 20 15 13 17 15 6 6 7 10 5 11 8 6 13 14 6 10 16 10 12 6 10 16 1 12 18 3 19 17 9 8 17 7 11 17 5 2 20 11 12 1 12 13 19 19 2 15 11 18 4 15 7 15 16 10 12 10 15 10 5 4 15 7 9 14 11 4 2 19 19 3 11 18 1 12 16 17 18 5 8 10 6 5 19 12 3 7 1 5 3 18 19 5 7 15 5 20 19 13 15 20 12 19 20 17 17 10 16 3 5 5 9 2 4 11 12 7 20 12 1 9 9 6 16 5 4 13 9 19 20 8 10 14 11 18 16 6 16 17 7 15 16 14 10 1 6 10 3 2 10 3 6 16 2 6 12 20 20 19 1 5 2 9 14 9 19 5 5 8 5 9 6 19 15 17 15 8 5 4 18 7 2 15 13 16 17 18 19 1 19 20 17 19 16 1 15 4 8 14 8 5 20 20 15 13 13 17 4 7 12 16 7 12 15 1 11 14 15 7 9 2 18 5 9 5 3 19 5 17 11 7 6 11 10 12 8 18 3 10 2 10 20 2 4 17 18 7 6 18 19 8 2 5 17 8 18 7 14 12 12 18 16 4 1 3 7 9 3 1 20 12 3 5 1 15 11 8 18 8 20 4 2 10 6 7 11 16 10 20 2 19 16 4 14 19 15 8 6 17 2 12 1 4 16 11 2 18 18 16 13 4 16 4 8 16 13 4 9 17 6 18 7 16 18 7 10 10 7 8 20 2 16 13 18 17 6 5 16 3 7 20 16 3 17 1 20 10 3 8 10 16 19 3 4 19 4 7 8 16 12 9 13 7 17 13 10 19 7 3 18 10 13 5 1 14 1 9 11 12 5 3 7 4 11 12 1 17 3 3 19 2 20 12 20 17 12 20 13 19 9 9 17 20 12 15 16 9 11 10 20 11 9 8 15 9 16 13 7 5 8 17 11 3 10 13 9 7 3 18 5 16 14 7 17 20 20 2 8 18 7 13 16 10 8 8 3 4 5 5 6 7 5 \n	197\n	10	20
24	10 2 3\n3 5 9 5 3 2 5 1 4 5\n	25\n	10	20
\.


--
-- TOC entry 4974 (class 0 OID 0)
-- Dependencies: 216
-- Name: contest_contest_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.contest_contest_id_seq', 51, true);


--
-- TOC entry 4975 (class 0 OID 0)
-- Dependencies: 218
-- Name: level_level_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.level_level_id_seq', 3, true);


--
-- TOC entry 4976 (class 0 OID 0)
-- Dependencies: 221
-- Name: professor_prof_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.professor_prof_id_seq', 3, true);


--
-- TOC entry 4977 (class 0 OID 0)
-- Dependencies: 224
-- Name: question_question_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.question_question_id_seq', 10, true);


--
-- TOC entry 4978 (class 0 OID 0)
-- Dependencies: 226
-- Name: student_studentid_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_studentid_seq', 203, true);


--
-- TOC entry 4979 (class 0 OID 0)
-- Dependencies: 228
-- Name: submission_submission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.submission_submission_id_seq', 1450, true);


--
-- TOC entry 4980 (class 0 OID 0)
-- Dependencies: 230
-- Name: submissionline_submissionline_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.submissionline_submissionline_id_seq', 3990, true);


--
-- TOC entry 4981 (class 0 OID 0)
-- Dependencies: 232
-- Name: test_case_test_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.test_case_test_id_seq', 24, true);


--
-- TOC entry 4761 (class 2606 OID 64574)
-- Name: contest contest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contest
    ADD CONSTRAINT contest_pkey PRIMARY KEY (contest_id);


--
-- TOC entry 4763 (class 2606 OID 64576)
-- Name: level level_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.level
    ADD CONSTRAINT level_pkey PRIMARY KEY (level_id);


--
-- TOC entry 4765 (class 2606 OID 64578)
-- Name: participants participants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT participants_pkey PRIMARY KEY (student_id, contest_id);


--
-- TOC entry 4767 (class 2606 OID 64580)
-- Name: professor professor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.professor
    ADD CONSTRAINT professor_pkey PRIMARY KEY (prof_id);


--
-- TOC entry 4771 (class 2606 OID 64582)
-- Name: question_contest question_contest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question_contest
    ADD CONSTRAINT question_contest_pkey PRIMARY KEY (question_id, contest_id);


--
-- TOC entry 4769 (class 2606 OID 64584)
-- Name: question question_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question
    ADD CONSTRAINT question_pkey PRIMARY KEY (question_id);


--
-- TOC entry 4773 (class 2606 OID 64586)
-- Name: student student_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT student_pkey PRIMARY KEY (student_id);


--
-- TOC entry 4775 (class 2606 OID 64588)
-- Name: submission submission_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submission
    ADD CONSTRAINT submission_pkey PRIMARY KEY (submission_id);


--
-- TOC entry 4777 (class 2606 OID 64590)
-- Name: submissionline submissionline_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submissionline
    ADD CONSTRAINT submissionline_pkey PRIMARY KEY (submissionline_id);


--
-- TOC entry 4779 (class 2606 OID 64592)
-- Name: test_case test_case_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_case
    ADD CONSTRAINT test_case_pkey PRIMARY KEY (test_id);


--
-- TOC entry 4794 (class 2620 OID 64593)
-- Name: submission trigger_update_participant_points; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_participant_points AFTER INSERT OR UPDATE ON public.submission FOR EACH ROW EXECUTE FUNCTION public.update_participant_points();


--
-- TOC entry 4795 (class 2620 OID 64724)
-- Name: submission trigger_update_participant_question; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_participant_question AFTER UPDATE ON public.submission FOR EACH ROW EXECUTE FUNCTION public.update_participant_question_trigger();


--
-- TOC entry 4796 (class 2620 OID 64722)
-- Name: submission trigger_update_points; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_points AFTER INSERT OR UPDATE ON public.submission FOR EACH ROW EXECUTE FUNCTION public.update_participant_question_points();


--
-- TOC entry 4797 (class 2620 OID 64594)
-- Name: submissionline update_evaluation_score_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_evaluation_score_trigger AFTER INSERT OR DELETE OR UPDATE ON public.submissionline FOR EACH ROW EXECUTE FUNCTION public.update_evaluation_score();


--
-- TOC entry 4798 (class 2620 OID 64595)
-- Name: submissionline update_submission_status_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_submission_status_trigger AFTER INSERT OR DELETE OR UPDATE ON public.submissionline FOR EACH ROW EXECUTE FUNCTION public.trigger_update_submission_status();


--
-- TOC entry 4785 (class 2606 OID 64596)
-- Name: question_contest fk_contest; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question_contest
    ADD CONSTRAINT fk_contest FOREIGN KEY (contest_id) REFERENCES public.contest(contest_id) NOT VALID;


--
-- TOC entry 4781 (class 2606 OID 64601)
-- Name: participants fk_contest; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT fk_contest FOREIGN KEY (contest_id) REFERENCES public.contest(contest_id) NOT VALID;


--
-- TOC entry 4783 (class 2606 OID 64611)
-- Name: question fk_level; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question
    ADD CONSTRAINT fk_level FOREIGN KEY (level_id) REFERENCES public.level(level_id) NOT VALID;


--
-- TOC entry 4780 (class 2606 OID 64616)
-- Name: contest fk_prof; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contest
    ADD CONSTRAINT fk_prof FOREIGN KEY (prof_id) REFERENCES public.professor(prof_id) NOT VALID;


--
-- TOC entry 4784 (class 2606 OID 64621)
-- Name: question fk_prof; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question
    ADD CONSTRAINT fk_prof FOREIGN KEY (prof_id) REFERENCES public.professor(prof_id) NOT VALID;


--
-- TOC entry 4786 (class 2606 OID 64626)
-- Name: question_contest fk_ques; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.question_contest
    ADD CONSTRAINT fk_ques FOREIGN KEY (question_id) REFERENCES public.question(question_id) NOT VALID;


--
-- TOC entry 4787 (class 2606 OID 64668)
-- Name: submission fk_question; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submission
    ADD CONSTRAINT fk_question FOREIGN KEY (question_id, contest_id) REFERENCES public.question_contest(question_id, contest_id) NOT VALID;


--
-- TOC entry 4782 (class 2606 OID 64636)
-- Name: participants fk_student; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.participants
    ADD CONSTRAINT fk_student FOREIGN KEY (student_id) REFERENCES public.student(student_id) NOT VALID;


--
-- TOC entry 4788 (class 2606 OID 64663)
-- Name: submission fk_student; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submission
    ADD CONSTRAINT fk_student FOREIGN KEY (student_id, contest_id) REFERENCES public.participants(student_id, contest_id) NOT VALID;


--
-- TOC entry 4792 (class 2606 OID 64696)
-- Name: participant_question participant_question_question_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.participant_question
    ADD CONSTRAINT participant_question_question_id_fkey FOREIGN KEY (question_id) REFERENCES public.question(question_id);


--
-- TOC entry 4793 (class 2606 OID 64691)
-- Name: participant_question participant_question_student_id_contest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.participant_question
    ADD CONSTRAINT participant_question_student_id_contest_id_fkey FOREIGN KEY (student_id, contest_id) REFERENCES public.participants(student_id, contest_id);


--
-- TOC entry 4789 (class 2606 OID 64646)
-- Name: submissionline submissionline_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submissionline
    ADD CONSTRAINT submissionline_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.submission(submission_id);


--
-- TOC entry 4790 (class 2606 OID 64651)
-- Name: submissionline submissionline_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.submissionline
    ADD CONSTRAINT submissionline_test_id_fkey FOREIGN KEY (test_id) REFERENCES public.test_case(test_id);


--
-- TOC entry 4791 (class 2606 OID 64656)
-- Name: test_case test_case_question_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_case
    ADD CONSTRAINT test_case_question_id_fkey FOREIGN KEY (question_id) REFERENCES public.question(question_id) NOT VALID;


-- Completed on 2024-12-19 23:50:24

--
-- PostgreSQL database dump complete
--

