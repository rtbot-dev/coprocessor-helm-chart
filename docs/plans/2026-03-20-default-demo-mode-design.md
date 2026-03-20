# Default Demo Mode Design

## Goal

Make the first chart install visibly useful by default. A new user should see a demo device producing telemetry, the coprocessor processing it, and derived telemetry coming back into ThingsBoard without extra setup beyond providing the required ThingsBoard access information.

## Decision

Enable demo mode by default during the current product phase.

## Behavior

When demo mode is enabled, the chart should:

- create or use a deterministic demo device
- continuously publish heartbeat-style telemetry for that device
- install a demo SQL program automatically
- publish derived telemetry back into ThingsBoard

The demo should be easy to remove later by disabling one values block.

## Demo Content

Use a slightly richer demo than a single boring metric. The first pass should include:

- heartbeat / alive signal
- temperature moving average
- temperature delta or trend signal
- threshold or anomaly flag

## Operational Model

Because automatic device creation depends on ThingsBoard-side permissions, the chart should support two modes under the same demo feature:

1. admin-assisted mode: chart has enough credentials to create/register the demo device automatically
2. pre-provisioned mode: chart uses an existing device/token supplied in values

For now, because demo mode is default-on, the README must make the required values explicit.

## Success Criteria

- a default install shows visible demo data flow in ThingsBoard
- operators can disable the demo later
- documentation clearly separates “quick demo experience” from “production cleanup/disable”
