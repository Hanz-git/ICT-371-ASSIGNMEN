/* 
   ICT371 POSTGRESQL
   SCENARIO 4: CAMPUS CLINIC MEDICINE DISPENSING

   COMPLETE SOLUTION

   Requirements covered:
   1. medicines and dispensing_records tables
   2. IF / ELSIF / ELSE
   3. WHILE and numeric FOR
   4. dispense_medicine procedure
   5. Two valid quantities + one exceeding stock
   6. reverse_dispensing procedure called twice
   7. Explicit cursor
   8. EXCEPTION for negative quantity
   9. Final queries
    */


/* 
   CREATE TABLES
   */

DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;


/* 
   Create medicines table
    */

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,

    medicine_name VARCHAR(150) NOT NULL,

    stock_quantity INTEGER NOT NULL
        CHECK (stock_quantity >= 0)
);


/*
   Create dispensing_records table
    */

CREATE TABLE dispensing_records (
    dispensing_id SERIAL PRIMARY KEY,

    student_number VARCHAR(20) NOT NULL,

    medicine_id INTEGER NOT NULL,

    quantity INTEGER NOT NULL
        CHECK (quantity > 0),

    dispensing_status VARCHAR(20) NOT NULL
        DEFAULT 'DISPENSED'
        CHECK (
            dispensing_status IN ('DISPENSED', 'REVERSED')
        ),

    dispensing_date TIMESTAMP
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_medicine
        FOREIGN KEY (medicine_id)
        REFERENCES medicines(medicine_id)
);


/* 
   Add at least THREE medicines
   */

INSERT INTO medicines
    (medicine_name, stock_quantity)
VALUES
    ('Paracetamol', 20),
    ('Amoxicillin', 5),
    ('Vitamin C', 2);


/* 
   Display medicines
    */

SELECT
    medicine_id,
    medicine_name,
    stock_quantity
FROM medicines
ORDER BY medicine_id;


/* 
   2. IF / ELSIF / ELSE

   Report whether medicine is:
   - OUT OF STOCK
   - LOW ON STOCK
   - SUFFICIENTLY STOCKED*/

DO $$
DECLARE
    v_medicine RECORD;
BEGIN

    FOR v_medicine IN
        SELECT
            medicine_id,
            medicine_name,
            stock_quantity
        FROM medicines
        ORDER BY medicine_id
    LOOP

        IF v_medicine.stock_quantity = 0 THEN

            RAISE NOTICE
                'Medicine: % -> OUT OF STOCK',
                v_medicine.medicine_name;


        ELSIF v_medicine.stock_quantity <= 3 THEN

            RAISE NOTICE
                'Medicine: % -> LOW ON STOCK (% remaining)',
                v_medicine.medicine_name,
                v_medicine.stock_quantity;


        ELSE

            RAISE NOTICE
                'Medicine: % -> SUFFICIENTLY STOCKED (% remaining)',
                v_medicine.medicine_name,
                v_medicine.stock_quantity;

        END IF;

    END LOOP;

END $$;


/* 
   3. WHILE
   Show three stock review days.

   NUMERIC FOR
   Number three shelf inspections.
    */

DO $$
DECLARE
    v_counter INTEGER := 1;
BEGIN

    /* 
       WHILE LOOP
        */

    WHILE v_counter <= 3 LOOP

        RAISE NOTICE
            'Stock Review Day: %',
            v_counter;

        v_counter := v_counter + 1;

    END LOOP;


    /* 
       NUMERIC FOR LOOP
       */

    FOR v_shelf IN 1..3 LOOP

        RAISE NOTICE
            'Shelf Inspection Number: %',
            v_shelf;

    END LOOP;

END $$;


/* 
   4. CREATE dispense_medicine PROCEDURE

   The procedure:
   - checks the quantity
   - checks whether medicine exists
   - checks available stock
   - reduces stock
   - records dispensing
   */

CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_student_number VARCHAR,
    p_medicine_id INTEGER,
    p_quantity INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock_quantity INTEGER;
BEGIN

    /* 
       Check quantity
       */

    IF p_quantity IS NULL OR p_quantity <= 0 THEN

        RAISE EXCEPTION
            'INVALID QUANTITY: Dispensing quantity must be greater than zero';

    END IF;


    /* 
       Get current stock and lock the medicine row
        */

    SELECT stock_quantity
    INTO v_stock_quantity
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;


    /* 
       Check whether medicine exists
        */

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'MEDICINE NOT FOUND: Medicine ID % does not exist',
            p_medicine_id;

    END IF;


    /* 
       Check whether enough medicine is available
       */
    IF p_quantity > v_stock_quantity THEN

        RAISE EXCEPTION
            'INSUFFICIENT STOCK: Requested %, but only % available',
            p_quantity,
            v_stock_quantity;

    END IF;


    /* 
       Reduce medicine stock
       */

    UPDATE medicines
    SET stock_quantity =
        stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;


    /* 
       Record dispensing action
        */

    INSERT INTO dispensing_records
    (
        student_number,
        medicine_id,
        quantity,
        dispensing_status
    )
    VALUES
    (
        TRIM(p_student_number),
        p_medicine_id,
        p_quantity,
        'DISPENSED'
    );


    RAISE NOTICE
        'Medicine successfully dispensed to student %.',
        p_student_number;

END;
$$;


