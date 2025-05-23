
DROP TABLE IF EXISTS 
    aircraft_model,
    aircrafts,
    airlines,
    departments,
    destinations,
    employees,
    flights,
    gateassignments,
    gates,
    luggage,
    passengers,
    reservations 
CASCADE;

CREATE TABLE airlines (
    airline_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    country VARCHAR(50) NOT NULL
);


CREATE TABLE aircraft_model(
model VARCHAR(50) PRIMARY KEY);

CREATE TABLE aircrafts(
aircraft_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
airline_id INTEGER NOT NULL REFERENCES airlines(airline_id) ON UPDATE CASCADE ON DELETE RESTRICT,
model VARCHAR(50) NOT NULL REFERENCES aircraft_model(model) ON UPDATE CASCADE ON DELETE RESTRICT,
seats INTEGER NOT NULL CHECK (seats > 0 AND seats <=450), 
Range DECIMAL(7, 2) NOT NULL,
fuel_consumption DECIMAL(7, 2) NOT NULL, 
fuel_type VARCHAR(50) NOT NULL CHECK(fuel_type IN ('Jet A1','SAF'))
);

CREATE TABLE destinations(
destination_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
startairport VARCHAR(50) NOT NULL,
destination VARCHAR(50) NOT NULL,
airline_id INTEGER NOT NULL REFERENCES airlines(airline_id) ON UPDATE CASCADE ON DELETE CASCADE,
flight_number VARCHAR(50) NOT NULL UNIQUE,
UNIQUE(startairport,destination, airline_id)
);

CREATE TABLE flights(
    flight_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
	destination_id INTEGER NOT NULL REFERENCES destinations(destination_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    departure_time TIMESTAMP NOT NULL CHECK (departure_time < arrival_time),
    arrival_time TIMESTAMP NOT NULL,
    aircraft_id INTEGER REFERENCES aircrafts(aircraft_id) ON UPDATE CASCADE ON DELETE SET NULL,
	status VARCHAR(10) NOT NULL DEFAULT('planned') CHECK(status IN ('delayed','planned','cancelled'))
);

CREATE OR REPLACE FUNCTION validate_flight_times()
RETURNS TRIGGER AS $$
BEGIN
  
    IF EXISTS (
        SELECT 1
        FROM flights f
        JOIN destinations d ON f.destination_id = d.destination_id
        WHERE d.startairport = (SELECT startairport FROM destinations WHERE destination_id = NEW.destination_id)
          AND f.departure_time = NEW.departure_time
          AND f.flight_id != NEW.flight_id
    ) THEN
        RAISE EXCEPTION 'Conflict: Two flights cannot depart from the same airport at the same time';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM flights f
        JOIN destinations d ON f.destination_id = d.destination_id
        WHERE d.destination = (SELECT destination FROM destinations WHERE destination_id = NEW.destination_id)
          AND f.arrival_time = NEW.arrival_time
          AND f.flight_id != NEW.flight_id
    ) THEN
        RAISE EXCEPTION 'Conflict: Two flights cannot arrive at the same destination at the same time';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER check_flight_times
BEFORE INSERT OR UPDATE ON flights
FOR EACH ROW
EXECUTE FUNCTION validate_flight_times();


CREATE OR REPLACE FUNCTION assign_aircraft_to_flight()
RETURNS TRIGGER AS $$
DECLARE
    p_airline_id INT;
    p_aircraft_id INT;
BEGIN
    SELECT airline_id INTO p_airline_id
    FROM destinations
    WHERE destination_id = NEW.destination_id;

    SELECT aircraft_id INTO p_aircraft_id
    FROM aircrafts
    WHERE airline_id = p_airline_id
      AND aircraft_id NOT IN (
          SELECT aircraft_id
          FROM flights
          WHERE DATE(departure_time) = DATE(NEW.departure_time)
      )
    ORDER BY random()
    LIMIT 1;

    NEW.aircraft_id = p_aircraft_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER assign_aircraft_before_insert
BEFORE INSERT ON flights
FOR EACH ROW
EXECUTE FUNCTION assign_aircraft_to_flight();
	  
	  
CREATE TABLE passengers(
passenger_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
first_name VARCHAR(50) NOT NULL,
last_name VARCHAR(50) NOT NULL,
document_number VARCHAR(15) NOT NULL UNIQUE,
date_of_birth DATE NOT NULL,
gender CHAR(1) CHECK (gender IN ('M', 'F')),
email VARCHAR(100) CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') UNIQUE,
phone_number VARCHAR(15) UNIQUE,
CONSTRAINT chk_contact_info CHECK (email IS NOT NULL OR phone_number IS NOT NULL));


CREATE TABLE reservations (
    reservation_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    flight_id INTEGER NOT NULL REFERENCES flights(flight_id) ON UPDATE CASCADE ON DELETE CASCADE,
    passenger_id INTEGER NOT NULL REFERENCES passengers(passenger_id) ON UPDATE CASCADE ON DELETE RESTRICT,
	UNIQUE (flight_id, passenger_id)
	);
	

