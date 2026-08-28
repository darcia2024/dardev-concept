-- ==============================================================================
-- Barber Membership & Loyalty Management System
-- Database Schema for Supabase (PostgreSQL)
-- Compatible for Phase 0 (Opening) to Phase 3 (Full Release)
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. TIER ENUM
DO $$ BEGIN
    CREATE TYPE member_tier AS ENUM ('Silver', 'Gold', 'Platinum', 'Infinite', 'Black');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. PAYMENT METHOD ENUM
DO $$ BEGIN
    CREATE TYPE payment_method_type AS ENUM ('Tunai', 'QRIS', 'EDC', 'Transfer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 4. MEMBERS TABLE
CREATE TABLE IF NOT EXISTS members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    phone_wa VARCHAR(30) UNIQUE NOT NULL,
    tier member_tier DEFAULT 'Silver' NOT NULL,
    points_balance INT DEFAULT 0 NOT NULL,
    total_spend NUMERIC(12, 2) DEFAULT 0.00 NOT NULL,
    visit_count INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. SERVICES (MASTER DATA LAYANAN)
CREATE TABLE IF NOT EXISTS services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    category VARCHAR(50) DEFAULT 'Haircut' NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    duration_minutes INT DEFAULT 30 NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. CAPSTERS (MASTER DATA STAF / CAPSTER)
CREATE TABLE IF NOT EXISTS capsters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(30),
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 7. TRANSACTIONS (TRANSAKSI POS KASIR)
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_no VARCHAR(50) UNIQUE NOT NULL,
    member_id UUID REFERENCES members(id) ON DELETE SET NULL,
    member_name VARCHAR(150),
    member_phone VARCHAR(30),
    capster_id UUID REFERENCES capsters(id) ON DELETE SET NULL,
    capster_name VARCHAR(150),
    service_id UUID REFERENCES services(id) ON DELETE SET NULL,
    service_name VARCHAR(150),
    subtotal NUMERIC(12, 2) NOT NULL,
    discount_points NUMERIC(12, 2) DEFAULT 0.00 NOT NULL,
    final_amount NUMERIC(12, 2) NOT NULL,
    payment_method payment_method_type NOT NULL,
    payment_ref VARCHAR(100), -- approval code EDC / no ref QRIS
    cash_paid NUMERIC(12, 2) DEFAULT 0.00,
    cash_change NUMERIC(12, 2) DEFAULT 0.00,
    points_earned INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 8. POINT MUTATION LEDGER (FASE 1 LOYALTY ENGINE)
CREATE TABLE IF NOT EXISTS point_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID REFERENCES members(id) ON DELETE CASCADE NOT NULL,
    transaction_id UUID REFERENCES transactions(id) ON DELETE SET NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('EARN', 'REDEEM', 'ADJUSTMENT', 'BONUS')),
    points_amount INT NOT NULL,
    balance_after INT NOT NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 9. PRODUCTS & HPP CALCULATOR (FASE 3)
CREATE TABLE IF NOT EXISTS products_hpp (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    category VARCHAR(50) DEFAULT 'Retail',
    buy_price NUMERIC(12, 2) NOT NULL,
    shipping_per_unit NUMERIC(12, 2) DEFAULT 0.00,
    packaging_cost NUMERIC(12, 2) DEFAULT 0.00,
    overhead_cost NUMERIC(12, 2) DEFAULT 0.00,
    sell_price NUMERIC(12, 2) NOT NULL,
    target_margin_percent NUMERIC(5, 2) DEFAULT 40.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 10. EMPLOYEE ATTENDANCE & LEAVE (FASE 3)
CREATE TABLE IF NOT EXISTS attendances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    capster_id UUID REFERENCES capsters(id) ON DELETE CASCADE NOT NULL,
    check_in_time TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    check_out_time TIMESTAMP WITH TIME ZONE,
    selfie_url TEXT,
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    is_valid_location BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- SEED INITIAL MASTER DATA FOR PHASE 0
INSERT INTO services (name, category, price, duration_minutes) VALUES
('Gentleman Haircut (Wash + Hot Towel + Styling)', 'Haircut', 50000.00, 45),
('Express Haircut', 'Haircut', 35000.00, 30),
('Hair Wash, Massage & Tonic Styling', 'Treatment', 25000.00, 20),
('Beard Trim & Hot Towel Shave', 'Grooming', 35000.00, 25),
('Kids Haircut (Under 12)', 'Haircut', 40000.00, 30),
('Complete VIP Grooming Package', 'Package', 90000.00, 60);

INSERT INTO capsters (name, phone) VALUES
('Alex Master Barber', '081298765431'),
('Reza Senior Stylist', '081298765432'),
('Dimas Barber', '081298765433');