/* 
   5. CALL dispense_medicine

   TWO VALID QUANTITIES
   ONE QUANTITY EXCEEDING STOCK
   */


/* 
   VALID DISPENSING 1

   Paracetamol has 20.
   Dispense 5.
   Remaining = 15.
   */

CALL dispense_medicine(
    '202600001',
    1,
    5
);


/* 
   VALID DISPENSING 2

   Amoxicillin has 5.
   Dispense 2.
   Remaining = 3.
   */

CALL dispense_medicine(
    '202600002',
    2,
    2
);


/* 
   INVALID DISPENSING

   Amoxicillin has only 3 remaining.
   Requesting 10 must fail.
    */

DO $$
BEGIN

    BEGIN

        CALL dispense_medicine(
            '202600003',
            2,
            10
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'Expected dispensing error: %',
                SQLERRM;

    END;

END $$;


/* 
   Query medicines
    */

SELECT
    medicine_id,
    medicine_name,
    stock_quantity
FROM medicines
ORDER BY medicine_id;


/* 
   Query dispensing records
   */

SELECT
    dispensing_id,
    student_number,
    medicine_id,
    quantity,
    dispensing_status,
    dispensing_date
FROM dispensing_records
ORDER BY dispensing_id;


/*
   6. CREATE reverse_dispensing PROCEDURE

   The procedure:
   - finds the dispensing record
   - checks its status
   - restores the stock
   - marks the record REVERSED
   - prevents restoring stock twice
   */

CREATE OR REPLACE PROCEDURE reverse_dispensing(
    p_dispensing_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INTEGER;
    v_quantity INTEGER;
    v_status VARCHAR(20);
BEGIN

    /* 
       Find and lock the dispensing record
        */

    SELECT
        medicine_id,
        quantity,
        dispensing_status
    INTO
        v_medicine_id,
        v_quantity,
        v_status
    FROM dispensing_records
    WHERE dispensing_id = p_dispensing_id
    FOR UPDATE;



    IF NOT FOUND THEN

        RAISE EXCEPTION
            'DISPENSING RECORD NOT FOUND: ID % does not exist',
            p_dispensing_id;

    END IF;


    /* 
       Prevent reversing the same record twice
       */

    IF v_status = 'REVERSED' THEN

        RAISE NOTICE
            'Dispensing record % is already reversed.',
            p_dispensing_id;

        RAISE NOTICE
            'Stock will NOT be restored again.';

        RETURN;

    END IF;


    /* 
       Restore the medicine stock
        */

    UPDATE medicines
    SET stock_quantity =
        stock_quantity + v_quantity
    WHERE medicine_id = v_medicine_id;


    /* -
       Mark dispensing record as reversed
        */

    UPDATE dispensing_records
    SET dispensing_status = 'REVERSED'
    WHERE dispensing_id = p_dispensing_id;


    RAISE NOTICE
        'Dispensing record % successfully reversed.',
        p_dispensing_id;

END;
$$;


/* 
   CALL reverse_dispensing TWICE FOR THE SAME RECORD
    */


/* First reversal */

CALL reverse_dispensing(1);


/* Second reversal
   This must NOT restore stock again.
*/

CALL reverse_dispensing(1);


/* Check results */

SELECT
    medicine_id,
    medicine_name,
    stock_quantity
FROM medicines
ORDER BY medicine_id;


SELECT
    dispensing_id,
    student_number,
    medicine_id,
    quantity,
    dispensing_status
FROM dispensing_records
ORDER BY dispensing_id;


/* 

   Display medicines below the low-stock threshold.

   Threshold = 5
    */

DO $$
DECLARE

    medicine_cursor CURSOR FOR

        SELECT
            medicine_id,
            medicine_name,
            stock_quantity

        FROM medicines

        WHERE stock_quantity < 5

        ORDER BY medicine_id;


    v_medicine RECORD;

BEGIN

    /* Open cursor */

    OPEN medicine_cursor;


    /* Fetch medicines one at a time */

    LOOP

        FETCH medicine_cursor
        INTO v_medicine;


        /* Stop when no more records exist */

        EXIT WHEN NOT FOUND;


        RAISE NOTICE
            'LOW STOCK -> Medicine: %, Stock Remaining: %',
            v_medicine.medicine_name,
            v_medicine.stock_quantity;

    END LOOP;


    /* Close cursor */

    CLOSE medicine_cursor;

END $$;


/* 
   8. REQUEST A NEGATIVE DISPENSING QUANTITY

   Handle invalid input using EXCEPTION
    */

DO $$
BEGIN

    BEGIN

        CALL dispense_medicine(
            '202600004',
            1,
            -5
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'NEGATIVE QUANTITY HANDLED: %',
                SQLERRM;

    END;

END $$;


/* 
   9. FINAL QUERIES

   Show final medicine stock and dispensing statuses.
    */


/* 
   FINAL MEDICINE STOCK
   */

SELECT
    medicine_id,
    medicine_name,
    stock_quantity
FROM medicines
ORDER BY medicine_id;


/* 
   FINAL DISPENSING RECORDS
    */

SELECT
    d.dispensing_id,
    d.student_number,
    m.medicine_name,
    d.quantity,
    d.dispensing_status,
    d.dispensing_date
FROM dispensing_records d
JOIN medicines m
    ON d.medicine_id = m.medicine_id
ORDER BY d.dispensing_id;