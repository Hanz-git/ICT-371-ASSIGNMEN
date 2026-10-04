/* 
   SCENARIO 3: STUDENT HOSTEL ROOM ALLOCATION*/


/* CREATE TABLES*/

DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;


/* HOSTEL ROOMS TABLE*/

CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,

    room_number VARCHAR(20) NOT NULL UNIQUE,

    available_bed_spaces INTEGER NOT NULL
        CHECK (available_bed_spaces >= 0)
);


/* ALLOCATIONS TABLE*/

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,

    student_number VARCHAR(20) NOT NULL,

    room_id INTEGER NOT NULL,

    allocation_status VARCHAR(20) NOT NULL
        DEFAULT 'ALLOCATED'
        CHECK (
            allocation_status IN ('ALLOCATED', 'COMPLETED')
        ),

    allocation_date TIMESTAMP
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_room
        FOREIGN KEY (room_id)
        REFERENCES hostel_rooms(room_id)
);


/* INSERT AT LEAST THREE ROOMS*/

INSERT INTO hostel_rooms
(
    room_number,
    available_bed_spaces
)
VALUES
(
    'A101',
    4
),
(
    'A102',
    1
),
(
    'A103',
    0
);


/* Display rooms */

SELECT
    room_id,
    room_number,
    available_bed_spaces
FROM hostel_rooms
ORDER BY room_id;


/* 
   2. IF / ELSIF / ELSE

   Report whether a room:
   - is FULL
   - has ONE SPACE LEFT
   - has SEVERAL SPACES
*/

DO $$
DECLARE
    v_room RECORD;
BEGIN

    FOR v_room IN
        SELECT
            room_id,
            room_number,
            available_bed_spaces
        FROM hostel_rooms
        ORDER BY room_id
    LOOP

        IF v_room.available_bed_spaces = 0 THEN

            RAISE NOTICE
                'Room % -> FULL',
                v_room.room_number;

        ELSIF v_room.available_bed_spaces = 1 THEN

            RAISE NOTICE
                'Room % -> ONE SPACE LEFT',
                v_room.room_number;

        ELSE

            RAISE NOTICE
                'Room % -> SEVERAL SPACES (% available)',
                v_room.room_number,
                v_room.available_bed_spaces;

        END IF;

    END LOOP;

END
$$;


/* 
   3. WHILE LOOP
   Show three hostel inspection days

   NUMERIC FOR LOOP
   Number three room checks
*/

DO $$
DECLARE
    v_counter INTEGER := 1;
BEGIN

    /* WHILE LOOP */

    WHILE v_counter <= 3 LOOP

        RAISE NOTICE
            'Hostel Inspection Day: %',
            v_counter;

        v_counter := v_counter + 1;

    END LOOP;


    /* NUMERIC FOR LOOP*/

    FOR v_check IN 1..3 LOOP

        RAISE NOTICE
            'Room Check Number: %',
            v_check;

    END LOOP;

END
$$;


/* CREATE allocate_room PROCEDURE*/

CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available_spaces INTEGER;
    v_student_number VARCHAR(20);
BEGIN

    /* Remove spaces around student number*/

    v_student_number :=
        TRIM(COALESCE(p_student_number, ''));


    /* Check for blank student number*/

    IF v_student_number = '' THEN

        RAISE EXCEPTION
            'INVALID STUDENT NUMBER: Student number cannot be blank';

    END IF;


    /* Find and lock the room*/

    SELECT
        available_bed_spaces
    INTO
        v_available_spaces
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;


    /* Check whether room exists*/

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'ROOM NOT FOUND: Room ID % does not exist',
            p_room_id;

    END IF;


    /* Check whether room has space*/

    IF v_available_spaces <= 0 THEN

        RAISE EXCEPTION
            'ROOM FULL: Room ID % has no available bed spaces',
            p_room_id;

    END IF;


    /* Reduce available spaces by ON*/

    UPDATE hostel_rooms
    SET available_bed_spaces =
        available_bed_spaces - 1
    WHERE room_id = p_room_id;


    /* Record student allocation*/

    INSERT INTO allocations
    (
        student_number,
        room_id,
        allocation_status
    )
    VALUES
    (
        v_student_number,
        p_room_id,
        'ALLOCATED'
    );


    RAISE NOTICE
        'Student % successfully allocated to room ID %.',
        v_student_number,
        p_room_id;