CREATE OR REPLACE FUNCTION check_seat_number() 
RETURNS TRIGGER AS $$
DECLARE
    max_seats INTEGER;
    reserved_seats INTEGER;
BEGIN
 
    SELECT a.seats INTO max_seats
    FROM aircrafts a
    JOIN flights f ON f.aircraft_id = a.aircraft_id
    WHERE f.flight_id = NEW.flight_id;

    
    SELECT COUNT(*) INTO reserved_seats
    FROM reservations
    WHERE flight_id = NEW.flight_id;


    IF reserved_seats >= max_seats THEN
        RAISE EXCEPTION 'Maximum number of seats (%s) exceeded for flight %s', max_seats, NEW.flight_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TABLE luggage(
luggage_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
reservation_id INTEGER NOT NULL REFERENCES reservations(reservation_id) ON UPDATE CASCADE ON DELETE CASCADE,
weight DECIMAL(5,2) NOT NULL CHECK (weight > 0 AND weight <= 40),
status VARCHAR(30) CHECK (status IN('Checked-in','Loaded','Awaiting Pick-up','Lost','Found','Claimed'))
);

CREATE TABLE gates(
    gate_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    terminal VARCHAR(50) NOT NULL CHECK(terminal IN ('A','B')), 
    gate_number VARCHAR(10) NOT NULL,
    UNIQUE (terminal, gate_number)
);


CREATE TABLE gateassignments(
    assignment_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    flight_id INTEGER NOT NULL UNIQUE REFERENCES flights(flight_id) ON UPDATE CASCADE ON DELETE CASCADE,
    gate_id INTEGER NOT NULL REFERENCES gates(gate_id) ON UPDATE CASCADE ON DELETE CASCADE,
	opening_time TIMESTAMP, 
    UNIQUE (flight_id, gate_id),
	UNIQUE(gate_id,opening_Time)
);

