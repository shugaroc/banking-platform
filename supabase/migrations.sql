-- Create migrations table to track database changes
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version BIGINT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    applied_at TIMESTAMPTZ DEFAULT NOW(),
    applied_by UUID REFERENCES auth.users(id),
    checksum TEXT NOT NULL,
    execution_time INTERVAL,
    is_success BOOLEAN DEFAULT true,
    rollback_script TEXT
);

-- Function to record a migration
CREATE OR REPLACE FUNCTION record_migration(
    p_version BIGINT,
    p_name TEXT,
    p_description TEXT,
    p_checksum TEXT,
    p_execution_time INTERVAL,
    p_rollback_script TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.schema_migrations (
        version,
        name,
        description,
        applied_by,
        checksum,
        execution_time,
        rollback_script
    ) VALUES (
        p_version,
        p_name,
        p_description,
        auth.uid(),
        p_checksum,
        p_execution_time,
        p_rollback_script
    );
END;
$$;

-- Function to get current database version
CREATE OR REPLACE FUNCTION get_current_db_version()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_version BIGINT;
BEGIN
    SELECT COALESCE(MAX(version), 0)
    INTO v_version
    FROM public.schema_migrations
    WHERE is_success = true;
    
    RETURN v_version;
END;
$$;

-- Function to verify migration integrity
CREATE OR REPLACE FUNCTION verify_migration_integrity()
RETURNS TABLE (
    version BIGINT,
    name TEXT,
    status TEXT,
    error_details TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH migration_checks AS (
        SELECT 
            version,
            name,
            CASE
                WHEN lead(version) OVER (ORDER BY version) - version != 1 
                THEN 'Gap in version numbers detected'
                WHEN COUNT(*) OVER (PARTITION BY version) > 1 
                THEN 'Duplicate version number'
                WHEN NOT is_success 
                THEN 'Failed migration'
                ELSE 'OK'
            END as status,
            CASE
                WHEN NOT is_success THEN 'Migration failed at ' || applied_at::text
                ELSE NULL
            END as error_details
        FROM public.schema_migrations
    )
    SELECT *
    FROM migration_checks
    WHERE status != 'OK'
    ORDER BY version;
END;
$$;

-- Function to generate migration rollback plan
CREATE OR REPLACE FUNCTION generate_rollback_plan(
    p_target_version BIGINT
)
RETURNS TABLE (
    version BIGINT,
    name TEXT,
    rollback_script TEXT,
    estimated_impact TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Only administrators can generate rollback plans';
    END IF;

    RETURN QUERY
    SELECT 
        sm.version,
        sm.name,
        sm.rollback_script,
        CASE
            WHEN sm.rollback_script IS NULL THEN 'WARNING: No rollback script available'
            ELSE 'Normal rollback possible'
        END as estimated_impact
    FROM public.schema_migrations sm
    WHERE sm.version > p_target_version
        AND sm.is_success = true
    ORDER BY sm.version DESC;
END;
$$;

-- Create view for migration history
CREATE OR REPLACE VIEW public.migration_history AS
SELECT 
    version,
    name,
    description,
    applied_at,
    p.first_name || ' ' || p.last_name as applied_by_user,
    execution_time,
    is_success,
    CASE
        WHEN rollback_script IS NOT NULL THEN true
        ELSE false
    END as has_rollback
FROM public.schema_migrations sm
LEFT JOIN public.profiles p ON sm.applied_by = p.id
ORDER BY version DESC;

-- Add RLS policies
ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view migrations"
    ON public.schema_migrations
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'admin'
        )
    );

-- Example migration record
-- SELECT record_migration(
--     1,
--     'initial_schema',
--     'Initial database schema setup',
--     md5('initial_schema_sql_content'),
--     '00:05:23'::interval,
--     'DROP TABLE IF EXISTS profiles, accounts, transactions CASCADE;'
-- );