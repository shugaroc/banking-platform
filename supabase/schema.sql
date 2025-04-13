-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create custom types
CREATE TYPE account_type AS ENUM ('checking', 'savings', 'investment');
CREATE TYPE account_status AS ENUM ('active', 'inactive', 'suspended', 'closed');
CREATE TYPE transaction_type AS ENUM ('deposit', 'withdrawal', 'transfer', 'payment');
CREATE TYPE transaction_status AS ENUM ('pending', 'completed', 'failed', 'reversed');
CREATE TYPE kyc_status AS ENUM ('not_started', 'pending', 'approved', 'rejected');
CREATE TYPE notification_type AS ENUM ('transaction', 'security', 'account', 'marketing');
CREATE TYPE currency_code AS ENUM ('USD', 'EUR', 'GBP', 'JPY');

-- Create tables
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    postal_code TEXT,
    country TEXT,
    date_of_birth DATE,
    kyc_status kyc_status DEFAULT 'not_started',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT proper_names CHECK (
        first_name ~ '^[A-Za-z\s\-'']+$' AND
        last_name ~ '^[A-Za-z\s\-'']+$'
    ),
    CONSTRAINT proper_phone CHECK (phone ~ '^\+?[0-9\s\-\(\)]+$')
);

CREATE TABLE public.accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    account_number TEXT UNIQUE NOT NULL,
    account_type account_type NOT NULL,
    currency currency_code NOT NULL DEFAULT 'USD',
    balance DECIMAL(19,4) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    available_balance DECIMAL(19,4) NOT NULL DEFAULT 0 CHECK (available_balance >= 0),
    status account_status NOT NULL DEFAULT 'active',
    opened_at TIMESTAMPTZ DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_account_number CHECK (account_number ~ '^[A-Z0-9]{8,}$')
);

CREATE TABLE public.transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_account_id UUID REFERENCES public.accounts(id),
    destination_account_id UUID REFERENCES public.accounts(id),
    amount DECIMAL(19,4) NOT NULL CHECK (amount > 0),
    currency currency_code NOT NULL,
    type transaction_type NOT NULL,
    status transaction_status NOT NULL DEFAULT 'pending',
    description TEXT,
    reference_number TEXT UNIQUE NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_transfer CHECK (
        (type = 'transfer' AND source_account_id IS NOT NULL AND destination_account_id IS NOT NULL) OR
        (type IN ('deposit', 'withdrawal') AND (source_account_id IS NULL OR destination_account_id IS NULL))
    )
);

CREATE TABLE public.beneficiaries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    account_number TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    bank_code TEXT,
    swift_code TEXT,
    iban TEXT,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_beneficiary_name CHECK (name ~ '^[A-Za-z0-9\s\-'']+$'),
    CONSTRAINT unique_beneficiary UNIQUE (user_id, account_number)
);

CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create recurring transfers table
CREATE TABLE public.recurring_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
    destination_account_id UUID NOT NULL REFERENCES public.accounts(id),
    amount DECIMAL(19,4) NOT NULL CHECK (amount > 0),
    description TEXT,
    frequency INTERVAL NOT NULL,
    next_execution DATE NOT NULL,
    end_date DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_execution_at TIMESTAMPTZ,
    failure_count INTEGER DEFAULT 0,
    metadata JSONB,
    CONSTRAINT valid_schedule CHECK (
        next_execution >= CURRENT_DATE AND
        (end_date IS NULL OR end_date >= next_execution)
    )
);

-- Create failed transactions log table
CREATE TABLE public.failed_transactions_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_type transaction_type NOT NULL,
    source_account_id UUID REFERENCES public.accounts(id),
    destination_account_id UUID REFERENCES public.accounts(id),
    amount DECIMAL(19,4) NOT NULL,
    currency currency_code NOT NULL,
    error_code TEXT,
    error_message TEXT,
    attempted_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB
);

-- Create security events log table
CREATE TABLE public.security_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    description TEXT NOT NULL,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB,
    CHECK (severity IN ('low', 'medium', 'high', 'critical'))
);

