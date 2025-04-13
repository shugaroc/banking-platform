-- Seed data for development and testing

-- Function to create a test user profile
CREATE OR REPLACE FUNCTION create_test_user(
    p_user_id UUID,
    p_first_name TEXT,
    p_last_name TEXT,
    p_kyc_status kyc_status DEFAULT 'approved'
)
RETURNS UUID AS $$
BEGIN
    INSERT INTO public.profiles (
        id,
        first_name,
        last_name,
        phone,
        address,
        city,
        state,
        postal_code,
        country,
        kyc_status
    ) VALUES (
        p_user_id,
        p_first_name,
        p_last_name,
        '+1234567890',
        '123 Test Street',
        'Test City',
        'Test State',
        '12345',
        'United States',
        p_kyc_status
    );
    
    RETURN p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to create a test account
CREATE OR REPLACE FUNCTION create_test_account(
    p_user_id UUID,
    p_account_type account_type,
    p_initial_balance DECIMAL DEFAULT 1000.00
)
RETURNS UUID AS $$
DECLARE
    v_account_id UUID;
    v_account_number TEXT;
BEGIN
    -- Generate unique account number
    v_account_number := UPPER(
        substring(md5(random()::text) from 1 for 4) || 
        to_char(NOW(), 'MMYY') ||
        substring(md5(random()::text) from 1 for 4)
    );
    
    INSERT INTO public.accounts (
        user_id,
        account_number,
        account_type,
        balance,
        available_balance
    ) VALUES (
        p_user_id,
        v_account_number,
        p_account_type,
        p_initial_balance,
        p_initial_balance
    ) RETURNING id INTO v_account_id;
    
    RETURN v_account_id;
END;
$$ LANGUAGE plpgsql;

-- Create test data function
CREATE OR REPLACE FUNCTION create_test_data()
RETURNS void AS $$
DECLARE
    v_user1_id UUID := '11111111-1111-1111-1111-111111111111'::UUID;
    v_user2_id UUID := '22222222-2222-2222-2222-222222222222'::UUID;
    v_account1_id UUID;
    v_account2_id UUID;
    v_account3_id UUID;
BEGIN
    -- Create test users
    PERFORM create_test_user(v_user1_id, 'John', 'Doe');
    PERFORM create_test_user(v_user2_id, 'Jane', 'Smith');
    
    -- Create test accounts
    v_account1_id := create_test_account(v_user1_id, 'checking', 5000.00);
    v_account2_id := create_test_account(v_user1_id, 'savings', 10000.00);
    v_account3_id := create_test_account(v_user2_id, 'checking', 3000.00);
    
    -- Create some test transactions
    INSERT INTO public.transactions (
        source_account_id,
        destination_account_id,
        amount,
        currency,
        type,
        status,
        description,
        reference_number
    ) VALUES
    (
        v_account1_id,
        v_account3_id,
        500.00,
        'USD',
        'transfer',
        'completed',
        'Test transfer',
        'TEST-' || to_char(NOW(), 'YYYYMMDD') || '-001'
    ),
    (
        NULL,
        v_account2_id,
        1000.00,
        'USD',
        'deposit',
        'completed',
        'Test deposit',
        'TEST-' || to_char(NOW(), 'YYYYMMDD') || '-002'
    );
    
    -- Create test beneficiaries
    INSERT INTO public.beneficiaries (
        user_id,
        name,
        account_number,
        bank_name,
        bank_code,
        swift_code
    ) VALUES
    (
        v_user1_id,
        'Alice Johnson',
        'BENE000123',
        'Test Bank',
        'TESTBANK01',
        'TESTSWIFT'
    );
    
    -- Create test notifications
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content
    ) VALUES
    (
        v_user1_id,
        'transaction',
        'Welcome to Banking Platform',
        'Thank you for joining our platform!'
    ),
    (
        v_user2_id,
        'security',
        'Security Alert',
        'New device logged into your account'
    );
END;
$$ LANGUAGE plpgsql;

-- Function to reset test data
CREATE OR REPLACE FUNCTION reset_test_data()
RETURNS void AS $$
BEGIN
    -- Clean up existing test data
    DELETE FROM public.notifications;
    DELETE FROM public.transactions;
    DELETE FROM public.beneficiaries;
    DELETE FROM public.accounts;
    DELETE FROM public.profiles;
    
    -- Create fresh test data
    PERFORM create_test_data();
END;
$$ LANGUAGE plpgsql;