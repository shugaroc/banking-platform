-- Views for commonly accessed data combinations

-- Account balance view with user information
CREATE OR REPLACE VIEW public.account_balances AS
SELECT 
    a.id AS account_id,
    a.account_number,
    a.account_type,
    a.currency,
    a.balance,
    a.available_balance,
    a.status,
    p.id AS user_id,
    p.first_name,
    p.last_name,
    p.kyc_status
FROM public.accounts a
JOIN public.profiles p ON a.user_id = p.id;

-- Transaction history view with account details
CREATE OR REPLACE VIEW public.transaction_history AS
SELECT 
    t.id AS transaction_id,
    t.created_at,
    t.type,
    t.status,
    t.amount,
    t.currency,
    t.description,
    t.reference_number,
    src.account_number AS source_account_number,
    src_owner.first_name AS source_owner_first_name,
    src_owner.last_name AS source_owner_last_name,
    dest.account_number AS destination_account_number,
    dest_owner.first_name AS destination_owner_first_name,
    dest_owner.last_name AS destination_owner_last_name
FROM public.transactions t
LEFT JOIN public.accounts src ON t.source_account_id = src.id
LEFT JOIN public.profiles src_owner ON src.user_id = src_owner.id
LEFT JOIN public.accounts dest ON t.destination_account_id = dest.id
LEFT JOIN public.profiles dest_owner ON dest.user_id = dest_owner.id;

-- Monthly account statement view
CREATE OR REPLACE VIEW public.monthly_statements AS
SELECT 
    a.id AS account_id,
    a.account_number,
    a.account_type,
    p.first_name,
    p.last_name,
    date_trunc('month', t.created_at) AS statement_month,
    a.currency,
    SUM(CASE WHEN t.destination_account_id = a.id THEN t.amount ELSE 0 END) AS total_credits,
    SUM(CASE WHEN t.source_account_id = a.id THEN t.amount ELSE 0 END) AS total_debits,
    COUNT(t.id) AS total_transactions
FROM public.accounts a
JOIN public.profiles p ON a.user_id = p.id
LEFT JOIN public.transactions t ON (t.source_account_id = a.id OR t.destination_account_id = a.id)
    AND t.status = 'completed'
GROUP BY a.id, a.account_number, a.account_type, p.first_name, p.last_name, date_trunc('month', t.created_at), a.currency;