CREATE OR REPLACE FUNCTION set_opening_time() 
RETURNS TRIGGER AS $$
BEGIN
    NEW.Opening_Time := (
        SELECT Departure_Time - INTERVAL '30 minutes'
        FROM Flights
        WHERE Flight_ID = NEW.Flight_ID
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_opening_time_trigger
BEFORE INSERT ON GateAssignments
FOR EACH ROW
EXECUTE FUNCTION set_opening_time();


CREATE OR REPLACE FUNCTION update_opening_time() 
RETURNS TRIGGER AS $$
BEGIN
    UPDATE GateAssignments
    SET Opening_Time = NEW.Departure_Time - INTERVAL '30 minutes'
    WHERE Flight_ID = NEW.Flight_ID;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_opening_time_trigger
AFTER UPDATE OF Departure_Time ON Flights
FOR EACH ROW
EXECUTE FUNCTION update_opening_time();


CREATE OR REPLACE VIEW Arrivals AS
SELECT
    f.flight_id AS Flight_id,
    d.startairport AS Departure_airport,
    f.arrival_time AS Arrival_Time,
    al.name AS Airline,
	d.flight_number AS Flight_number,
    f.status AS Status
FROM
    flights f
JOIN
    destinations d ON f.destination_id = d.destination_id
JOIN
    airlines al ON d.airline_id = al.airline_id
WHERE d.destination = 'Wroclaw';


CREATE OR REPLACE VIEW Departures AS
SELECT
    f.flight_id AS Flight_id,
    d.destination AS Destination,
    f.departure_time AS Departure_Time,
    al.name AS Airline,
	d.flight_number AS Flight_Number,
    f.status AS Status,
    g.terminal AS Terminal,
    g.gate_number AS Gate,
    ga.opening_time AS Gate_Opening_Time
FROM
    flights f
JOIN
    destinations d ON f.destination_id = d.destination_id
JOIN
    airlines al ON d.airline_id = al.airline_id
LEFT JOIN
    gateassignments ga ON f.flight_id = ga.flight_id
LEFT JOIN
    gates g ON ga.gate_id = g.gate_id
WHERE d.startairport = 'Wroclaw';



CREATE TABLE departments (
    department_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    location VARCHAR(100) NOT NULL,
    contact_phone VARCHAR(15) NOT NULL 
);


CREATE TABLE employees (
    employee_id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    position VARCHAR(50) NOT NULL,
    hire_date DATE NOT NULL,
    department_id INTEGER NOT NULL REFERENCES departments(department_id) ON UPDATE CASCADE ON DELETE RESTRICT
);


CREATE OR REPLACE FUNCTION assign_gate(p_flight_id INTEGER, p_gate_id INTEGER)
RETURNS VOID AS $$
BEGIN
    -- Dodanie rekordu do tabeli gateassignments
    INSERT INTO gateassignments (flight_id, gate_id)
    VALUES (p_flight_id, p_gate_id);
	
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION update_flight_details(
    p_flight_id INTEGER,                  
    p_departure_time TIMESTAMP,
    p_arrival_time TIMESTAMP,
    p_aircraft_id INTEGER,
    p_status VARCHAR
)
RETURNS VOID AS $$
BEGIN
    

    IF p_departure_time IS NOT NULL THEN
        UPDATE flights
        SET departure_time = p_departure_time
        WHERE flight_id = p_flight_id;
    END IF;
    

    IF p_arrival_time IS NOT NULL THEN
        UPDATE flights
        SET arrival_time = p_arrival_time
        WHERE flight_id = p_flight_id;
    END IF;
    

    IF p_aircraft_id IS NOT NULL THEN
        UPDATE flights
        SET aircraft_id = p_aircraft_id
        WHERE flight_id = p_flight_id;
    END IF;

    IF p_status IS NOT NULL THEN
        UPDATE flights
        SET status = p_status
        WHERE flight_id = p_flight_id;
    END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION add_flight(
    p_destination_id INT,
    p_departure_time TIMESTAMP,
    p_arrival_time TIMESTAMP
) RETURNS VOID AS $$
BEGIN
    IF p_departure_time >= p_arrival_time THEN
        RAISE EXCEPTION 'Departure time must be earlier than arrival time';
    END IF;
	
    INSERT INTO flights (destination_id, departure_time, arrival_time )
    VALUES (p_destination_id, p_departure_time, p_arrival_time);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_reservation(p_flight_id INTEGER, p_passenger_id INTEGER) 
RETURNS VOID AS $$
BEGIN
    INSERT INTO reservations (flight_id, passenger_id)
    VALUES (p_flight_id, p_passenger_id);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_passenger(
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    document_number VARCHAR(15),
    date_of_birth DATE,
    gender CHAR(1),
    email VARCHAR(100),
    phone_number VARCHAR(15)
) RETURNS VOID AS $$
BEGIN
    INSERT INTO passengers (first_name, last_name, document_number, date_of_birth, gender, email, phone_number)
    VALUES (
        first_name, 
        last_name, 
        document_number, 
        date_of_birth, 
        gender, 
        CASE WHEN LENGTH(email) > 0 THEN email ELSE NULL END,
        CASE WHEN LENGTH(phone_number) > 0 THEN phone_number ELSE NULL END
    );
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION add_luggage(reservation_id INTEGER, weight DECIMAL(5,2))
RETURNS VOID AS $$
BEGIN
    INSERT INTO luggage (reservation_id, weight, status)
    VALUES (reservation_id, weight, NULL);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_aircraft_to_wizzair(
    p_model TEXT,
    p_seats INTEGER,
    p_range INTEGER,
    p_fuel_consumption NUMERIC,
    p_fuel_type TEXT
)
RETURNS VOID AS $$
DECLARE
    wizzair_id INTEGER;
BEGIN

    SELECT airline_id INTO wizzair_id
    FROM airlines
    WHERE name = 'Wizz Air';

    INSERT INTO aircrafts (model, seats, range, fuel_consumption, fuel_type, airline_id)
    VALUES (p_model, p_seats, p_range, p_fuel_consumption, p_fuel_type, wizzair_id);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_aircraft_to_lot(
    p_model TEXT,
    p_seats INTEGER,
    p_range INTEGER,
    p_fuel_consumption NUMERIC,
    p_fuel_type TEXT
)
RETURNS VOID AS $$
DECLARE
    lot_id INTEGER;
BEGIN

    SELECT airline_id INTO lot_id
    FROM airlines
    WHERE name = 'LOT';

    INSERT INTO aircrafts (model, seats, range, fuel_consumption, fuel_type, airline_id)
    VALUES (p_model, p_seats, p_range, p_fuel_consumption, p_fuel_type, lot_id);
END;
$$ LANGUAGE plpgsql;

--add aircraft-ryanair
CREATE OR REPLACE FUNCTION add_aircraft_to_ryanair(
    p_model TEXT,
    p_seats INTEGER,
    p_range INTEGER,
    p_fuel_consumption NUMERIC,
    p_fuel_type TEXT
)
RETURNS VOID AS $$
DECLARE
    ryanair_id INTEGER;
BEGIN

    SELECT airline_id INTO ryanair_id
    FROM airlines
    WHERE name = 'Ryanair';

    INSERT INTO aircrafts (model, seats, range, fuel_consumption, fuel_type, airline_id)
    VALUES (p_model, p_seats, p_range, p_fuel_consumption, p_fuel_type, ryanair_id);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION remove_aircraft_from_wizzair(p_aircraft_id INTEGER)
RETURNS VOID AS $$
BEGIN
    DELETE FROM aircrafts
    WHERE aircraft_id = p_aircraft_id AND airline_id = (
        SELECT airline_id FROM airlines WHERE name = 'Wizz Air'
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION remove_aircraft_from_lot(p_aircraft_id INTEGER)
RETURNS VOID AS $$
BEGIN
    DELETE FROM aircrafts
    WHERE aircraft_id = p_aircraft_id AND airline_id = (
        SELECT airline_id FROM airlines WHERE name = 'LOT'
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION remove_aircraft_from_ryanair(p_aircraft_id INTEGER)
RETURNS VOID AS $$
BEGIN
    DELETE FROM aircrafts
    WHERE aircraft_id = p_aircraft_id AND airline_id = (
        SELECT airline_id FROM airlines WHERE name = 'Ryanair'
    );
END;
$$ LANGUAGE plpgsql;

