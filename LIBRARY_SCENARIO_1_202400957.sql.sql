/* SCENARIO 1: UNIVERSITY LIBRARY BOOK LOANS*/


/* CREATE TABLE*/

DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;


/* BOOKS TABLE */

CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,

    title VARCHAR(150) NOT NULL,

    available_copies INTEGER NOT NULL
        CHECK (available_copies >= 0)
);


/* BOOK LOANS TABLE */

CREATE TABLE book_loans (
    loan_id SERIAL PRIMARY KEY,

    student_number VARCHAR(20) NOT NULL,

    book_id INTEGER NOT NULL,

    quantity INTEGER NOT NULL
        CHECK (quantity > 0),

    loan_status VARCHAR(20) NOT NULL
        DEFAULT 'BORROWED'
        CHECK (loan_status IN ('BORROWED', 'RETURNED')),

    loan_date TIMESTAMP
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_book
        FOREIGN KEY (book_id)
        REFERENCES books(book_id)
);


/* INSERT AT LEAST THREE BOOKS*/

INSERT INTO books
    (title, available_copies)
VALUES
    ('Database Systems', 10),
    ('Computer Networks', 4),
    ('Operating Systems', 0);


/* Display books */

SELECT *
FROM books
ORDER BY book_id;


/* 
   2. IF / ELSIF / ELSE

   Determine whether a book is:
   - UNAVAILABLE
   - LOW ON COPIES
   - SUFFICIENTLY STOCKED
 */

DO $$
DECLARE
    v_book RECORD;
BEGIN

    FOR v_book IN
        SELECT
            book_id,
            title,
            available_copies
        FROM books
        ORDER BY book_id
    LOOP

        IF v_book.available_copies = 0 THEN

            RAISE NOTICE
                'Book: % -> UNAVAILABLE',
                v_book.title;

        ELSIF v_book.available_copies <= 3 THEN

            RAISE NOTICE
                'Book: % -> LOW ON COPIES (% copies remaining)',
                v_book.title,
                v_book.available_copies;

        ELSE

            RAISE NOTICE
                'Book: % -> SUFFICIENTLY STOCKED (% copies remaining)',
                v_book.title,
                v_book.available_copies;

        END IF;

    END LOOP;

END
$$;


/* 
   3. WHILE LOOP
   Display three overdue reminder numbers

   NUMERIC FOR LOOP
   Display three library shelf numbers
 */

DO $$
DECLARE
    v_counter INTEGER := 1;
BEGIN

    /* WHILE LOOP */

    WHILE v_counter <= 3 LOOP

        RAISE NOTICE
            'Overdue Reminder Number: %',
            v_counter;

        v_counter := v_counter + 1;

    END LOOP;


    /* NUMERIC FOR LOOP */

    FOR v_shelf IN 1..3 LOOP

        RAISE NOTICE
            'Library Shelf Number: %',
            v_shelf;

    END LOOP;

END
$$;


/* 
   4. CREATE borrow_book PROCEDURE
*/