-- Create indexes
CREATE INDEX idx_profiles_kyc_status ON public.profiles(kyc_status);
CREATE INDEX idx_accounts_user_id ON public.accounts(user_id);
CREATE INDEX idx_accounts_status ON public.accounts(status);
CREATE INDEX idx_transactions_source_account ON public.transactions(source_account_id);
CREATE INDEX idx_transactions_destination_account ON public.transactions(destination_account_id);
CREATE INDEX idx_transactions_created_at ON public.transactions(created_at);
CREATE INDEX idx_transactions_status ON public.transactions(status);
CREATE INDEX idx_beneficiaries_user_id ON public.beneficiaries(user_id);
CREATE INDEX idx_notifications_user_id_read ON public.notifications(user_id, is_read);
CREATE INDEX idx_recurring_transfers_next_execution ON public.recurring_transfers(next_execution) WHERE is_active = true;
CREATE INDEX idx_recurring_transfers_source_account ON public.recurring_transfers(source_account_id);
CREATE INDEX idx_failed_transactions_source ON public.failed_transactions_log(source_account_id);
CREATE INDEX idx_failed_transactions_destination ON public.failed_transactions_log(destination_account_id);
CREATE INDEX idx_failed_transactions_date ON public.failed_transactions_log(attempted_at);
CREATE INDEX idx_security_events_user ON public.security_events(user_id);
CREATE INDEX idx_security_events_type_severity ON public.security_events(event_type, severity);
CREATE INDEX idx_security_events_date ON public.security_events(created_at);

-- Create audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply audit triggers
CREATE TRIGGER audit_profiles_trigger
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_accounts_trigger
    BEFORE UPDATE ON public.accounts
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_transactions_trigger
    BEFORE UPDATE ON public.transactions
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_beneficiaries_trigger
    BEFORE UPDATE ON public.beneficiaries
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_recurring_transfers_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.recurring_transfers
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

CREATE TRIGGER audit_failed_transactions_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.failed_transactions_log
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

CREATE TRIGGER audit_security_events_changes
    AFTER INSERT OR UPDATE OR DELETE ON public.security_events
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

-- Create RLS policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beneficiaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.failed_transactions_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- Accounts policies
CREATE POLICY "Users can view own accounts"
    ON public.accounts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own accounts"
    ON public.accounts FOR UPDATE
    USING (auth.uid() = user_id);

-- Transactions policies
CREATE POLICY "Users can view own transactions"
    ON public.transactions FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.accounts
            WHERE accounts.id IN (source_account_id, destination_account_id)
            AND accounts.user_id = auth.uid()
        )
    );

-- Beneficiaries policies
CREATE POLICY "Users can view own beneficiaries"
    ON public.beneficiaries FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own beneficiaries"
    ON public.beneficiaries FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own beneficiaries"
    ON public.beneficiaries FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own beneficiaries"
    ON public.beneficiaries FOR DELETE
    USING (auth.uid() = user_id);

-- Notifications policies
CREATE POLICY "Users can view own notifications"
    ON public.notifications FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications"
    ON public.notifications FOR UPDATE
    USING (auth.uid() = user_id);

-- Recurring transfers policies
CREATE POLICY "Users can view own recurring transfers"
    ON public.recurring_transfers FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.accounts
            WHERE id = source_account_id
            AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create recurring transfers"
    ON public.recurring_transfers FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.accounts
            WHERE id = source_account_id
            AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update own recurring transfers"
    ON public.recurring_transfers FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.accounts
            WHERE id = source_account_id
            AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete own recurring transfers"
    ON public.recurring_transfers FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.accounts
            WHERE id = source_account_id
            AND user_id = auth.uid()
        )
    );

