-- Create role enum type
CREATE TYPE user_role AS ENUM ('user', 'premium_user', 'support', 'admin');

-- Create roles table
CREATE TABLE public.user_roles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'user',
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    assigned_by UUID REFERENCES auth.users(id),
    metadata JSONB
);

-- Add moved policies from schema.sql
CREATE POLICY "Admins can view all failed transactions"
    ON public.failed_transactions_log
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('admin', 'support')
        )
    );

-- Security events policies
CREATE POLICY "Admins can view all security events"
    ON public.security_events
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'admin'
        )
    );

-- Users can view their own security events
CREATE POLICY "Users can view own security events"
    ON public.security_events
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- Create role assignment function
CREATE OR REPLACE FUNCTION assign_user_role(
    p_user_id UUID,
    p_role user_role
)
RETURNS VOID
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
        RAISE EXCEPTION 'Only administrators can assign roles';
    END IF;

    -- Insert or update role
    INSERT INTO public.user_roles (user_id, role, assigned_by)
    VALUES (p_user_id, p_role, auth.uid())
    ON CONFLICT (user_id)
    DO UPDATE SET 
        role = p_role,
        assigned_at = NOW(),
        assigned_by = auth.uid();
END;
$$;

-- Function to check if user has specific role
CREATE OR REPLACE FUNCTION has_role(
    p_role user_role
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role = p_role
    );
END;
$$;

-- Create admin policies
CREATE POLICY "Admins can view all profiles"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('admin', 'support')
        )
    );

CREATE POLICY "Admins can update all profiles"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'admin'
        )
    );

CREATE POLICY "Admins can view all accounts"
    ON public.accounts FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('admin', 'support')
        )
    );

CREATE POLICY "Admins can update all accounts"
    ON public.accounts FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'admin'
        )
    );

-- Create admin functions
CREATE OR REPLACE FUNCTION suspend_user_account(
    p_user_id UUID,
    p_reason TEXT
)
RETURNS VOID
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
        RAISE EXCEPTION 'Only administrators can suspend accounts';
    END IF;

    -- Suspend all user's accounts
    UPDATE public.accounts
    SET status = 'suspended'
    WHERE user_id = p_user_id;

    -- Create notification
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        metadata
    ) VALUES (
        p_user_id,
        'security',
        'Account Suspended',
        'Your account has been suspended. Please contact support for assistance.',
        jsonb_build_object('reason', p_reason, 'suspended_by', auth.uid())
    );
END;
$$;

-- Function to generate admin activity report
CREATE OR REPLACE FUNCTION get_admin_activity_report(
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    admin_id UUID,
    admin_name TEXT,
    action_type TEXT,
    action_count BIGINT
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
        RAISE EXCEPTION 'Only administrators can view activity reports';
    END IF;

    RETURN QUERY
    SELECT 
        ur.user_id as admin_id,
        p.first_name || ' ' || p.last_name as admin_name,
        'Role assignments' as action_type,
        COUNT(*) as action_count
    FROM public.user_roles ur
    JOIN public.profiles p ON ur.assigned_by = p.id
    WHERE ur.assigned_at BETWEEN p_start_date AND p_end_date
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = ur.assigned_by
        AND role = 'admin'
    )
    GROUP BY ur.user_id, p.first_name, p.last_name;
END;
$$;

-- Add audit trigger for user roles
CREATE TRIGGER audit_user_roles_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.user_roles
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();