CREATE OR REPLACE PROCEDURE borrow_book(
    p_student_number VARCHAR,
    p_book_id INTEGER,
    p_quantity INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available_copies INTEGER;
BEGIN

    /* Validate quantity */

    IF p_quantity IS NULL OR p_quantity <= 0 THEN

        RAISE EXCEPTION
            'INVALID QUANTITY: Quantity must be greater than zero';

    END IF;


    /* 
       Check that the book exists and lock its ro*/

    SELECT available_copies
    INTO v_available_copies
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;


    /* 
       Book does not exist
     */

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'BOOK NOT FOUND: Book ID % does not exist',
            p_book_id;

    END IF;


    /* Check available copies*/

    IF p_quantity > v_available_copies THEN

        RAISE EXCEPTION
            'INSUFFICIENT COPIES: Requested %, but only % copies are available',
            p_quantity,
            v_available_copies;

    END IF;


    /* 
       Reduce available copies
 */

    UPDATE books
    SET available_copies =
        available_copies - p_quantity
    WHERE book_id = p_book_id;


    /* 
       Record the loan
       */

    INSERT INTO book_loans
    (
        student_number,
        book_id,
        quantity,
        loan_status
    )
    VALUES
    (
        TRIM(p_student_number),
        p_book_id,
        p_quantity,
        'BORROWED'
    );


    RAISE NOTICE
        'Loan successfully recorded for student %.',
        p_student_number;

END
$$;


/* 
   5. TEST borrow_book
 */


/* VALID LOAN 1
   Database Systems:
   10 - 2 = 8
*/

CALL borrow_book(
    '202600001',
    1,
    2
);


/* VALID LOAN 2
   Computer Networks:
   4 - 2 = 2
*/

CALL borrow_book(
    '202600002',
    2,
    2
);


/* INVALID LOAN
   Computer Networks has only 2 remaining.
   Requesting 5 should fail.
*/

DO $$
BEGIN

    BEGIN

        CALL borrow_book(
            '202600003',
            2,
            5
        );

    EXCEPTION
        WHEN OTHERS THEN

            RAISE NOTICE
                'EXPECTED ERROR: %',
                SQLERRM;

    END;

END
$$;


/* Check books */

SELECT
    book_id,
    title,
    available_copies
FROM books
ORDER BY book_id;


/* Check loans */

SELECT
    loan_id,
    student_number,
    book_id,
    quantity,
    loan_status,
    loan_date
FROM book_loans
ORDER BY loan_id;


/* 
   6. CREATE return_book PROCEDURE
 */

CREATE OR REPLACE PROCEDURE return_book(
    p_loan_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INTEGER;
    v_quantity INTEGER;
    v_status VARCHAR(20);
BEGIN

    /* 
       Find and lock the loan
      */

    SELECT
        book_id,
        quantity,
        loan_status
    INTO
        v_book_id,
        v_quantity,
        v_status
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;


    /* 
       Check whether the loan exists
 */

    IF NOT FOUND THEN

        RAISE EXCEPTION
            'LOAN NOT FOUND: Loan ID % does not exist',
            p_loan_id;

    END IF;


    /* 
       Prevent returning the same loan twice
 */

    IF v_status = 'RETURNED' THEN

        RAISE NOTICE
            'Loan % has already been returned.',
            p_loan_id;

        RAISE NOTICE
            'Copies will NOT be restored again.';

        RETURN;

    END IF;


    /* 
       Restore book copies
 */

    UPDATE books
    SET available_copies =
        available_copies + v_quantity
    WHERE book_id = v_book_id;


    /* 
       Mark loan as returned
       */

    UPDATE book_loans
    SET loan_status = 'RETURNED'
    WHERE loan_id = p_loan_id;


    RAISE NOTICE
        'Loan % successfully returned.',
        p_loan_id;

END
$$;


/* 
   TEST return_book TWICE
 */


/* First return */

CALL return_book(1);


/* Second return
   No additional copies will be restored.
*/

CALL return_book(1);


/* 
   7. EXPLICIT CURSOR
   Display books with few copies remaining
 */

DO $$
DECLARE

    book_cursor CURSOR FOR
        SELECT
            book_id,
            title,
            available_copies
        FROM books
        WHERE available_copies <= 3
        ORDER BY book_id;

    v_book RECORD;

BEGIN

    OPEN book_cursor;


    LOOP

        FETCH book_cursor
        INTO v_book;


        EXIT WHEN NOT FOUND;


        RAISE NOTICE
            'LOW COPIES -> Book ID: %, Title: %, Copies Remaining: %',
            v_book.book_id,
            v_book.title,
            v_book.available_copies;

    END LOOP;


    CLOSE book_cursor;

END
$$;


/*  TRY TO BORROW ZERO COPIES
   Handle error using EXCEPTION
 */

DO $$
BEGIN

    BEGIN

        CALL borrow_book(
            '202600004',
            1,
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
   FINAL BOOK QUANTITIES
 */

SELECT
    book_id,
    title,
    available_copies
FROM books
ORDER BY book_id;


/* 
   FINAL LOAN STATUSES
    */

SELECT
    bl.loan_id,
    bl.student_number,
    b.title AS book_title,
    bl.quantity,
    bl.loan_status,
    bl.loan_date
FROM book_loans AS bl
INNER JOIN books AS b
    ON bl.book_id = b.book_id
ORDER BY bl.loan_id;