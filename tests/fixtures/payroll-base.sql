-- Fixture PostgreSQL terisolasi. Tidak menyambung atau mengubah Supabase produksi.
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id UUID PRIMARY KEY, email TEXT);
CREATE TABLE profiles(id UUID PRIMARY KEY REFERENCES auth.users(id), role TEXT);
CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::UUID
$$;
CREATE FUNCTION is_owner() RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role='owner')
$$;
CREATE FUNCTION jakarta_today() RETURNS DATE LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('test.today',true),'')::DATE,(now() AT TIME ZONE 'Asia/Jakarta')::DATE)
$$;
CREATE FUNCTION normalkan_nomor_wa(p TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$ SELECT p $$;
CREATE TABLE capsters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name VARCHAR(150) NOT NULL, phone VARCHAR(30),
  jabatan VARCHAR(40) DEFAULT 'Kapster', ikut_pos BOOLEAN DEFAULT TRUE, is_active BOOLEAN DEFAULT TRUE,
  auth_user_id UUID REFERENCES auth.users(id), jam_masuk TIME, jam_pulang TIME, foto_path TEXT,
  created_at TIMESTAMPTZ DEFAULT '2026-01-01T00:00:00+07:00'
);
CREATE TYPE attend_status AS ENUM ('hadir','terlambat');
CREATE TABLE attendances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),capster_id UUID REFERENCES capsters(id),business_date DATE,
  status attend_status DEFAULT 'hadir',check_in_time TIMESTAMPTZ DEFAULT now(),check_out_time TIMESTAMPTZ,
  terlambat_menit INT DEFAULT 0, menit_kerja INT DEFAULT 0, UNIQUE(capster_id,business_date)
);
CREATE TABLE jam_operasional (dow SMALLINT PRIMARY KEY,libur BOOLEAN DEFAULT FALSE);
INSERT INTO jam_operasional(dow) SELECT generate_series(0,6);
CREATE TABLE leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),capster_id UUID REFERENCES capsters(id),
  kind TEXT DEFAULT 'Izin',tanggal_mulai DATE,tanggal_selesai DATE,status TEXT,alasan TEXT
);
CREATE TABLE transactions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),business_date DATE);
CREATE TABLE transaction_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),transaction_id UUID REFERENCES transactions(id),
  capster_id UUID REFERENCES capsters(id),service_name VARCHAR(150),qty INT DEFAULT 1
);
GRANT USAGE ON SCHEMA public,auth TO authenticated,anon;
GRANT SELECT ON capsters TO authenticated;
