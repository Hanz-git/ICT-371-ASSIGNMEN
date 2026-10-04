/* 
   ICT371 - POSTGRESQL
   SCENARIO 2: COMPUTER LABORATORY RESERVATIONS

*/


/* 
   1. CREATE TABLES */

DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;


/*
   LAB SESSIONS TABLE
 */

CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,

    session_name VARCHAR(150) NOT NULL,

    available_workstations INTEGER NOT NULL
        CHECK (available_workstations >= 0)
);


/* 
   RESERVATIONS TABLE
 */

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,

    session_id INTEGER NOT NULL,

    lecturer VARCHAR(120) NOT NULL,

    number_of_workstations INTEGER NOT NULL
        CHECK (number_of_workstations > 0),

    reservation_status VARCHAR(20) NOT NULL
        DEFAULT 'ACTIVE'
        CHECK (
            reservation_status IN ('ACTIVE', 'CANCELLED')
        ),

    reservation_date TIMESTAMP
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_session
        FOREIGN KEY (session_id)
        REFERENCES lab_sessions(session_id)
);


/* 
   INSERT THREE LABORATORY SESSIONS
    */



INSERT INTO lab_sessions
(
    session_name,
    available_workstations
)
VALUES
(
    'Database Practical',
    30
),
(
    'Computer Networks Practical',
    8
),
(
    'Programming Practical',
    2
);


/* Display sessions */

SELECT
    session_id,
    session_name,
    available_workstations
FROM lab_sessions
ORDER BY session_id;


/*
   2. IF / ELSIF / ELSE

   FULL
   NEARLY FULL
   HAS ENOUGH WORKSTATIONS
 */

DO $$
DECLARE
    v_session RECORD;
BEGIN

    FOR v_session IN
        SELECT
            session_id,
            session_name,
            available_workstations
        FROM lab_sessions
        ORDER BY session_id
    LOOP

        IF v_session.available_workstations = 0 THEN

            RAISE NOTICE
                'Session: % -> FULL',
                v_session.session_name;

        ELSIF v_session.available_workstations <= 3 THEN

            RAISE NOTICE
                'Session: % -> NEARLY FULL (% workstations remaining)',
                v_session.session_name,
                v_session.available_workstations;

        ELSE

            RAISE NOTICE
                'Session: % -> HAS ENOUGH WORKSTATIONS (% remaining)',
                v_session.session_name,
                v_session.available_workstations;

        END IF;

    END LOOP;

END
$$;


/* 
   3. WHILE LOOP
   Three session preparation reminders

   NUMERIC FOR LOOP
   Three workstation checks
*/

DO $$
DECLARE
    v_counter INTEGER := 1;
BEGIN

    /* WHILE LOOP */

    WHILE v_counter <= 3 LOOP

        RAISE NOTICE
            'Session Preparation Reminder Number: %',
            v_counter;

        v_counter := v_counter + 1;

    END LOOP;


    /* NUMERIC FOR LOOP */

    FOR v_check IN 1..3 LOOP

        RAISE NOTICE
            'Workstation Check Number: %',
            v_check;

    END LOOP;

END
$$;


/* 
   4. CREATE reserve_workstations PROCEDURE
   */

CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INTEGER,
    p_lecturer VARCHAR,
    p_number_of_workstations INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available_workstations INTEGER;
BEGIN

    /* 
       Validate requested number
       */

    IF p_number_of_workstations IS NULL
       OR p_number_of_workstations <= 0 THEN

        RAISE EXCEPTION
            'INVALID QUANTITY: Number of workstations must be greater than zero';

    END IF;


    /* 
       Find and lock the laboratory session
        */

    SELECT
        available_workstations
    INTO
        v_available_workstations
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;


    /* 
       Check whether session exists
     */

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'SESSION NOT FOUND: Session ID % does not exist',
            p_session_id;

    END IF;


    /* 
       Check capacity
     */

    IF p_number_of_workstations > v_available_workstations THEN

        RAISE EXCEPTION
            'CAPACITY EXCEEDED: Requested %, but only % workstations are available',
            p_number_of_workstations,
            v_available_workstations;

    END IF;


    /* 
       Reduce available workstations
     */

    UPDATE lab_sessions
    SET available_workstations =
        available_workstations - p_number_of_workstations
    WHERE session_id = p_session_id;


    /* 
       Record reservation
        */

    INSERT INTO reservations
    (
        session_id,
        lecturer,
        number_of_workstations,
        reservation_status
    )
    VALUES
    (
        p_session_id,
        TRIM(p_lecturer),
        p_number_of_workstations,
        'ACTIVE'
    );


    RAISE NOTICE
        'Reservation successfully recorded for lecturer: %',
        p_lecturer;

END
$$;