-- Function to process deposits
CREATE OR REPLACE FUNCTION process_deposit(
    p_account_id UUID,
    p_amount DECIMAL,
    p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_transaction_id UUID;
    v_reference_number TEXT;
    v_currency currency_code;
BEGIN
    -- Get account currency
    SELECT currency INTO v_currency 
    FROM public.accounts 
    WHERE id = p_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid account';
    END IF;

    -- Generate reference number
    v_reference_number := 'DEP-' || to_char(NOW(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 8);

    -- Update account balance
    UPDATE public.accounts
    SET balance = balance + p_amount,
        available_balance = available_balance + p_amount
    WHERE id = p_account_id
    AND status = 'active'
    RETURNING id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or inactive account';
    END IF;

    -- Create transaction record
    INSERT INTO public.transactions (
        destination_account_id,
        amount,
        currency,
        type,
        status,
        description,
        reference_number
    ) VALUES (
        p_account_id,
        p_amount,
        v_currency,
        'deposit',
        'completed',
        p_description,
        v_reference_number
    ) RETURNING id INTO v_transaction_id;

    RETURN v_transaction_id;
END;
$$;

-- Function to process withdrawals
CREATE OR REPLACE FUNCTION process_withdrawal(
    p_account_id UUID,
    p_amount DECIMAL,
    p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_transaction_id UUID;
    v_reference_number TEXT;
    v_currency currency_code;
BEGIN
    -- Check if user owns the account
    IF NOT EXISTS (
        SELECT 1 FROM public.accounts 
        WHERE id = p_account_id 
        AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Unauthorized to withdraw from this account';
    END IF;

    -- Get account currency
    SELECT currency INTO v_currency 
    FROM public.accounts 
    WHERE id = p_account_id;

    -- Generate reference number
    v_reference_number := 'WTH-' || to_char(NOW(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 8);

    -- Update account balance
    UPDATE public.accounts
    SET balance = balance - p_amount,
        available_balance = available_balance - p_amount
    WHERE id = p_account_id
    AND balance >= p_amount
    AND available_balance >= p_amount
    AND status = 'active'
    RETURNING id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient funds or inactive account';
    END IF;

    -- Create transaction record
    INSERT INTO public.transactions (
        source_account_id,
        amount,
        currency,
        type,
        status,
        description,
        reference_number
    ) VALUES (
        p_account_id,
        p_amount,
        v_currency,
        'withdrawal',
        'completed',
        p_description,
        v_reference_number
    ) RETURNING id INTO v_transaction_id;

    RETURN v_transaction_id;
END;
$$;

-- Function to calculate account statistics
CREATE OR REPLACE FUNCTION get_account_statistics(
    p_account_id UUID,
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    total_credits DECIMAL,
    total_debits DECIMAL,
    transaction_count INTEGER,
    average_transaction_amount DECIMAL,
    largest_transaction DECIMAL,
    smallest_transaction DECIMAL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH account_transactions AS (
        SELECT
            amount,
            CASE 
                WHEN destination_account_id = p_account_id THEN 'credit'
                ELSE 'debit'
            END as transaction_direction
        FROM public.transactions
        WHERE (source_account_id = p_account_id OR destination_account_id = p_account_id)
        AND status = 'completed'
        AND created_at BETWEEN p_start_date AND p_end_date
    )
    SELECT
        COALESCE(SUM(CASE WHEN transaction_direction = 'credit' THEN amount ELSE 0 END), 0) as total_credits,
        COALESCE(SUM(CASE WHEN transaction_direction = 'debit' THEN amount ELSE 0 END), 0) as total_debits,
        COUNT(*) as transaction_count,
        COALESCE(AVG(amount), 0) as average_transaction_amount,
        COALESCE(MAX(amount), 0) as largest_transaction,
        COALESCE(MIN(amount), 0) as smallest_transaction
    FROM account_transactions;
END;
$$;

-- Function to check for suspicious transactions
CREATE OR REPLACE FUNCTION check_suspicious_activity(
    p_account_id UUID,
    p_amount DECIMAL,
    p_currency currency_code
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_avg_transaction DECIMAL;
    v_transaction_count INTEGER;
    v_daily_total DECIMAL;
BEGIN
    -- Get average transaction amount for last 30 days
    SELECT AVG(amount), COUNT(*)
    INTO v_avg_transaction, v_transaction_count
    FROM public.transactions
    WHERE (source_account_id = p_account_id OR destination_account_id = p_account_id)
    AND created_at >= NOW() - INTERVAL '30 days'
    AND currency = p_currency;

    -- Get total transaction amount for today
    SELECT COALESCE(SUM(amount), 0)
    INTO v_daily_total
    FROM public.transactions
    WHERE source_account_id = p_account_id
    AND DATE(created_at) = CURRENT_DATE
    AND currency = p_currency;

    -- Check suspicious conditions
    RETURN (
        -- Amount is more than 5x the average
        (p_amount > v_avg_transaction * 5 AND v_transaction_count >= 5) OR
        -- Daily total would exceed $10,000
        (v_daily_total + p_amount > 10000 AND p_currency = 'USD') OR
        -- First transaction is unusually large
        (v_transaction_count = 0 AND p_amount > 1000)
    );
END;
$$;

-- Function to generate account statements
CREATE OR REPLACE FUNCTION generate_account_statement(
    p_account_id UUID,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    transaction_date TIMESTAMPTZ,
    description TEXT,
    reference_number TEXT,
    debit DECIMAL,
    credit DECIMAL,
    balance DECIMAL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if user owns the account or is admin/support
    IF NOT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = p_account_id
        AND (
            a.user_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM public.user_roles
                WHERE user_id = auth.uid()
                AND role IN ('admin', 'support')
            )
        )
    ) THEN
        RAISE EXCEPTION 'Unauthorized to access this account statement';
    END IF;

    RETURN QUERY
    WITH RECURSIVE balance_changes AS (
        SELECT
            t.created_at as transaction_date,
            t.description,
            t.reference_number,
            CASE WHEN t.source_account_id = p_account_id THEN t.amount ELSE 0 END as debit,
            CASE WHEN t.destination_account_id = p_account_id THEN t.amount ELSE 0 END as credit,
            row_number() OVER (ORDER BY t.created_at) as rn
        FROM public.transactions t
        WHERE (t.source_account_id = p_account_id OR t.destination_account_id = p_account_id)
        AND t.status = 'completed'
        AND DATE(t.created_at) BETWEEN p_start_date AND p_end_date
    ),
    running_balance AS (
        SELECT
            bc.*,
            (bc.credit - bc.debit) as balance
        FROM balance_changes bc
        WHERE rn = 1
        UNION ALL
        SELECT
            bc.*,
            rb.balance + (bc.credit - bc.debit) as balance
        FROM balance_changes bc
        JOIN running_balance rb ON bc.rn = rb.rn + 1
    )
    SELECT
        rb.transaction_date,
        rb.description,
        rb.reference_number,
        rb.debit,
        rb.credit,
        rb.balance
    FROM running_balance rb
    ORDER BY rb.transaction_date;
END;
$$;

-- Function to validate beneficiary bank details
CREATE OR REPLACE FUNCTION validate_beneficiary_details(
    p_bank_code TEXT,
    p_account_number TEXT,
    p_swift_code TEXT DEFAULT NULL,
    p_iban TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Basic format validation
    IF NOT (
        p_bank_code ~ '^[A-Z0-9]{4,11}$' AND  -- Common bank code format
        p_account_number ~ '^[A-Z0-9]{5,34}$'  -- General account number format
    ) THEN
        RETURN FALSE;
    END IF;

    -- SWIFT code validation if provided
    IF p_swift_code IS NOT NULL AND NOT (
        p_swift_code ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'  -- SWIFT/BIC format
    ) THEN
        RETURN FALSE;
    END IF;

    -- IBAN validation if provided
    IF p_iban IS NOT NULL AND NOT (
        p_iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{4,}$'  -- Basic IBAN format
    ) THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

-- Function to process recurring transfers
CREATE OR REPLACE FUNCTION schedule_recurring_transfer(
    p_source_account_id UUID,
    p_destination_account_id UUID,
    p_amount DECIMAL,
    p_description TEXT,
    p_frequency INTERVAL,
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_schedule_id UUID;
BEGIN
    -- Create schedule record
    INSERT INTO public.recurring_transfers (
        source_account_id,
        destination_account_id,
        amount,
        description,
        frequency,
        next_execution,
        end_date
    ) VALUES (
        p_source_account_id,
        p_destination_account_id,
        p_amount,
        p_description,
        p_frequency,
        p_start_date,
        p_end_date
    ) RETURNING id INTO v_schedule_id;

    RETURN v_schedule_id;
END;
$$;

-- Function to set up a cron job for recurring transfers
CREATE OR REPLACE FUNCTION setup_recurring_transfers_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Run recurring transfers processor every day at midnight
    SELECT cron.schedule(
        'process-recurring-transfers',  -- job name
        '0 0 * * *',                   -- every day at midnight
        'SELECT process_pending_recurring_transfers();'
    );
END;
$$;

-- Function to get recurring transfer status
CREATE OR REPLACE FUNCTION get_recurring_transfer_status(
    p_transfer_id UUID
)
RETURNS TABLE (
    next_execution DATE,
    last_execution_at TIMESTAMPTZ,
    remaining_transfers INTEGER,
    total_processed INTEGER,
    total_failed INTEGER,
    is_active BOOLEAN,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if user owns the recurring transfer
    IF NOT EXISTS (
        SELECT 1 
        FROM public.recurring_transfers rt
        JOIN public.accounts a ON rt.source_account_id = a.id
        WHERE rt.id = p_transfer_id 
        AND a.user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Unauthorized to view this recurring transfer';
    END IF;

    RETURN QUERY
    WITH transfer_counts AS (
        SELECT 
            COUNT(*) FILTER (WHERE status = 'completed') as successful_count,
            COUNT(*) FILTER (WHERE status = 'failed') as failed_count
        FROM public.transactions t
        WHERE t.description LIKE '%Recurring Transfer%'
        AND t.metadata->>'recurring_transfer_id' = p_transfer_id::text
    )
    SELECT 
        rt.next_execution,
        rt.last_execution_at,
        CASE 
            WHEN rt.end_date IS NULL THEN NULL
            ELSE (rt.end_date - CURRENT_DATE)::integer
        END as remaining_transfers,
        tc.successful_count::integer as total_processed,
        tc.failed_count::integer as total_failed,
        rt.is_active,
        CASE
            WHEN NOT rt.is_active THEN 'Inactive'
            WHEN rt.failure_count >= 3 THEN 'Failed'
            WHEN rt.end_date < CURRENT_DATE THEN 'Completed'
            ELSE 'Active'
        END as status
    FROM public.recurring_transfers rt
    CROSS JOIN transfer_counts tc
    WHERE rt.id = p_transfer_id;
END;
$$;

-- Create function to get recurring transfers summary
CREATE OR REPLACE FUNCTION get_recurring_transfers_summary()
RETURNS TABLE (
    id UUID,
    amount DECIMAL,
    frequency INTERVAL,
    next_execution DATE,
    source_account TEXT,
    destination_account TEXT,
    owner_name TEXT,
    successful_transfers_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rt.id,
        rt.amount,
        rt.frequency,
        rt.next_execution,
        src.account_number as source_account,
        dest.account_number as destination_account,
        p.first_name || ' ' || p.last_name as owner_name,
        COALESCE(
            (
                SELECT COUNT(*)
                FROM public.transactions t
                WHERE t.description LIKE '%Recurring Transfer%'
                AND t.metadata->>'recurring_transfer_id' = rt.id::text
                AND t.status = 'completed'
            ),
            0
        ) as successful_transfers_count
    FROM public.recurring_transfers rt
    JOIN public.accounts src ON rt.source_account_id = src.id
    JOIN public.accounts dest ON rt.destination_account_id = dest.id
    JOIN public.profiles p ON src.user_id = p.id
    WHERE rt.is_active = true
    AND (rt.end_date IS NULL OR rt.end_date >= CURRENT_DATE)
    AND (
        src.user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('admin', 'support')
        )
    );
END;
$$;

-- Create view using the security definer function
CREATE OR REPLACE VIEW public.active_recurring_transfers_summary AS
SELECT * FROM get_recurring_transfers_summary();

-- Function to log security events
CREATE OR REPLACE FUNCTION log_security_event(
    p_user_id UUID,
    p_event_type TEXT,
    p_severity TEXT,
    p_description TEXT,
    p_metadata JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_event_id UUID;
BEGIN
    INSERT INTO public.security_events (
        user_id,
        event_type,
        severity,
        description,
        ip_address,
        user_agent,
        metadata
    ) VALUES (
        p_user_id,
        p_event_type,
        p_severity,
        p_description,
        current_setting('request.headers')::jsonb->>'x-real-ip',
        current_setting('request.headers')::jsonb->>'user-agent',
        p_metadata
    ) RETURNING id INTO v_event_id;

    -- Create notification for high severity events
    IF p_severity IN ('high', 'critical') THEN
        INSERT INTO public.notifications (
            user_id,
            type,
            title,
            content,
            metadata
        ) VALUES (
            p_user_id,
            'security',
            'Security Alert: ' || p_event_type,
            p_description,
            jsonb_build_object(
                'security_event_id', v_event_id,
                'severity', p_severity
            )
        );
    END IF;

    RETURN v_event_id;
END;
$$;

-- Function to generate security report
CREATE OR REPLACE FUNCTION generate_security_report(
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    event_date DATE,
    event_type TEXT,
    severity TEXT,
    event_count BIGINT,
    unique_users BIGINT
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
        RAISE EXCEPTION 'Only administrators can generate security reports';
    END IF;

    RETURN QUERY
    SELECT
        DATE(created_at) as event_date,
        event_type,
        severity,
        COUNT(*) as event_count,
        COUNT(DISTINCT user_id) as unique_users
    FROM public.security_events
    WHERE created_at BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(created_at), event_type, severity
    ORDER BY event_date DESC, severity DESC;
END;
$$;

-- Function to analyze suspicious patterns
CREATE OR REPLACE FUNCTION analyze_suspicious_patterns(
    p_user_id UUID,
    p_lookback_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    pattern_type TEXT,
    severity TEXT,
    description TEXT,
    occurrence_count BIGINT
)
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
        RAISE EXCEPTION 'Unauthorized to analyze suspicious patterns';
    END IF;

    RETURN QUERY
    -- Failed login attempts
    SELECT
        'Failed Authentication' as pattern_type,
        CASE
            WHEN COUNT(*) >= 10 THEN 'critical'
            WHEN COUNT(*) >= 5 THEN 'high'
            ELSE 'medium'
        END as severity,
        'Multiple failed login attempts detected' as description,
        COUNT(*) as occurrence_count
    FROM public.security_events
    WHERE user_id = p_user_id
    AND event_type = 'failed_login'
    AND created_at >= NOW() - (p_lookback_days || ' days')::INTERVAL
    HAVING COUNT(*) >= 3

    UNION ALL

    -- Large transactions
    SELECT
        'Large Transactions' as pattern_type,
        CASE
            WHEN COUNT(*) >= 5 THEN 'high'
            ELSE 'medium'
        END as severity,
        'Multiple large transactions detected' as description,
        COUNT(*) as occurrence_count
    FROM public.transactions t
    JOIN public.accounts a ON t.source_account_id = a.id
    WHERE a.user_id = p_user_id
    AND t.amount >= 10000
    AND t.created_at >= NOW() - (p_lookback_days || ' days')::INTERVAL
    HAVING COUNT(*) >= 2

    UNION ALL

    -- Failed transfers
    SELECT
        'Failed Transfers' as pattern_type,
        CASE
            WHEN COUNT(*) >= 5 THEN 'high'
            ELSE 'medium'
        END as severity,
        'Multiple failed transfer attempts detected' as description,
        COUNT(*) as occurrence_count
    FROM public.failed_transactions_log ftl
    JOIN public.accounts a ON ftl.source_account_id = a.id
    WHERE a.user_id = p_user_id
    AND attempted_at >= NOW() - (p_lookback_days || ' days')::INTERVAL
    HAVING COUNT(*) >= 3;
END;
$$;

-- Function to get account access history
CREATE OR REPLACE FUNCTION get_account_access_history(
    p_account_id UUID,
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    access_time TIMESTAMPTZ,
    event_type TEXT,
    ip_address TEXT,
    user_agent TEXT,
    access_status TEXT,
    additional_info JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if user owns the account or is admin/support
    IF NOT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = p_account_id
        AND (
            a.user_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM public.user_roles
                WHERE user_id = auth.uid()
                AND role IN ('admin', 'support')
            )
        )
    ) THEN
        RAISE EXCEPTION 'Unauthorized to view account access history';
    END IF;

    RETURN QUERY
    SELECT
        se.created_at as access_time,
        se.event_type,
        se.ip_address,
        se.user_agent,
        CASE
            WHEN se.event_type LIKE '%failed%' THEN 'Failed'
            ELSE 'Success'
        END as access_status,
        se.metadata as additional_info
    FROM public.security_events se
    WHERE se.metadata->>'account_id' = p_account_id::text
    AND se.created_at BETWEEN p_start_date AND p_end_date
    ORDER BY se.created_at DESC;
END;
$$;