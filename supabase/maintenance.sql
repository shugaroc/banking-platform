-- Create table for system health metrics
CREATE TABLE IF NOT EXISTS public.system_health_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    metric_name TEXT NOT NULL,
    metric_value NUMERIC,
    metric_unit TEXT,
    collected_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB
);

-- Function to collect system metrics
CREATE OR REPLACE FUNCTION collect_system_metrics()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Record transaction counts
    INSERT INTO public.system_health_metrics (metric_name, metric_value, metric_unit, metadata)
    SELECT 
        'daily_transaction_count',
        COUNT(*),
        'count',
        jsonb_build_object(
            'completed', SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END),
            'failed', SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END),
            'pending', SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END)
        )
    FROM public.transactions
    WHERE created_at >= NOW() - INTERVAL '1 day';

    -- Record active users
    INSERT INTO public.system_health_metrics (metric_name, metric_value, metric_unit, metadata)
    SELECT 
        'active_users',
        COUNT(DISTINCT user_id),
        'count',
        jsonb_build_object(
            'with_transactions', COUNT(DISTINCT t.source_account_id)
        )
    FROM public.accounts a
    LEFT JOIN public.transactions t ON a.id = t.source_account_id
    WHERE a.status = 'active';

    -- Record average transaction value
    INSERT INTO public.system_health_metrics (metric_name, metric_value, metric_unit, metadata)
    SELECT 
        'avg_transaction_value',
        AVG(amount),
        'currency_amount',
        jsonb_build_object(
            'currency', currency,
            'min_value', MIN(amount),
            'max_value', MAX(amount)
        )
    FROM public.transactions
    WHERE created_at >= NOW() - INTERVAL '1 day'
    GROUP BY currency;

    -- Record system errors
    INSERT INTO public.system_health_metrics (metric_name, metric_value, metric_unit, metadata)
    SELECT 
        'error_count',
        COUNT(*),
        'count',
        jsonb_build_object(
            'high_severity', SUM(CASE WHEN severity IN ('high', 'critical') THEN 1 ELSE 0 END),
            'types', jsonb_object_agg(event_type, COUNT(*))
        )
    FROM public.security_events
    WHERE created_at >= NOW() - INTERVAL '1 day';
END;
$$;

