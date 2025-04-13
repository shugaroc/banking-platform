-- Create audit log table
CREATE TABLE public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by UUID REFERENCES auth.users(id),
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    client_info JSONB
);

-- Create index for faster audit log queries
CREATE INDEX idx_audit_logs_table_record ON public.audit_logs(table_name, record_id);
CREATE INDEX idx_audit_logs_changed_by ON public.audit_logs(changed_by);
CREATE INDEX idx_audit_logs_changed_at ON public.audit_logs(changed_at);

-- Function to record audit log
CREATE OR REPLACE FUNCTION record_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        v_old_data = to_jsonb(OLD);
        v_new_data = null;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_old_data = to_jsonb(OLD);
        v_new_data = to_jsonb(NEW);
    ELSE
        v_old_data = null;
        v_new_data = to_jsonb(NEW);
    END IF;

    INSERT INTO public.audit_logs (
        table_name,
        record_id,
        operation,
        old_data,
        new_data,
        changed_by,
        client_info
    ) VALUES (
        TG_TABLE_NAME,
        CASE 
            WHEN TG_OP = 'DELETE' THEN OLD.id
            ELSE NEW.id
        END,
        TG_OP,
        v_old_data,
        v_new_data,
        auth.uid(),
        jsonb_build_object(
            'client_ip', current_setting('request.headers')::jsonb->>'x-real-ip',
            'user_agent', current_setting('request.headers')::jsonb->>'user-agent'
        )
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Apply audit triggers to important tables
CREATE TRIGGER audit_profiles_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

CREATE TRIGGER audit_accounts_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.accounts
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

CREATE TRIGGER audit_transactions_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

-- Function to query audit logs with filtering
CREATE OR REPLACE FUNCTION get_audit_logs(
    p_table_name TEXT DEFAULT NULL,
    p_record_id UUID DEFAULT NULL,
    p_operation TEXT DEFAULT NULL,
    p_changed_by UUID DEFAULT NULL,
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS SETOF public.audit_logs
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if caller is admin or support
    IF NOT EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('admin', 'support')
    ) THEN
        RAISE EXCEPTION 'Only administrators and support staff can view audit logs';
    END IF;

    RETURN QUERY
    SELECT *
    FROM public.audit_logs
    WHERE (p_table_name IS NULL OR table_name = p_table_name)
    AND (p_record_id IS NULL OR record_id = p_record_id)
    AND (p_operation IS NULL OR operation = p_operation)
    AND (p_changed_by IS NULL OR changed_by = p_changed_by)
    AND changed_at BETWEEN p_start_date AND p_end_date
    ORDER BY changed_at DESC;
END;
$$;

-- Create view for recent important changes
CREATE OR REPLACE VIEW public.recent_important_changes AS
SELECT 
    al.id,
    al.table_name,
    al.operation,
    al.changed_at,
    COALESCE(p.first_name || ' ' || p.last_name, 'System') as changed_by_name,
    CASE
        WHEN al.table_name = 'accounts' THEN 
            CASE 
                WHEN al.operation = 'UPDATE' THEN 
                    CASE 
                        WHEN (al.old_data->>'status') IS NOT NULL 
                             AND (al.new_data->>'status') IS NOT NULL 
                             AND (al.old_data->>'status')::text != (al.new_data->>'status')::text
                        THEN format('Account status changed from %s to %s', 
                             al.old_data->>'status', 
                             al.new_data->>'status')
                        ELSE 'Account details updated'
                    END
                WHEN al.operation = 'INSERT' THEN 'New account created'
                ELSE 'Account deleted'
            END
        WHEN al.table_name = 'transactions' THEN 
            CASE 
                WHEN al.operation = 'INSERT' AND al.new_data IS NOT NULL THEN 
                    format('New %s transaction of %s %s',
                        COALESCE(al.new_data->>'type', 'unknown'),
                        COALESCE(al.new_data->>'amount', '0'),
                        COALESCE(al.new_data->>'currency', 'unknown'))
                ELSE format('Transaction %s', lower(al.operation))
            END
        ELSE format('%s %s', al.table_name, lower(al.operation))
    END as change_description
FROM public.audit_logs al
LEFT JOIN public.profiles p ON al.changed_by = p.id
WHERE al.changed_at >= NOW() - INTERVAL '24 hours'
ORDER BY al.changed_at DESC;