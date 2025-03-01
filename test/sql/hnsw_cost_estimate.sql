SET client_min_messages=debug5;

\ir utils/sift10k_array.sql

-- This function executes the given SQL query and returns its estimated total cost.
-- It parses the EXPLAIN output to retrieve the outermost (top-level) cost estimation.
-- Example EXPLAIN line: "Limit  (cost=0.00..0.47 rows=10 width=40)"
-- The regex captures the cost range and returns the higher end.
-- Returns NULL if no cost is found or if the provided query doesn't match the expected format.
CREATE OR REPLACE FUNCTION get_cost_estimate(explain_query text) RETURNS real AS $$
DECLARE
    explain_output text;
    cost_match text;
    line text;
BEGIN
    EXECUTE explain_query INTO explain_output;
    FOR line IN (
        SELECT
            unnest(string_to_array(explain_output, E'\n')))
        LOOP
            IF position(' ' IN
            LEFT (line, 1)) = 0 AND line LIKE '%cost=%' THEN
                cost_match :=(regexp_matches(line, 'cost=\d+\.\d+..\d+\.\d+'))[1];
                -- Adjust regex to capture both costs
                RETURN split_part(split_part(cost_match, '=', 2), '..', 2)::real;
                -- Extract the total cost
            END IF;
        END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- This function checks if val2 is within some error margin of val1.
CREATE OR REPLACE FUNCTION is_within_error(val1 real, val2 real, error_margin real) RETURNS boolean AS $$
BEGIN
    RETURN val2 BETWEEN val1 * (1 - error_margin) AND val1 * (1 + error_margin);
END;
$$ LANGUAGE plpgsql;

-- This function checks if the cost estimate for the given query is within some error margin of the expected cost.
CREATE OR REPLACE FUNCTION is_cost_estimate_within_error(explain_query text, expected_cost real, error_margin real DEFAULT 0.05) RETURNS boolean AS $$
BEGIN
    RETURN is_within_error(get_cost_estimate(explain_query), expected_cost, error_margin);    
END;
$$ LANGUAGE plpgsql;

-- Goal: make sure query cost estimate is accurate
-- when index is created with varying costruction parameters.
SELECT v AS v4444 FROM sift_base10k WHERE id = 4444 \gset
\set explain_query_template 'EXPLAIN SELECT * FROM sift_base10k ORDER BY v <-> ''%s'' LIMIT 10'
\set enable_seqscan = off;

-- Case 0, sanity check. No data.
CREATE TABLE empty_table(id SERIAL PRIMARY KEY, v REAL[2]);
CREATE INDEX empty_idx ON empty_table USING hnsw (v dist_l2sq_ops) WITH (M=2, ef_construction=10, ef=2, dim=2);
SELECT is_cost_estimate_within_error('EXPLAIN SELECT * FROM empty_table ORDER BY v <-> ''{1,2}'' LIMIT 10', 0.47);
DROP INDEX empty_idx;

-- Case 1, more data in index.
-- Should see higher cost than Case 0.
CREATE INDEX hnsw_idx ON sift_base10k USING hnsw (v dist_l2sq_ops) WITH (M=2, ef_construction=10, ef=4, dim=128);
SELECT is_cost_estimate_within_error(format(:'explain_query_template', :'v4444'), 3.00);
DROP INDEX hnsw_idx;

-- Case 2, higher M.
-- Should see higher cost than Case 1.
CREATE INDEX hnsw_idx ON sift_base10k USING hnsw (v dist_l2sq_ops) WITH (M=20, ef_construction=10, ef=4, dim=128);
SELECT is_cost_estimate_within_error(format(:'explain_query_template', :'v4444'), 3.27);
DROP INDEX hnsw_idx;

-- Case 3, higher ef.
-- Should see higher cost than Case 2.
CREATE INDEX hnsw_idx ON sift_base10k USING hnsw (v dist_l2sq_ops) WITH (M=20, ef_construction=10, ef=16, dim=128);
SELECT is_cost_estimate_within_error(format(:'explain_query_template', :'v4444'), 3.91);
DROP INDEX hnsw_idx;