/* 
   5. TEST reserve_workstations
 */


/* 
   VALID RESERVATION 1

   Database Practical:
   30 - 10 = 20
 */

CALL reserve_workstations(
    1,
    'Dr. Banda',
    10
);


/* 
   VALID RESERVATION 2

   Computer Networks:
   8 - 3 = 5
   */

CALL reserve_workstations(
    2,
    'Mr. Phiri',
    3
);


/* 
   INVALID RESERVATION

   Programming Practical has only 2.
   Requesting 5 must fail.
 */

DO $$
BEGIN

    BEGIN

        CALL reserve_workstations(
            3,
            'Dr. Mwansa',
            5
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'EXPECTED RESERVATION ERROR: %',
                SQLERRM;

    END;

END
$$;

/*-
   Display sessions
   */

SELECT
    session_id,
    session_name,
    available_workstations
FROM lab_sessions
ORDER BY session_id;



   
SELECT
    reservation_id,
    session_id,
    lecturer,
    number_of_workstations,
    reservation_status,
    reservation_date
FROM reservations
ORDER BY reservation_id;


/* 
   6. CREATE cancel_reservation PROCEDURE
   */

CREATE OR REPLACE PROCEDURE cancel_reservation(
    p_reservation_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INTEGER;
    v_number_of_workstations INTEGER;
    v_status VARCHAR(20);
BEGIN

    /* 
       Find and lock reservation
        */

    SELECT
        session_id,
        number_of_workstations,
        reservation_status
    INTO
        v_session_id,
        v_number_of_workstations,
        v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;


    /* 
       Check reservation exists
        */

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'RESERVATION NOT FOUND: Reservation ID % does not exist',
            p_reservation_id;

    END IF;


    /* 
       Prevent double cancellation
      */

    IF v_status = 'CANCELLED' THEN

        RAISE NOTICE
            'Reservation % is already cancelled.',
            p_reservation_id;

        RAISE NOTICE
            'Workstations will NOT be released again.';

        RETURN;

    END IF;


    /* 
       Release workstations
        */

    UPDATE lab_sessions
    SET available_workstations =
        available_workstations + v_number_of_workstations
    WHERE session_id = v_session_id;


    /* 
       Mark reservation as cancelled
       */

    UPDATE reservations
    SET reservation_status = 'CANCELLED'
    WHERE reservation_id = p_reservation_id;


    RAISE NOTICE
        'Reservation % successfully cancelled.',
        p_reservation_id;

END
$$;


/* 
   CALL cancel_reservation TWICE
   */


/* First cancellation */

CALL cancel_reservation(1);


/* Second cancellation
   Workstations must NOT be released again.
*/

CALL cancel_reservation(1);


/* 
   CHECK AFTER CANCELLATION
    */

SELECT
    session_id,
    session_name,
    available_workstations
FROM lab_sessions
ORDER BY session_id;


SELECT
    reservation_id,
    session_id,
    lecturer,
    number_of_workstations,
    reservation_status
FROM reservations
ORDER BY reservation_id;


/*
   Display sessions with few workstations remaining

   FEW = 3 OR FEWER
   */

DO $$
DECLARE

    session_cursor CURSOR FOR
        SELECT
            session_id,
            session_name,
            available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 3
        ORDER BY session_id;

    v_session RECORD;

BEGIN

    /* Open cursor */

    OPEN session_cursor;


    /* Read records one by one */

    LOOP

        FETCH session_cursor
        INTO v_session;

        EXIT WHEN NOT FOUND;


        RAISE NOTICE
            'FEW WORKSTATIONS -> Session ID: %, Session: %, Available: %',
            v_session.session_id,
            v_session.session_name,
            v_session.available_workstations;

    END LOOP;


    /* Close cursor */

    CLOSE session_cursor;

END
$$;


/* 
   8. REQUEST ZERO WORKSTATIONS
   Handle invalid quantity with EXCEPTION
 */

DO $$
BEGIN

    BEGIN

        CALL reserve_workstations(
            1,
            'Dr. Invalid',
            0
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'INVALID QUANTITY HANDLED: %',
                SQLERRM;

    END;

END
$$;


/* 
   9. FINAL RESULTS
    */


/* 
   FINAL LAB SESSION AVAILABILITY
   */

SELECT
    session_id,
    session_name,
    available_workstations
FROM lab_sessions
ORDER BY session_id;


/* 
   FINAL RESERVATION STATUS
   */

SELECT
    r.reservation_id,
    l.session_name,
    r.lecturer,
    r.number_of_workstations,
    r.reservation_status,
    r.reservation_date
FROM reservations AS r
INNER JOIN lab_sessions AS l
    ON r.session_id = l.session_id
ORDER BY r.reservation_id;