END
$$;


/* 
   5. TEST allocate_room
*/


/* 
   VALID ALLOCATION 1
 */

CALL allocate_room(
    '202600001',
    1
);


/*
   VALID ALLOCATION 2

   A102:
   1 - 1 = 0
  */

CALL allocate_room(
    '202600002',
    2
);


/* INVALID ALLOCATION

   A103 has 0 available spaces.
   This request must fail.*/

DO $$
BEGIN

    BEGIN

        CALL allocate_room(
            '202600003',
            3
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'EXPECTED ALLOCATION ERROR: %',
                SQLERRM;

    END;

END
$$;


/* Check rooms after allocation*/

SELECT
    room_id,
    room_number,
    available_bed_spaces
FROM hostel_rooms
ORDER BY room_id;


/* Check allocations */

SELECT
    allocation_id,
    student_number,
    room_id,
    allocation_status,
    allocation_date
FROM allocations
ORDER BY allocation_id;


/* CREATE check_out PROCEDURE*/

CREATE OR REPLACE PROCEDURE check_out(
    p_allocation_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INTEGER;
    v_status VARCHAR(20);
BEGIN

    /* Find and lock allocation*/

    SELECT
        room_id,
        allocation_status
    INTO
        v_room_id,
        v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;


    /*Check whether allocation exists*/

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'ALLOCATION NOT FOUND: Allocation ID % does not exist',
            p_allocation_id;

    END IF;


    /*Prevent double checkout*/

    IF v_status = 'COMPLETED' THEN

        RAISE NOTICE
            'Allocation % is already completed.',
            p_allocation_id;

        RAISE NOTICE
            'No additional bed space will be released.';

        RETURN;

    END IF;


    /* Release one bed space*/

    UPDATE hostel_rooms
    SET available_bed_spaces =
        available_bed_spaces + 1
    WHERE room_id = v_room_id;


    /* Mark allocation as completed*/

    UPDATE allocations
    SET allocation_status = 'COMPLETED'
    WHERE allocation_id = p_allocation_id;


    RAISE NOTICE
        'Allocation % successfully checked out.',
        p_allocation_id;

END
$$;


/*CALL check_out TWICE FOR SAME ALLOCATION */


/* First checkout */

CALL check_out(1);


/* Second checkout
   This must NOT release another bed space.
*/

CALL check_out(1);


/* Check rooms */

SELECT
    room_id,
    room_number,
    available_bed_spaces
FROM hostel_rooms
ORDER BY room_id;


/* Check allocations */

SELECT
    allocation_id,
    student_number,
    room_id,
    allocation_status
FROM allocations
ORDER BY allocation_id;

/*
   7. EXPLICIT CURSOR

   Display full or nearly full rooms.

   0 = FULL
   1 = NEARLY FULL
   */

DO $$
DECLARE

    room_cursor CURSOR FOR
        SELECT
            room_id,
            room_number,
            available_bed_spaces
        FROM hostel_rooms
        WHERE available_bed_spaces <= 1
        ORDER BY room_id;

    v_room RECORD;

BEGIN

    /* Open cursor */

    OPEN room_cursor;


    /* Fetch rooms one by one */

    LOOP

        FETCH room_cursor
        INTO v_room;

        EXIT WHEN NOT FOUND;


        RAISE NOTICE
            'FULL/NEARLY FULL -> Room: %, Available Spaces: %',
            v_room.room_number,
            v_room.available_bed_spaces;

    END LOOP;


    /* Close cursor */

    CLOSE room_cursor;

END
$$;


/*BLANK STUDENT NUMBER
   Handle invalid input using EXCEPTION */

DO $$
BEGIN

    BEGIN

        CALL allocate_room(
            '   ',
            1
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'BLANK STUDENT NUMBER HANDLED: %',
                SQLERRM;

    END;

END
$$;


/*FINAL RESULTS */


/*FINAL HOSTEL ROOM AVAILABILITY */

SELECT
    room_id,
    room_number,
    available_bed_spaces
FROM hostel_rooms
ORDER BY room_id;


/*FINAL ALLOCATION STATUS */

SELECT
    a.allocation_id,
    a.student_number,
    r.room_number,
    a.allocation_status,
    a.allocation_date
FROM allocations AS a
INNER JOIN hostel_rooms AS r
    ON a.room_id = r.room_id
ORDER BY a.allocation_id;