-- Definitions concerning our hnsw-based index data strucuture

CREATE FUNCTION hnsw_handler(internal) RETURNS index_am_handler
	AS 'MODULE_PATHNAME' LANGUAGE C;

DO $BODY$
DECLARE
	hnsw_am_exists boolean;
	pgvector_exists boolean;
BEGIN
	-- Check if another extension already created an access method named 'hnsw'
	SELECT EXISTS (
		SELECT 1
		FROM pg_am
		WHERE amname = 'hnsw'
	) INTO hnsw_am_exists;

	-- Check if the vector type from pgvector exists
	SELECT EXISTS (
		SELECT 1
		FROM pg_type
		WHERE typname = 'vector'
	) INTO pgvector_exists;

	IF pgvector_exists OR hnsw_am_exists THEN
		-- RAISE NOTICE 'hnsw access method already exists. Creating lantern_hnsw access method';
		CREATE ACCESS METHOD lantern_hnsw TYPE INDEX HANDLER hnsw_handler;
		COMMENT ON ACCESS METHOD lantern_hnsw IS 'LanternDB access method for vector embeddings, based on the hnsw algorithm';
	END IF;

	IF pgvector_exists THEN
		-- taken from pgvector so our index can work with pgvector types
		CREATE FUNCTION vector_l2sq_dist(vector, vector) RETURNS float8
			AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

		CREATE OPERATOR CLASS dist_vec_l2sq_ops
			DEFAULT FOR TYPE vector USING lantern_hnsw AS
			OPERATOR 1 <-> (vector, vector) FOR ORDER BY float_ops,
			FUNCTION 1 vector_l2sq_dist(vector, vector);
	END IF;


	IF hnsw_am_exists THEN
		RAISE WARNING 'Access method(index type) "hnsw" already exists. Creating lantern_hnsw access method';
	ELSE
		-- create access method
		CREATE ACCESS METHOD hnsw TYPE INDEX HANDLER hnsw_handler;
		COMMENT ON ACCESS METHOD hnsw IS 'LanternDB access method for vector embeddings, based on the hnsw algorithm';
		IF pgvector_exists THEN
			-- An older version of pgvector exists, which does not have hnsw yet
			-- So, there is no naming conflict. We still add a compatibility operator class
			-- so pgvector vector type can be used with our index
			-- taken from pgvector so our index can work with pgvector types
			CREATE OPERATOR CLASS dist_vec_l2sq_ops
				DEFAULT FOR TYPE vector USING hnsw AS
				OPERATOR 1 <-> (vector, vector) FOR ORDER BY float_ops,
				FUNCTION 1 vector_l2sq_dist(vector, vector);
		END IF;
	END IF;
END;
$BODY$
LANGUAGE plpgsql;

-- functions
CREATE FUNCTION ldb_generic_dist(real[], real[]) RETURNS real
	AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
	
CREATE FUNCTION ldb_generic_dist(integer[], integer[]) RETURNS real
	AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
	
CREATE FUNCTION l2sq_dist(real[], real[]) RETURNS real
	AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION cos_dist(real[], real[]) RETURNS real
	AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION hamming_dist(integer[], integer[]) RETURNS integer
	AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- operators
CREATE OPERATOR <-> (
	LEFTARG = real[], RIGHTARG = real[], PROCEDURE = ldb_generic_dist,
	COMMUTATOR = '<->'
);

CREATE OPERATOR <-> (
	LEFTARG = integer[], RIGHTARG = integer[], PROCEDURE = ldb_generic_dist,
	COMMUTATOR = '<->'
);

-- operator classes
CREATE OPERATOR CLASS dist_l2sq_ops
  DEFAULT FOR TYPE real[] USING hnsw AS
	OPERATOR 1 <-> (real[], real[]) FOR ORDER BY float_ops,
	FUNCTION 1 l2sq_dist(real[], real[]);

CREATE OPERATOR CLASS dist_cos_ops
	FOR TYPE real[] USING hnsw AS
	OPERATOR 1 <-> (real[], real[]) FOR ORDER BY float_ops,
	FUNCTION 1 cos_dist(real[], real[]);

CREATE OPERATOR CLASS dist_hamming_ops
	FOR TYPE integer[] USING hnsw AS
	OPERATOR 1 <-> (integer[], integer[]) FOR ORDER BY float_ops,
	FUNCTION 1 hamming_dist(integer[], integer[]);