-- Function to process money transfers
CREATE OR REPLACE FUNCTION process_transfer(
    p_source_account_id UUID,
    p_destination_account_id UUID,
    p_amount DECIMAL,
    p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_source_currency currency_code;
    v_dest_currency currency_code;
    v_transaction_id UUID;
    v_reference_number TEXT;
BEGIN
    -- Check if user owns the source account
    IF NOT EXISTS (
        SELECT 1 FROM public.accounts 
        WHERE id = p_source_account_id 
        AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Unauthorized to transfer from this account';
    END IF;

    -- Get account currencies
    SELECT currency INTO v_source_currency FROM public.accounts WHERE id = p_source_account_id;
    SELECT currency INTO v_dest_currency FROM public.accounts WHERE id = p_destination_account_id;

    -- Check if currencies match (for simplicity, we're not handling conversion)
    IF v_source_currency != v_dest_currency THEN
        RAISE EXCEPTION 'Currency mismatch between accounts';
    END IF;

    -- Generate reference number
    v_reference_number := 'TRF-' || to_char(NOW(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 8);

    -- Begin transaction
    BEGIN
        -- Check and update source account balance
        UPDATE public.accounts
        SET balance = balance - p_amount,
            available_balance = available_balance - p_amount
        WHERE id = p_source_account_id
        AND balance >= p_amount
        AND available_balance >= p_amount
        AND status = 'active';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient funds or inactive account';
        END IF;

        -- Update destination account balance
        UPDATE public.accounts
        SET balance = balance + p_amount,
            available_balance = available_balance + p_amount
        WHERE id = p_destination_account_id
        AND status = 'active';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid destination account';
        END IF;

        -- Create transaction record
        INSERT INTO public.transactions (
            source_account_id,
            destination_account_id,
            amount,
            currency,
            type,
            status,
            description,
            reference_number
        ) VALUES (
            p_source_account_id,
            p_destination_account_id,
            p_amount,
            v_source_currency,
            'transfer',
            'completed',
            p_description,
            v_reference_number
        ) RETURNING id INTO v_transaction_id;

        -- Create notification for sender
        INSERT INTO public.notifications (
            user_id,
            type,
            title,
            content
        ) VALUES (
            auth.uid(),
            'transaction',
            'Transfer Completed',
            format('Transfer of %s %s has been completed. Ref: %s', 
                v_source_currency, 
                p_amount::text, 
                v_reference_number
            )
        );

        RETURN v_transaction_id;
    END;
END;
$$;

-- Function to process pending recurring transfers
CREATE OR REPLACE FUNCTION process_pending_recurring_transfers()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_processed_count INTEGER := 0;
    v_transfer RECORD;
    v_transaction_id UUID;
BEGIN
    FOR v_transfer IN
        SELECT *
        FROM public.recurring_transfers
        WHERE is_active = true
        AND next_execution <= CURRENT_DATE
        AND (end_date IS NULL OR end_date >= CURRENT_DATE)
        FOR UPDATE SKIP LOCKED
    LOOP
        BEGIN
            -- Attempt to process the transfer
            v_transaction_id := process_transfer(
                v_transfer.source_account_id,
                v_transfer.destination_account_id,
                v_transfer.amount,
                v_transfer.description || ' (Recurring Transfer)'
            );

            -- Update next execution date and last execution timestamp
            UPDATE public.recurring_transfers
            SET next_execution = CURRENT_DATE + frequency,
                last_execution_at = NOW(),
                failure_count = 0
            WHERE id = v_transfer.id;

            v_processed_count := v_processed_count + 1;
        EXCEPTION WHEN OTHERS THEN
            -- Handle failed transfer
            UPDATE public.recurring_transfers
            SET failure_count = failure_count + 1,
                is_active = (failure_count < 3)  -- Deactivate after 3 failures
            WHERE id = v_transfer.id;

            -- Create notification for failed transfer
            INSERT INTO public.notifications (
                user_id,
                type,
                title,
                content,
                metadata
            ) VALUES (
                (SELECT user_id FROM public.accounts WHERE id = v_transfer.source_account_id),
                'transaction',
                'Recurring Transfer Failed',
                format('The recurring transfer of %s to account %s has failed. Reason: %s',
                    v_transfer.amount::text,
                    (SELECT account_number FROM public.accounts WHERE id = v_transfer.destination_account_id),
                    SQLERRM
                ),
                jsonb_build_object(
                    'error', SQLERRM,
                    'recurring_transfer_id', v_transfer.id
                )
            );
        END;
    END LOOP;

    RETURN v_processed_count;
END;
$$;