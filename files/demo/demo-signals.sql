CREATE STREAM demo_sensors (
  device_id DOUBLE PRECISION,
  temperature DOUBLE PRECISION,
  heartbeat DOUBLE PRECISION
);

CREATE MATERIALIZED VIEW demo_signals AS
SELECT device_id,
       heartbeat AS alive,
       temperature,
       MOVING_AVERAGE(temperature, 5) AS temperature_avg_5,
       MOVING_AVERAGE(temperature, 12) AS temperature_avg_12,
       temperature - MOVING_AVERAGE(temperature, 5) AS temperature_delta,
       MOVING_AVERAGE(temperature, 5) - MOVING_AVERAGE(temperature, 12) AS trend_delta,
       (temperature - MOVING_AVERAGE(temperature, 12)) * (temperature - MOVING_AVERAGE(temperature, 12)) AS anomaly_score
FROM demo_sensors
GROUP BY device_id;