-- Function to analyze database performance
CREATE OR REPLACE FUNCTION analyze_db_performance(
    p_days INTEGER DEFAULT 7
)
RETURNS TABLE (
    metric_name TEXT,
    current_value NUMERIC,
    change_percentage NUMERIC,
    trend TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH current_metrics AS (
        SELECT 
            metric_name,
            AVG(metric_value) as current_avg
        FROM public.system_health_metrics
        WHERE collected_at >= NOW() - INTERVAL '1 day'
        GROUP BY metric_name
    ),
    previous_metrics AS (
        SELECT 
            metric_name,
            AVG(metric_value) as previous_avg
        FROM public.system_health_metrics
        WHERE collected_at BETWEEN NOW() - (p_days || ' days')::INTERVAL AND NOW() - INTERVAL '1 day'
        GROUP BY metric_name
    )
    SELECT 
        cm.metric_name,
        cm.current_avg as current_value,
        CASE 
            WHEN pm.previous_avg > 0 
            THEN ((cm.current_avg - pm.previous_avg) / pm.previous_avg * 100)
            ELSE 0 
        END as change_percentage,
        CASE
            WHEN cm.current_avg > pm.previous_avg THEN 'increasing'
            WHEN cm.current_avg < pm.previous_avg THEN 'decreasing'
            ELSE 'stable'
        END as trend
    FROM current_metrics cm
    JOIN previous_metrics pm ON cm.metric_name = pm.metric_name;
END;
$$;

-- Function to clean up old data
CREATE OR REPLACE FUNCTION cleanup_old_data(
    p_months INTEGER DEFAULT 12
)
RETURNS TABLE (
    table_name TEXT,
    records_cleaned BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cutoff_date TIMESTAMPTZ := NOW() - (p_months || ' months')::INTERVAL;
    v_records_cleaned BIGINT;
BEGIN
    -- Check if caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Only administrators can perform data cleanup';
    END IF;

    -- Clean up old notifications
    DELETE FROM public.notifications
    WHERE created_at < v_cutoff_date
    AND is_read = true;
    GET DIAGNOSTICS v_records_cleaned = ROW_COUNT;
    
    RETURN QUERY SELECT 'notifications'::TEXT, v_records_cleaned;

    -- Clean up old security events
    DELETE FROM public.security_events
    WHERE created_at < v_cutoff_date
    AND severity NOT IN ('high', 'critical');
    GET DIAGNOSTICS v_records_cleaned = ROW_COUNT;
    
    RETURN QUERY SELECT 'security_events'::TEXT, v_records_cleaned;

    -- Clean up old system health metrics
    DELETE FROM public.system_health_metrics
    WHERE collected_at < v_cutoff_date;
    GET DIAGNOSTICS v_records_cleaned = ROW_COUNT;
    
    RETURN QUERY SELECT 'system_health_metrics'::TEXT, v_records_cleaned;

    -- Clean up old audit logs
    DELETE FROM public.audit_logs
    WHERE changed_at < v_cutoff_date;
    GET DIAGNOSTICS v_records_cleaned = ROW_COUNT;
    
    RETURN QUERY SELECT 'audit_logs'::TEXT, v_records_cleaned;
END;
$$;

-- Function to get system status report
CREATE OR REPLACE FUNCTION get_system_status_report()
RETURNS TABLE (
    component TEXT,
    status TEXT,
    last_check_time TIMESTAMPTZ,
    details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    -- Check transaction processing
    SELECT 
        'Transaction Processing'::TEXT as component,
        CASE 
            WHEN COUNT(*) > 0 THEN 'Warning'
            ELSE 'Healthy'
        END as status,
        NOW() as last_check_time,
        jsonb_build_object(
            'pending_transactions', COUNT(*),
            'oldest_pending', MIN(created_at)
        ) as details
    FROM public.transactions
    WHERE status = 'pending'
    AND created_at < NOW() - INTERVAL '15 minutes'

    UNION ALL

    -- Check recurring transfers
    SELECT 
        'Recurring Transfers'::TEXT,
        CASE 
            WHEN COUNT(*) > 0 THEN 'Warning'
            ELSE 'Healthy'
        END,
        NOW(),
        jsonb_build_object(
            'failed_schedules', COUNT(*),
            'affected_users', COUNT(DISTINCT user_id)
        )
    FROM public.recurring_transfers rt
    JOIN public.accounts a ON rt.source_account_id = a.id
    WHERE rt.failure_count > 0

    UNION ALL

    -- Check security status
    SELECT 
        'Security Status'::TEXT,
        CASE 
            WHEN COUNT(*) > 10 THEN 'Critical'
            WHEN COUNT(*) > 5 THEN 'Warning'
            ELSE 'Healthy'
        END,
        NOW(),
        jsonb_build_object(
            'high_severity_events', COUNT(*),
            'affected_users', COUNT(DISTINCT user_id)
        )
    FROM public.security_events
    WHERE severity IN ('high', 'critical')
    AND created_at >= NOW() - INTERVAL '1 hour'

    UNION ALL

    -- Check database health
    SELECT 
        'Database Health'::TEXT,
        CASE 
            WHEN pg_database_size(current_database()) > 1024 * 1024 * 1024 * 100 THEN 'Warning'
            ELSE 'Healthy'
        END,
        NOW(),
        jsonb_build_object(
            'size_gb', (pg_database_size(current_database()) / (1024^3))::INTEGER,
            'active_connections', (SELECT COUNT(*) FROM pg_stat_activity)
        );
END;
$$;

-- Schedule regular maintenance tasks
CREATE OR REPLACE FUNCTION schedule_maintenance_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Schedule metric collection every hour
    SELECT cron.schedule(
        'collect-system-metrics',
        '0 * * * *',
        'SELECT collect_system_metrics();'
    );

    -- Schedule data cleanup monthly
    SELECT cron.schedule(
        'monthly-data-cleanup',
        '0 0 1 * *',
        'SELECT cleanup_old_data(12);'
    );

    -- Schedule database analysis weekly
    SELECT cron.schedule(
        'weekly-performance-analysis',
        '0 0 * * 0',
        'SELECT analyze_db_performance(7);'
    );
END;
$$;

-- Create RLS policies
ALTER TABLE public.system_health_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view system metrics"
    ON public.system_health_metrics
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'admin'
        )
    );