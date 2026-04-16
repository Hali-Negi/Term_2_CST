-- ==============================================
-- COMP 2714 - Lab 8 (DCL) - Instructor Solution
-- Aligned to Lab 5 schema + Lab 6 seed data
-- ==============================================

SET client_min_messages TO WARNING;

-- 0) Use Lab 5 schema
SET search_path TO lab5, public;

-- ----------------------------------------------
-- 1) Create Roles (idempotent)
-- ----------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_role') THEN
    CREATE ROLE admin_role;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'instructor_role') THEN
    CREATE ROLE instructor_role;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'student_role') THEN
    CREATE ROLE student_role;
  END IF;
END $$;

-- Schema visibility so roles can access objects by name
GRANT USAGE ON SCHEMA lab5 TO admin_role, instructor_role, student_role;

-- ----------------------------------------------
-- 2) Grant Object Privileges (no data changes)
-- ----------------------------------------------

-- Admin: full control on all tables & sequences
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA lab5 TO admin_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA lab5 TO admin_role;

-- Instructor: read key tables + update limited enrollment columns
GRANT SELECT ON
  location, department, professor, term, course, course_offering, student, enrollment
TO instructor_role;

GRANT UPDATE (enr_status, enr_grade, enr_notes) ON enrollment TO instructor_role;

-- Student: read offerings; personal rows via view below
GRANT SELECT ON course_offering TO student_role;

-- Default grants for objects created later by the current owner
ALTER DEFAULT PRIVILEGES IN SCHEMA lab5
  GRANT SELECT ON TABLES TO instructor_role, student_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA lab5
  GRANT ALL ON TABLES TO admin_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA lab5
  GRANT ALL ON SEQUENCES TO admin_role;

-- ----------------------------------------------
-- 3) Create Login Users and Assign Roles (idempotent)
--    Use seeded identities from Lab 6 for realistic testing:
--      Professors: A00123456, A00987654, A00111111
--      Student:    A10000001
--    PostgreSQL folds unquoted identifiers to lowercase -> logins in lowercase.
-- ----------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    EXECUTE 'CREATE USER admin_user PASSWORD ''admin123''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'instructor_user') THEN
    EXECUTE 'CREATE USER instructor_user PASSWORD ''teach123''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'a00123456') THEN
    EXECUTE 'CREATE USER a00123456 PASSWORD ''teach123''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'a00987654') THEN
    EXECUTE 'CREATE USER a00987654 PASSWORD ''teach123''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'a00111111') THEN
    EXECUTE 'CREATE USER a00111111 PASSWORD ''teach123''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'a10000001') THEN
    EXECUTE 'CREATE USER a10000001 PASSWORD ''stud123''';
  END IF;
END $$;

GRANT admin_role      TO admin_user;
GRANT instructor_role TO instructor_user;
GRANT instructor_role TO a00123456;
GRANT instructor_role TO a00987654;
GRANT instructor_role TO a00111111;
GRANT student_role    TO a10000001;

-- ----------------------------------------------
-- 4) Views (drop & recreate) – least-privilege access
-- ----------------------------------------------
DROP VIEW IF EXISTS v_instructor_enrollments CASCADE;
DROP VIEW IF EXISTS v_my_enrollments CASCADE;

-- Instructor sees enrollments only for offerings they teach.
-- Works if the login equals the professor’s BCIT ID (lowercased) OR is 'instructor_user'.
CREATE VIEW v_instructor_enrollments AS
SELECT e.*
FROM enrollment e
JOIN course_offering co ON co.offer_id = e.offer_id
JOIN professor p ON p.prof_bcit_id = co.offer_prof_id
WHERE lower(current_user) IN (lower(p.prof_bcit_id), 'instructor_user');

GRANT SELECT ON v_instructor_enrollments TO instructor_role;

-- Student sees only their own enrollments
CREATE VIEW v_my_enrollments AS
SELECT e.*
FROM enrollment e
WHERE lower(e.stu_bcit_id) = lower(current_user);

GRANT SELECT ON v_my_enrollments TO student_role;

-- ----------------------------------------------
-- 5) Quick Verification (read-only or commented writes)
-- ----------------------------------------------

-- Who am I?
SELECT 'Current user:' AS label, current_user;

-- A) Instructor checks (role switch)
SET ROLE instructor_role;
SELECT (SELECT count(*) FROM course_offering) AS offerings_cnt,
       (SELECT count(*) FROM enrollment)      AS enrollment_cnt;  -- ✅ allowed due to SELECT grants
-- DELETE FROM enrollment;  -- ❌ should fail (no DELETE privilege)
RESET ROLE;

-- Identity-scoped view using generic instructor login
SET SESSION AUTHORIZATION instructor_user;
SELECT count(*) AS rows_visible_to_generic_instructor
FROM v_instructor_enrollments; -- ✅ rows for all offerings taught (whoever matches)
RESET SESSION AUTHORIZATION;

-- Identity-scoped view using a real professor id (seeded)
SET SESSION AUTHORIZATION a00123456;
SELECT count(*) AS rows_visible_to_prof_123456
FROM v_instructor_enrollments; -- ✅ rows for offerings taught by A00123456
RESET SESSION AUTHORIZATION;

-- B) Student checks
SET SESSION AUTHORIZATION a10000001;
SELECT count(*) AS my_rows FROM v_my_enrollments;  -- ✅ only this student's enrollments
-- SELECT * FROM student;                           -- ❌ should fail (no SELECT on base table)
RESET SESSION AUTHORIZATION;

-- (Optional) Revoke test
-- REVOKE UPDATE (enr_status, enr_grade, enr_notes) ON enrollment FROM instructor_role;
-- SET ROLE instructor_role;
-- UPDATE enrollment SET enr_grade='A' WHERE false; -- ❌ should fail after revoke
-- RESET ROLE;

-- End of aligned Lab 8 DCL solution
